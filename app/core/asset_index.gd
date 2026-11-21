extends RefCounted
## Dependency-aware asset root indexer with DOCP v2 .pak support,
## directory/pak timestamp stamp invalidation, ODF/material parsing,
## duplicate/override detection, and exact mission DLL SHA-256 identity checks.

const ASSET_EXTENSIONS := [
	"odf", "msh", "fbx", "xsi", "material", "dds", "tga", "png",
	"wav", "ogg", "dll", "lua", "aip",
]
const MAX_INDEXED_FILES := 300_000
const MAX_PAK_ENTRIES := 65536
const MAX_TEXT_READ := 256 * 1024

## Verified mission DLL SHA-256 signatures collected from installed BZCC 2.0.185
## Stock, VSR (Workshop 1325933293), and VRV (Workshop 3820486276).
const KNOWN_DLL_SIGNATURES := {
	"415ad6ca656c02972ff5b88c574d51cb508f6574001b848b84c30b776d9b1bc2": {"mod": "stock", "name": "Strategy02.dll", "size": 27136},
	"c3dc76d348ef8a31cfade7b3928e0f650d4bfb62348942177e1bc364470c65ce": {"mod": "stock", "name": "Instant.dll", "size": 29696},
	"62f296053c99bb5b871e17b5140ac3b53f75ce6442721219c581611fad9439fc": {"mod": "stock", "name": "mpinstant.dll", "size": 34816},
	"20344ce75d291e68e95692d8b6202b7f7d3ae08c93a3664907d65ec987071046": {"mod": "stock", "name": "deathmatch01.dll", "size": 37888},
	"687c1ed92f6eaee882a688f78f75eb7be8972e3f7590db0fc9b0b53e8c56eec6": {"mod": "stock", "name": "StratCTF.dll", "size": 28160},
	"b197f15b12901c9d87a0b80a7b775860a15302320cd33f1b09fa2b8683da57db": {"mod": "stock", "name": "LuaMission.dll", "size": 230400},
	"a4b3ce223fc305df88507b07d1e0790ced781df5147ccce4886d776c45c0b6bb": {"mod": "vsr", "name": "Strategy02.dll", "size": 465408},
	"c17c7d1c7fa7a75b87f3350f3b66599e207e9ece580d555b5c7c5051bd7e407d": {"mod": "vsr", "name": "Instant.dll", "size": 445952},
	"b982c41694aba3e7d48fe4bc2d145d6d4f0261d529dea17d644212478c5e6020": {"mod": "vsr", "name": "deathmatch01.dll", "size": 449536},
	"a7097e937761f2ef81d84693ef537c0102cc359ad3d6a7aa1d7d01a6b98a5a2a": {"mod": "vsr", "name": "LuaMission.dll", "size": 433152},
	"afc99de3250ab37dccfbaf099b4983a7a402c0f8ae8d535f63fac7f91297a989": {"mod": "vrv", "name": "Strategy02.dll", "size": 5331968},
	"8879f1e83d507720774d48c196a0f750b40044ad3c80c279ff348436edb79c0d": {"mod": "vrv", "name": "Instant.dll", "size": 5287424},
	"f7759194b4798120ed87525cd27c4e6574454fdb2eb67d58cc33cd47a9e79834": {"mod": "vrv", "name": "mpinstant.dll", "size": 1714688},
	"d09c8bfc1e4a71723185e0ebf5f2cb1f4c88821e726396eaa43d45a7743dcd4a": {"mod": "vrv", "name": "deathmatch01.dll", "size": 1710080},
	"e3f6e4b5062cfced01f70f81809b83d7bbed1fb9f4ab563b33257fc015fa0130": {"mod": "vrv", "name": "StratCTF.dll", "size": 1703424},
	"65e575b840c5840ebc7df8b21ee35c116c1fd88abe63528be9483f0dbf115d11": {"mod": "vrv", "name": "VrvPrepare.dll", "size": 1309184},
}

