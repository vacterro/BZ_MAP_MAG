extends RefCounted
## Universal BZCC EngineProfile & ModProfile registry, Workshop auto-discovery,
## deterministic dependency-stack resolution, open-map profile detection, and
## dependency-aware dry-run conversion compatibility analysis.
##
## Architecture:
## - EngineProfile, ModProfile, MissionProfile, and FormatProfile stay strictly independent.
## - Stock BZCC works without VRV or VSR installed.
## - Unknown Workshop mods open safely as custom profiles without fabricated DLL rules.
## - Stock ODF verification requires positive manifest or installed bz2r_res proof;
##   naming-convention heuristics are strictly hints and NEVER compatibility proof.
## - Discovery is read-only, bounded, symlink-safe, and never executes installed DLLs.

const AssetIndex := preload("res://core/asset_index.gd")

const SCHEMA := "bzmag.mod-profile/1"
const BZCC_APP_ID := "624970"
const VSR_WORKSHOP_ID := "1325933293"
const VRV_WORKSHOP_ID := "3820486276"

const ODF_VERIFIED_STOCK := "VERIFIED_STOCK_ODF"
const ODF_VERIFIED_MOD := "VERIFIED_MOD_ODF"
const ODF_LIKELY_STOCK_NAMING := "LIKELY_STOCK_NAMING"
const ODF_UNKNOWN := "UNKNOWN_ODF"

const ENGINE_PROFILES := {
	"bzcc-2.0.185": {
		"id": "bzcc-2.0.185",
		"displayName": "BZCC 2.0.185",
		"version": "2.0.185",
		"verified": true,
		"supportedRoutes": ["native-1192", "convert-1196"],
	},
	"bzcc-auto-detected": {
		"id": "bzcc-auto-detected",
		"displayName": "BZCC (Auto)",
		"version": "auto",
		"verified": false,
		"supportedRoutes": [],
	},
	"bzcc-unknown-readonly": {
		"id": "bzcc-unknown-readonly",
		"displayName": "No Install (Read-only)",
		"version": "unknown",
		"verified": false,
		"supportedRoutes": [],
	},
}

var profiles: Dictionary = {}
var discovered_order: Array[String] = []
var workshop_items: Dictionary = {}
var disabled_mods: Dictionary = {}
var custom_mods: Dictionary = {}
var last_game_dir := ""
var last_vrv_dir := ""
var last_workshop_root := ""


func _init() -> void:
	reset_builtins()


func reset_builtins() -> void:
	profiles.clear()
	discovered_order.clear()
	workshop_items.clear()
	_register(builtin_stock())
	_register(builtin_vsr())
	_register(builtin_vrv())


static func builtin_stock(game_root: String = "") -> Dictionary:
	return {
		"schema": SCHEMA,
		"id": "stock",
		"displayName": "Stock BZCC",
		"version": "auto",
		"workshopId": "",
		"homepage": "https://steamcommunity.com/app/624970/workshop/",
		"modType": "base",
		"gameRoot": game_root,
		"assetRoots": [],
		"dependencies": [],
		"missingDependencies": [],
		"missionModes": ["blank", "strategy", "instant", "mpi", "duel", "lua", "custom-dll"],
		"missionDlls": ["Strategy02.dll", "Instant.dll", "mpinstant.dll", "deathmatch01.dll", "StratCTF.dll", "LuaMission.dll"],
		"templates": [],
		"installed": not game_root.is_empty() and DirAccess.dir_exists_absolute(game_root.path_join("bz2r_res")),
		"capabilities": {
			"terrain": "NATIVE",
			"water": "NATIVE",
			"paths": "NATIVE",
			"objects": "GAME_LOAD_VERIFIED",
			"soundPoints": "UNSUPPORTED",
		},
		"provenance": {
			"source": "builtin-stock",
			"note": "Base Battlezone: Combat Commander installation; zero VRV/VSR dependency.",
		},
	}


static func builtin_vsr() -> Dictionary:
	return {
		"schema": SCHEMA,
		"id": "vsr",
		"displayName": "VSR — Vet Strat Recycler Variant",
		"version": "workshop",
		"workshopId": VSR_WORKSHOP_ID,
		"homepage": "https://steamcommunity.com/sharedfiles/filedetails/?id=1325933293",
		"modType": "config",
		"gameRoot": "",
		"assetRoots": [],
		"dependencies": ["stock", "3532748119", "1329659846", "2785557433", "2785542655", "2814914461", "2049956570", "3493379153", "2467249743", "3672472526", "3627212766"],
		"missingDependencies": [],
		"missionModes": ["blank", "strategy", "instant", "duel", "lua", "custom-dll"],
		"missionDlls": ["Strategy02.dll", "Instant.dll", "deathmatch01.dll", "LuaMission.dll"],
		"templates": [],
		"installed": false,
		"capabilities": {
			"terrain": "NATIVE",
			"water": "NATIVE",
			"paths": "NATIVE",
			"objects": "GAME_LOAD_VERIFIED",
			"soundPoints": "UNSUPPORTED",
		},
		"provenance": {
			"source": "workshop-1325933293",
			"url": "https://steamcommunity.com/sharedfiles/filedetails/?id=1325933293",
		},
	}


static func builtin_vrv() -> Dictionary:
	return {
		"schema": SCHEMA,
		"id": "vrv",
		"displayName": "VRV — Vacuum Recycler Variant",
		"version": "workshop",
		"workshopId": VRV_WORKSHOP_ID,
		"homepage": "https://steamcommunity.com/sharedfiles/filedetails/?id=3820486276",
		"modType": "config",
		"gameRoot": "",
		"assetRoots": [],
		"parentMods": [VSR_WORKSHOP_ID],
		"dependencies": ["stock", "3532748119", "1329659846", "2785557433", "2785542655", "2814914461", "2049956570", "3493379153", "2467249743"],
		"missingDependencies": [],
		"missionModes": ["blank", "strategy", "instant", "mpi", "duel", "lua", "custom-dll"],
		"missionDlls": ["Strategy02.dll", "Instant.dll", "mpinstant.dll", "StratCTF.dll", "deathmatch01.dll", "VrvPrepare.dll"],
		"templates": [],
		"installed": false,
		"capabilities": {
			"terrain": "NATIVE",
			"water": "NATIVE",
			"paths": "NATIVE",
			"objects": "GAME_LOAD_VERIFIED",
			"soundPoints": "VRV_RUNTIME",
		},
		"provenance": {
			"source": "workshop-3820486276",
			"url": "https://steamcommunity.com/sharedfiles/filedetails/?id=3820486276",
		},
	}


static func validate_manifest(manifest: Variant) -> String:
	if not (manifest is Dictionary):
		return "Mod profile must be a dictionary."
	if String(manifest.get("schema", "")) != SCHEMA:
		return "Unsupported mod profile schema (expected %s)." % SCHEMA
	var id := String(manifest.get("id", "")).strip_edges()
	if id.is_empty():
		return "Mod profile id is required."
	var id_re := RegEx.new()
	id_re.compile("^[a-z0-9][a-z0-9._:-]{0,63}$")
	if id_re.search(id) == null:
		return "Mod profile id '%s' contains unsupported characters." % id
	if String(manifest.get("displayName", "")).strip_edges().is_empty():
		return "Mod profile displayName is required."
	if not (manifest.get("assetRoots", []) is Array) or not (manifest.get("dependencies", []) is Array):
		return "assetRoots and dependencies must be arrays."
	return ""


func _register(manifest: Dictionary) -> bool:
	if not validate_manifest(manifest).is_empty():
		return false
	var id := String(manifest["id"])
	profiles[id] = manifest
	if not (id in discovered_order):
		discovered_order.append(id)
	return true


func get_profile(id: String) -> Dictionary:
	return profiles.get(id, {}) as Dictionary


func has_profile(id: String) -> bool:
	return profiles.has(id)


func enabled_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in discovered_order:
		if id == "stock" or not disabled_mods.get(id, false):
			result.append(id)
	return result


func all_profile_ids() -> Array[String]:
	return discovered_order.duplicate()


func set_mod_enabled(id: String, enabled: bool) -> void:
	if id == "stock":
		disabled_mods.erase("stock")
		return
	if enabled:
		disabled_mods.erase(id)
	else:
		disabled_mods[id] = true


func register_custom_mod(id_slug: String, display_name: String, folder: String, deps: Array = []) -> Dictionary:
	var clean_id := id_slug.strip_edges().to_lower()
	if not clean_id.begins_with("custom:"):
		clean_id = "custom:" + clean_id
	var dlls := _scan_shallow_dlls(folder)
	var manifest := {
		"schema": SCHEMA,
		"id": clean_id,
		"displayName": display_name.strip_edges(),
		"version": "local",
		"workshopId": "",
		"homepage": "",
		"modType": "config",
		"gameRoot": folder,
		"assetRoots": [folder] if not folder.is_empty() and DirAccess.dir_exists_absolute(folder) else [],
		"dependencies": deps.duplicate(),
		"missingDependencies": [],
		"missionModes": ["blank", "custom-dll", "lua", "strategy", "instant", "duel"],
		"missionDlls": dlls,
		"templates": [],
		"installed": not folder.is_empty() and DirAccess.dir_exists_absolute(folder),
		"capabilities": {"terrain": "NATIVE", "soundPoints": "UNSUPPORTED"},
		"provenance": {"source": "user-custom", "folder": folder},
	}
	var err := validate_manifest(manifest)
	if not err.is_empty():
		return {"error": err}
	custom_mods[clean_id] = manifest
	_register(manifest)
	return manifest


static func derive_workshop_root(game_dir: String) -> String:
	if game_dir.is_empty():
		return ""
	var norm := game_dir.simplify_path()
	var candidate := norm.path_join("../../workshop/content/" + BZCC_APP_ID).simplify_path()
	if DirAccess.dir_exists_absolute(candidate):
		return candidate
	return ""


