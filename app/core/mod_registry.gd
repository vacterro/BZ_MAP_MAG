extends RefCounted
## Universal BZCC EngineProfile & ModProfile registry, Workshop auto-discovery,
## open-map profile detection, and dry-run conversion compatibility analysis.
##
## Architecture:
## - EngineProfile, ModProfile, MissionProfile, and FormatProfile stay strictly independent.
## - Stock BZCC works without VRV or VSR installed.
## - Unknown Workshop mods open safely as custom profiles without fabricated DLL rules.
## - Discovery is read-only, bounded, symlink-safe, and never executes installed DLLs.

const SCHEMA := "bzmag.mod-profile/1"
const BZCC_APP_ID := "624970"
const VSR_WORKSHOP_ID := "1325933293"
const VRV_WORKSHOP_ID := "3820486276"

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
var disabled_mods: Dictionary = {}
var custom_mods: Dictionary = {}
var last_game_dir := ""
var last_workshop_root := ""


func _init() -> void:
	reset_builtins()


func reset_builtins() -> void:
	profiles.clear()
	discovered_order.clear()
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
		"dependencies": ["stock", "vsr", "3532748119", "1329659846", "2785557433", "2785542655", "2814914461", "2049956570", "3493379153", "2467249743"],
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


func discover_installed(game_dir: String, vrv_dir: String = "", workshop_override: String = "") -> Dictionary:
	reset_builtins()
	last_game_dir = game_dir.strip_edges()
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

	# 2. Scan Steam Workshop items (bounded, lazy: top-level .ini + Missions/*.dll only)
	var workshop_items := {}
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
		var roots: Array[String] = [String(item["path"])]
		var missing: Array[String] = []
		var deps: Array = item["assetDependencies"]
		if not deps.is_empty():
			var full_deps: Array[String] = ["stock"]
			for d_v in deps:
				var dep_id := String(d_v)
				full_deps.append(dep_id)
				if workshop_items.has(dep_id):
					roots.append(String(workshop_items[dep_id]["path"]))
				else:
					missing.append(dep_id)
			vsr["dependencies"] = full_deps
		vsr["assetRoots"] = roots
		vsr["missingDependencies"] = missing
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
		vrv_roots.append(String(item["path"]))
		if workshop_items.has(VSR_WORKSHOP_ID):
			vrv_roots.append(String(workshop_items[VSR_WORKSHOP_ID]["path"]))
		else:
			vrv_missing.append(VSR_WORKSHOP_ID)
		for d_v in item["assetDependencies"]:
			var dep_id := String(d_v)
			if workshop_items.has(dep_id):
				vrv_roots.append(String(workshop_items[dep_id]["path"]))
			else:
				vrv_missing.append(dep_id)
		if not (item["dlls"] as Array).is_empty():
			vrv["missionDlls"] = item["dlls"]
	elif not last_game_dir.is_empty() and DirAccess.dir_exists_absolute(last_game_dir.path_join("VRV")):
		vrv["installed"] = true
		vrv["gameRoot"] = last_game_dir.path_join("VRV")
		vrv_roots.append(last_game_dir.path_join("VRV"))
	if not vrv_dir.strip_edges().is_empty() and DirAccess.dir_exists_absolute(vrv_dir.strip_edges().path_join("mod/Data/Templates")):
		var tpl_dir := vrv_dir.strip_edges().path_join("mod/Data/Templates")
		var tpl := tpl_dir.path_join("vrv_new_blank.ter")
		if FileAccess.file_exists(tpl):
			vrv["templates"] = [tpl]
	vrv["assetRoots"] = vrv_roots
	vrv["missingDependencies"] = vrv_missing
	_register(vrv)

	# 5. Register all other discovered config Workshop mods as custom:<workshopId>
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
		var roots: Array[String] = [String(item["path"])]
		var missing: Array[String] = []
		var deps: Array[String] = ["stock"]
		for d_v in item["assetDependencies"]:
			var dep_id := String(d_v)
			deps.append(dep_id)
			if workshop_items.has(dep_id):
				roots.append(String(workshop_items[dep_id]["path"]))
			else:
				missing.append(dep_id)
		var modes: Array[String] = ["blank", "custom-dll", "lua"]
		for dll_name: String in item["dlls"]:
			var dl := dll_name.to_lower()
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
			"assetRoots": roots,
			"dependencies": deps,
			"missingDependencies": missing,
			"missionModes": modes,
			"missionDlls": item["dlls"],
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
		if not profiles.has(dep):
			continue
		var st := int(state.get(dep, 0))
		if st == 1:
			cycles.append("%s -> %s" % [node, dep])
		elif st == 0:
			_dfs_cycle(dep, state, cycles)
	state[node] = 2


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