## Process-local per-root cache keyed by "normalized_path|recurse" -> {stamp, files, odfs, ...}
static var _root_cache: Dictionary = {}
static var _cache_hits: int = 0
static var _cache_misses: int = 0


static func clear_cache() -> void:
	_root_cache.clear()
	_cache_hits = 0
	_cache_misses = 0


static func cache_stats() -> Dictionary:
	return {"entries": _root_cache.size(), "hits": _cache_hits, "misses": _cache_misses}


static func normalize_key(name: String, extension: String = "") -> String:
	var clean := name.strip_edges().replace("\\", "/").get_file().to_lower()
	if clean.is_empty():
		return ""
	if not extension.is_empty():
		var suffix := "." + extension.to_lower()
		if not clean.ends_with(suffix):
			clean += suffix
	return clean


## Computes a deterministic freshness stamp over directory modification times,
## direct file counts/sizes for small mutable roots, and DOCP .pak sizes/mtimes.
static func compute_root_stamp(root: String, recurse: bool = true) -> String:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return "missing"
	var norm := root.simplify_path()
	var parts := PackedStringArray()
	parts.append("r:%d" % FileAccess.get_modified_time(norm))
	var pending: Array[String] = [norm]
	var dir_count := 0
	while not pending.is_empty() and dir_count < 4096:
		var current: String = pending.pop_back()
		dir_count += 1
		var handle := DirAccess.open(current)
		if handle == null:
			continue
		var rel_dir := current.substr(norm.length())
		var files := handle.get_files()
		var sub_count := 0
		var pak_entries := PackedStringArray()
		for fname in files:
			var ext := fname.get_extension().to_lower()
			if ext in ASSET_EXTENSIONS:
				sub_count += 1
			elif ext == "pak":
				var fp := current.path_join(fname)
				var f := FileAccess.open(fp, FileAccess.READ)
				var flen := f.get_length() if f != null else 0
				if f != null:
					f.close()
				pak_entries.append("%s:%d:%d" % [fname.to_lower(), flen, FileAccess.get_modified_time(fp)])
		pak_entries.sort()
		parts.append("d:%s:%d:%d:%s" % [rel_dir, FileAccess.get_modified_time(current), sub_count, ",".join(pak_entries)])
		if recurse:
			var dirs := Array(handle.get_directories())
			dirs.sort()
			dirs.reverse()
			for sub_v in dirs:
				var sub := String(sub_v)
				if sub.begins_with(".") or handle.is_link(sub):
					continue
				pending.append(current.path_join(sub))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Reads a DOCP v2 .pak directory table and returns entries as "pak_path::entry_name".
static func read_docp_pak_entries(pak_path: String) -> PackedStringArray:
	var entries := PackedStringArray()
	var file := FileAccess.open(pak_path, FileAccess.READ)
	if file == null:
		return entries
	var total := file.get_length()
	if total < 32:
		file.close()
		return entries
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != "DOCP":
		file.close()
		return entries
	var ver := file.get_32()
	file.get_32()
	file.get_32()
	var count := file.get_32()
	var dir_offset := file.get_32()
	if ver != 2 or count <= 0 or count > MAX_PAK_ENTRIES or dir_offset >= total:
		file.close()
		return entries
	file.seek(dir_offset)
	for _i in count:
		if file.get_position() + 5 > total:
			break
		file.get_32()
		var name_len := file.get_8()
		if file.get_position() + name_len + 12 > total:
			break
		var entry_name := file.get_buffer(name_len).get_string_from_ascii()
		file.get_buffer(12)
		var ext := entry_name.get_extension().to_lower()
		if ext in ASSET_EXTENSIONS:
			entries.append("%s::%s" % [pak_path, entry_name])
	file.close()
	return entries