static func parse_workshop_ini(path: String) -> Dictionary:
	var out := {"modName": "", "modType": "", "assetDependencies": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return out
	var text := file.get_as_text()
	for raw in text.split("\n"):
		var line := raw.get_slice(";", 0).get_slice("//", 0).strip_edges()
		if line.is_empty() or not line.contains("="):
			continue
		var key := line.get_slice("=", 0).strip_edges().to_lower()
		var val := line.substr(line.find("=") + 1).strip_edges().trim_prefix('"').trim_suffix('"')
		match key:
			"modname":
				out["modName"] = val
			"modtype":
				out["modType"] = val.to_lower()
			"assetdependencies":
				var dep_list: Array[String] = []
				for token in val.split(","):
					var clean := token.strip_edges()
					if not clean.is_empty():
						dep_list.append(clean)
				out["assetDependencies"] = dep_list
	return out


static func _scan_shallow_dlls(folder: String) -> Array[String]:
	var dlls: Array[String] = []
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return dlls
	var dirs: Array[String] = [folder]
	var top := DirAccess.open(folder)
	if top != null:
		for sub in top.get_directories():
			if sub.begins_with("."):
				continue
			var p := folder.path_join(sub)
			dirs.append(p)
			var sub_dir := DirAccess.open(p)
			if sub_dir != null:
				for sub2 in sub_dir.get_directories():
					if sub2.to_lower() == "missions":
						dirs.append(p.path_join(sub2))
	var seen := {}
	for d in dirs:
		var handle := DirAccess.open(d)
		if handle == null:
			continue
		for name in handle.get_files():
			if name.get_extension().to_lower() == "dll":
				var lower := name.to_lower()
				if not seen.has(lower):
					seen[lower] = true
					dlls.append(name)
	dlls.sort()
	return dlls


static func discover_stock_templates(game_dir: String) -> Array[String]:
	var found: Array[String] = []
	if game_dir.is_empty():
		return found
	var plgr := game_dir.path_join("maps/Missions/Instant/PLGR/plgr.bzn").simplify_path()
	if FileAccess.file_exists(plgr):
		found.append(plgr)
	return found


func _collect_workshop_deps_recursive(start_id: String, include_self: bool = true) -> Dictionary:
	var roots: Array[String] = []
	var missing: Array[String] = []
	var cycles: Array[String] = []
	var all_dlls: Array[String] = []
	var seen_dll := {}
	var seen_root := {}
	var state := {} # 1=visiting, 2=done
	_walk_ws_dep(start_id, include_self, state, roots, seen_root, missing, cycles, all_dlls, seen_dll)
	all_dlls.sort()
	return {"roots": roots, "missing": missing, "cycles": cycles, "dlls": all_dlls}


func _walk_ws_dep(item_id: String, include_root: bool, state: Dictionary, roots: Array[String], seen_root: Dictionary, missing: Array[String], cycles: Array[String], all_dlls: Array[String], seen_dll: Dictionary) -> void:
	if not workshop_items.has(item_id):
		if not (item_id in missing):
			missing.append(item_id)
		return
	var st := int(state.get(item_id, 0))
	if st == 1:
		cycles.append("ws:%s" % item_id)
		return
	if st == 2:
		return
	state[item_id] = 1
	var item: Dictionary = workshop_items[item_id]
	var item_path := String(item["path"])
	if include_root and not item_path.is_empty() and not seen_root.has(item_path.to_lower()):
		seen_root[item_path.to_lower()] = true
		roots.append(item_path)
	for dll_v in item.get("dlls", []):
		var dn := String(dll_v)
		if not seen_dll.has(dn.to_lower()):
			seen_dll[dn.to_lower()] = true
			all_dlls.append(dn)
	for dep_v in item.get("assetDependencies", []):
		var dep_id := String(dep_v).strip_edges()
		if not dep_id.is_empty():
			_walk_ws_dep(dep_id, true, state, roots, seen_root, missing, cycles, all_dlls, seen_dll)
	state[item_id] = 2


func discover_installed(game_dir: String, vrv_dir: String = "", workshop_override: String = "") -> Dictionary:
	reset_builtins()
	last_game_dir = game_dir.strip_edges()
	last_vrv_dir = vrv_dir.strip_edges()
	var ws_root := workshop_override.strip_edges() if not workshop_override.strip_edges().is_empty() else derive_workshop_root(last_game_dir)
	last_workshop_root = ws_root

	# 1. Stock profile bound purely to game_dir (never requires VRV/VSR)
	var stock := builtin_stock(last_game_dir)
	stock["templates"] = discover_stock_templates(last_game_dir)
	var stock_missions := last_game_dir.path_join("Missions")
	if not last_game_dir.is_empty() and DirAccess.dir_exists_absolute(stock_missions):
		var found_dlls := _scan_shallow_dlls(stock_missions)
		if not found_dlls.is_empty():
			stock["missionDlls"] = found_dlls
	_register(stock)

	# 2. Scan Steam Workshop items (bounded, read-only: top-level .ini + shallow DLLs)
	workshop_items.clear()
	if not ws_root.is_empty() and DirAccess.dir_exists_absolute(ws_root):
		var ws_dir := DirAccess.open(ws_root)
		if ws_dir != null:
			var ids := Array(ws_dir.get_directories())
			ids.sort()
			for item_id_v in ids:
				var item_id := String(item_id_v)
				if not item_id.is_valid_int():
					continue
				var item_path := ws_root.path_join(item_id)
				var item_dir := DirAccess.open(item_path)
				if item_dir == null:
					continue
				var meta := {"modName": "", "modType": "", "assetDependencies": []}
				for f in item_dir.get_files():
					if f.get_extension().to_lower() == "ini":
						meta = parse_workshop_ini(item_path.path_join(f))
						if not String(meta["modName"]).is_empty() or not String(meta["modType"]).is_empty():
							break
				var dlls := _scan_shallow_dlls(item_path)
				workshop_items[item_id] = {
					"id": item_id,
					"path": item_path,
					"modName": String(meta["modName"]),
					"modType": String(meta["modType"]),
					"assetDependencies": meta["assetDependencies"],
					"dlls": dlls,
				}

	# 3. Populate VSR profile from Workshop 1325933293 (independent of VRV!)
	var vsr := builtin_vsr()
	if workshop_items.has(VSR_WORKSHOP_ID):
		var item: Dictionary = workshop_items[VSR_WORKSHOP_ID]
		vsr["installed"] = true
		vsr["gameRoot"] = String(item["path"])
		if not String(item["modName"]).is_empty():
			vsr["displayName"] = "VSR — " + String(item["modName"])
		var walked := _collect_workshop_deps_recursive(VSR_WORKSHOP_ID, true)
		var full_deps: Array[String] = ["stock"]
		for d_v in item["assetDependencies"]:
			full_deps.append(String(d_v))
		vsr["dependencies"] = full_deps
		vsr["assetRoots"] = walked["roots"]
		vsr["missingDependencies"] = walked["missing"]
		if not (item["dlls"] as Array).is_empty():
			vsr["missionDlls"] = item["dlls"]
	_register(vsr)

	# 4. Populate VRV profile from Workshop 3820486276 or local BZ2R/VRV (separate from VSR!)
	var vrv := builtin_vrv()
	var vrv_roots: Array[String] = []
	var vrv_missing: Array[String] = []
	if workshop_items.has(VRV_WORKSHOP_ID):
		var item: Dictionary = workshop_items[VRV_WORKSHOP_ID]
		vrv["installed"] = true
		vrv["gameRoot"] = String(item["path"])
		if not String(item["modName"]).is_empty():
			vrv["displayName"] = String(item["modName"])
		var full_deps: Array[String] = ["stock"]
		for d_v in item["assetDependencies"]:
			full_deps.append(String(d_v))
		vrv["dependencies"] = full_deps
		vrv["parentMods"] = [VSR_WORKSHOP_ID]
		var walked := _collect_workshop_deps_recursive(VRV_WORKSHOP_ID, true)
		for r_v in walked["roots"]:
			vrv_roots.append(String(r_v))
		if workshop_items.has(VSR_WORKSHOP_ID):
			var vsr_path := String(workshop_items[VSR_WORKSHOP_ID]["path"])
			if not (vsr_path in vrv_roots):
				vrv_roots.insert(1, vsr_path)
		else:
			if not (VSR_WORKSHOP_ID in vrv_missing):
				vrv_missing.append(VSR_WORKSHOP_ID)
		for m_v in walked["missing"]:
			if not (String(m_v) in vrv_missing):
				vrv_missing.append(String(m_v))
		if not (item["dlls"] as Array).is_empty():
			vrv["missionDlls"] = item["dlls"]
	elif not last_game_dir.is_empty() and DirAccess.dir_exists_absolute(last_game_dir.path_join("VRV")):
		vrv["installed"] = true
		vrv["gameRoot"] = last_game_dir.path_join("VRV")
		vrv_roots.append(last_game_dir.path_join("VRV"))
	if not last_vrv_dir.is_empty() and DirAccess.dir_exists_absolute(last_vrv_dir.path_join("mod/Data/Templates")):
		var tpl_dir := last_vrv_dir.path_join("mod/Data/Templates")
		var tpl := tpl_dir.path_join("vrv_new_blank.ter")
		if FileAccess.file_exists(tpl):
			vrv["templates"] = [tpl]
	vrv["assetRoots"] = vrv_roots
	vrv["missingDependencies"] = vrv_missing
	_register(vrv)

	# 5. Register all other discovered config Workshop mods as custom:ws-<workshopId>
	for item_id: String in workshop_items:
		if item_id == VSR_WORKSHOP_ID or item_id == VRV_WORKSHOP_ID:
			continue
		var item: Dictionary = workshop_items[item_id]
		if String(item["modType"]) != "config" and (item["dlls"] as Array).is_empty():
			continue
		var mod_id := "custom:ws-" + item_id
		var title := String(item["modName"])
		if title.is_empty():
			title = "Workshop Mod " + item_id
		var walked := _collect_workshop_deps_recursive(item_id, true)
		var deps: Array[String] = ["stock"]
		for d_v in item["assetDependencies"]:
			deps.append(String(d_v))
		var modes: Array[String] = ["blank", "custom-dll", "lua"]
		for dll_v in walked["dlls"]:
			var dl := String(dll_v).to_lower()
			if "strat" in dl and not ("strategy" in modes):
				modes.append("strategy")
			if "instant" in dl and not ("instant" in modes):
				modes.append("instant")
			if "deathmatch" in dl and not ("duel" in modes):
				modes.append("duel")
		_register({
			"schema": SCHEMA,
			"id": mod_id,
			"displayName": title,
			"version": "workshop",
			"workshopId": item_id,
			"homepage": "https://steamcommunity.com/sharedfiles/filedetails/?id=" + item_id,
			"modType": String(item["modType"]) if not String(item["modType"]).is_empty() else "config",
			"gameRoot": String(item["path"]),
			"assetRoots": walked["roots"],
			"dependencies": deps,
			"missingDependencies": walked["missing"],
			"missionModes": modes,
			"missionDlls": walked["dlls"],
			"templates": [],
			"installed": true,
			"capabilities": {"terrain": "NATIVE", "soundPoints": "UNSUPPORTED"},
			"provenance": {"source": "workshop-" + item_id, "url": "https://steamcommunity.com/sharedfiles/filedetails/?id=" + item_id},
		})

	# 6. Re-register user custom mods
	for cid: String in custom_mods:
		_register(custom_mods[cid])

	return {
		"count": discovered_order.size(),
		"workshopRoot": ws_root,
		"cycles": detect_dependency_cycles(),
	}


func detect_dependency_cycles() -> Array[String]:
	var cycles: Array[String] = []
	var state := {} # 0=unvisited, 1=visiting, 2=done
	for id: String in profiles:
		if int(state.get(id, 0)) == 0:
			_dfs_cycle(id, state, cycles)
	return cycles


func _dfs_cycle(node: String, state: Dictionary, cycles: Array[String]) -> void:
	state[node] = 1
	var entry: Dictionary = profiles.get(node, {})
	for dep_v in entry.get("dependencies", []):
		var dep := String(dep_v)
		var target := dep
		if not profiles.has(target) and dep.is_valid_int():
			if dep == VSR_WORKSHOP_ID:
				target = "vsr"
			elif dep == VRV_WORKSHOP_ID:
				target = "vrv"
			elif profiles.has("custom:ws-" + dep):
				target = "custom:ws-" + dep
		if not profiles.has(target):
			continue
		var st := int(state.get(target, 0))
		if st == 1:
			cycles.append("%s -> %s" % [node, target])
		elif st == 0:
			_dfs_cycle(target, state, cycles)
	state[node] = 2


## Deterministic recursive dependency traversal for a target mod profile.
## Produces ordered roots, exact provenance, missing/disabled dependencies,
## dependency cycles, duplicate roots, and unavailable roots.
## Never fakes `complete = true` when any dependency is missing or disabled.
func resolve_dependency_stack(mod_id: String, game_dir: String = "", vrv_dir: String = "") -> Dictionary:
	var eff_game := game_dir.strip_edges() if not game_dir.strip_edges().is_empty() else last_game_dir
	var eff_mod := mod_id.strip_edges().to_lower()
	if eff_mod.is_empty():
		eff_mod = "stock"
	var native_roots: Array[String] = []
	if not eff_game.is_empty():
		for sub in ["bz2r_res", "bz2r_loc"]:
			var p := eff_game.path_join(sub)
			if DirAccess.dir_exists_absolute(p):
				native_roots.append(p)
	var stock_installed := not eff_game.is_empty() and DirAccess.dir_exists_absolute(eff_game.path_join("bz2r_res"))
	if eff_mod == "stock":
		var stock_stack: Array[Dictionary] = []
		for nr in native_roots:
			stock_stack.append({"id": "stock", "source": "stock", "path": nr, "modType": "base"})
		return {
			"modId": "stock",
			"knownProfile": true,
			"installed": stock_installed,
			"modAssetRoots": [],
			"nativeRoots": native_roots,
			"dependencyStack": stock_stack,
			"missingDependencies": [],
			"disabledDependencies": [],
			"dependencyCycles": [],
			"duplicateRoots": [],
			"unavailableRoots": [],
			"localFallbackUsed": false,
			"complete": stock_installed,
		}

	var known := has_profile(eff_mod)
	var prof := get_profile(eff_mod)
	if not known or eff_mod == "custom:unknown":
		return {
			"modId": eff_mod,
			"knownProfile": false,
			"installed": false,
			"modAssetRoots": [],
			"nativeRoots": native_roots,
			"dependencyStack": [],
			"missingDependencies": [eff_mod],
			"disabledDependencies": [],
			"dependencyCycles": [],
			"duplicateRoots": [],
			"unavailableRoots": [],
			"localFallbackUsed": false,
			"complete": false,
		}

	var state := {
		"eff_mod": eff_mod,
		"eff_game": eff_game,
		"stock_installed": stock_installed,
		"mod_roots": [] as Array[String],
		"stack": [] as Array[Dictionary],
		"missing_deps": [] as Array[String],
		"disabled_deps": [] as Array[String],
		"cycles": [] as Array[String],
		"dup_roots": [] as Array[String],
		"unavailable_roots": [] as Array[String],
		"local_fallback_used": false,
		"seen_root": {},
		"visit_state": {},
	}

	# Check primary profile disabled state
	if disabled_mods.get(eff_mod, false):
		(state["disabled_deps"] as Array).append(eff_mod)

	_walk_dependency_node(state, eff_mod, true)

	var mod_roots: Array[String] = state["mod_roots"]
	var stack: Array[Dictionary] = state["stack"]
	var missing_deps: Array[String] = state["missing_deps"]
	var disabled_deps: Array[String] = state["disabled_deps"]
	var cycles: Array[String] = state["cycles"]
	var dup_roots: Array[String] = state["dup_roots"]
	var unavailable_roots: Array[String] = state["unavailable_roots"]
	var local_fallback_used: bool = bool(state["local_fallback_used"])

	# Include Stock native roots at bottom of stack
	for nr in native_roots:
		stack.append({"id": "stock", "source": "stock", "path": nr, "modType": "base"})

	var is_installed := bool(prof.get("installed", false)) or (local_fallback_used and not mod_roots.is_empty())
	var complete := is_installed and missing_deps.is_empty() and disabled_deps.is_empty() and cycles.is_empty() and unavailable_roots.is_empty()
	return {
		"modId": eff_mod,
		"knownProfile": true,
		"installed": is_installed,
		"modAssetRoots": mod_roots,
		"nativeRoots": native_roots,
		"dependencyStack": stack,
		"missingDependencies": missing_deps,
		"disabledDependencies": disabled_deps,
		"dependencyCycles": cycles,
		"duplicateRoots": dup_roots,
		"unavailableRoots": unavailable_roots,
		"localFallbackUsed": local_fallback_used,
		"complete": complete,
	}


func _add_dep_root_entry(state: Dictionary, root_path: String, dep_id: String, source_tag: String, mtype: String) -> void:
	var clean_p := root_path.strip_edges().simplify_path()
	if clean_p.is_empty():
		return
	var low := clean_p.to_lower()
	var seen_root: Dictionary = state["seen_root"]
	if seen_root.has(low):
		var dup_roots: Array = state["dup_roots"]
		if not (clean_p in dup_roots):
			dup_roots.append(clean_p)
		return
	if not DirAccess.dir_exists_absolute(clean_p):
		var unavailable_roots: Array = state["unavailable_roots"]
		if not (clean_p in unavailable_roots):
			unavailable_roots.append(clean_p)
		return
	seen_root[low] = true
	(state["mod_roots"] as Array).append(clean_p)
	(state["stack"] as Array).append({"id": dep_id, "source": source_tag, "path": clean_p, "modType": mtype})


func _walk_dependency_node(state: Dictionary, node_id: String, is_root_mod: bool) -> void:
	var eff_mod := String(state["eff_mod"])
	var eff_game := String(state["eff_game"])
	var missing_deps: Array = state["missing_deps"]
	var disabled_deps: Array = state["disabled_deps"]
	var cycles: Array = state["cycles"]
	var visit_state: Dictionary = state["visit_state"]

	if node_id == "stock":
		if not bool(state["stock_installed"]) and not ("stock" in missing_deps):
			missing_deps.append("stock")
		return
	var st := int(visit_state.get(node_id, 0))
	if st == 1:
		var cyc := "%s -> %s" % [eff_mod, node_id]
		if not (cyc in cycles):
			cycles.append(cyc)
		return
	if st == 2:
		return
	visit_state[node_id] = 1

	# Resolve either registered profile or raw Workshop numeric ID
	var resolved_prof_id := node_id
	if not has_profile(resolved_prof_id) and node_id.is_valid_int():
		if node_id == VSR_WORKSHOP_ID:
			resolved_prof_id = "vsr"
		elif node_id == VRV_WORKSHOP_ID:
			resolved_prof_id = "vrv"
		elif has_profile("custom:ws-" + node_id):
			resolved_prof_id = "custom:ws-" + node_id

	if has_profile(resolved_prof_id):
		var p: Dictionary = get_profile(resolved_prof_id)
		if not is_root_mod and disabled_mods.get(resolved_prof_id, false) and not (resolved_prof_id in disabled_deps):
			disabled_deps.append(resolved_prof_id)
		var primary_root := String(p.get("gameRoot", "")).strip_edges()
		if not primary_root.is_empty():
			_add_dep_root_entry(state, primary_root, resolved_prof_id, String(p.get("provenance", {}).get("source", resolved_prof_id)), String(p.get("modType", "config")))
		elif bool(p.get("installed", false)):
			for ar_v in p.get("assetRoots", []):
				_add_dep_root_entry(state, String(ar_v), resolved_prof_id, resolved_prof_id, String(p.get("modType", "config")))
		elif resolved_prof_id in ["vsr", "vrv"] and not eff_game.is_empty():
			# Explicit local VRV/deps fallback only when Workshop item itself is absent
			var fallback_path := eff_game.path_join("VRV/Core") if resolved_prof_id == "vrv" else eff_game.path_join("VRV/deps/VSR")
			if DirAccess.dir_exists_absolute(fallback_path):
				state["local_fallback_used"] = true
				_add_dep_root_entry(state, fallback_path, resolved_prof_id, "local-vrv-fallback:" + resolved_prof_id, "fallback")
			elif not (resolved_prof_id in missing_deps):
				missing_deps.append(resolved_prof_id)
		elif not (resolved_prof_id in missing_deps):
			missing_deps.append(resolved_prof_id)

		for pm_v in p.get("parentMods", []):
			var pm_id := String(pm_v).strip_edges()
			if pm_id.is_empty():
				continue
			if workshop_items.has(pm_id):
				var pwi: Dictionary = workshop_items[pm_id]
				_add_dep_root_entry(state, String(pwi["path"]), pm_id, "workshop-parent-" + pm_id, String(pwi.get("modType", "config")))
			elif pm_id == VSR_WORKSHOP_ID and not eff_game.is_empty() and DirAccess.dir_exists_absolute(eff_game.path_join("VRV/deps/VSR")):
				state["local_fallback_used"] = true
				_add_dep_root_entry(state, eff_game.path_join("VRV/deps/VSR"), pm_id, "local-vrv-fallback:vsr", "fallback")
			elif not (pm_id in missing_deps):
				missing_deps.append(pm_id)

		for dep_v in p.get("dependencies", []):
			var d := String(dep_v).strip_edges()
			if not d.is_empty():
				_walk_dependency_node(state, d, false)
	elif workshop_items.has(node_id):
		var wi: Dictionary = workshop_items[node_id]
		_add_dep_root_entry(state, String(wi["path"]), node_id, "workshop-" + node_id, String(wi.get("modType", "asset")))
		for dep_v in wi.get("assetDependencies", []):
			var d := String(dep_v).strip_edges()
			if not d.is_empty():
				_walk_dependency_node(state, d, false)
	else:
		# Missing Workshop dependency ID: check targeted VRV/deps/<id> fallback only for vsr/vrv
		var found_fallback := false
		if eff_mod in ["vsr", "vrv"] and not eff_game.is_empty() and node_id.is_valid_int():
			var local_dep := eff_game.path_join("VRV/deps").path_join(node_id)
			if DirAccess.dir_exists_absolute(local_dep):
				state["local_fallback_used"] = true
				found_fallback = true
				_add_dep_root_entry(state, local_dep, node_id, "local-vrv-fallback:" + node_id, "fallback")
		if not found_fallback and not (node_id in missing_deps):
			missing_deps.append(node_id)

	visit_state[node_id] = 2


const STOCK_KNOWN_DLLS := ["strategy02.dll", "instant.dll", "mpinstant.dll", "deathmatch01.dll", "stratctf.dll", "luamission.dll"]

## Verified semantic ODF conversion table (vsr -> stock).
## Every entry is backed by direct ODF inspection of Workshop 3532748119
## (VSR Standard Recycler Variants) and Stock BZ2R/bz2r_res. Heuristic string
## stripping (e.g. odf.replace("_vsr", "")) is strictly forbidden.
const VERIFIED_VSR_TO_STOCK_ODFS := {
	"ivtank_vsr": {
		"sourceOdf": "ivtank_vsr", "targetOdf": "ivtank", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivtank", "targetClass": "wingman", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivtank00.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivtank_vsr.odf (classLabel=ivtank) -> Stock bz2r_res ivtank.odf (ivtank00.fbx)",
	},
	"ivscout_vsr": {
		"sourceOdf": "ivscout_vsr", "targetOdf": "ivscout", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivscout", "targetClass": "wingman", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivscout00.fbx", "missionRole": "scout_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivscout_vsr.odf (classLabel=ivscout) -> Stock bz2r_res ivscout.odf (ivscout00.fbx)",
	},
	"ivmisl_vsr": {
		"sourceOdf": "ivmisl_vsr", "targetOdf": "ivmisl", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivmisl", "targetClass": "wingman", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivmisl00.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivmisl_vsr.odf (classLabel=ivmisl) -> Stock bz2r_res ivmisl.odf (ivmisl00.fbx)",
	},
	"ivturr_vsr": {
		"sourceOdf": "ivturr_vsr", "targetOdf": "ivturr", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivturr", "targetClass": "turrettank", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivturr00.fbx", "missionRole": "turret_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivturr_vsr.odf (classLabel=ivturr) -> Stock bz2r_res ivturr.odf (ivturr00.fbx)",
	},
	"ivscav_vsr": {
		"sourceOdf": "ivscav_vsr", "targetOdf": "ivscav", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivscav", "targetClass": "scavenger", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivscav00.fbx", "missionRole": "scavenger", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivscav_vsr.odf (classLabel=ivscav) -> Stock bz2r_res ivscav.odf (ivscav00.fbx)",
	},
	"ivcons_vsr": {
		"sourceOdf": "ivcons_vsr", "targetOdf": "ivcons", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivcons", "targetClass": "constructionrig", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivcons_skel.fbx", "missionRole": "constructor", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivcons_vsr.odf (classLabel=ivcons) -> Stock bz2r_res ivcons.odf (ivcons_skel.fbx)",
	},
	"ivserv_vsr": {
		"sourceOdf": "ivserv_vsr", "targetOdf": "ivserv", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivserv", "targetClass": "service", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivserv00.fbx", "missionRole": "service_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivserv_vsr.odf (classLabel=ivserv) -> Stock bz2r_res ivserv.odf (ivserv00.fbx)",
	},
	"ivatank_vsr": {
		"sourceOdf": "ivatank_vsr", "targetOdf": "ivatank", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivatank", "targetClass": "assaulttank", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivatank00.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivatank_vsr.odf (classLabel=ivatank) -> Stock bz2r_res ivatank.odf (ivatank00.fbx)",
	},
	"ivrckt_vsr": {
		"sourceOdf": "ivrckt_vsr", "targetOdf": "ivrckt", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivrckt", "targetClass": "wingman", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivrckt00.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivrckt_vsr.odf (classLabel=ivrckt) -> Stock bz2r_res ivrckt.odf (ivrckt00.fbx)",
	},
	"ivmbike_vsr": {
		"sourceOdf": "ivmbike_vsr", "targetOdf": "ivmbike", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivmbike", "targetClass": "wingman", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivmbike00.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivmbike_vsr.odf (classLabel=ivmbike) -> Stock bz2r_res ivmbike.odf (ivmbike00.fbx)",
	},
	"ivwalk_vsr": {
		"sourceOdf": "ivwalk_vsr", "targetOdf": "ivwalk", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivwalk", "targetClass": "walker", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivwalk_skel.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivwalk_vsr.odf (classLabel=ivwalk) -> Stock bz2r_res ivwalk.odf (ivwalk_skel.fbx)",
	},
	"ivrecy_vsr": {
		"sourceOdf": "ivrecy_vsr", "targetOdf": "ivrecy", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ivrecy", "targetClass": "recyclervehicle", "classFamily": "craft", "faction": "ISDF",
		"geometry": "ivrecy00.fbx", "missionRole": "recycler_vehicle", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 ivrecy_vsr.odf (classLabel=ivrecy) -> Stock bz2r_res ivrecy.odf (ivrecy00.fbx)",
	},
	"ibrecy_vsr": {
		"sourceOdf": "ibrecy_vsr", "targetOdf": "ibrecy", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "ibrecy", "targetClass": "recycler", "classFamily": "building", "faction": "ISDF",
		"geometry": "ibrecy00.fbx", "missionRole": "recycler_building", "requiredState": "building_binary_tail",
		"evidence": "VSR 3532748119 ibrecy_vsr.odf (classLabel=ibrecy) -> Stock bz2r_res ibrecy.odf (ibrecy00.fbx)",
	},
	"fvscout_vsr": {
		"sourceOdf": "fvscout_vsr", "targetOdf": "fvscout", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvscout", "targetClass": "morphtank", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvscout_skel.fbx", "missionRole": "scout_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvscout_vsr.odf (classLabel=fvscout) -> Stock bz2r_res fvscout.odf (fvscout_skel.fbx)",
	},
	"fvtank_vsr": {
		"sourceOdf": "fvtank_vsr", "targetOdf": "fvtank", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvtank", "targetClass": "morphtank", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvtank_skel.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvtank_vsr.odf (classLabel=fvtank) -> Stock bz2r_res fvtank.odf (fvtank_skel.fbx)",
	},
	"fvsent_vsr": {
		"sourceOdf": "fvsent_vsr", "targetOdf": "fvsent", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvsent", "targetClass": "morphtank", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvsent_skel.fbx", "missionRole": "combat_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvsent_vsr.odf (classLabel=fvsent) -> Stock bz2r_res fvsent.odf (fvsent_skel.fbx)",
	},
	"fvturr_vsr": {
		"sourceOdf": "fvturr_vsr", "targetOdf": "fvturr", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvturr", "targetClass": "turrettank", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvturr_skel.fbx", "missionRole": "turret_craft", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvturr_vsr.odf (classLabel=fvturr) -> Stock bz2r_res fvturr.odf (fvturr_skel.fbx)",
	},
	"fvscav_vsr": {
		"sourceOdf": "fvscav_vsr", "targetOdf": "fvscav", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvscav", "targetClass": "scavenger", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvscav00.fbx", "missionRole": "scavenger", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvscav_vsr.odf (classLabel=fvscav) -> Stock bz2r_res fvscav.odf (fvscav00.fbx)",
	},
	"fvcons_vsr": {
		"sourceOdf": "fvcons_vsr", "targetOdf": "fvcons", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvcons", "targetClass": "constructionrig", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvconst_skel.fbx", "missionRole": "constructor", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvcons_vsr.odf (classLabel=fvcons) -> Stock bz2r_res fvcons.odf (fvconst_skel.fbx)",
	},
	"fvrecy_vsr": {
		"sourceOdf": "fvrecy_vsr", "targetOdf": "fvrecy", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fvrecy", "targetClass": "recyclervehicle", "classFamily": "craft", "faction": "Scion",
		"geometry": "fvrecy00.fbx", "missionRole": "recycler_vehicle", "requiredState": "craft_binary_tail",
		"evidence": "VSR 3532748119 fvrecy_vsr.odf (classLabel=fvrecy) -> Stock bz2r_res fvrecy.odf (fvrecy00.fbx)",
	},
	"fbrecy_vsr": {
		"sourceOdf": "fbrecy_vsr", "targetOdf": "fbrecy", "sourceMod": "vsr", "targetMod": "stock",
		"sourceClass": "fbrecy", "targetClass": "recycler", "classFamily": "building", "faction": "Scion",
		"geometry": "fbrecy00.fbx", "missionRole": "recycler_building", "requiredState": "building_binary_tail",
		"evidence": "VSR 3532748119 fbrecy_vsr.odf (classLabel=fbrecy) -> Stock bz2r_res fbrecy.odf (fbrecy00.fbx)",
	},
}

## Exact verified Stock ODF manifest (every entry verified in BZCC 2.0.185 bz2r_res).
## Additional Stock ODFs are positively identified dynamically from installed game_dir/bz2r_res.
const VERIFIED_STOCK_ODF_FAMILIES := {
	"player": "craft",
	"ivtank": "craft", "ivscout": "craft", "ivmisl": "craft", "ivturr": "craft",
	"ivscav": "craft", "ivcons": "craft", "ivcons2": "craft", "ivserv": "craft", "ivatank": "craft",
	"ivrckt": "craft", "ivmbike": "craft", "ivwalk": "craft", "ivapc": "craft",
	"ivrecy": "craft", "ivrecy_m": "craft", "ivrecycpu": "craft", "ivtug": "craft",
	"ivintc": "craft", "ivbomb": "craft", "ivcarr": "craft", "ivdrop": "craft", "ivdrop2": "craft",
	"ivdrop_fly": "craft", "ivdrop2_fl": "craft", "ivdrop_land": "craft", "ivdrop2_ld": "craft",
	"ivdrop_sh": "craft", "ivpdrop": "craft",
	"fvscout": "craft", "fvtank": "craft", "fvsent": "craft", "fvturr": "craft",
	"fvscav": "craft", "fvcons": "craft", "fvserv": "craft", "fvatank": "craft",
	"fvarch": "craft", "fvwalk": "craft", "fvartl": "craft", "fvrecy": "craft",
	"fvrecy_m": "craft", "fvrecycpu": "craft", "fvtug": "craft",
	"ibrecy": "building", "ibrecy_m": "building", "ibfact": "building", "ibsbay": "building",
	"ibbomb": "building", "ibtele": "building", "ibtcen": "building", "ibtrain": "building",
	"ibarmo": "building", "ibcbun": "building", "ibgtow": "building", "ibgtow01": "building", "ibgtoww1": "building",
	"ibpgen": "building", "ibpgen01": "building",
	"ibbstr": "building", "ibbseg": "building", "ibcrat00": "building", "ibcrat01": "building",
	"iblite": "building", "ibscav": "building", "ibscup": "building", "ibwseg": "building",
	"ibwstr": "building", "fbrecy": "building", "fbrecy_m": "building", "fbfact": "building",
	"fbkiln": "building", "fbforb": "building", "fbdowe": "building", "fbstro": "building",
	"fbover": "building", "fbspir": "building", "fbantm": "building", "fbjamm": "building",
	"fbscav": "building", "fbscup": "building", "ipdrop": "building",
	"ispilo": "pilot", "issold": "pilot", "fspilo": "pilot", "fssold": "pilot",
	"becras02a": "building", "crashdrop": "building", "crashdrop2": "building", "crashsite": "building",
	"perecy": "building", "petank": "building", "pescav": "building", "peapc": "building", "recarr00": "building",
	"pbscen01": "prop", "pbscen02": "prop", "pbscen06": "prop", "pbscen07": "prop", "pbscen08": "prop", "pbscen10": "prop",
	"morock01": "prop", "morock03": "prop", "mobush01": "prop", "mobush02": "prop", "mopalm02": "prop",
	"rbruin01": "prop", "rbruin02": "prop", "rbruin04": "prop", "rbruin05": "prop", "rbruin06": "prop",
	"ropilr01": "prop", "ropilr02": "prop", "ropilr03": "prop", "ropilr05": "prop",
	"pspwn_1": "spawnpoint",
	"npscrx": "scrap", "npscr1": "scrap", "npscr2": "scrap", "npscr3": "scrap",
	"npba": "pool", "epgysr00": "pool", "uepool01": "pool", "tepool01": "pool", "cpool01": "pool",
}


static func classify_odf_family(odf: String) -> String:
	var clean := odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	if VERIFIED_STOCK_ODF_FAMILIES.has(clean):
		return String(VERIFIED_STOCK_ODF_FAMILIES[clean])
	if VERIFIED_VSR_TO_STOCK_ODFS.has(clean):
		return String(VERIFIED_VSR_TO_STOCK_ODFS[clean]["classFamily"])
	if clean == "vrv_sndpoint" or clean.begins_with("vrv_"):
		return "vrv_runtime"
	if clean.begins_with("pspwn"):
		return "spawnpoint"
	if "pool" in clean or clean.begins_with("npscr"):
		return "pool"
	return ""


## Positive Stock ODF verification ONLY.
## Checks the exact verified Stock manifest AND (when supplied) the live installed
## Stock bz2r_res / .pak ODF index. NEVER falls back to naming-prefix heuristics.
static func is_verified_stock_odf(odf: String, stock_odf_index: Dictionary = {}) -> bool:
	var clean := odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	if clean.is_empty():
		return false
	if clean.begins_with("vrv_") or clean == "vrv_sndpoint" or clean.ends_with("_vsr") or "_vsr" in clean or ":" in clean:
		return false
	if VERIFIED_STOCK_ODF_FAMILIES.has(clean):
		return true
	if not stock_odf_index.is_empty() and stock_odf_index.has(clean + ".odf"):
		return true
	return false


## Naming-convention hint ONLY. Never used as Stock compatibility proof or to
## elevate Stock detection confidence.
static func is_likely_stock_naming(odf: String) -> bool:
	var clean := odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	if clean.is_empty():
		return false
	if clean.begins_with("vrv_") or clean.ends_with("_vsr") or "_vsr" in clean or ":" in clean:
		return false
	for prefix in ["iv", "ib", "is", "ie", "fv", "fb", "fs", "fe", "av", "ab", "bv", "bb", "be", "cv", "cb", "ev", "eb", "gv", "gb", "hv", "hb", "mv", "mb", "nv", "nb", "ov", "ob", "pv", "pb", "pe", "ps", "sv", "sb", "tv", "tb", "uv", "ub", "wv", "wb", "xv", "xb", "yv", "yb", "np", "sp", "ap", "op", "gp", "ep", "cp", "fp", "ip", "mp", "rp", "tp", "vp", "wp", "xp", "mo", "ba", "mi", "du", "pl", "cr", "tr", "bu", "tu", "wa", "la", "br", "ro", "st", "cl", "pi", "co", "de", "fl", "gl", "gr", "hi", "ic", "ju", "ma", "me", "mu", "pa", "po", "qu", "ra", "re", "ri", "ru", "sa", "sc", "se", "sh", "si", "sk", "sl", "sm", "sn", "so", "sq", "su", "sw", "ta", "te", "th", "ti", "to", "un", "va", "ve", "vi", "vo", "wi", "wo", "wr", "ze"]:
		if clean.begins_with(prefix):
			return true
	return false


## Legacy alias kept strictly as a naming hint helper (never called by is_verified_stock_odf).
static func _is_likely_stock_odf(odf: String) -> bool:
	return is_likely_stock_naming(odf)


## Classifies an ODF strictly into VERIFIED_STOCK_ODF, VERIFIED_MOD_ODF,
## LIKELY_STOCK_NAMING (hint only), or UNKNOWN_ODF.
static func classify_odf_origin(odf: String, stock_odf_index: Dictionary = {}, mod_odf_sources: Dictionary = {}) -> Dictionary:
	var clean := odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	var key := clean + ".odf"
	if clean.is_empty():
		return {"odf": "", "classification": ODF_UNKNOWN, "sourceMod": "unknown", "resolvedPath": "", "hint": "Empty ODF name."}
	if clean == "vrv_sndpoint" or clean.begins_with("vrv_"):
		return {"odf": clean, "classification": ODF_VERIFIED_MOD, "sourceMod": "vrv", "resolvedPath": "", "hint": "VRV runtime ODF."}
	if clean.ends_with("_vsr") or "_vsr" in clean:
		return {"odf": clean, "classification": ODF_VERIFIED_MOD, "sourceMod": "vsr", "resolvedPath": "", "hint": "VSR ODF."}
	if mod_odf_sources.has(key):
		var src_info: Variant = mod_odf_sources[key]
		var src_mod := String(src_info.get("source", "custom")) if src_info is Dictionary else String(src_info)
		var src_path := String(src_info.get("path", "")) if src_info is Dictionary else ""
		if src_mod != "stock" and src_mod != "map":
			return {"odf": clean, "classification": ODF_VERIFIED_MOD, "sourceMod": src_mod, "resolvedPath": src_path, "hint": "Resolved in mod asset root (%s)." % src_mod}
	if is_verified_stock_odf(clean, stock_odf_index):
		var path := ""
		if stock_odf_index.has(key) and stock_odf_index[key] is Array and not (stock_odf_index[key] as Array).is_empty():
			path = String((stock_odf_index[key] as Array)[0])
		return {"odf": clean, "classification": ODF_VERIFIED_STOCK, "sourceMod": "stock", "resolvedPath": path, "hint": "Verified Stock resource."}
	if is_likely_stock_naming(clean):
		return {
			"odf": clean,
			"classification": ODF_LIKELY_STOCK_NAMING,
			"sourceMod": "unknown",
			"resolvedPath": "",
			"hint": "Naming prefix resembles Stock convention, but origin is NOT verified in Stock manifest or installed bz2r_res.",
		}
	return {"odf": clean, "classification": ODF_UNKNOWN, "sourceMod": "unknown", "resolvedPath": "", "hint": "Unrecognized ODF origin."}


func get_stock_odf_index(game_dir: String = "") -> Dictionary:
	var eff_game := game_dir.strip_edges() if not game_dir.strip_edges().is_empty() else last_game_dir
	if eff_game.is_empty():
		return {}
	var combined := {}
	var res_dir := eff_game.path_join("bz2r_res")
	if DirAccess.dir_exists_absolute(res_dir):
		var idx := AssetIndex.get_root_index(res_dir, true, false)
		var odfs: Dictionary = idx.get("odfs", {})
		for k: String in odfs:
			combined[k] = odfs[k]
	var loc_dir := eff_game.path_join("bz2r_loc")
	if DirAccess.dir_exists_absolute(loc_dir):
		var lidx := AssetIndex.get_root_index(loc_dir, true, false)
		var lodfs: Dictionary = lidx.get("odfs", {})
		for k: String in lodfs:
			if not combined.has(k):
				combined[k] = lodfs[k]
	if DirAccess.dir_exists_absolute(eff_game):
		var gidx := AssetIndex.get_root_index(eff_game, false, false)
		var godfs: Dictionary = gidx.get("odfs", {})
		for k: String in godfs:
			if not combined.has(k):
				combined[k] = godfs[k]
	return combined


## Looks up a verified semantic conversion for a single ODF from source_mod to target_mod.
## Never performs heuristic name-stripping (such as odf.replace("_vsr", "")).
static func lookup_verified_odf_conversion(source_odf: String, target_mod: String = "stock", manual_map: Dictionary = {}, stock_odf_index: Dictionary = {}) -> Dictionary:
	var clean := source_odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	var tgt_mod := target_mod.strip_edges().to_lower()
	if manual_map.has(clean) or manual_map.has(source_odf):
		var chosen_raw := String(manual_map.get(clean, manual_map.get(source_odf, ""))).strip_edges().to_lower()
		if chosen_raw.ends_with(".odf"):
			chosen_raw = chosen_raw.substr(0, chosen_raw.length() - 4)
		if chosen_raw.is_empty():
			return {"status": "missing_target", "sourceOdf": source_odf, "targetOdf": "", "error": "Manual replacement ODF for '%s' cannot be empty." % source_odf}
		if tgt_mod == "stock" and not is_verified_stock_odf(chosen_raw, stock_odf_index):
			return {"status": "missing_target", "sourceOdf": source_odf, "targetOdf": chosen_raw, "error": "Manual replacement '%s' is not a verified Stock ODF." % chosen_raw}
		var src_fam := classify_odf_family(clean)
		var tgt_fam := classify_odf_family(chosen_raw)
		if not src_fam.is_empty() and not tgt_fam.is_empty() and src_fam != tgt_fam:
			return {
				"status": "incompatible_class",
				"sourceOdf": source_odf,
				"targetOdf": chosen_raw,
				"sourceClass": src_fam,
				"targetClass": tgt_fam,
				"error": "Incompatible object class: cannot replace '%s' (%s) with '%s' (%s)." % [source_odf, src_fam, chosen_raw, tgt_fam],
			}
		return {
			"status": "verified_manual",
			"sourceOdf": source_odf,
			"targetOdf": chosen_raw,
			"sourceMod": "custom",
			"targetMod": tgt_mod,
			"classFamily": tgt_fam if not tgt_fam.is_empty() else src_fam,
			"classCompatible": true,
			"evidence": "Verified manual same-class replacement %s -> %s" % [source_odf, chosen_raw],
			"error": "",
		}
	if tgt_mod == "stock":
		if is_verified_stock_odf(clean, stock_odf_index):
			return {
				"status": "native",
				"sourceOdf": source_odf,
				"targetOdf": source_odf,
				"sourceMod": "stock",
				"targetMod": "stock",
				"classFamily": classify_odf_family(clean),
				"classCompatible": true,
				"error": "",
			}
		if VERIFIED_VSR_TO_STOCK_ODFS.has(clean):
			var rec: Dictionary = VERIFIED_VSR_TO_STOCK_ODFS[clean].duplicate(true)
			rec["status"] = "verified"
			rec["classCompatible"] = true
			rec["error"] = ""
			return rec
		if clean == "vrv_sndpoint" or clean.begins_with("vrv_"):
			return {
				"status": "unsupported_vrv",
				"sourceOdf": source_odf,
				"targetOdf": "",
				"sourceMod": "vrv",
				"targetMod": "stock",
				"classCompatible": false,
				"error": "VRV runtime object '%s' has no Stock counterpart." % source_odf,
			}
		var origin := classify_odf_origin(clean, stock_odf_index)
		return {
			"status": "unverified",
			"sourceOdf": source_odf,
			"targetOdf": "",
			"sourceMod": "vsr" if "_vsr" in clean else "unknown",
			"targetMod": "stock",
			"classification": String(origin["classification"]),
			"classCompatible": false,
			"error": "No verified Stock resource or counterpart for '%s' (%s)." % [source_odf, String(origin["classification"])],
		}
	elif tgt_mod == "vsr":
		if clean == "vrv_sndpoint" or clean.begins_with("vrv_"):
			return {
				"status": "unsupported_vrv",
				"sourceOdf": source_odf,
				"targetOdf": "",
				"sourceMod": "vrv",
				"targetMod": "vsr",
				"classCompatible": false,
				"error": "VRV runtime object '%s' is not supported in VSR without VRV runtime." % source_odf,
			}
		if is_verified_stock_odf(clean, stock_odf_index) or VERIFIED_VSR_TO_STOCK_ODFS.has(clean):
			return {
				"status": "native",
				"sourceOdf": source_odf,
				"targetOdf": source_odf,
				"sourceMod": "vsr",
				"targetMod": "vsr",
				"classCompatible": true,
				"error": "",
			}
		return {
			"status": "unverified",
			"sourceOdf": source_odf,
			"targetOdf": "",
			"sourceMod": "unknown",
			"targetMod": "vsr",
			"classCompatible": false,
			"error": "Unverified ODF '%s' for target mod VSR." % source_odf,
		}
	return {
		"status": "native",
		"sourceOdf": source_odf,
		"targetOdf": source_odf,
		"sourceMod": tgt_mod,
		"targetMod": tgt_mod,
		"classCompatible": true,
		"error": "",
	}


## Plans and validates semantic ODF conversion across a BZN object list.
## Checks duplicate object pointer IDs, duplicate sequences, pointer reference
## safety on removals, and verified ODF replacement mappings.
static func plan_bzn_odf_conversion(entries: Array, ptr_counts: Dictionary, target_mod: String = "stock", manual_map: Dictionary = {}, allow_drop_vrv: bool = false, stock_odf_index: Dictionary = {}) -> Dictionary:
	var odf_edits := {}
	var removals: Array[int] = []
	var replacements: Array[Dictionary] = []
	var unsupported: Array[String] = []
	var unverified_odfs: Array[String] = []
	var seen_ptrs := {}
	var seen_seqs := {}
	for idx in entries.size():
		var entry: Dictionary = entries[idx]
		var ptr_id := int(entry.get("flag8", 0))
		if ptr_id > 0:
			if seen_ptrs.has(ptr_id):
				unsupported.append("Duplicate object pointer ID %d at object #%d and #%d." % [ptr_id, int(seen_ptrs[ptr_id]), idx])
			else:
				seen_ptrs[ptr_id] = idx
		var seq := int(entry.get("sequence", -1))
		if seq >= 0:
			if seen_seqs.has(seq):
				unsupported.append("Duplicate object sequence %d at object #%d and #%d." % [seq, int(seen_seqs[seq]), idx])
			else:
				seen_seqs[seq] = idx
		var odf := String(entry.get("odf", ""))
		var lbl := String(entry.get("label", ""))
		var check_odf := "vrv_sndpoint" if lbl.to_lower().begins_with("vrvsnd:") and odf.to_lower() != "vrv_sndpoint" else odf
		var lookup := lookup_verified_odf_conversion(check_odf, target_mod, manual_map, stock_odf_index)
		var st := String(lookup.get("status", ""))
		if st == "native":
			continue
		elif st in ["verified", "verified_manual"]:
			var target_odf := String(lookup["targetOdf"])
			if target_odf.nocasecmp_to(odf) != 0:
				odf_edits[idx] = target_odf
				var rep := lookup.duplicate(true)
				rep["index"] = idx
				replacements.append(rep)
		elif st == "unsupported_vrv" and allow_drop_vrv:
			if ptr_id > 0 and int(ptr_counts.get(ptr_id, 0)) > 1:
				unsupported.append("Invalid reference: cannot remove VRV object #%d (%s, ptr %d) referenced by another BZN record." % [idx, odf, ptr_id])
				if not (odf.to_lower() in unverified_odfs):
					unverified_odfs.append(odf.to_lower())
			else:
				removals.append(idx)
				replacements.append({
					"index": idx,
					"status": "removed_vrv",
					"sourceOdf": odf,
					"targetOdf": "(removed)",
					"evidence": "Explicit VRV sound-point removal requested",
				})
		else:
			var err_msg := String(lookup.get("error", "Unsupported ODF '%s'" % odf))
			if not (err_msg in unsupported):
				unsupported.append(err_msg)
			if not (odf.to_lower() in unverified_odfs):
				unverified_odfs.append(odf.to_lower())
	var summary_lines: Array[String] = []
	var seen_pairs := {}
	for rep: Dictionary in replacements:
		var pair_key := "%s->%s" % [String(rep["sourceOdf"]).to_lower(), String(rep["targetOdf"]).to_lower()]
		if not seen_pairs.has(pair_key):
			seen_pairs[pair_key] = true
			summary_lines.append("%s -> %s (%s)" % [
				String(rep["sourceOdf"]), String(rep["targetOdf"]), String(rep.get("evidence", "verified"))])
	return {
		"ok": unsupported.is_empty(),
		"targetMod": target_mod,
		"odfEdits": odf_edits,
		"removals": removals,
		"replacements": replacements,
		"unsupported": unsupported,
		"unverifiedOdfs": unverified_odfs,
		"summaryLines": summary_lines,
	}


## Builds a single unified ResolvedContentEnvironment for models, terrain
## materials, ODF lookup, sound lookup, mission assets, export validation, and
## Playtest. Uses deterministic recursive dependency traversal.
## Strict Stock isolation: when mod_profile == 'stock', modAssetRoots is ALWAYS empty.
func resolve_content_environment(document: Object, game_dir: String = "", vrv_dir: String = "", target_mod_override: String = "", target_mission_override: String = "", target_engine_override: String = "", asset_profile_override: String = "", extra_roots_override: Array = []) -> Dictionary:
	var eff_game := game_dir.strip_edges() if not game_dir.strip_edges().is_empty() else last_game_dir
	var eff_vrv := vrv_dir.strip_edges() if not vrv_dir.strip_edges().is_empty() else last_vrv_dir
	var mod_id := target_mod_override.strip_edges().to_lower() if not target_mod_override.strip_edges().is_empty() else (String(document.mod_profile).strip_edges().to_lower() if document != null and "mod_profile" in document else "stock")
	var mis_id := target_mission_override.strip_edges().to_lower() if not target_mission_override.strip_edges().is_empty() else (String(document.mission_profile).strip_edges().to_lower() if document != null and "mission_profile" in document else "blank")
	var eng_id := target_engine_override.strip_edges() if not target_engine_override.strip_edges().is_empty() else (String(document.engine_profile).strip_edges() if document != null and "engine_profile" in document else "bzcc-2.0.185")
	var map_folder := ""
	if document != null:
		if "package" in document and document.package != null:
			map_folder = String(document.package.source_path).get_base_dir()
		elif "source_path" in document:
			map_folder = String(document.source_path).get_base_dir()

	var ap := asset_profile_override.strip_edges()
	if ap.is_empty() and document != null and "asset_profile" in document:
		ap = String(document.asset_profile).strip_edges()
	var linked_folders: Array[String] = []
	var unavailable_linked: Array[String] = []
	if not ap.is_empty() and FileAccess.file_exists(ap):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ap))
		if parsed is Dictionary and parsed.get("folders", null) is Array:
			var base_dir := ap.get_base_dir()
			for entry_v in parsed["folders"]:
				var entry := String(entry_v).strip_edges()
				if entry.is_empty():
					continue
				var full := entry if entry.is_absolute_path() else base_dir.path_join(entry).simplify_path()
				if DirAccess.dir_exists_absolute(full):
					if not (full in linked_folders):
						linked_folders.append(full)
				elif not (full in unavailable_linked):
					unavailable_linked.append(full)
	for er_v in extra_roots_override:
		var er := String(er_v).strip_edges().simplify_path()
		if er.is_empty():
			continue
		if DirAccess.dir_exists_absolute(er):
			if not (er in linked_folders):
				linked_folders.append(er)
		elif not (er in unavailable_linked):
			unavailable_linked.append(er)

	var dep_res := resolve_dependency_stack(mod_id, eff_game, eff_vrv)
	var mod_roots: Array[String] = []
	for r_v in dep_res["modAssetRoots"]:
		mod_roots.append(String(r_v))
	var native_roots: Array[String] = []
	for r_v in dep_res["nativeRoots"]:
		native_roots.append(String(r_v))

	var search_roots: Array[String] = []
	var layered_roots: Array[Dictionary] = []
	if not map_folder.is_empty():
		search_roots.append(map_folder)
		layered_roots.append({"path": map_folder, "source": "map", "recurse": true, "volatile": true})
	for lf in linked_folders:
		if not (lf in search_roots):
			search_roots.append(lf)
			layered_roots.append({"path": lf, "source": "linked", "recurse": true, "volatile": false})
	for item_v in dep_res["dependencyStack"]:
		var item: Dictionary = item_v
		var p := String(item["path"])
		if not (p in search_roots):
			search_roots.append(p)
			layered_roots.append({"path": p, "source": String(item["source"]), "recurse": true, "volatile": false})
	if not eff_game.is_empty() and DirAccess.dir_exists_absolute(eff_game):
		# Root game folder (non-recursive) for top-level DOCP .pak archives (smtex.pak, bumps.pak)
		layered_roots.append({"path": eff_game, "source": "stock-pak", "recurse": false, "volatile": false})

	var sound_roots: Array[String] = []
	if not map_folder.is_empty():
		sound_roots.append(map_folder)
	for r in linked_folders + mod_roots:
		if not (r in sound_roots):
			sound_roots.append(r)
	if not eff_game.is_empty():
		for sub in ["bz2r_res/audio", "bz2r_res"]:
			var p := eff_game.path_join(sub)
			if DirAccess.dir_exists_absolute(p) and not (p in sound_roots):
				sound_roots.append(p)

	var dll_roots: Array[String] = []
	if not map_folder.is_empty():
		dll_roots.append(map_folder)
	for r in linked_folders + mod_roots:
		if not (r in dll_roots):
			dll_roots.append(r)
	if not eff_game.is_empty():
		var m_dir := eff_game.path_join("Missions")
		if DirAccess.dir_exists_absolute(m_dir) and not (m_dir in dll_roots):
			dll_roots.append(m_dir)
	for r in native_roots:
		if not (r in dll_roots):
			dll_roots.append(r)

	var unavailable_all: Array[String] = []
	for u_v in dep_res["unavailableRoots"]:
		unavailable_all.append(String(u_v))
	for u_v in unavailable_linked:
		if not (u_v in unavailable_all):
			unavailable_all.append(u_v)

	return {
		"engineProfile": eng_id,
		"modProfile": mod_id,
		"missionProfile": mis_id,
		"mapFolder": map_folder,
		"gameRoot": eff_game,
		"vrvRoot": eff_vrv,
		"linkedFolders": linked_folders,
		"modAssetRoots": mod_roots,
		"nativeRoots": native_roots,
		"searchRoots": search_roots,
		"layeredRoots": layered_roots,
		"soundRoots": sound_roots,
		"missionDllRoots": dll_roots,
		"dependencyStack": dep_res["dependencyStack"],
		"missingDependencies": dep_res["missingDependencies"],
		"disabledDependencies": dep_res["disabledDependencies"],
		"dependencyCycles": dep_res["dependencyCycles"],
		"duplicateRoots": dep_res["duplicateRoots"],
		"unavailableRoots": unavailable_all,
		"localFallbackUsed": bool(dep_res["localFallbackUsed"]),
		"modInstalled": bool(dep_res["installed"]),
		"knownProfile": bool(dep_res["knownProfile"]),
		"dependenciesComplete": bool(dep_res["complete"]) and unavailable_linked.is_empty(),
	}


