extends RefCounted
## Dependency-aware asset root indexer with safe read-only DOCP v2 .pak reader,
## staged per-file + targeted content cache invalidation, unified loose/packed
## ODF & material parsing, explicit inspection capability states, and exact
## mission DLL identity verification (SHA-256 + canonical name + BZN ref + mission contract + mod).

const ASSET_EXTENSIONS := [
	"odf", "msh", "fbx", "xsi", "material", "dds", "tga", "png",
	"wav", "ogg", "dll", "lua", "aip",
]
const TARGETED_HASH_EXTENSIONS := ["odf", "material", "dll", "lua"]
const MAX_INDEXED_FILES := 300_000
const MAX_PAK_ENTRIES := 65536
const MAX_TEXT_READ := 256 * 1024
const MAX_PAK_ENTRY_UNPACKED := 4 * 1024 * 1024
const SMALL_ROOT_HASH_LIMIT := 512
const SMALL_MSH_HASH_LIMIT := 64 * 1024
const RACILY_CLEAN_WINDOW_SEC := 2

## Explicit mission DLL verification statuses (Section 3)
const DLL_STATUS_NONE := "NONE"
const DLL_STATUS_VERIFIED_EXACT := "VERIFIED_EXACT"
const DLL_STATUS_VERIFIED_EXPLICIT_INHERITANCE := "VERIFIED_EXPLICIT_INHERITANCE"
const DLL_STATUS_DLL_NAME_MISMATCH := "DLL_NAME_MISMATCH"
const DLL_STATUS_MISSION_PROFILE_MISMATCH := "MISSION_PROFILE_MISMATCH"
const DLL_STATUS_HASH_UNVERIFIED := "HASH_UNVERIFIED"
const DLL_STATUS_HASH_MISMATCH := "HASH_MISMATCH"
const DLL_STATUS_MISSING := "MISSING"

## Explicit ODF / asset inspection capability stages (Section 4)
const INSPECT_MISSING := "MISSING"
const INSPECT_ENTRY_INDEXED := "ENTRY_INDEXED"
const INSPECT_CONTENT_READABLE := "CONTENT_READABLE"
const INSPECT_CONTENT_PARSED := "CONTENT_PARSED"
const INSPECT_DEPENDENCIES_RESOLVED := "DEPENDENCIES_RESOLVED"
const INSPECT_DEPENDENCIES_UNVERIFIED := "DEPENDENCIES_UNVERIFIED"
const INSPECT_ENTRY_CORRUPT := "ENTRY_CORRUPT"

## Verified mission DLL SHA-256 signatures collected from installed BZCC 2.0.185
## Stock, VSR (Workshop 1325933293), and VRV (Workshop 3820486276).
const KNOWN_DLL_SIGNATURES := {
	"415ad6ca656c02972ff5b88c574d51cb508f6574001b848b84c30b776d9b1bc2": {"mod": "stock", "name": "Strategy02.dll", "mission": "strategy", "size": 27136},
	"c3dc76d348ef8a31cfade7b3928e0f650d4bfb62348942177e1bc364470c65ce": {"mod": "stock", "name": "Instant.dll", "mission": "instant", "size": 29696},
	"62f296053c99bb5b871e17b5140ac3b53f75ce6442721219c581611fad9439fc": {"mod": "stock", "name": "mpinstant.dll", "mission": "mpi", "size": 34816},
	"20344ce75d291e68e95692d8b6202b7f7d3ae08c93a3664907d65ec987071046": {"mod": "stock", "name": "deathmatch01.dll", "mission": "duel", "size": 37888},
	"687c1ed92f6eaee882a688f78f75eb7be8972e3f7590db0fc9b0b53e8c56eec6": {"mod": "stock", "name": "StratCTF.dll", "mission": "strategy", "size": 28160},
	"b197f15b12901c9d87a0b80a7b775860a15302320cd33f1b09fa2b8683da57db": {"mod": "stock", "name": "LuaMission.dll", "mission": "lua", "size": 230400},
	"a4b3ce223fc305df88507b07d1e0790ced781df5147ccce4886d776c45c0b6bb": {"mod": "vsr", "name": "Strategy02.dll", "mission": "strategy", "size": 465408},
	"c17c7d1c7fa7a75b87f3350f3b66599e207e9ece580d555b5c7c5051bd7e407d": {"mod": "vsr", "name": "Instant.dll", "mission": "instant", "size": 445952},
	"b982c41694aba3e7d48fe4bc2d145d6d4f0261d529dea17d644212478c5e6020": {"mod": "vsr", "name": "deathmatch01.dll", "mission": "duel", "size": 449536},
	"a7097e937761f2ef81d84693ef537c0102cc359ad3d6a7aa1d7d01a6b98a5a2a": {"mod": "vsr", "name": "LuaMission.dll", "mission": "lua", "size": 433152},
	"afc99de3250ab37dccfbaf099b4983a7a402c0f8ae8d535f63fac7f91297a989": {"mod": "vrv", "name": "Strategy02.dll", "mission": "strategy", "size": 5331968},
	"8879f1e83d507720774d48c196a0f750b40044ad3c80c279ff348436edb79c0d": {"mod": "vrv", "name": "Instant.dll", "mission": "instant", "size": 5287424},
	"f7759194b4798120ed87525cd27c4e6574454fdb2eb67d58cc33cd47a9e79834": {"mod": "vrv", "name": "mpinstant.dll", "mission": "mpi", "size": 1714688},
	"d09c8bfc1e4a71723185e0ebf5f2cb1f4c88821e726396eaa43d45a7743dcd4a": {"mod": "vrv", "name": "deathmatch01.dll", "mission": "duel", "size": 1710080},
	"e3f6e4b5062cfced01f70f81809b83d7bbed1fb9f4ab563b33257fc015fa0130": {"mod": "vrv", "name": "StratCTF.dll", "mission": "strategy", "size": 1703424},
	"65e575b840c5840ebc7df8b21ee35c116c1fd88abe63528be9483f0dbf115d11": {"mod": "vrv", "name": "VrvPrepare.dll", "mission": "custom-dll", "size": 1309184},
}

## Explicit verified DLL inheritance rules (never implicit!).
## VSR ships Strategy02/Instant/deathmatch01/LuaMission, inheriting only mpinstant & StratCTF from Stock.
## VRV ships Strategy02/Instant/mpinstant/deathmatch01/StratCTF/VrvPrepare, inheriting only LuaMission from Stock.
const EXPLICIT_DLL_INHERITANCE := {
	"vsr": {
		"mpinstant.dll": "stock",
		"stratctf.dll": "stock",
	},
	"vrv": {
		"luamission.dll": "stock",
	},
}