const VERIFIED_STOCK_ODF_FAMILIES := {
	"player": "craft",
	"ivtank": "craft", "ivscout": "craft", "ivmisl": "craft", "ivturr": "craft",
	"ivscav": "craft", "ivcons": "craft", "ivserv": "craft", "ivatank": "craft",
	"ivrckt": "craft", "ivmbike": "craft", "ivwalk": "craft", "ivapc": "craft",
	"ivrecy": "craft", "ivrecy_m": "craft", "ivrecycpu": "craft", "ivtug": "craft",
	"ivintc": "craft", "ivbomb": "craft", "ivdrop": "craft", "ivdrop_fly": "craft",
	"ivdrop_land": "craft", "ivdrop_sh": "craft", "ivpdrop": "craft",
	"fvscout": "craft", "fvtank": "craft", "fvsent": "craft", "fvturr": "craft",
	"fvscav": "craft", "fvcons": "craft", "fvserv": "craft", "fvatank": "craft",
	"fvarch": "craft", "fvwalk": "craft", "fvartl": "craft", "fvrecy": "craft",
	"fvrecy_m": "craft", "fvrecycpu": "craft", "fvtug": "craft",
	"ibrecy": "building", "ibrecy_m": "building", "ibfact": "building", "ibsbay": "building",
	"ibbomb": "building", "ibtele": "building", "ibtcen": "building", "ibtrain": "building",
	"ibarmo": "building", "ibcbun": "building", "ibgtow": "building", "ibpgen": "building",
	"ibbstr": "building", "ibbseg": "building", "ibcrat00": "building", "ibcrat01": "building",
	"iblite": "building", "ibscav": "building", "ibscup": "building", "ibwseg": "building",
	"ibwstr": "building", "fbrecy": "building", "fbrecy_m": "building", "fbfact": "building",
	"fbkiln": "building", "fbforb": "building", "fbdowe": "building", "fbstro": "building",
	"fbover": "building", "fbspir": "building", "fbantm": "building", "fbjamm": "building",
	"fbscav": "building", "fbscup": "building", "ipdrop": "building",
	"ispilo": "pilot", "issold": "pilot", "fspilo": "pilot", "fssold": "pilot",
	"becras02a": "building", "perecy": "building", "petank": "building", "pescav": "building", "peapc": "building",
	"pspwn_1": "spawnpoint",
	"npscrx": "pool", "npscr1": "pool", "npscr2": "pool", "npscr3": "pool",
	"npba": "pool", "uepool01": "pool", "tepool01": "pool", "cpool01": "pool",
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


static func is_verified_stock_odf(odf: String) -> bool:
	var clean := odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	if clean.is_empty():
		return false
	if clean.begins_with("vrv_") or clean == "vrv_sndpoint" or clean.ends_with("_vsr") or "_vsr" in clean or ":" in clean:
		return false
	if VERIFIED_STOCK_ODF_FAMILIES.has(clean):
		return true
	return _is_likely_stock_odf(clean)


## Looks up a verified semantic conversion for a single ODF from source_mod to target_mod.
## Never performs heuristic name-stripping (such as odf.replace("_vsr", "")).
static func lookup_verified_odf_conversion(source_odf: String, target_mod: String = "stock", manual_map: Dictionary = {}) -> Dictionary:
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
		if tgt_mod == "stock" and not VERIFIED_STOCK_ODF_FAMILIES.has(chosen_raw):
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
		if is_verified_stock_odf(clean):
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
		return {
			"status": "unverified",
			"sourceOdf": source_odf,
			"targetOdf": "",
			"sourceMod": "vsr" if "_vsr" in clean else "unknown",
			"targetMod": "stock",
			"classCompatible": false,
			"error": "No verified Stock counterpart for '%s' (heuristic _vsr stripping is prohibited)." % source_odf,
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
		if is_verified_stock_odf(clean) or VERIFIED_VSR_TO_STOCK_ODFS.has(clean):
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
static func plan_bzn_odf_conversion(entries: Array, ptr_counts: Dictionary, target_mod: String = "stock", manual_map: Dictionary = {}, allow_drop_vrv: bool = false) -> Dictionary:
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
		var lookup := lookup_verified_odf_conversion(check_odf, target_mod, manual_map)
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
## Playtest. Strict Stock isolation: when mod_profile == 'stock', modAssetRoots
## is ALWAYS empty (never mounts VRV/Core, VRV/deps, or Workshop mod folders).
func resolve_content_environment(document: Object, game_dir: String = "", vrv_dir: String = "") -> Dictionary:
	var eff_game := game_dir.strip_edges() if not game_dir.strip_edges().is_empty() else last_game_dir
	var mod_id := String(document.mod_profile).strip_edges().to_lower() if document != null and "mod_profile" in document else "stock"
	var mis_id := String(document.mission_profile).strip_edges().to_lower() if document != null and "mission_profile" in document else "blank"
	var eng_id := String(document.engine_profile).strip_edges() if document != null and "engine_profile" in document else "bzcc-2.0.185"
	var map_folder: String = String(document.package.source_path).get_base_dir() if document != null and document.package != null else ""

	var linked_folders: Array[String] = []
	if document != null and "asset_profile" in document and not String(document.asset_profile).is_empty():
		var ap := String(document.asset_profile)
		if FileAccess.file_exists(ap):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ap))
			if parsed is Dictionary and parsed.get("folders", null) is Array:
				var base_dir := ap.get_base_dir()
				for entry_v in parsed["folders"]:
					var entry := String(entry_v).strip_edges()
					if entry.is_empty():
						continue
					var full := entry if entry.is_absolute_path() else base_dir.path_join(entry).simplify_path()
					if DirAccess.dir_exists_absolute(full) and not (full in linked_folders):
						linked_folders.append(full)

	var mod_roots: Array[String] = []
	if mod_id != "stock":
		var prof := get_profile(mod_id)
		for r_v in prof.get("assetRoots", []):
			var r := String(r_v).strip_edges()
			if not r.is_empty() and DirAccess.dir_exists_absolute(r) and not (r in mod_roots):
				mod_roots.append(r)
		# Local VRV/deps fallback only for VSR/VRV when Workshop roots are absent
		if mod_roots.is_empty() and not eff_game.is_empty() and mod_id in ["vsr", "vrv"]:
			if mod_id == "vrv":
				var vrv_core := eff_game.path_join("VRV/Core")
				if DirAccess.dir_exists_absolute(vrv_core):
					mod_roots.append(vrv_core)
			var deps_dir := eff_game.path_join("VRV/deps")
			for sub in ["VSR", "3532748119", "1329659846", "2785557433", "2785542655", "2814914461", "2049956570", "3493379153", "2467249743"]:
				var p := deps_dir.path_join(sub)
				if DirAccess.dir_exists_absolute(p) and not (p in mod_roots):
					mod_roots.append(p)

	var native_roots: Array[String] = []
	if not eff_game.is_empty():
		for sub in ["bz2r_res", "bz2r_loc"]:
			var p := eff_game.path_join(sub)
			if DirAccess.dir_exists_absolute(p):
				native_roots.append(p)

	var search_roots: Array[String] = []
	if not map_folder.is_empty():
		search_roots.append(map_folder)
	for r in linked_folders + mod_roots + native_roots:
		if not (r in search_roots):
			search_roots.append(r)

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

	return {
		"engineProfile": eng_id,
		"modProfile": mod_id,
		"missionProfile": mis_id,
		"mapFolder": map_folder,
		"gameRoot": eff_game,
		"vrvRoot": vrv_dir.strip_edges(),
		"linkedFolders": linked_folders,
		"modAssetRoots": mod_roots,
		"nativeRoots": native_roots,
		"searchRoots": search_roots,
		"soundRoots": sound_roots,
		"missionDllRoots": dll_roots,
	}