## Inspects real map package data (BZN DLL, ODF names, path names, Lua files)
## and produces evidence-based candidate ModProfile + MissionProfile rankings.
## NEVER selects VRV merely because a converter or VRV tools exist locally.
## NEVER promotes naming-convention hints (LIKELY_STOCK_NAMING) to VERIFIED_STOCK
## or Stock HIGH confidence, and NEVER treats a matching DLL basename alone as
## Stock proof when unverified ODFs exist.
static func detect_map_profiles(package: Object, registry: Object = null) -> Dictionary:
	var dll := String(package.mission_dll).strip_edges().to_lower() if package != null else ""
	var has_lua := false
	if package != null:
		for member: String in package.files:
			if member.get_extension().to_lower() == "lua":
				has_lua = true
				break
	var stock_odf_index := {}
	if registry != null and registry.has_method("get_stock_odf_index"):
		stock_odf_index = registry.get_stock_odf_index()

	var vsr_odfs: Array[String] = []
	var vrv_odfs: Array[String] = []
	var verified_stock_odfs: Array[String] = []
	var likely_stock_odfs: Array[String] = []
	var unknown_odfs: Array[String] = []
	var odf_classifications := {}
	var seen_odf := {}

	if package != null:
		for obj: Dictionary in package.objects:
			var odf := String(obj.get("odf", "")).to_lower()
			var lbl := String(obj.get("label", "")).to_lower()
			if lbl.begins_with("vrvsnd:") and odf != "vrv_sndpoint":
				if not ("vrv_sndpoint" in vrv_odfs):
					vrv_odfs.append("vrv_sndpoint")
				odf_classifications["vrv_sndpoint"] = ODF_VERIFIED_MOD
			if odf.is_empty() or seen_odf.has(odf):
				continue
			seen_odf[odf] = true
			var origin := classify_odf_origin(odf, stock_odf_index)
			var cls := String(origin["classification"])
			odf_classifications[odf] = cls
			if cls == ODF_VERIFIED_MOD:
				var src_mod := String(origin["sourceMod"])
				if src_mod == "vrv":
					vrv_odfs.append(odf)
				elif src_mod == "vsr":
					vsr_odfs.append(odf)
				else:
					unknown_odfs.append(odf)
			elif cls == ODF_VERIFIED_STOCK:
				verified_stock_odfs.append(odf)
			elif cls == ODF_LIKELY_STOCK_NAMING:
				likely_stock_odfs.append(odf)
			else:
				unknown_odfs.append(odf)

	var unverified_all: Array[String] = []
	unverified_all.append_array(likely_stock_odfs)
	unverified_all.append_array(unknown_odfs)

	var path_lower := {}
	if package != null:
		for p: Dictionary in package.paths:
			path_lower[String(p.get("name", "")).to_lower()] = true

	var has_vrv_paths := path_lower.has("11patrol1") or path_lower.has("11mlay1") or path_lower.has("capturegoal1")
	var has_instant_paths := path_lower.has("recyclerenemy") or path_lower.has("gtow2")
	var has_vsr_strat_paths := path_lower.has("enemy_11") and path_lower.has("player_1")
	var is_custom_dll := not dll.is_empty() and not (dll in STOCK_KNOWN_DLLS)

	# Determine mission mode independently from mod
	var mission_mode := "blank"
	var mission_evidence: Array[String] = []
	if dll == "luamission.dll" or has_lua:
		mission_mode = "lua"
		mission_evidence.append("LuaMission.dll / .lua companion present")
	elif dll == "strategy02.dll":
		mission_mode = "strategy"
		mission_evidence.append("BZN mission DLL basename is Strategy02.dll")
	elif dll == "instant.dll":
		mission_mode = "instant"
		mission_evidence.append("BZN mission DLL basename is Instant.dll")
	elif dll == "mpinstant.dll":
		mission_mode = "mpi"
		mission_evidence.append("BZN mission DLL basename is mpinstant.dll")
	elif dll == "deathmatch01.dll":
		mission_mode = "duel"
		mission_evidence.append("BZN mission DLL basename is deathmatch01.dll")
	elif not dll.is_empty():
		mission_mode = "custom-dll"
		mission_evidence.append("BZN references custom DLL '%s'" % package.mission_dll)
	elif has_instant_paths:
		mission_mode = "instant"
		mission_evidence.append("Instant Action paths (RecyclerEnemy/gtow2) found")
	elif has_vsr_strat_paths:
		mission_mode = "strategy"
		mission_evidence.append("Strategy spawn paths (Player_1/Enemy_11) found")
	else:
		mission_evidence.append("No fixed mission DLL or script paths detected")

	# Score candidate ModProfiles purely from verified map evidence
	var candidates: Array[Dictionary] = []
	if not vrv_odfs.is_empty():
		candidates.append({
			"modProfile": "vrv",
			"missionProfile": mission_mode,
			"confidence": "high",
			"evidence": ["VRV-specific ODF(s): " + ", ".join(vrv_odfs.slice(0, 4))] + mission_evidence,
		})
	if not vsr_odfs.is_empty():
		var conf := "high" if vrv_odfs.is_empty() and not has_vrv_paths else "medium"
		candidates.append({
			"modProfile": "vsr",
			"missionProfile": mission_mode,
			"confidence": conf,
			"evidence": ["VSR ODF(s): " + ", ".join(vsr_odfs.slice(0, 4))] + mission_evidence,
		})
		if has_vrv_paths and vrv_odfs.is_empty():
			candidates.append({
				"modProfile": "vrv",
				"missionProfile": mission_mode,
				"confidence": "medium",
				"evidence": ["VSR ODFs + VRV/AIP patrol paths (11Patrol1/11MLay1)"] + mission_evidence,
			})
	if vrv_odfs.is_empty() and vsr_odfs.is_empty():
		var matched_custom_mod := ""
		var matched_custom_reason := ""
		if registry != null and registry.has_method("all_profile_ids"):
			if is_custom_dll:
				for mid: String in registry.all_profile_ids():
					if mid in ["stock", "vsr", "vrv"]:
						continue
					var prof: Dictionary = registry.get_profile(mid)
					for mdll_v in prof.get("missionDlls", []):
						if String(mdll_v).to_lower() == dll:
							matched_custom_mod = mid
							matched_custom_reason = "Matched custom mod DLL '%s' in profile %s" % [package.mission_dll, matched_custom_mod]
							break
					if not matched_custom_mod.is_empty():
						break
			# If unverified ODFs exist, try positive ODF resolution in installed custom mods
			if matched_custom_mod.is_empty() and not unverified_all.is_empty():
				var best_hits := 0
				for mid: String in registry.all_profile_ids():
					if mid in ["stock", "vsr", "vrv"]:
						continue
					var prof: Dictionary = registry.get_profile(mid)
					if not bool(prof.get("installed", false)):
						continue
					var hits := 0
					for ar_v in prof.get("assetRoots", []):
						var idx := AssetIndex.get_root_index(String(ar_v), true, false)
						var odf_map: Dictionary = idx.get("odfs", {})
						for u_odf in unverified_all:
							if odf_map.has(u_odf + ".odf"):
								hits += 1
					if hits > best_hits:
						best_hits = hits
						matched_custom_mod = mid
						matched_custom_reason = "Resolved %d/%d mod ODF(s) directly in installed profile %s" % [hits, unverified_all.size(), mid]

		if not matched_custom_mod.is_empty():
			candidates.append({
				"modProfile": matched_custom_mod,
				"missionProfile": mission_mode,
				"confidence": "high",
				"evidence": [matched_custom_reason] + mission_evidence,
			})
		elif is_custom_dll or not unverified_all.is_empty():
			var u_ev: Array[String] = []
			if is_custom_dll:
				u_ev.append("Unrecognized non-Stock mission DLL '%s'" % package.mission_dll)
			elif not dll.is_empty() and not unverified_all.is_empty():
				u_ev.append("DLL basename '%s' alone does not prove Stock when unverified ODF(s) are present" % package.mission_dll)
			if not unknown_odfs.is_empty():
				u_ev.append("UNKNOWN_ODF: " + ", ".join(unknown_odfs.slice(0, 4)))
			if not likely_stock_odfs.is_empty():
				u_ev.append("LIKELY_STOCK_NAMING (unverified hint only): " + ", ".join(likely_stock_odfs.slice(0, 4)))
			candidates.append({
				"modProfile": "custom:unknown",
				"missionProfile": mission_mode,
				"confidence": "medium",
				"evidence": u_ev + mission_evidence,
			})
			candidates.append({
				"modProfile": "stock",
				"missionProfile": mission_mode,
				"confidence": "low",
				"evidence": ["Unverified Stock fallback (%d verified Stock, %d unverified ODFs)" % [verified_stock_odfs.size(), unverified_all.size()]] + mission_evidence,
			})
		else:
			candidates.append({
				"modProfile": "stock",
				"missionProfile": mission_mode,
				"confidence": "high" if not verified_stock_odfs.is_empty() else "medium",
				"evidence": ["%d verified Stock ODF(s), 0 unverified ODFs" % verified_stock_odfs.size()] + mission_evidence,
			})

	var recommended_mod := String(candidates[0]["modProfile"]) if not candidates.is_empty() else "stock"
	var ambiguous := (candidates.size() > 1 and String(candidates[0]["confidence"]) != "high") or recommended_mod == "custom:unknown"
	return {
		"recommendedMod": recommended_mod,
		"recommendedMission": mission_mode,
		"ambiguous": ambiguous,
		"unknownMod": recommended_mod == "custom:unknown",
		"missionDll": String(package.mission_dll) if package != null else "",
		"formatProfile": String(package.layout_id) if package != null else "",
		"candidates": candidates,
		"vsrOdfs": vsr_odfs,
		"vrvOdfs": vrv_odfs,
		"verifiedStockOdfs": verified_stock_odfs,
		"likelyStockOdfs": likely_stock_odfs,
		"unknownOdfs": unverified_all,
		"strictUnknownOdfs": unknown_odfs,
		"odfClassifications": odf_classifications,
	}