const MISSION_CANONICAL_DLL := {
	"strategy": "strategy02.dll",
	"instant": "instant.dll",
	"mpi": "mpinstant.dll",
	"duel": "deathmatch01.dll",
	"lua": "luamission.dll",
}

## Process-local per-root cache keyed by "normalized_path|recurse" -> {stamp, files, odfs, pakMeta, ...}
static var _root_cache: Dictionary = {}
static var _pak_dir_cache: Dictionary = {}
static var _cache_hits: int = 0
static var _cache_misses: int = 0


static func clear_cache() -> void:
	_root_cache.clear()
	_pak_dir_cache.clear()
	_cache_hits = 0
	_cache_misses = 0


static func invalidate_root(root: String) -> void:
	var norm := root.strip_edges().simplify_path().to_lower()
	if norm.is_empty():
		return
	for key: String in _root_cache.keys():
		if key.begins_with(norm + "|"):
			_root_cache.erase(key)
	for pkey: String in _pak_dir_cache.keys():
		if pkey.begins_with(norm):
			_pak_dir_cache.erase(pkey)


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


static func _fast_file_length(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var length := f.get_length()
	f.close()
	return length


static func _bounded_content_hash(path: String, max_bytes: int = MAX_TEXT_READ) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var length := f.get_length()
	if length > max_bytes:
		f.close()
		return ""
	var buf := f.get_buffer(length)
	f.close()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf)
	return ctx.finish().hex_encode().left(16)


## Computes a deterministic freshness stamp over root identity, directory mtimes,
## and EVERY tracked loose asset & DOCP .pak entry (relative path + size + mtime).
## Applies staged targeted hashing for small roots and racily-clean entries (within 2s)
## so same-size edits and timestamp collisions invalidate immediately without hashing
## giant Workshop media trees on every check.
static func compute_root_stamp(root: String, recurse: bool = true) -> String:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return "missing"
	var norm := root.simplify_path()
	var now_sec := int(Time.get_unix_time_from_system())
	var parts := PackedStringArray()
	parts.append("root:%s:%d" % [norm.to_lower(), FileAccess.get_modified_time(norm)])

	var tracked_candidates: Array[Dictionary] = []
	var pending: Array[String] = [norm]
	var dir_count := 0
	var total_tracked := 0

	while not pending.is_empty() and dir_count < 4096:
		var current: String = pending.pop_back()
		dir_count += 1
		var handle := DirAccess.open(current)
		if handle == null:
			continue
		var rel_dir := current.substr(norm.length()).replace("\\", "/").to_lower()
		var files := Array(handle.get_files())
		files.sort()
		var file_entries := PackedStringArray()
		for fname_v in files:
			var fname := String(fname_v)
			var ext := fname.get_extension().to_lower()
			if not (ext in ASSET_EXTENSIONS) and ext != "pak":
				continue
			var fp := current.path_join(fname)
			var flen := _fast_file_length(fp)
			var mtime := FileAccess.get_modified_time(fp)
			var rel_file := (rel_dir + "/" + fname.to_lower()).lstrip("/")
			total_tracked += 1
			var rec := "f:%s:%d:%d" % [rel_file, flen, mtime]
			var is_racily_clean := absi(now_sec - mtime) <= RACILY_CLEAN_WINDOW_SEC
			if is_racily_clean and flen >= 0 and flen <= MAX_TEXT_READ:
				rec += ":h=" + _bounded_content_hash(fp, MAX_TEXT_READ)
			elif total_tracked <= SMALL_ROOT_HASH_LIMIT and flen >= 0:
				if (ext in TARGETED_HASH_EXTENSIONS and flen <= MAX_TEXT_READ) or (ext == "msh" and flen <= SMALL_MSH_HASH_LIMIT) or (ext == "pak" and flen <= MAX_TEXT_READ):
					tracked_candidates.append({"path": fp, "rel": rel_file, "limit": MAX_TEXT_READ if ext != "msh" else SMALL_MSH_HASH_LIMIT})
			file_entries.append(rec)
		parts.append("d:%s:%d:%s" % [rel_dir, FileAccess.get_modified_time(current), ",".join(file_entries)])
		if recurse:
			var dirs := Array(handle.get_directories())
			dirs.sort()
			dirs.reverse()
			for sub_v in dirs:
				var sub := String(sub_v)
				if sub.begins_with(".") or handle.is_link(sub):
					continue
				pending.append(current.path_join(sub))

	# Small mutable roots (map folders, linked folders, custom mods, test fixtures):
	# include targeted content fingerprints for compatibility-critical files to defeat
	# same-size + forced historical timestamp collisions while staying zero-cost on huge installs.
	if total_tracked <= SMALL_ROOT_HASH_LIMIT and not tracked_candidates.is_empty():
		var h_parts := PackedStringArray()
		for cand in tracked_candidates:
			var h := _bounded_content_hash(String(cand["path"]), int(cand["limit"]))
			h_parts.append("%s=%s" % [String(cand["rel"]), h])
		h_parts.sort()
		parts.append("ch:" + ",".join(h_parts))

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _valid_pak_entry_name(name: String) -> bool:
	if name.is_empty() or name.length() > 255:
		return false
	if ".." in name or name.begins_with("/") or name.begins_with("\\") or ":" in name:
		return false
	for i in name.length():
		var cp := name.unicode_at(i)
		if cp < 32 or cp > 126:
			return false
	return true


