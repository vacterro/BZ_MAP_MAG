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
		"displayName": "BZCC 2.0.185 (Verified)",
		"version": "2.0.185",
		"verified": true,
		"supportedRoutes": ["native-1192", "convert-1196"],
	},
	"bzcc-auto-detected": {
		"id": "bzcc-auto-detected",
		"displayName": "BZCC (Auto-detected)",
		"version": "auto",
		"verified": false,
		"supportedRoutes": [],
	},
	"bzcc-unknown-readonly": {
		"id": "bzcc-unknown-readonly",
		"displayName": "Unknown / No Game Install (Read-only Playtest)",
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


## Inspects real map package data (BZN DLL, ODF names, path names, Lua files)
## and produces evidence-based candidate ModProfile + MissionProfile rankings.
## Never selects VRV merely because a converter or VRV tools exist locally.
static func detect_map_profiles(package: Object) -> Dictionary:
	var dll := String(package.mission_dll).strip_edges().to_lower() if package != null else ""
	var has_lua := false
	if package != null:
		for member: String in package.files:
			if member.get_extension().to_lower() == "lua":
				has_lua = true
				break
	var vsr_odfs: Array[String] = []
	var vrv_odfs: Array[String] = []
	var stock_odf_count := 0
	if package != null:
		for obj: Dictionary in package.objects:
			var odf := String(obj.get("odf", "")).to_lower()
			if odf.begins_with("vrv_") or odf == "vrv_sndpoint":
				if not (odf in vrv_odfs):
					vrv_odfs.append(odf)
			elif odf.ends_with("_vsr") or "_vsr" in odf:
				if not (odf in vsr_odfs):
					vsr_odfs.append(odf)
			elif not odf.is_empty():
				stock_odf_count += 1
	var path_lower := {}
	if package != null:
		for p: Dictionary in package.paths:
			path_lower[String(p.get("name", "")).to_lower()] = true

	var has_vrv_paths := path_lower.has("11patrol1") or path_lower.has("11mlay1") or path_lower.has("capturegoal1")
	var has_instant_paths := path_lower.has("recyclerenemy") or path_lower.has("gtow2")
	var has_vsr_strat_paths := path_lower.has("enemy_11") and path_lower.has("player_1")

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
		candidates.append({
			"modProfile": "stock",
			"missionProfile": mission_mode,
			"confidence": "high" if stock_odf_count > 0 or not dll.is_empty() else "medium",
			"evidence": ["No VSR/VRV-prefixed ODFs found (%d stock/generic objects)" % stock_odf_count] + mission_evidence,
		})

	var recommended_mod := String(candidates[0]["modProfile"]) if not candidates.is_empty() else "stock"
	var ambiguous := candidates.size() > 1 and String(candidates[0]["confidence"]) != "high"
	return {
		"recommendedMod": recommended_mod,
		"recommendedMission": mission_mode,
		"ambiguous": ambiguous,
		"missionDll": String(package.mission_dll) if package != null else "",
		"formatProfile": String(package.layout_id) if package != null else "",
		"candidates": candidates,
		"vsrOdfs": vsr_odfs,
		"vrvOdfs": vrv_odfs,
	}


## Read-only dry-run compatibility report when converting a map from its current
## profile to a different target (ModProfile, MissionProfile). Mutates nothing.
func analyze_conversion(document: Object, target_mod_id: String, target_mission_id: String, mission_profiles_script: Script) -> Dictionary:
	var missing_odfs: Array[String] = []
	var incompatible_odfs: Array[String] = []
	var seen := {}
	for view in document.object_count():
		var odf := String(document.object_odf(view)).to_lower()
		if odf.is_empty() or seen.has(odf):
			continue
		seen[odf] = true
		if target_mod_id == "stock":
			if odf.begins_with("vrv_") or odf == "vrv_sndpoint":
				incompatible_odfs.append(odf + " (VRV-specific)")
			elif odf.ends_with("_vsr") or "_vsr" in odf:
				incompatible_odfs.append(odf + " (VSR-specific)")
		elif target_mod_id == "vsr":
			if odf.begins_with("vrv_") or odf == "vrv_sndpoint":
				incompatible_odfs.append(odf + " (VRV-specific)")
	var target_manifest := get_profile(target_mod_id)
	var mod_installed := bool(target_manifest.get("installed", target_mod_id == "stock"))
	var validation: Dictionary = mission_profiles_script.validate(document, target_mission_id, target_mod_id)
	var current_dll := String(document.package.mission_dll)
	var expected_dll: String = String(mission_profiles_script.expected_dll(target_mission_id, target_mod_id))
	var dll_change := ""
	if not expected_dll.is_empty() and current_dll.nocasecmp_to(expected_dll) != 0:
		dll_change = "%s -> %s" % [current_dll if not current_dll.is_empty() else "(none)", expected_dll]
	var lossy: Array[String] = []
	if not incompatible_odfs.is_empty():
		lossy.append("Target mod '%s' does not include %d mod-specific ODF class(es); source objects will NOT be silently replaced." % [target_mod_id, incompatible_odfs.size()])
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
		"missingOdfs": missing_odfs,
		"dllChange": dll_change,
		"missingRequiredPaths": validation.get("missing_required", []),
		"pathErrors": validation.get("errors", []),
		"pathWarnings": validation.get("warnings", []),
		"lossyWarnings": lossy,
		"safeToSwitchEnvironment": true,
		"requiresExplicitSaveAs": not incompatible_odfs.is_empty() or not dll_change.is_empty(),
	}