## Builds an asset index for one root folder (loose files + DOCP v2 .pak archives).
## Each lowercase filename maps to an Array[String] of all resolved paths in that root
## so intra-root duplicates are preserved instead of silently hidden.
static func build_root_index(root: String, recurse: bool = true) -> Dictionary:
	var files_map := {}
	var odf_map := {}
	var pak_count := 0
	var file_count := 0
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return {"root": root, "exists": false, "files": files_map, "odfs": odf_map, "pakCount": 0, "fileCount": 0}
	var norm := root.simplify_path()
	var pending: Array[String] = [norm]
	while not pending.is_empty() and file_count < MAX_INDEXED_FILES:
		var current: String = pending.pop_back()
		var handle := DirAccess.open(current)
		if handle == null:
			continue
		var dir_files := Array(handle.get_files())
		dir_files.sort()
		for fname_v in dir_files:
			var fname := String(fname_v)
			var ext := fname.get_extension().to_lower()
			var full := current.path_join(fname)
			if ext == "pak":
				pak_count += 1
				for pak_entry in read_docp_pak_entries(full):
					var sep := pak_entry.find("::")
					var leaf := pak_entry.substr(sep + 2).replace("\\", "/").get_file().to_lower()
					if leaf.is_empty():
						continue
					if not files_map.has(leaf):
						files_map[leaf] = []
					(files_map[leaf] as Array).append(pak_entry)
					file_count += 1
					if leaf.ends_with(".odf"):
						if not odf_map.has(leaf):
							odf_map[leaf] = []
						(odf_map[leaf] as Array).append(pak_entry)
			elif ext in ASSET_EXTENSIONS:
				var key := fname.to_lower()
				if not files_map.has(key):
					files_map[key] = []
				(files_map[key] as Array).append(full)
				file_count += 1
				if ext == "odf":
					if not odf_map.has(key):
						odf_map[key] = []
					(odf_map[key] as Array).append(full)
		if recurse:
			var dirs := Array(handle.get_directories())
			dirs.sort()
			dirs.reverse()
			for sub_v in dirs:
				var sub := String(sub_v)
				if sub.begins_with(".") or handle.is_link(sub):
					continue
				pending.append(current.path_join(sub))
	return {
		"root": norm,
		"exists": true,
		"files": files_map,
		"odfs": odf_map,
		"pakCount": pak_count,
		"fileCount": file_count,
	}


static func get_root_index(root: String, recurse: bool = true, bypass_cache: bool = false) -> Dictionary:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return {"root": root, "exists": false, "files": {}, "odfs": {}, "pakCount": 0, "fileCount": 0, "stamp": "missing"}
	var norm := root.simplify_path()
	var cache_key := "%s|%s" % [norm.to_lower(), "1" if recurse else "0"]
	var stamp := compute_root_stamp(norm, recurse)
	if not bypass_cache and _root_cache.has(cache_key):
		var cached: Dictionary = _root_cache[cache_key]
		if String(cached.get("stamp", "")) == stamp:
			_cache_hits += 1
			return cached
	if not bypass_cache:
		_cache_misses += 1
	var built := build_root_index(norm, recurse)
	built["stamp"] = stamp
	if not bypass_cache:
		_root_cache[cache_key] = built
	return built