## Safely parses a DOCP v2 .pak directory table with full bounds, offset, size,
## truncation, and duplicate detection. Strictly read-only; never extracts to disk.
static func read_docp_pak_directory(pak_path: String) -> Dictionary:
	var result := {
		"ok": false,
		"pakPath": pak_path,
		"sizeBytes": 0,
		"version": 0,
		"declaredCount": 0,
		"dirOffset": 0,
		"entries": {},
		"entryList": [],
		"duplicateEntries": [],
		"corruptEntries": [],
		"truncated": false,
		"corrupt": false,
		"error": "",
	}
	if pak_path.is_empty() or not FileAccess.file_exists(pak_path):
		result["error"] = "PAK file missing."
		return result
	var flen := _fast_file_length(pak_path)
	var mtime := FileAccess.get_modified_time(pak_path)
	var cache_key := "%s|%d|%d" % [pak_path.simplify_path().to_lower(), flen, mtime]
	if flen <= MAX_TEXT_READ:
		cache_key += "|" + _bounded_content_hash(pak_path, MAX_TEXT_READ)
	if _pak_dir_cache.has(cache_key):
		return _pak_dir_cache[cache_key]

	var file := FileAccess.open(pak_path, FileAccess.READ)
	if file == null:
		result["error"] = "Cannot open PAK file for reading."
		return result
	var total := file.get_length()
	result["sizeBytes"] = total
	if total < 32:
		file.close()
		result["corrupt"] = true
		result["truncated"] = true
		result["error"] = "PAK archive truncated (< 32-byte DOCP header)."
		_pak_dir_cache[cache_key] = result
		return result
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != "DOCP":
		file.close()
		result["corrupt"] = true
		result["error"] = "Not a DOCP archive (magic='%s')." % magic
		_pak_dir_cache[cache_key] = result
		return result
	var ver := file.get_32()
	file.get_32() # header flags
	file.get_32() # data end
	var count := file.get_32()
	var dir_offset := file.get_32()
	result["version"] = ver
	result["declaredCount"] = count
	result["dirOffset"] = dir_offset
	if ver != 2:
		file.close()
		result["corrupt"] = true
		result["error"] = "Unsupported DOCP version %d (expected 2)." % ver
		_pak_dir_cache[cache_key] = result
		return result
	if count > MAX_PAK_ENTRIES:
		file.close()
		result["corrupt"] = true
		result["error"] = "DOCP entry count %d exceeds safe limit %d." % [count, MAX_PAK_ENTRIES]
		_pak_dir_cache[cache_key] = result
		return result
	if count == 0:
		file.close()
		result["ok"] = true
		_pak_dir_cache[cache_key] = result
		return result
	if dir_offset < 32 or dir_offset >= total:
		file.close()
		result["corrupt"] = true
		result["truncated"] = true
		result["error"] = "DOCP directory offset %d out of archive bounds (%d)." % [dir_offset, total]
		_pak_dir_cache[cache_key] = result
		return result

	file.seek(dir_offset)
	var entries_by_key := {}
	var entry_list: Array[Dictionary] = []
	var dup_entries: Array[String] = []
	var corrupt_entries: Array[Dictionary] = []

	for i in count:
		if file.get_position() + 5 > total:
			result["truncated"] = true
			result["corrupt"] = true
			result["error"] = "DOCP directory truncated at entry %d/%d." % [i, count]
			break
		var entry_flags := file.get_32()
		var name_len := file.get_8()
		if name_len <= 0 or file.get_position() + name_len + 12 > total:
			result["truncated"] = true
			result["corrupt"] = true
			result["error"] = "DOCP directory entry %d truncated or invalid name length %d." % [i, name_len]
			break
		var entry_name := file.get_buffer(name_len).get_string_from_ascii()
		var data_offset := file.get_32()
		var packed_size := file.get_32()
		var unpacked_size := file.get_32()

		var entry_corrupt := false
		var entry_err := ""
		var empty_stub := (data_offset == 0 and packed_size == 0 and unpacked_size == 0)
		if not _valid_pak_entry_name(entry_name):
			entry_corrupt = true
			entry_err = "Invalid or unsafe DOCP entry name."
		elif not empty_stub:
			if data_offset < 32 or data_offset >= total:
				entry_corrupt = true
				entry_err = "Entry offset %d out of bounds (%d)." % [data_offset, total]
			elif packed_size > total - data_offset:
				entry_corrupt = true
				entry_err = "Entry range [%d..%d) exceeds archive size %d." % [data_offset, data_offset + packed_size, total]
			elif dir_offset > data_offset and data_offset + packed_size > dir_offset:
				entry_corrupt = true
				entry_err = "Entry data overlaps DOCP directory table."
			elif packed_size == 0 and unpacked_size > 0:
				entry_corrupt = true
				entry_err = "Entry has zero packed size for non-zero unpacked size %d." % unpacked_size
			elif unpacked_size > 0 and packed_size > unpacked_size + 1024 + (unpacked_size >> 4):
				entry_corrupt = true
				entry_err = "Entry packed size %d implausibly exceeds unpacked size %d." % [packed_size, unpacked_size]

		var oversized := unpacked_size > MAX_PAK_ENTRY_UNPACKED
		var compressed := (not empty_stub) and (packed_size > 0) and (packed_size != unpacked_size or (entry_flags & 1) != 0)
		var leaf := entry_name.replace("\\", "/").get_file().to_lower()
		var meta := {
			"name": entry_name,
			"leaf": leaf,
			"flags": entry_flags,
			"offset": data_offset,
			"packedSize": packed_size,
			"unpackedSize": unpacked_size,
			"compressed": compressed,
			"emptyStub": empty_stub,
			"oversized": oversized,
			"corrupt": entry_corrupt,
			"error": entry_err,
			"provenance": "%s::%s" % [pak_path, entry_name],
		}
		entry_list.append(meta)
		if entry_corrupt:
			corrupt_entries.append(meta)
		if entries_by_key.has(leaf):
			if not (leaf in dup_entries):
				dup_entries.append(leaf)
			# Keep first valid entry (first-hit precedence inside archive), record duplicate
			var prev: Dictionary = entries_by_key[leaf]
			if bool(prev.get("corrupt", false)) and not entry_corrupt:
				entries_by_key[leaf] = meta
		else:
			entries_by_key[leaf] = meta

	file.close()
	result["entries"] = entries_by_key
	result["entryList"] = entry_list
	result["duplicateEntries"] = dup_entries
	result["corruptEntries"] = corrupt_entries
	result["ok"] = not bool(result["truncated"]) and entry_list.size() == count
	_pak_dir_cache[cache_key] = result
	return result