static func _is_likely_stock_odf(odf: String) -> bool:
	var clean := odf.strip_edges().to_lower()
	if clean.ends_with(".odf"):
		clean = clean.substr(0, clean.length() - 4)
	if clean.is_empty():
		return true
	if clean.begins_with("vrv_") or clean.ends_with("_vsr") or "_vsr" in clean or ":" in clean:
		return false
	# Standard BZCC Stock ODF faction/prop prefixes (ISDF i*, Scion f*, scrap/pools np*/sp*/ap*/gp*/ep*/cp*/pb*/mb*/ob*/bb*/cb*/sb*/tb*/ub*/wb*/xb*/yb*)
	for prefix in ["iv", "ib", "is", "ie", "fv", "fb", "fs", "fe", "av", "ab", "bv", "bb", "be", "cv", "cb", "ev", "eb", "gv", "gb", "hv", "hb", "mv", "mb", "nv", "nb", "ov", "ob", "pv", "pb", "pe", "ps", "sv", "sb", "tv", "tb", "uv", "ub", "wv", "wb", "xv", "xb", "yv", "yb", "np", "sp", "ap", "op", "gp", "ep", "cp", "fp", "ip", "mp", "rp", "tp", "vp", "wp", "xp", "mo", "ba", "mi", "du", "pl", "cr", "tr", "bu", "tu", "wa", "la", "br", "ro", "st", "cl", "pi", "co", "de", "fl", "gl", "gr", "hi", "ic", "ju", "ma", "me", "mu", "pa", "po", "qu", "ra", "re", "ri", "ru", "sa", "sc", "se", "sh", "si", "sk", "sl", "sm", "sn", "so", "sq", "su", "sw", "ta", "te", "th", "ti", "to", "un", "va", "ve", "vi", "vo", "wi", "wo", "wr", "ze"]:
		if clean.begins_with(prefix):
			return true
	return false