## Builds a layered lookup table across ordered root descriptors:
## each item in `layered_roots` is {"path": String, "source": String, "recurse": bool, "volatile": bool}.
## Precedence is first-root-wins, while recording intra-root duplicates and cross-root overrides.
static func index_layered_roots(layered_roots: Array[Dictionary]) -> Dictionary:
	var ordered: Array[Dictionary] = []
	var first_hit := {}
	var first_source := {}
	var all_hits := {}
	var duplicate_odfs: Array[Dictionary] = []
	var odf_overrides: Array[Dictionary] = []
	var odf_sources := {}
	var seen_root_keys := {}
	var duplicate_roots: Array[String] = []
	var unavailable_roots: Array[String] = []

	for desc in layered_roots:
		var raw_path := String(desc.get("path", "")).strip_edges()
		if raw_path.is_empty():
			continue
		var norm := raw_path.simplify_path()
		var rec := bool(desc.get("recurse", true))
		var rkey := "%s|%s" % [norm.to_lower(), "1" if rec else "0"]
		if seen_root_keys.has(rkey):
			duplicate_roots.append(norm)
			continue
		seen_root_keys[rkey] = true
		if not DirAccess.dir_exists_absolute(norm):
			unavailable_roots.append(norm)
			continue
		var source_id := String(desc.get("source", "unknown"))
		var volatile := bool(desc.get("volatile", false))
		var idx := get_root_index(norm, rec, volatile)
		ordered.append({"path": norm, "source": source_id, "index": idx})
		var fmap: Dictionary = idx["files"]
		for key: String in fmap:
			var paths: Array = fmap[key]
			if paths.is_empty():
				continue
			if key.ends_with(".odf") and paths.size() > 1:
				duplicate_odfs.append({"odf": key, "root": norm, "source": source_id, "matches": paths.duplicate()})
			if not first_hit.has(key):
				first_hit[key] = String(paths[0])
				first_source[key] = source_id
				if key.ends_with(".odf"):
					odf_sources[key] = source_id
			elif key.ends_with(".odf"):
				var prev_src := String(first_source[key])
				if prev_src != source_id:
					odf_overrides.append({
						"odf": key,
						"winnerPath": String(first_hit[key]),
						"winnerSource": prev_src,
						"shadowedPath": String(paths[0]),
						"shadowedSource": source_id,
					})
			if not all_hits.has(key):
				all_hits[key] = []
			for p_v in paths:
				(all_hits[key] as Array).append({"path": String(p_v), "source": source_id, "root": norm})
	return {
		"roots": ordered,
		"firstHit": first_hit,
		"firstSource": first_source,
		"allHits": all_hits,
		"odfSources": odf_sources,
		"duplicateOdfs": duplicate_odfs,
		"odfOverrides": odf_overrides,
		"duplicateRoots": duplicate_roots,
		"unavailableRoots": unavailable_roots,
	}


## Parses an ODF file (loose on disk) and extracts key [GameObjectClass] / audio metadata.
static func parse_odf_file(path: String) -> Dictionary:
	var out := {
		"path": path,
		"packed": "::" in path,
		"classLabel": "",
		"geometryName": "",
		"geometryScale": 1.0,
		"unitName": "",
		"scrapCost": -1,
		"scrapValue": -1,
		"maxHealth": -1,
		"sounds": [],
		"sections": {},
	}
	if path.is_empty() or "::" in path:
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_TEXT_READ:
		if file != null:
			file.close()
		return out
	var text := file.get_buffer(file.get_length()).get_string_from_ascii()
	file.close()
	var section := ""
	var sounds: Array[String] = []
	var seen_sounds := {}
	var sections := {}
	for raw in text.split("\n"):
		var clean := raw.get_slice("//", 0).strip_edges()
		if clean.is_empty():
			continue
		if clean.begins_with("[") and clean.ends_with("]"):
			section = clean.substr(1, clean.length() - 2).strip_edges().to_lower()
			if not sections.has(section):
				sections[section] = {}
			continue
		if not clean.contains("="):
			continue
		var key := clean.get_slice("=", 0).strip_edges().to_lower()
		var val := clean.substr(clean.find("=") + 1).strip_edges().trim_prefix('"').trim_suffix('"')
		if not section.is_empty():
			(sections[section] as Dictionary)[key] = val
		if section == "gameobjectclass":
			match key:
				"classlabel":
					out["classLabel"] = val.to_lower()
				"geometryname":
					out["geometryName"] = val
				"geometryscale":
					var sc := val.to_float()
					if is_finite(sc) and sc > 0.0 and sc <= 100.0:
						out["geometryScale"] = sc
				"unitname":
					out["unitName"] = val
				"scrapcost":
					if val.is_valid_int():
						out["scrapCost"] = int(val)
				"scrapvalue":
					if val.is_valid_int():
						out["scrapValue"] = int(val)
				"maxhealth":
					if val.is_valid_int():
						out["maxHealth"] = int(val)
		if key.ends_with("sound") or key.begins_with("sound"):
			var s_clean := val.strip_edges().to_lower()
			var ext := s_clean.get_extension()
			if ext in ["wav", "ogg"] and not seen_sounds.has(s_clean):
				seen_sounds[s_clean] = true
				sounds.append(s_clean)
	out["sounds"] = sounds
	out["sections"] = sections
	return out