## Reads a single entry's raw/decompressed bytes from a DOCP v2 .pak strictly in memory.
## Enforces bounds, max unpacked size, zlib header check, and exact decompressed length.
static func read_docp_pak_entry(pak_path: String, entry_name: String, max_unpacked: int = MAX_PAK_ENTRY_UNPACKED) -> Dictionary:
	var out := {
		"ok": false,
		"status": INSPECT_ENTRY_INDEXED,
		"bytes": PackedByteArray(),
		"provenance": "%s::%s" % [pak_path, entry_name],
		"compressed": false,
		"compression": "none",
		"packedSize": 0,
		"unpackedSize": 0,
		"offset": 0,
		"duplicateInPak": false,
		"error": "",
	}
	var dir_info := read_docp_pak_directory(pak_path)
	if bool(dir_info["truncated"]) and (dir_info["entries"] as Dictionary).is_empty():
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["error"] = String(dir_info["error"])
		return out
	var leaf := entry_name.replace("\\", "/").get_file().to_lower()
	var entries: Dictionary = dir_info["entries"]
	if not entries.has(leaf):
		out["status"] = INSPECT_MISSING if not bool(dir_info["corrupt"]) else INSPECT_ENTRY_CORRUPT
		out["error"] = String(dir_info["error"]) if bool(dir_info["corrupt"]) else ("Entry '%s' not found in PAK." % entry_name)
		return out
	var meta: Dictionary = entries[leaf]
	out["offset"] = int(meta["offset"])
	out["packedSize"] = int(meta["packedSize"])
	out["unpackedSize"] = int(meta["unpackedSize"])
	out["compressed"] = bool(meta["compressed"])
	out["duplicateInPak"] = leaf in (dir_info["duplicateEntries"] as Array)
	if bool(meta["corrupt"]):
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["error"] = String(meta["error"])
		return out
	if bool(meta["emptyStub"]):
		out["status"] = INSPECT_ENTRY_INDEXED
		out["error"] = "PAK directory entry has no stored payload (metadata-only / empty entry)."
		return out
	var unpacked_size := int(meta["unpackedSize"])
	var limit := mini(max_unpacked, MAX_PAK_ENTRY_UNPACKED)
	if unpacked_size > limit:
		out["status"] = INSPECT_ENTRY_INDEXED
		out["error"] = "PAK entry unpacked size %d exceeds safe read limit %d." % [unpacked_size, limit]
		return out
	var file := FileAccess.open(pak_path, FileAccess.READ)
	if file == null:
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["error"] = "Unable to reopen PAK archive."
		return out
	var total := file.get_length()
	var offset := int(meta["offset"])
	var packed_size := int(meta["packedSize"])
	if offset + packed_size > total:
		file.close()
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["error"] = "PAK entry exceeds live archive size."
		return out
	file.seek(offset)
	var raw := file.get_buffer(packed_size)
	file.close()
	if raw.size() != packed_size:
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["error"] = "Short read on PAK entry payload."
		return out
	if not bool(meta["compressed"]):
		# Even when packedSize == unpackedSize and flags == 0, check if payload is actually zlib-wrapped
		if raw.size() >= 6:
			var z_cmf := int(raw[0])
			var z_flg := int(raw[1])
			if ((z_cmf & 0x0f) == 8) and (((z_cmf << 8) | z_flg) % 31 == 0):
				var try_dec := raw.decompress(unpacked_size, FileAccess.COMPRESSION_DEFLATE)
				if try_dec.size() == unpacked_size:
					out["ok"] = true
					out["status"] = INSPECT_CONTENT_READABLE
					out["bytes"] = try_dec
					out["compressed"] = true
					out["compression"] = "zlib"
					return out
		out["ok"] = true
		out["status"] = INSPECT_CONTENT_READABLE
		out["bytes"] = raw
		out["compression"] = "stored"
		return out
	# Compressed DOCP v2 entry: verify standard zlib header (RFC 1950: CM=8, FCHECK % 31 == 0)
	if raw.size() < 2:
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["error"] = "Compressed PAK entry too short."
		return out
	var cmf := int(raw[0])
	var flg := int(raw[1])
	var is_zlib := ((cmf & 0x0f) == 8) and (((cmf << 8) | flg) % 31 == 0)
	if not is_zlib:
		out["status"] = INSPECT_ENTRY_INDEXED
		out["compression"] = "unsupported"
		out["error"] = "Unsupported PAK compression header (0x%02x 0x%02x); expected zlib." % [cmf, flg]
		return out
	var decompressed := raw.decompress(unpacked_size, FileAccess.COMPRESSION_DEFLATE)
	if decompressed.size() != unpacked_size:
		out["status"] = INSPECT_ENTRY_CORRUPT
		out["compression"] = "zlib"
		out["error"] = "Zlib decompression failed or size mismatch (got %d, expected %d)." % [decompressed.size(), unpacked_size]
		return out
	out["ok"] = true
	out["status"] = INSPECT_CONTENT_READABLE
	out["bytes"] = decompressed
	out["compression"] = "zlib"
	return out


## Reads a DOCP v2 .pak directory table and returns asset entries as "pak_path::entry_name".
static func read_docp_pak_entries(pak_path: String) -> PackedStringArray:
	var entries := PackedStringArray()
	var dir_info := read_docp_pak_directory(pak_path)
	var seen := {}
	for meta_v in dir_info.get("entryList", []):
		var meta: Dictionary = meta_v
		var entry_name := String(meta.get("name", ""))
		if not _valid_pak_entry_name(entry_name):
			continue
		var ext := entry_name.get_extension().to_lower()
		if ext in ASSET_EXTENSIONS:
			var prov := String(meta["provenance"])
			if not seen.has(prov):
				seen[prov] = true
				entries.append(prov)
	return entries


## Builds an asset index for one root folder (loose files + DOCP v2 .pak archives).
## Loose files take precedence over .pak entries within the same root (matching BZCC VFS).
## Intra-root duplicates are preserved instead of silently hidden.
static func build_root_index(root: String, recurse: bool = true) -> Dictionary:
	var files_map := {}
	var odf_map := {}
	var pak_diagnostics: Array[Dictionary] = []
	var pak_count := 0
	var file_count := 0
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return {"root": root, "exists": false, "files": files_map, "odfs": odf_map, "pakCount": 0, "fileCount": 0, "pakDiagnostics": pak_diagnostics}
	var norm := root.simplify_path()
	var pending: Array[String] = [norm]
	var deferred_paks: Array[String] = []
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
				deferred_paks.append(full)
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

	# Index .pak archives AFTER loose files so loose assets always take precedence over packed entries
	deferred_paks.sort()
	for pak_full in deferred_paks:
		if file_count >= MAX_INDEXED_FILES:
			break
		pak_count += 1
		var dir_info := read_docp_pak_directory(pak_full)
		if bool(dir_info["corrupt"]) or bool(dir_info["truncated"]) or not (dir_info["duplicateEntries"] as Array).is_empty() or not (dir_info["corruptEntries"] as Array).is_empty():
			pak_diagnostics.append({
				"pakPath": pak_full,
				"corrupt": bool(dir_info["corrupt"]),
				"truncated": bool(dir_info["truncated"]),
				"duplicateEntries": dir_info["duplicateEntries"],
				"corruptEntryCount": (dir_info["corruptEntries"] as Array).size(),
				"error": String(dir_info["error"]),
			})
		for meta_v in dir_info.get("entryList", []):
			var meta: Dictionary = meta_v
			var entry_name := String(meta.get("name", ""))
			if not _valid_pak_entry_name(entry_name):
				continue
			var ext := entry_name.get_extension().to_lower()
			if not (ext in ASSET_EXTENSIONS):
				continue
			var leaf := String(meta["leaf"])
			if leaf.is_empty():
				continue
			var pak_entry := String(meta["provenance"])
			if not files_map.has(leaf):
				files_map[leaf] = []
			(files_map[leaf] as Array).append(pak_entry)
			file_count += 1
			if leaf.ends_with(".odf"):
				if not odf_map.has(leaf):
					odf_map[leaf] = []
				(odf_map[leaf] as Array).append(pak_entry)

	return {
		"root": norm,
		"exists": true,
		"files": files_map,
		"odfs": odf_map,
		"pakCount": pak_count,
		"fileCount": file_count,
		"pakDiagnostics": pak_diagnostics,
	}