## Inspects real map package data (BZN DLL, ODF names, path names, Lua files)
## and produces evidence-based candidate ModProfile + MissionProfile rankings.
## Never selects VRV merely because a converter or VRV tools exist locally,
## and never assumes an unknown custom DLL or unknown mod ODFs are Stock.
static func detect_map_profiles(package: Object, registry: Object = null) -> Dictionary:
	var dll := String(package.mission_dll).strip_edges().to_lower() if package != null else ""
	var has_lua := false
	if package != null:
		for member: String in package.files:
			if member.get_extension().to_lower() == "lua":
				has_lua = true
				break
	var vsr_odfs: Array[String] = []
	var vrv_odfs: Array[String] = []
	var unknown_odfs: Array[String] = []
	var stock_odf_count := 0
	if package != null:
		for obj: Dictionary in package.objects:
			var odf := String(obj.get("odf", "")).to_lower()
			var lbl := String(obj.get("label", "")).to_lower()
			if odf.begins_with("vrv_") or odf == "vrv_sndpoint" or lbl.begins_with("vrvsnd:"):
				if not (odf in vrv_odfs):
					vrv_odfs.append(odf)
			elif odf.ends_with("_vsr") or "_vsr" in odf:
				if not (odf in vsr_odfs):
					vsr_odfs.append(odf)
			elif not odf.is_empty():
				if is_verified_stock_odf(odf):
					stock_odf_count += 1
				else:
					if not (odf in unknown_odfs):
						unknown_odfs.append(odf)
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
		mission_evidence.append("BZN mission DLL is Strategy02.dll")
	elif dll == "instant.dll":
		mission_mode = "instant"
		mission_evidence.append("BZN mission DLL is Instant.dll")
	elif dll == "mpinstant.dll":
		mission_mode = "mpi"
		mission_evidence.append("BZN mission DLL is mpinstant.dll")
	elif dll == "deathmatch01.dll":
		mission_mode = "duel"
		mission_evidence.append("BZN mission DLL is deathmatch01.dll")
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

	# Score candidate ModProfiles purely from map data
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
		# Check if a custom DLL or unknown ODFs indicate a non-Stock mod
		var matched_custom_mod := ""
		if is_custom_dll and registry != null and registry.has_method("all_profile_ids"):
			for mid: String in registry.all_profile_ids():
				if mid in ["stock", "vsr", "vrv"]:
					continue
				var prof: Dictionary = registry.get_profile(mid)
				for mdll_v in prof.get("missionDlls", []):
					if String(mdll_v).to_lower() == dll:
						matched_custom_mod = mid
						break
				if not matched_custom_mod.is_empty():
					break
		if not matched_custom_mod.is_empty():
			candidates.append({
				"modProfile": matched_custom_mod,
				"missionProfile": mission_mode,
				"confidence": "high",
				"evidence": ["Matched custom mod DLL '%s' in profile %s" % [package.mission_dll, matched_custom_mod]] + mission_evidence,
			})
		elif is_custom_dll or not unknown_odfs.is_empty():
			var u_ev: Array[String] = []
			if is_custom_dll:
				u_ev.append("Unrecognized non-Stock mission DLL '%s'" % package.mission_dll)
			if not unknown_odfs.is_empty():
				u_ev.append("Non-Stock ODF prefix(es): " + ", ".join(unknown_odfs.slice(0, 4)))
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
				"evidence": ["Fallback Stock profile (unverified with custom DLL/ODFs)"] + mission_evidence,
			})
		else:
			candidates.append({
				"modProfile": "stock",
				"missionProfile": mission_mode,
				"confidence": "high" if stock_odf_count > 0 or not dll.is_empty() else "medium",
				"evidence": ["No VSR/VRV-prefixed ODFs found (%d stock/generic objects)" % stock_odf_count] + mission_evidence,
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
		"unknownOdfs": unknown_odfs,
	}


## Read-only dry-run compatibility report when converting a map from its current
## profile to a different target (ModProfile, MissionProfile). Mutates nothing.
func analyze_conversion(document: Object, target_mod_id: String, target_mission_id: String, mission_profiles_script: Script, manual_map: Dictionary = {}) -> Dictionary:
	var missing_odfs: Array[String] = []
	var incompatible_odfs: Array[String] = []
	var verified_replacements: Array[String] = []
	var unverified_odfs: Array[String] = []
	var seen := {}
	for view in document.object_count():
		var odf := String(document.object_odf(view)).to_lower()
		var lbl := String(document.object_label(view)).to_lower()
		var key_odf := "vrv_sndpoint" if lbl.begins_with("vrvsnd:") and odf != "vrv_sndpoint" else odf
		if key_odf.is_empty() or seen.has(key_odf):
			continue
		seen[key_odf] = true
		var lookup := lookup_verified_odf_conversion(key_odf, target_mod_id, manual_map)
		var st := String(lookup.get("status", "native"))
		if st == "native":
			continue
		elif st in ["verified", "verified_manual"]:
			incompatible_odfs.append("%s -> %s (verified)" % [key_odf, String(lookup["targetOdf"])])
			verified_replacements.append("%s -> %s" % [key_odf, String(lookup["targetOdf"])])
		else:
			var reason := String(lookup.get("error", "unverified"))
			incompatible_odfs.append("%s (UNSUPPORTED: %s)" % [key_odf, reason])
			unverified_odfs.append(key_odf)
	var target_manifest := get_profile(target_mod_id)
	var mod_installed := bool(target_manifest.get("installed", target_mod_id == "stock"))
	var validation: Dictionary = mission_profiles_script.validate(document, target_mission_id, target_mod_id)
	var current_dll := String(document.package.mission_dll)
	var expected_dll: String = String(mission_profiles_script.expected_dll(target_mission_id, target_mod_id))
	var dll_change := ""
	if not expected_dll.is_empty() and current_dll.nocasecmp_to(expected_dll) != 0:
		dll_change = "%s -> %s" % [current_dll if not current_dll.is_empty() else "(none)", expected_dll]
	var lossy: Array[String] = []
	if not unverified_odfs.is_empty():
		lossy.append("Target mod '%s' has %d unverified/unsupported ODF class(es) (%s); conversion is blocked without a verified same-class mapping." % [
			target_mod_id, unverified_odfs.size(), ", ".join(unverified_odfs)])
	elif not verified_replacements.is_empty():
		lossy.append("Target mod '%s' requires verified semantic ODF conversion for %d class(es): %s." % [
			target_mod_id, verified_replacements.size(), ", ".join(verified_replacements)])
	if not mod_installed:
		lossy.append("Target mod '%s' is not detected locally; preview and Playtest assets may be unavailable." % target_mod_id)
	return {
		"sourceMod": String(document.mod_profile),
		"sourceMission": String(document.mission_profile),
		"targetMod": target_mod_id,
		"targetMission": target_mission_id,
		"formatProfile": String(document.package.layout_id),
		"modInstalled": mod_installed,
		"incompatibleOdfs": incompatible_odfs,
		"verifiedReplacements": verified_replacements,
		"unverifiedOdfs": unverified_odfs,
		"conversionFeasible": unverified_odfs.is_empty(),
		"missingOdfs": missing_odfs,
		"dllChange": dll_change,
		"missingRequiredPaths": validation.get("missing_required", []),
		"pathErrors": validation.get("errors", []),
		"pathWarnings": validation.get("warnings", []),
		"lossyWarnings": lossy,
		"safeToSwitchEnvironment": true,
		"requiresExplicitSaveAs": not incompatible_odfs.is_empty() or not dll_change.is_empty(),
	}