## Resolves transitive ODF inheritance (up to depth 12) and checks mesh, material,
## texture, and sound references against the layered index.
static func inspect_odf_dependencies(odf_name: String, layered_index: Dictionary, depth: int = 0) -> Dictionary:
	var key := normalize_key(odf_name, "odf")
	var first_hit: Dictionary = layered_index.get("firstHit", {})
	var first_source: Dictionary = layered_index.get("firstSource", {})
	if key.is_empty() or not first_hit.has(key):
		return {
			"odf": key,
			"found": false,
			"path": "",
			"source": "missing",
			"packed": false,
			"classLabel": "",
			"baseClass": "",
			"geometryName": "",
			"meshPath": "",
			"meshMissing": false,
			"missingTextures": [],
			"missingSounds": [],
			"unitName": "",
			"parentChain": [],
		}
	var resolved_path := String(first_hit[key])
	var source_id := String(first_source.get(key, "unknown"))
	var parsed := parse_odf_file(resolved_path)
	var parent_chain: Array[String] = [key]
	var class_label := String(parsed["classLabel"])
	var geom := String(parsed["geometryName"])
	var unit_name := String(parsed["unitName"])
	var base_class := class_label
	var sounds: Array[String] = []
	for s_v in parsed["sounds"]:
		sounds.append(String(s_v))

	if depth < 12 and not class_label.is_empty():
		var parent_key := normalize_key(class_label, "odf")
		if parent_key != key and first_hit.has(parent_key):
			var parent_info := inspect_odf_dependencies(parent_key, layered_index, depth + 1)
			if geom.is_empty():
				geom = String(parent_info.get("geometryName", ""))
			if unit_name.is_empty():
				unit_name = String(parent_info.get("unitName", ""))
			if not String(parent_info.get("baseClass", "")).is_empty():
				base_class = String(parent_info["baseClass"])
			for pc_v in parent_info.get("parentChain", []):
				parent_chain.append(String(pc_v))

	var mesh_path := ""
	var mesh_missing := false
	var missing_textures: Array[String] = []
	if not geom.is_empty() and not bool(parsed["packed"]):
		var geom_lower := geom.replace("\\", "/").get_file().to_lower()
		var geom_stem := geom_lower.get_basename()
		var msh_key := geom_stem + ".msh"
		if first_hit.has(msh_key):
			mesh_path = String(first_hit[msh_key])
		elif first_hit.has(geom_lower):
			mesh_path = String(first_hit[geom_lower])
		else:
			mesh_missing = true
		# Check optional companion .material file diffuse texture if present
		var mat_key := geom_stem + ".material"
		if first_hit.has(mat_key):
			var mat_path := String(first_hit[mat_key])
			if not ("::" in mat_path):
				for tex_name in _extract_material_textures(mat_path):
					var tk := tex_name.to_lower()
					if not first_hit.has(tk) and not first_hit.has(tk.get_basename() + ".dds"):
						missing_textures.append(tex_name)

	var missing_sounds: Array[String] = []
	for snd in sounds:
		if not first_hit.has(snd):
			missing_sounds.append(snd)

	return {
		"odf": key,
		"found": true,
		"path": resolved_path,
		"source": source_id,
		"packed": bool(parsed["packed"]),
		"classLabel": class_label,
		"baseClass": base_class,
		"geometryName": geom,
		"meshPath": mesh_path,
		"meshMissing": mesh_missing,
		"missingTextures": missing_textures,
		"missingSounds": missing_sounds,
		"unitName": unit_name,
		"parentChain": parent_chain,
	}