static func get_root_index(root: String, recurse: bool = true, bypass_cache: bool = false) -> Dictionary:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return {"root": root, "exists": false, "files": {}, "odfs": {}, "pakCount": 0, "fileCount": 0, "pakDiagnostics": [], "stamp": "missing"}
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
## Precedence is first-root-wins (and loose-before-packed inside each root),
## while recording intra-root duplicates, cross-root overrides, and PAK diagnostics.
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
	var pak_diagnostics: Array[Dictionary] = []
	var root_stamps := PackedStringArray()

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
		root_stamps.append("%s=%s" % [rkey, String(idx.get("stamp", ""))])
		ordered.append({"path": norm, "source": source_id, "index": idx, "stamp": String(idx.get("stamp", ""))})
		for pd_v in idx.get("pakDiagnostics", []):
			pak_diagnostics.append(pd_v as Dictionary)
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

	var composite_ctx := HashingContext.new()
	composite_ctx.start(HashingContext.HASH_SHA256)
	composite_ctx.update("\n".join(root_stamps).to_utf8_buffer())
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
		"pakDiagnostics": pak_diagnostics,
		"compositeStamp": composite_ctx.finish().hex_encode(),
	}


## Reads a loose or packed ("pak_path::entry_name") text/asset file strictly read-only.
static func read_asset_bytes(path: String, max_bytes: int = MAX_TEXT_READ) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "status": INSPECT_MISSING, "packed": false, "bytes": PackedByteArray(), "error": "Empty path."}
	if "::" in path:
		var sep := path.find("::")
		var pak_path := path.substr(0, sep)
		var entry_name := path.substr(sep + 2)
		var res := read_docp_pak_entry(pak_path, entry_name, max_bytes)
		res["packed"] = true
		return res
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "status": INSPECT_MISSING, "packed": false, "bytes": PackedByteArray(), "error": "Cannot open asset file."}
	var flen := file.get_length()
	if flen > max_bytes:
		file.close()
		return {"ok": false, "status": INSPECT_ENTRY_INDEXED, "packed": false, "bytes": PackedByteArray(), "error": "Asset file exceeds max read limit (%d > %d)." % [flen, max_bytes]}
	var data := file.get_buffer(flen)
	file.close()
	return {"ok": true, "status": INSPECT_CONTENT_READABLE, "packed": false, "bytes": data, "error": ""}


## Single shared ODF text parser used by both loose and packed ODF files.
static func parse_odf_text(text: String, path: String = "", packed: bool = false, provenance: Dictionary = {}) -> Dictionary:
	var out := {
		"ok": false,
		"path": path,
		"packed": packed,
		"inspectionStatus": INSPECT_CONTENT_READABLE,
		"contentReadable": true,
		"contentParsed": false,
		"readError": "",
		"provenance": provenance,
		"classLabel": "",
		"geometryName": "",
		"geometryScale": 1.0,
		"unitName": "",
		"scrapCost": -1,
		"scrapValue": -1,
		"maxHealth": -1,
		"sounds": [],
		"textures": [],
		"sections": {},
	}
	var section := ""
	var sounds: Array[String] = []
	var seen_sounds := {}
	var textures: Array[String] = []
	var seen_textures := {}
	var sections := {}
	var parsed_keys := 0
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
		parsed_keys += 1
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
			var s_clean := val.strip_edges().replace("\\", "/").get_file().to_lower()
			var ext := s_clean.get_extension()
			if ext in ["wav", "ogg"] and not seen_sounds.has(s_clean):
				seen_sounds[s_clean] = true
				sounds.append(s_clean)
		if key.ends_with("texture") or key.begins_with("texture") or key == "icon":
			var t_clean := val.strip_edges().replace("\\", "/").get_file().to_lower()
			var text_ext := t_clean.get_extension()
			if text_ext in ["dds", "tga", "png"] and not seen_textures.has(t_clean):
				seen_textures[t_clean] = true
				textures.append(t_clean)
	out["sounds"] = sounds
	out["textures"] = textures
	out["sections"] = sections
	var is_parsed := parsed_keys > 0 or not sections.is_empty()
	out["contentParsed"] = is_parsed
	out["ok"] = is_parsed
	out["inspectionStatus"] = INSPECT_CONTENT_PARSED if is_parsed else INSPECT_CONTENT_READABLE
	return out