## Read-only dependency-aware dry-run conversion & compatibility report.
## Populates real missingOdfs/meshes/textures/sounds/DLL identity via AssetIndex
## and separates environmentSwitchStatus, nativeConversionStatus, and playtestStatus.
## Mutates nothing.
func analyze_conversion(document: Object, target_mod_id: String, target_mission_id: String, mission_profiles_script: Script, manual_map: Dictionary = {}, game_dir: String = "", vrv_dir: String = "") -> Dictionary:
	var compat_script: Script = load("res://core/compatibility_engine.gd")
	var eff_game := game_dir.strip_edges() if not game_dir.strip_edges().is_empty() else last_game_dir
	var eff_vrv := vrv_dir.strip_edges() if not vrv_dir.strip_edges().is_empty() else last_vrv_dir
	var eng_id := String(document.engine_profile) if document != null and "engine_profile" in document else "bzcc-2.0.185"
	var result: Dictionary = compat_script.evaluate(
		document, self, target_mod_id, target_mission_id, eng_id,
		eff_game, eff_vrv, manual_map, false, mission_profiles_script)
	var conv: Dictionary = result["conversionRequirements"]
	var missing_block: Dictionary = result["missingDependencies"]
	var mod_block: Dictionary = result["modProfile"]
	var mis_block: Dictionary = result["missionProfile"]
	var lossy: Array[String] = []
	for w_v in result.get("warnings", []):
		lossy.append(String(w_v))
	for r_v in result.get("refusalReasons", []):
		var r := String(r_v)
		if not (r in lossy):
			lossy.append(r)
	var env_status := String(result["environmentSwitchStatus"])
	return {
		"schema": String(result["schema"]),
		"compatibilityResult": result,
		"sourceMod": String(document.mod_profile) if document != null and "mod_profile" in document else "stock",
		"sourceMission": String(document.mission_profile) if document != null and "mission_profile" in document else "blank",
		"targetMod": target_mod_id,
		"targetMission": target_mission_id,
		"formatProfile": String(result["formatProfile"].get("id", "")),
		"modInstalled": bool(mod_block.get("installed", false)),
		"incompatibleOdfs": conv.get("incompatibleOdfs", []),
		"verifiedReplacements": conv.get("verifiedReplacements", []),
		"unverifiedOdfs": conv.get("unverifiedOdfs", []),
		"conversionFeasible": bool(conv.get("feasible", false)),
		"missingOdfs": missing_block.get("odfs", []),
		"missingMeshes": missing_block.get("meshes", []),
		"missingTextures": missing_block.get("textures", []),
		"missingSounds": missing_block.get("sounds", []),
		"missingDependencies": missing_block,
		"ambiguousOverrides": result.get("ambiguousOverrides", {}),
		"dllIdentity": result.get("dllIdentity", {}),
		"dllChange": String(conv.get("dllChange", "")),
		"missingRequiredPaths": mis_block.get("missingRequiredPaths", []),
		"pathErrors": mis_block.get("pathErrors", []),
		"pathWarnings": mis_block.get("pathWarnings", []),
		"lossyWarnings": lossy,
		"environmentSwitchStatus": env_status,
		"nativeConversionStatus": String(result["nativeConversionStatus"]),
		"playtestStatus": String(result["validationStatus"]),
		"safeToSwitchEnvironment": env_status != "INVALID_PROFILE",
		"requiresExplicitSaveAs": not (conv.get("incompatibleOdfs", []) as Array).is_empty() or not String(conv.get("dllChange", "")).is_empty(),
	}