static func _extract_material_textures(mat_path: String) -> Array[String]:
	var out: Array[String] = []
	var file := FileAccess.open(mat_path, FileAccess.READ)
	if file == null or file.get_length() > 128 * 1024:
		if file != null:
			file.close()
		return out
	var text := file.get_buffer(file.get_length()).get_string_from_ascii()
	file.close()
	var in_tex := false
	for raw in text.split("\n"):
		var trimmed := raw.get_slice("//", 0).strip_edges().to_lower()
		if trimmed.begins_with("["):
			in_tex = trimmed == "[texture]"
		elif in_tex and trimmed.contains("="):
			var k := trimmed.get_slice("=", 0).strip_edges()
			if k == "diffuse":
				var v := trimmed.substr(trimmed.find("=") + 1).strip_edges().trim_prefix('"').trim_suffix('"').get_file()
				if not v.is_empty() and not (v in out):
					out.append(v)
	return out


## Resolves a mission DLL across ordered DLL roots and verifies its exact SHA-256 identity.
static func inspect_dll_identity(dll_name: String, dll_roots: Array[String], target_mod: String = "stock") -> Dictionary:
	var clean := dll_name.strip_edges()
	if clean.is_empty():
		return {
			"requested": "",
			"resolvedPath": "",
			"sha256": "",
			"sizeBytes": 0,
			"matchedMod": "",
			"status": "NONE",
			"detail": "No mission DLL requested.",
		}
	var target_lower := clean.to_lower()
	var found_path := ""
	for root in dll_roots:
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue
		var direct := root.path_join(clean)
		if FileAccess.file_exists(direct):
			found_path = direct
			break
		var idx := get_root_index(root, true, false)
		var fmap: Dictionary = idx["files"]
		if fmap.has(target_lower):
			var matches: Array = fmap[target_lower]
			for m_v in matches:
				var mp := String(m_v)
				if not ("::" in mp) and FileAccess.file_exists(mp):
					found_path = mp
					break
		if not found_path.is_empty():
			break
	if found_path.is_empty():
		return {
			"requested": clean,
			"resolvedPath": "",
			"sha256": "",
			"sizeBytes": 0,
			"matchedMod": "",
			"status": "MISSING",
			"detail": "Mission DLL '%s' was not found in active mission DLL roots." % clean,
		}
	var sha := FileAccess.get_sha256(found_path).to_lower()
	var f := FileAccess.open(found_path, FileAccess.READ)
	var size_bytes := f.get_length() if f != null else 0
	if f != null:
		f.close()
	var sig: Dictionary = KNOWN_DLL_SIGNATURES.get(sha, {})
	var matched_mod := String(sig.get("mod", "unknown")) if not sig.is_empty() else "unknown"
	var tgt := target_mod.strip_edges().to_lower()
	var status := "VERIFIED"
	var detail := ""
	if tgt in ["stock", "vsr", "vrv"]:
		if matched_mod == tgt:
			status = "VERIFIED"
			detail = "Exact %s DLL SHA-256 verified (%s)." % [tgt.to_upper(), sha.left(12)]
		elif matched_mod == "stock" and tgt in ["vsr", "vrv"] and target_lower in ["mpinstant.dll", "stratctf.dll", "luamission.dll"]:
			status = "VERIFIED_INHERITED_STOCK"
			detail = "Inherited Stock %s DLL SHA-256 (%s)." % [clean, sha.left(12)]
		elif matched_mod == "unknown":
			status = "HASH_UNVERIFIED"
			detail = "Mission DLL '%s' (%s) does not match known %s signature; basename alone does not prove %s compatibility." % [
				clean, sha.left(12), tgt.to_upper(), tgt.to_upper()]
		else:
			status = "HASH_MISMATCH"
			detail = "Mission DLL '%s' matches %s (%s), not target mod %s." % [
				clean, matched_mod.to_upper(), sha.left(12), tgt.to_upper()]
	else:
		status = "CUSTOM_PRESENT" if matched_mod == "unknown" else "VERIFIED_KNOWN_BASE"
		detail = "Custom mod resolved DLL '%s' (SHA-256 %s, matched=%s)." % [clean, sha.left(12), matched_mod]
	return {
		"requested": clean,
		"resolvedPath": found_path,
		"sha256": sha,
		"sizeBytes": size_bytes,
		"matchedMod": matched_mod,
		"status": status,
		"detail": detail,
	}