## Parses an ODF file (loose on disk OR packed inside DOCP v2 .pak) using the
## single shared ODF parser. Distinguishes ENTRY_INDEXED, CONTENT_READABLE,
## CONTENT_PARSED, and ENTRY_CORRUPT explicitly.
static func parse_odf_file(path: String) -> Dictionary:
	var is_packed := "::" in path
	var fallback := {
		"ok": false,
		"path": path,
		"packed": is_packed,
		"inspectionStatus": INSPECT_MISSING if path.is_empty() else INSPECT_ENTRY_INDEXED,
		"contentReadable": false,
		"contentParsed": false,
		"readError": "",
		"provenance": {},
		"classLabel": "",
		"geometryName": "",
		"geometryScale": 1.0,
		"unitName": "",
		"scrapCost": -1,
		"scrapValue": -1,
		"maxHealth": -1,
		"sounds": [],
		"textures": [],
		"sections": {},
	}
	if path.is_empty():
		return fallback
	var read_res := read_asset_bytes(path, MAX_TEXT_READ)
	if not bool(read_res.get("ok", false)):
		fallback["inspectionStatus"] = String(read_res.get("status", INSPECT_ENTRY_INDEXED))
		fallback["readError"] = String(read_res.get("error", ""))
		if is_packed:
			fallback["provenance"] = {
				"offset": int(read_res.get("offset", 0)),
				"packedSize": int(read_res.get("packedSize", 0)),
				"unpackedSize": int(read_res.get("unpackedSize", 0)),
				"compression": String(read_res.get("compression", "none")),
				"duplicateInPak": bool(read_res.get("duplicateInPak", false)),
			}
		return fallback
	var buf: PackedByteArray = read_res["bytes"]
	var text := buf.get_string_from_ascii()
	var prov := {}
	if is_packed:
		prov = {
			"offset": int(read_res.get("offset", 0)),
			"packedSize": int(read_res.get("packedSize", 0)),
			"unpackedSize": int(read_res.get("unpackedSize", 0)),
			"compression": String(read_res.get("compression", "stored")),
			"duplicateInPak": bool(read_res.get("duplicateInPak", false)),
		}
	return parse_odf_text(text, path, is_packed, prov)


## Resolves transitive ODF inheritance (up to depth 12, cycle-safe, both loose
## and packed parent ODFs) and checks mesh, material, texture, and sound references.
## Reports explicit capability stage (`inspectionStatus`) instead of collapsing to `found`.
static func inspect_odf_dependencies(odf_name: String, layered_index: Dictionary, depth: int = 0, visited: Dictionary = {}) -> Dictionary:
	var key := normalize_key(odf_name, "odf")
	var first_hit: Dictionary = layered_index.get("firstHit", {})
	var first_source: Dictionary = layered_index.get("firstSource", {})
	if key.is_empty() or not first_hit.has(key):
		return {
			"odf": key,
			"found": false,
			"entryIndexed": false,
			"contentReadable": false,
			"contentParsed": false,
			"dependenciesResolved": false,
			"inspectionStatus": INSPECT_MISSING,
			"readError": "ODF not found in mounted asset roots.",
			"unverifiedReasons": ["ODF '%s' not found." % key],
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
			"missingParents": [],
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
	var seen_sounds := {}
	for s_v in parsed["sounds"]:
		var s := String(s_v)
		if not seen_sounds.has(s):
			seen_sounds[s] = true
			sounds.append(s)
	var odf_textures: Array[String] = []
	var seen_tex := {}
	for t_v in parsed.get("textures", []):
		var t := String(t_v)
		if not seen_tex.has(t):
			seen_tex[t] = true
			odf_textures.append(t)

	var content_readable := bool(parsed.get("contentReadable", false))
	var content_parsed := bool(parsed.get("contentParsed", false))
	var read_status := String(parsed.get("inspectionStatus", INSPECT_ENTRY_INDEXED))
	var read_error := String(parsed.get("readError", ""))
	var unverified_reasons: Array[String] = []
	var missing_parents: Array[String] = []
	var parent_corrupt := false

	if not content_readable:
		if not read_error.is_empty():
			unverified_reasons.append(read_error)
		else:
			unverified_reasons.append("Entry indexed at '%s' but content could not be read." % resolved_path)
	elif not content_parsed:
		unverified_reasons.append("ODF content readable but contained no recognizable INI sections/keys.")

	var next_visited := visited.duplicate()
	next_visited[key] = true

	if content_parsed and depth < 12 and not class_label.is_empty():
		var parent_key := normalize_key(class_label, "odf")
		if parent_key != key and not next_visited.has(parent_key) and first_hit.has(parent_key):
			var parent_info := inspect_odf_dependencies(parent_key, layered_index, depth + 1, next_visited)
			if geom.is_empty():
				geom = String(parent_info.get("geometryName", ""))
			if unit_name.is_empty():
				unit_name = String(parent_info.get("unitName", ""))
			if not String(parent_info.get("baseClass", "")).is_empty():
				base_class = String(parent_info["baseClass"])
			for pc_v in parent_info.get("parentChain", []):
				var pc := String(pc_v)
				if not (pc in parent_chain):
					parent_chain.append(pc)
			for ps_v in parent_info.get("missingSounds", []):
				var ps := String(ps_v)
				if not seen_sounds.has(ps):
					seen_sounds[ps] = true
					sounds.append(ps)
			var p_status := String(parent_info.get("inspectionStatus", ""))
			if p_status == INSPECT_ENTRY_CORRUPT:
				parent_corrupt = true
				unverified_reasons.append("Parent ODF '%s' is corrupt: %s" % [parent_key, String(parent_info.get("readError", ""))])
			elif p_status in [INSPECT_ENTRY_INDEXED, INSPECT_CONTENT_READABLE, INSPECT_DEPENDENCIES_UNVERIFIED]:
				for pr_v in parent_info.get("unverifiedReasons", []):
					var pr := String(pr_v)
					if not (pr in unverified_reasons):
						unverified_reasons.append(pr)
		elif parent_key != key and next_visited.has(parent_key):
			unverified_reasons.append("Circular ODF inheritance detected at '%s'." % parent_key)
		elif parent_key != key and not first_hit.has(parent_key):
			missing_parents.append(parent_key)
			unverified_reasons.append("Parent ODF '%s' named by classLabel is missing from mounted roots." % parent_key)

	var mesh_path := ""
	var mesh_missing := false
	var missing_textures: Array[String] = []
	if content_parsed and not geom.is_empty():
		var geom_lower := geom.replace("\\", "/").get_file().to_lower()
		var geom_stem := geom_lower.get_basename()
		var msh_key := geom_stem + ".msh"
		if first_hit.has(msh_key):
			mesh_path = String(first_hit[msh_key])
		elif first_hit.has(geom_lower):
			mesh_path = String(first_hit[geom_lower])
		else:
			mesh_missing = true
			unverified_reasons.append("Missing geometry mesh '%s'." % geom)
		# Check optional companion .material file diffuse textures (both loose AND packed!)
		var mat_key := geom_stem + ".material"
		if first_hit.has(mat_key):
			var mat_path := String(first_hit[mat_key])
			var mat_read := _extract_material_textures_checked(mat_path)
			if not bool(mat_read["ok"]):
				unverified_reasons.append("Material '%s' unreadable (%s)." % [mat_key, String(mat_read["error"])])
			else:
				for tex_name in mat_read["textures"]:
					var tk := String(tex_name).to_lower()
					if not first_hit.has(tk) and not first_hit.has(tk.get_basename() + ".dds") and not first_hit.has(tk.get_basename() + ".tga") and not first_hit.has(tk.get_basename() + ".png"):
						if not (String(tex_name) in missing_textures):
							missing_textures.append(String(tex_name))

	for odf_tex in odf_textures:
		if not first_hit.has(odf_tex) and not first_hit.has(odf_tex.get_basename() + ".dds") and not first_hit.has(odf_tex.get_basename() + ".tga") and not first_hit.has(odf_tex.get_basename() + ".png"):
			if not (odf_tex in missing_textures):
				missing_textures.append(odf_tex)

	var missing_sounds: Array[String] = []
	for snd in sounds:
		if not first_hit.has(snd):
			missing_sounds.append(snd)

	if not missing_textures.is_empty():
		unverified_reasons.append("Missing texture(s): %s." % ", ".join(missing_textures))
	if not missing_sounds.is_empty():
		unverified_reasons.append("Missing sound(s): %s." % ", ".join(missing_sounds))

	var final_status := INSPECT_DEPENDENCIES_RESOLVED
	if read_status == INSPECT_ENTRY_CORRUPT or parent_corrupt:
		final_status = INSPECT_ENTRY_CORRUPT
	elif not content_readable:
		final_status = INSPECT_ENTRY_INDEXED
	elif not content_parsed:
		final_status = INSPECT_CONTENT_READABLE
	elif mesh_missing or not missing_textures.is_empty() or not missing_sounds.is_empty() or not missing_parents.is_empty() or not unverified_reasons.is_empty():
		final_status = INSPECT_DEPENDENCIES_UNVERIFIED

	return {
		"odf": key,
		"found": true,
		"entryIndexed": true,
		"contentReadable": content_readable,
		"contentParsed": content_parsed,
		"dependenciesResolved": final_status == INSPECT_DEPENDENCIES_RESOLVED,
		"inspectionStatus": final_status,
		"readError": read_error,
		"unverifiedReasons": unverified_reasons,
		"provenance": parsed.get("provenance", {}),
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
		"missingParents": missing_parents,
		"unitName": unit_name,
		"parentChain": parent_chain,
	}


static func _extract_material_textures_text(text: String) -> Array[String]:
	var out: Array[String] = []
	var in_tex := false
	for raw in text.split("\n"):
		var trimmed := raw.get_slice("//", 0).strip_edges().to_lower()
		if trimmed.begins_with("["):
			in_tex = trimmed == "[texture]"
		elif in_tex and trimmed.contains("="):
			var k := trimmed.get_slice("=", 0).strip_edges()
			if k in ["diffuse", "normal", "specular", "emissive"]:
				var v := trimmed.substr(trimmed.find("=") + 1).strip_edges().trim_prefix('"').trim_suffix('"').replace("\\", "/").get_file()
				if not v.is_empty() and not (v in out):
					out.append(v)
	return out


static func _extract_material_textures_checked(mat_path: String) -> Dictionary:
	var read_res := read_asset_bytes(mat_path, 128 * 1024)
	if not bool(read_res.get("ok", false)):
		return {"ok": false, "textures": [] as Array[String], "error": String(read_res.get("error", "unreadable material"))}
	var buf: PackedByteArray = read_res["bytes"]
	return {"ok": true, "textures": _extract_material_textures_text(buf.get_string_from_ascii()), "error": ""}


static func _extract_material_textures(mat_path: String) -> Array[String]:
	return _extract_material_textures_checked(mat_path)["textures"]


## Always locates and SHA-256-verifies live DLL bytes on disk (never trusts cached DLL hash).
## Verifies ALL FIVE dimensions jointly:
##   SHA256 + canonical DLL filename + actual BZN reference + expected mission contract + ModProfile.
## Explicit states: VERIFIED_EXACT, VERIFIED_EXPLICIT_INHERITANCE, DLL_NAME_MISMATCH,
##   MISSION_PROFILE_MISMATCH, HASH_UNVERIFIED, HASH_MISMATCH, MISSING (and NONE).
static func inspect_dll_identity(dll_name: String, dll_roots: Array[String], target_mod: String = "stock", expected_dll: String = "", mission_profile: String = "", actual_bzn_dll: String = "__UNSET__") -> Dictionary:
	var clean := dll_name.strip_edges()
	var exp_clean := expected_dll.strip_edges()
	var mis_clean := mission_profile.strip_edges().to_lower()
	var tgt := target_mod.strip_edges().to_lower()
	var actual_ref := clean if actual_bzn_dll == "__UNSET__" else actual_bzn_dll.strip_edges()

	# If mission_profile implies an expected canonical DLL and expected_dll wasn't supplied, derive it.
	if exp_clean.is_empty() and MISSION_CANONICAL_DLL.has(mis_clean):
		exp_clean = String(MISSION_CANONICAL_DLL[mis_clean])

	var base_result := {
		"requested": clean,
		"actualBznDll": actual_ref,
		"expected": exp_clean,
		"missionProfile": mis_clean,
		"targetMod": tgt,
		"resolvedPath": "",
		"canonicalName": "",
		"sha256": "",
		"sizeBytes": 0,
		"matchedMod": "",
		"verified": false,
		"knownSignature": false,
		"semanticState": "UNKNOWN",
		"status": DLL_STATUS_NONE,
		"detail": "",
	}

	# Blank / no-DLL case
	if clean.is_empty() and exp_clean.is_empty() and actual_ref.is_empty():
		base_result["verified"] = true
		base_result["semanticState"] = "NONE"
		base_result["status"] = DLL_STATUS_NONE
		base_result["detail"] = "No mission DLL requested or expected."
		return base_result

	# Check explicit mission contract vs actual BZN reference mismatch BEFORE declaring verified
	var mission_ref_mismatch := false
	var mission_mismatch_reason := ""
	if not exp_clean.is_empty():
		if actual_ref.is_empty():
			mission_ref_mismatch = true
			mission_mismatch_reason = "BZN embeds no mission DLL, but mission profile '%s' requires '%s'." % [mis_clean if not mis_clean.is_empty() else "selected", exp_clean]
		elif actual_ref.nocasecmp_to(exp_clean) != 0:
			mission_ref_mismatch = true
			mission_mismatch_reason = "BZN embeds mission DLL '%s', contradicting mission profile '%s' which expects '%s'." % [actual_ref, mis_clean if not mis_clean.is_empty() else "selected", exp_clean]
	elif mis_clean == "blank" and not actual_ref.is_empty():
		mission_ref_mismatch = true
		mission_mismatch_reason = "BZN embeds mission DLL '%s', contradicting 'blank' mission profile (expects no mission DLL)." % actual_ref

	# Locate the DLL file live across ordered DLL roots
	var lookup_name := clean if not clean.is_empty() else exp_clean
	var target_lower := lookup_name.to_lower()
	var found_path := ""
	for root in dll_roots:
		if root.is_empty() or not DirAccess.dir_exists_absolute(root):
			continue
		var direct := root.path_join(lookup_name)
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
		if mission_ref_mismatch and actual_ref.is_empty():
			base_result["status"] = DLL_STATUS_MISSION_PROFILE_MISMATCH
			base_result["detail"] = mission_mismatch_reason
			return base_result
		base_result["status"] = DLL_STATUS_MISSING
		base_result["detail"] = "Mission DLL '%s' was not found in active mission DLL roots." % lookup_name
		return base_result

	# Always compute live SHA-256 directly from disk bytes (never trust cache for security-critical DLLs)
	var sha := FileAccess.get_sha256(found_path).to_lower()
	var size_bytes := maxi(_fast_file_length(found_path), 0)
	var found_leaf := found_path.get_file()
	var sig: Dictionary = KNOWN_DLL_SIGNATURES.get(sha, {})
	var matched_mod := String(sig.get("mod", "unknown")) if not sig.is_empty() else "unknown"
	var canonical_name := String(sig.get("name", "")) if not sig.is_empty() else ""

	base_result["resolvedPath"] = found_path
	base_result["canonicalName"] = canonical_name
	base_result["sha256"] = sha
	base_result["sizeBytes"] = size_bytes
	base_result["matchedMod"] = matched_mod
	base_result["knownSignature"] = not sig.is_empty()

	# 1. Unknown binary signature -> NEVER verified (even for custom mods!)
	if sig.is_empty():
		if mission_ref_mismatch:
			base_result["status"] = DLL_STATUS_MISSION_PROFILE_MISMATCH
			base_result["detail"] = "%s (resolved '%s', unverified SHA-256 %s)." % [mission_mismatch_reason, found_leaf, sha.left(12)]
			return base_result
		base_result["status"] = DLL_STATUS_HASH_UNVERIFIED
		base_result["semanticState"] = "UNKNOWN"
		base_result["detail"] = "Mission DLL '%s' (%s) does not match any verified %s signature; semantics are UNKNOWN." % [
			found_leaf, sha.left(12), tgt.to_upper() if not tgt.is_empty() else "BZCC"]
		return base_result

	# 2. Canonical filename mismatch (e.g., Stock Instant.dll bytes renamed to Strategy02.dll!)
	if canonical_name.nocasecmp_to(lookup_name) != 0 or canonical_name.nocasecmp_to(found_leaf) != 0:
		base_result["status"] = DLL_STATUS_DLL_NAME_MISMATCH
		base_result["semanticState"] = "MISMATCH"
		base_result["detail"] = "DLL name mismatch: '%s' carries the SHA-256 of %s '%s' (%s); renamed mission DLLs are refused." % [
			found_leaf, matched_mod.to_upper(), canonical_name, sha.left(12)]
		return base_result

	# 3. Mission contract / actual BZN reference mismatch
	if mission_ref_mismatch:
		base_result["status"] = DLL_STATUS_MISSION_PROFILE_MISMATCH
		base_result["semanticState"] = "MISMATCH"
		base_result["detail"] = "%s (file '%s' verified as %s '%s', SHA-256 %s)." % [
			mission_mismatch_reason, found_leaf, matched_mod.to_upper(), canonical_name, sha.left(12)]
		return base_result
	if not exp_clean.is_empty() and canonical_name.nocasecmp_to(exp_clean) != 0:
		base_result["status"] = DLL_STATUS_MISSION_PROFILE_MISMATCH
		base_result["semanticState"] = "MISMATCH"
		base_result["detail"] = "Mission contract mismatch: resolved '%s' (%s), but mission '%s' requires '%s'." % [
			canonical_name, sha.left(12), mis_clean, exp_clean]
		return base_result

	# 4. ModProfile match vs explicit verified inheritance
	if tgt in ["stock", "vsr", "vrv"]:
		if matched_mod == tgt:
			base_result["verified"] = true
			base_result["semanticState"] = "VERIFIED"
			base_result["status"] = DLL_STATUS_VERIFIED_EXACT
			base_result["detail"] = "Exact %s '%s' SHA-256 verified (%s)." % [tgt.to_upper(), canonical_name, sha.left(12)]
			return base_result
		var inh_table: Dictionary = EXPLICIT_DLL_INHERITANCE.get(tgt, {})
		var allowed_parent := String(inh_table.get(canonical_name.to_lower(), ""))
		if not allowed_parent.is_empty() and matched_mod == allowed_parent:
			base_result["verified"] = true
			base_result["semanticState"] = "VERIFIED"
			base_result["status"] = DLL_STATUS_VERIFIED_EXPLICIT_INHERITANCE
			base_result["detail"] = "Explicitly inherited %s '%s' for %s verified (%s)." % [
				allowed_parent.to_upper(), canonical_name, tgt.to_upper(), sha.left(12)]
			return base_result
		base_result["status"] = DLL_STATUS_HASH_MISMATCH
		base_result["semanticState"] = "MISMATCH"
		base_result["detail"] = "Mod DLL hash mismatch: '%s' belongs to %s (%s), not target mod %s (no verified inheritance rule)." % [
			canonical_name, matched_mod.to_upper(), sha.left(12), tgt.to_upper()]
		return base_result

	# Custom mod profile referencing a known Stock base DLL -> explicit Stock inheritance
	if matched_mod == "stock":
		base_result["verified"] = true
		base_result["semanticState"] = "VERIFIED"
		base_result["status"] = DLL_STATUS_VERIFIED_EXPLICIT_INHERITANCE
		base_result["detail"] = "Custom mod '%s' explicitly inherits verified Stock '%s' (%s)." % [tgt, canonical_name, sha.left(12)]
		return base_result

	base_result["status"] = DLL_STATUS_HASH_MISMATCH
	base_result["semanticState"] = "MISMATCH"
	base_result["detail"] = "Custom mod '%s' resolved %s '%s' (%s) without verified inheritance." % [
		tgt, matched_mod.to_upper(), canonical_name, sha.left(12)]
	return base_result
