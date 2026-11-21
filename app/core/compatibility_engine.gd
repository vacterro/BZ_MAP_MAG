extends RefCounted
## Unified authoritative compatibility engine (bzmag.compatibility-result/1).
##
## Single source of truth consumed by:
## - Open Map (editor.gd)
## - New Map Wizard (new_map_wizard.gd)
## - Target Profile & Conversion Analysis (target_profile_dialog.gd, mod_registry.gd)
## - Object Browser (object_browser.gd)
## - Export Native (editor.gd)
## - F5 Playtest (editor.gd)
## - Playtest -ValidateOnly (playtest_validation.gd / Start-Playtest.ps1)
##
## Design guarantees:
## - Never claims READY when required assets, DLLs, dependencies, layout, or engine
##   are missing or unverified. Returns UNKNOWN when inputs are indeterminate.
## - Never elevates naming heuristics (LIKELY_STOCK_NAMING) to VERIFIED_STOCK.
## - Decouples Stock native 1192 launch route from optional/stale VRV converter setup.

const SCHEMA := "bzmag.compatibility-result/1"

const AssetIndex := preload("res://core/asset_index.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const BznPaths := preload("res://formats/bzn_paths.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const MapPackage := preload("res://formats/map_package.gd")

# Separate outcome constants (Section 3 & 4)
const ENV_SAFE_NONDESTRUCTIVE := "SAFE_NONDESTRUCTIVE"
const ENV_MISSING_PREVIEW_ASSETS := "MISSING_PREVIEW_ASSETS"
const ENV_INVALID_PROFILE := "INVALID_PROFILE"
const ENV_UNRESOLVED_DEPENDENCIES := "UNRESOLVED_DEPENDENCIES"

const CONV_VERIFIED_AVAILABLE := "VERIFIED_CONVERSION_AVAILABLE"
const CONV_MANUAL_REQUIRED := "MANUAL_MAPPING_REQUIRED"
const CONV_UNSUPPORTED := "UNSUPPORTED"
const CONV_UNKNOWN := "UNKNOWN"

const PLAYTEST_READY := "READY"
const PLAYTEST_MISSING_ASSETS := "MISSING_ASSETS"
const PLAYTEST_MISSING_DLL := "MISSING_DLL"
const PLAYTEST_FORMAT_UNSUPPORTED := "FORMAT_UNSUPPORTED"
const PLAYTEST_ENGINE_UNVERIFIED := "ENGINE_UNVERIFIED"
const PLAYTEST_MISSION_UNVERIFIED := "MISSION_UNVERIFIED"
const PLAYTEST_UNKNOWN := "UNKNOWN"

# Gameplay evidence levels (Section 6)
const EV_UNKNOWN := "UNKNOWN"
const EV_FORMAT_VERIFIED := "FORMAT_VERIFIED"
const EV_GAME_LOAD_VERIFIED := "GAME_LOAD_VERIFIED"
const EV_MISSION_RUN_VERIFIED := "MISSION_RUN_VERIFIED"
const EV_INTERACTIVE_GAMEPLAY_VERIFIED := "INTERACTIVE_GAMEPLAY_VERIFIED"
const EV_NORMAL_EXIT_VERIFIED := "NORMAL_EXIT_VERIFIED"


static func valid_converter_path(path: String) -> bool:
	var clean := path.strip_edges()
	if clean.is_empty() or not clean.is_absolute_path():
		return false
	if clean.to_lower().ends_with(".py"):
		return FileAccess.file_exists(clean)
	return FileAccess.file_exists(clean.path_join("tools/bzn_compat.py"))


static func valid_game_dir(path: String) -> bool:
	var clean := path.strip_edges()
	return clean.is_absolute_path() and FileAccess.file_exists(clean.path_join("battlezone2.exe")) and DirAccess.dir_exists_absolute(clean.path_join("bz2r_res"))


## Evaluates compatibility for an open MapDocument OR a MapPackage.
static func evaluate(subject: Object, registry: ModRegistry, target_mod: String = "", target_mission: String = "", target_engine: String = "", game_dir: String = "", vrv_dir: String = "", manual_map: Dictionary = {}, without_mission_script: bool = false, mission_profiles_script: Script = null, asset_profile_override: String = "", extra_roots_override: Array = []) -> Dictionary:
	var mp_script: Script = mission_profiles_script if mission_profiles_script != null else MissionProfiles
	var reg: ModRegistry = registry if registry != null else ModRegistry.new()
	var is_doc := subject != null and ("package" in subject) and subject.has_method("object_count")
	var pkg: Object = subject.package if is_doc else subject

	var eff_mod := target_mod.strip_edges().to_lower()
	if eff_mod.is_empty():
		eff_mod = String(subject.mod_profile).strip_edges().to_lower() if is_doc else "stock"
	var eff_mission := target_mission.strip_edges().to_lower()
	if eff_mission.is_empty():
		eff_mission = String(subject.mission_profile).strip_edges().to_lower() if is_doc else "blank"
	var eff_engine := target_engine.strip_edges()
	if eff_engine.is_empty():
		eff_engine = String(subject.engine_profile).strip_edges() if is_doc else "bzcc-2.0.185"
	var eff_game := game_dir.strip_edges() if not game_dir.strip_edges().is_empty() else reg.last_game_dir
	var eff_vrv := vrv_dir.strip_edges() if not vrv_dir.strip_edges().is_empty() else reg.last_vrv_dir

	var env := reg.resolve_content_environment(subject, eff_game, eff_vrv, eff_mod, eff_mission, eff_engine, asset_profile_override, extra_roots_override)
	var stock_odf_index := reg.get_stock_odf_index(eff_game)
	var layered_roots: Array[Dictionary] = []
	for lr_v in env.get("layeredRoots", []):
		layered_roots.append(lr_v as Dictionary)
	var layered_index := AssetIndex.index_layered_roots(layered_roots)

	# 1. Source map identity & format capabilities
	var bzn_version := int(pkg.bzn_version) if pkg != null and "bzn_version" in pkg else 0
	var layout_id := String(pkg.layout_id) if pkg != null and "layout_id" in pkg else ""
	var layout_info := Layouts.profile(layout_id)
	var encoding := String(layout_info.get("encoding", "binary" if bzn_version > 0 else ""))
	var route := Layouts.playtest_route(bzn_version, encoding) if bzn_version > 0 else "refuse"
	var writer_caps := Layouts.capabilities(layout_id)
	var map_path := String(pkg.source_path) if pkg != null and "source_path" in pkg else ""
	var map_folder := String(env.get("mapFolder", ""))
	var current_dll := String(pkg.mission_dll) if pkg != null and "mission_dll" in pkg else ""
	var obj_count := int(subject.object_count()) if is_doc else ((pkg.objects as Array).size() if pkg != null and "objects" in pkg else 0)
	var path_count := (subject.path_indices() as Array).size() if is_doc else ((pkg.paths as Array).size() if pkg != null and "paths" in pkg else 0)

	var source_identity := {
		"path": map_path,
		"bznName": String(pkg.bzn_name) if pkg != null and "bzn_name" in pkg else map_path.get_file(),
		"bznVersion": bzn_version,
		"layoutId": layout_id,
		"missionDll": current_dll,
		"objectCount": obj_count,
		"pathCount": path_count,
		"files": pkg.files.duplicate() if pkg != null and "files" in pkg else {},
	}

	# 2. EngineProfile verification
	var eng_meta: Dictionary = ModRegistry.ENGINE_PROFILES.get(eff_engine, {})
	var eng_verified_profile := bool(eng_meta.get("verified", false))
	var exe_path := eff_game.path_join("battlezone2.exe") if not eff_game.is_empty() else ""
	var exe_present := not eff_game.is_empty() and valid_game_dir(eff_game)
	var exe_size := 0
	if exe_present:
		var ef := FileAccess.open(exe_path, FileAccess.READ)
		if ef != null:
			exe_size = ef.get_length()
			ef.close()
	# Distinguish a real BZCC executable from a 1-byte mock fixture
	var real_stock_assets_present := not stock_odf_index.is_empty() or exe_size > 4096
	var engine_block := {
		"id": eff_engine,
		"version": String(eng_meta.get("version", "unknown")),
		"verified": eng_verified_profile and exe_present,
		"gameRoot": eff_game,
		"exePresent": exe_present,
		"exeSizeBytes": exe_size,
		"realStockAssetsPresent": real_stock_assets_present,
	}

	# 3. ModProfile & Dependency Stack
	var known_mod := bool(env.get("knownProfile", false))
	var mod_installed := bool(env.get("modInstalled", false))
	var missing_mod_deps: Array[String] = []
	for d_v in env.get("missingDependencies", []):
		missing_mod_deps.append(String(d_v))
	var disabled_mod_deps: Array[String] = []
	for d_v in env.get("disabledDependencies", []):
		disabled_mod_deps.append(String(d_v))
	var dep_cycles: Array[String] = []
	for c_v in env.get("dependencyCycles", []):
		dep_cycles.append(String(c_v))
	var unavailable_roots: Array[String] = []
	for u_v in env.get("unavailableRoots", []):
		unavailable_roots.append(String(u_v))
	var deps_complete := bool(env.get("dependenciesComplete", false))
	var mod_prof_data := reg.get_profile(eff_mod)
	var mod_block := {
		"id": eff_mod,
		"displayName": String(mod_prof_data.get("displayName", eff_mod)),
		"known": known_mod,
		"installed": mod_installed,
		"modAssetRoots": env.get("modAssetRoots", []),
		"missingDependencies": missing_mod_deps,
		"disabledDependencies": disabled_mod_deps,
		"dependencyCycles": dep_cycles,
		"unavailableRoots": unavailable_roots,
		"localFallbackUsed": bool(env.get("localFallbackUsed", false)),
		"complete": deps_complete,
	}

	# 4. Collect effective object list + sounds from document or package
	var entries: Array = []
	var vrvsnd_files: Array[String] = []
	var seen_vrvsnd := {}
	if is_doc:
		for view in subject.object_count():
			var odf := String(subject.object_odf(view))
			var lbl := String(subject.object_label(view))
			var team := int(subject.object_team(view))
			var tpl: Dictionary = subject.object_template(view)
			entries.append({
				"odf": odf,
				"label": lbl,
				"team": team,
				"flag8": int(tpl.get("flag8", 0)),
				"sequence": int(subject.object_sequence(view)),
			})
			if lbl.to_lower().begins_with("vrvsnd:"):
				var sp: Dictionary = subject.sound_point(lbl)
				if not sp.is_empty():
					var sf := String(sp["sound"]).to_lower()
					if not seen_vrvsnd.has(sf):
						seen_vrvsnd[sf] = true
						vrvsnd_files.append(sf)
	elif pkg != null and "objects" in pkg:
		for obj_v in pkg.objects:
			var obj: Dictionary = obj_v
			entries.append(obj)
			var lbl := String(obj.get("label", ""))
			if lbl.to_lower().begins_with("vrvsnd:"):
				var parts := lbl.split(":")
				if parts.size() == 8:
					var sf := parts[1].strip_edges().to_lower()
					if not sf.is_empty() and not seen_vrvsnd.has(sf):
						seen_vrvsnd[sf] = true
						vrvsnd_files.append(sf)

	# 5. Inspect every placed ODF for provenance, existence, meshes, textures, sounds, overrides, conversion
	var resolved_odfs := {}
	var resolved_meshes := {}
	var missing_odfs: Array[String] = []
	var missing_meshes: Array[String] = []
	var missing_textures: Array[String] = []
	var missing_sounds: Array[String] = []
	var odf_classifications := {}
	var incompatible_odfs: Array[String] = []
	var verified_replacements: Array[String] = []
	var unverified_odfs: Array[String] = []
	var vsr_odfs: Array[String] = []
	var vrv_odfs: Array[String] = []
	var unknown_odfs: Array[String] = []
	var likely_stock_odfs: Array[String] = []
	var seen_odf := {}

	var layered_odf_sources: Dictionary = layered_index.get("odfSources", {})
	var layered_first_hit: Dictionary = layered_index.get("firstHit", {})

	for entry: Dictionary in entries:
		var raw_odf := String(entry.get("odf", "")).strip_edges()
		var lbl := String(entry.get("label", "")).strip_edges().to_lower()
		var check_odf := "vrv_sndpoint" if lbl.begins_with("vrvsnd:") and raw_odf.to_lower() != "vrv_sndpoint" else raw_odf
		var clean := check_odf.to_lower()
		if clean.ends_with(".odf"):
			clean = clean.substr(0, clean.length() - 4)
		if clean.is_empty() or seen_odf.has(clean):
			continue
		seen_odf[clean] = true

		# Origin classification (never uses naming heuristics as Stock proof)
		var origin := ModRegistry.classify_odf_origin(clean, stock_odf_index, layered_odf_sources)
		var cls := String(origin["classification"])
		odf_classifications[clean] = origin
		if cls == ModRegistry.ODF_VERIFIED_MOD:
			var sm := String(origin["sourceMod"])
			if sm == "vrv":
				vrv_odfs.append(clean)
			elif sm == "vsr":
				vsr_odfs.append(clean)
		elif cls == ModRegistry.ODF_LIKELY_STOCK_NAMING:
			likely_stock_odfs.append(clean)
			unknown_odfs.append(clean)
		elif cls == ModRegistry.ODF_UNKNOWN:
			unknown_odfs.append(clean)

		# Conversion lookup for target mod
		var lookup := ModRegistry.lookup_verified_odf_conversion(clean, eff_mod, manual_map, stock_odf_index)
		var conv_st := String(lookup.get("status", "unverified"))
		var odf_key := clean + ".odf"
		if conv_st == "native":
			# For custom mods, also check if ODF actually resolves in the target environment
			if not (eff_mod in ["stock", "vsr"]) and not layered_first_hit.has(odf_key) and not ModRegistry.is_verified_stock_odf(clean, stock_odf_index):
				if not (clean in unverified_odfs):
					unverified_odfs.append(clean)
				incompatible_odfs.append("%s (MISSING in %s)" % [clean, eff_mod])
		elif conv_st in ["verified", "verified_manual"]:
			incompatible_odfs.append("%s -> %s (verified)" % [clean, String(lookup["targetOdf"])])
			verified_replacements.append("%s -> %s" % [clean, String(lookup["targetOdf"])])
		else:
			# Check if ODF exists directly in the target mod's own installed roots (e.g. a VSR-only ODF in VSR!)
			var resolved_in_target_mod := layered_first_hit.has(odf_key) and (
				eff_mod != "stock" or String(layered_odf_sources.get(odf_key, "")) in ["stock", "stock-pak", "map", "linked"]
			)
			if eff_mod == "vsr" and resolved_in_target_mod and not (clean == "vrv_sndpoint" or clean.begins_with("vrv_")):
				pass # Valid VSR resource physically resolved inside VSR roots
			else:
				var reason := String(lookup.get("error", "unverified"))
				incompatible_odfs.append("%s (UNSUPPORTED: %s)" % [clean, reason])
				unverified_odfs.append(clean)

		# Real asset dependency inspection against active target environment
		var dep_info := AssetIndex.inspect_odf_dependencies(clean, layered_index)
		if bool(dep_info["found"]):
			resolved_odfs[odf_key] = {
				"path": String(dep_info["path"]),
				"source": String(dep_info["source"]),
				"packed": bool(dep_info["packed"]),
				"classLabel": String(dep_info["classLabel"]),
				"geometryName": String(dep_info["geometryName"]),
				"meshPath": String(dep_info["meshPath"]),
			}
			if not String(dep_info["meshPath"]).is_empty():
				resolved_meshes[odf_key] = String(dep_info["meshPath"])
			elif bool(dep_info["meshMissing"]):
				missing_meshes.append("%s (%s)" % [odf_key, String(dep_info["geometryName"])])
			for tx_v in dep_info["missingTextures"]:
				var tx := String(tx_v)
				if not (tx in missing_textures):
					missing_textures.append(tx)
			for sn_v in dep_info["missingSounds"]:
				var sn := String(sn_v)
				if not (sn in missing_sounds):
					missing_sounds.append(sn)
		else:
			# Report missing ODF whenever we have a real/indexed target environment, OR
			# whenever the ODF isn't even a verified Stock ODF (so missing mod/unknown ODFs ALWAYS surface!)
			if real_stock_assets_present or not ModRegistry.is_verified_stock_odf(clean, stock_odf_index):
				missing_odfs.append(odf_key)

	# Check VRV sound point audio files against sound roots
	var resolved_sounds := {}
	if not vrvsnd_files.is_empty():
		var sound_layered: Array[Dictionary] = []
		for sr_v in env.get("soundRoots", []):
			sound_layered.append({"path": String(sr_v), "source": "sound", "recurse": true, "volatile": false})
		var sound_idx := AssetIndex.index_layered_roots(sound_layered)
		var sf_hits: Dictionary = sound_idx.get("firstHit", {})
		for sf in vrvsnd_files:
			if sf_hits.has(sf):
				resolved_sounds[sf] = String(sf_hits[sf])
			elif not (sf in missing_sounds):
				missing_sounds.append(sf)

	# 6. Exact DLL identity & Lua companion check
	var expected_dll := String(mp_script.expected_dll(eff_mission, eff_mod))
	var effective_dll := current_dll if not current_dll.is_empty() else expected_dll
	var dll_roots: Array[String] = []
	for dr_v in env.get("missionDllRoots", []):
		dll_roots.append(String(dr_v))
	var dll_identity := AssetIndex.inspect_dll_identity(effective_dll, dll_roots, eff_mod)
	dll_identity["expected"] = expected_dll
	var dll_change := ""
	if not expected_dll.is_empty() and current_dll.nocasecmp_to(expected_dll) != 0:
		dll_change = "%s -> %s" % [current_dll if not current_dll.is_empty() else "(none)", expected_dll]

	var lua_resolved := ""
	var lua_missing := ""
	if not without_mission_script and effective_dll.to_lower() == "luamission.dll":
		var stem := map_path.get_file().get_basename()
		if not stem.is_empty():
			var lua_key := (stem + ".lua").to_lower()
			if layered_first_hit.has(lua_key):
				lua_resolved = String(layered_first_hit[lua_key])
			else:
				lua_missing = stem + ".lua"

	# 7. Mission AI path & team/spawn compatibility
	var path_validation := {"ok": true, "errors": [], "warnings": [], "missing_required": [], "semantics": "UNKNOWN"}
	if is_doc and subject.package != null and subject.package.terrain != null:
		path_validation = mp_script.validate(subject, eff_mission, eff_mod)
	var missing_required_paths: Array[String] = []
	for p_v in path_validation.get("missing_required", []):
		missing_required_paths.append(String(p_v))
	var path_errors: Array[String] = []
	for e_v in path_validation.get("errors", []):
		path_errors.append(String(e_v))
	var path_warnings: Array[String] = []
	for w_v in path_validation.get("warnings", []):
		path_warnings.append(String(w_v))

	# Team / spawn check for Stock Strategy/Instant
	if eff_mod == "stock" and eff_mission in ["strategy", "instant", "mpi", "duel"]:
		var has_spawn := false
		for entry: Dictionary in entries:
			if String(entry.get("odf", "")).to_lower().begins_with("pspwn"):
				has_spawn = true
				break
		if not has_spawn:
			path_warnings.append("No pspwn_1 spawnpoint object found in map for Stock %s." % eff_mission)

	var mission_block := {
		"id": eff_mission,
		"expectedDll": expected_dll,
		"actualDll": current_dll,
		"semantics": String(path_validation.get("semantics", "UNKNOWN")),
		"missingRequiredPaths": missing_required_paths,
		"pathErrors": path_errors,
		"pathWarnings": path_warnings,
	}

	# 8. Playtest route & converter decoupling (Section 5: Stock 1192 NEVER blocked by stale/empty VRV!)
	var converter_required := (route == "convert")
	var converter_available := valid_converter_path(eff_vrv)
	var unused_converter_warning := ""
	if not converter_required and not eff_vrv.is_empty() and not converter_available:
		unused_converter_warning = "Configured VRV converter path '%s' is invalid/stale, but ignored because native %d route does not require a converter." % [eff_vrv, bzn_version]
	var playtest_route_block := {
		"route": route,
		"converterRequired": converter_required,
		"converterAvailable": converter_available,
		"converterPath": eff_vrv if converter_required else "",
		"unusedConverterWarning": unused_converter_warning,
	}

	# 9. Compute separate outcome statuses (Section 3)
	var env_status := ENV_SAFE_NONDESTRUCTIVE
	if not known_mod or eff_mod == "custom:unknown":
		env_status = ENV_INVALID_PROFILE
	elif not missing_mod_deps.is_empty() or not disabled_mod_deps.is_empty() or not dep_cycles.is_empty() or not unavailable_roots.is_empty():
		env_status = ENV_UNRESOLVED_DEPENDENCIES
	elif not mod_installed or not missing_odfs.is_empty() or not missing_meshes.is_empty():
		env_status = ENV_MISSING_PREVIEW_ASSETS

	var native_conv_status := CONV_VERIFIED_AVAILABLE
	if eff_mod == "custom:unknown" or not known_mod:
		native_conv_status = CONV_UNKNOWN
	elif not unverified_odfs.is_empty():
		var has_vrv_only := false
		for uo in unverified_odfs:
			if uo == "vrv_sndpoint" or uo.begins_with("vrv_"):
				has_vrv_only = true
				break
		native_conv_status = CONV_UNSUPPORTED if (has_vrv_only and eff_mod in ["stock", "vsr"]) else CONV_MANUAL_REQUIRED
	elif not verified_replacements.is_empty() or not incompatible_odfs.is_empty():
		native_conv_status = CONV_VERIFIED_AVAILABLE

	# 10. Authoritative Playtest / Validation Status (NO false READY!)
	var refusal_reasons: Array[String] = []
	var warnings: Array[String] = []
	if not unused_converter_warning.is_empty():
		warnings.append(unused_converter_warning)
	for w in path_warnings:
		warnings.append(w)

	var ambig_dups: Array = layered_index.get("duplicateOdfs", [])
	var ambig_ovrs: Array = layered_index.get("odfOverrides", [])
	# Filter overrides to placed ODFs so unrelated mod overrides don't spam warnings
	var placed_overrides: Array[Dictionary] = []
	for ov_v in ambig_ovrs:
		var ov: Dictionary = ov_v
		var odf_stem := String(ov["odf"]).get_basename().to_lower()
		if seen_odf.has(odf_stem):
			placed_overrides.append(ov)
			warnings.append("ODF override for '%s': %s shadows %s." % [
				String(ov["odf"]), String(ov["winnerSource"]), String(ov["shadowedSource"])])
	var placed_dups: Array[Dictionary] = []
	for dp_v in ambig_dups:
		var dp: Dictionary = dp_v
		var odf_stem := String(dp["odf"]).get_basename().to_lower()
		if seen_odf.has(odf_stem):
			placed_dups.append(dp)
			warnings.append("Duplicate ODF '%s' inside root %s (%d copies)." % [
				String(dp["odf"]), String(dp["root"]), (dp["matches"] as Array).size()])

	var validation_status := PLAYTEST_READY

	# Check format & layout capabilities first
	if bzn_version <= 0 or route == "refuse":
		validation_status = PLAYTEST_FORMAT_UNSUPPORTED
		refusal_reasons.append("BZN layout '%s' (version %d) has no verified Playtest route." % [layout_id, bzn_version])
	elif converter_required and not converter_available:
		validation_status = PLAYTEST_FORMAT_UNSUPPORTED
		refusal_reasons.append("BZN version %d requires the verified conversion adapter (tools/bzn_compat.py)." % bzn_version)
	elif is_doc and (not subject.object_additions.is_empty() or not subject.object_removals.is_empty()) and not (Layouts.capability_status(layout_id, Layouts.EDIT_OBJECT_COUNT) in ["NATIVE", "BAKED"]):
		validation_status = PLAYTEST_FORMAT_UNSUPPORTED
		refusal_reasons.append("Object count edits are %s on layout '%s'." % [Layouts.capability_status(layout_id, Layouts.EDIT_OBJECT_COUNT), layout_id])

	# Check engine verification
	if not eng_verified_profile:
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_ENGINE_UNVERIFIED
		refusal_reasons.append("Engine profile '%s' is not verified for automated Playtest." % eff_engine)
	elif not exe_present:
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_ENGINE_UNVERIFIED
		refusal_reasons.append("Battlezone installation (battlezone2.exe + bz2r_res) is not configured or missing.")

	# Check mod identity & dependency stack completeness
	if eff_mod == "custom:unknown" or not known_mod:
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_UNKNOWN
		refusal_reasons.append("Active mod profile '%s' is unknown/unregistered; refusing unverified Playtest." % eff_mod)
	elif not mod_installed:
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		refusal_reasons.append("Target mod '%s' is not installed locally." % eff_mod)
	if not missing_mod_deps.is_empty():
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		refusal_reasons.append("Incomplete dependency graph for '%s': missing %s." % [eff_mod, ", ".join(missing_mod_deps)])
	if not disabled_mod_deps.is_empty():
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		refusal_reasons.append("Disabled dependency for '%s': %s." % [eff_mod, ", ".join(disabled_mod_deps)])
	if not dep_cycles.is_empty():
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		refusal_reasons.append("Dependency cycle detected: %s." % ", ".join(dep_cycles))
	if not unavailable_roots.is_empty():
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		refusal_reasons.append("Unavailable asset root(s): %s." % ", ".join(unavailable_roots))

	# Check incompatible / missing ODFs
	if not incompatible_odfs.is_empty():
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		var bad_names: Array[String] = []
		for uo in unverified_odfs:
			bad_names.append(uo)
		for vr in verified_replacements:
			bad_names.append(vr.get_slice(" -> ", 0))
		refusal_reasons.append("Profile contradiction: active profile is '%s' but map contains incompatible/unverified ODF(s): %s." % [
			eff_mod, ", ".join(bad_names if not bad_names.is_empty() else incompatible_odfs)])
	if not missing_odfs.is_empty():
		if validation_status == PLAYTEST_READY:
			validation_status = PLAYTEST_MISSING_ASSETS
		refusal_reasons.append("Missing object ODF dependencies in target '%s' roots: %s." % [eff_mod, ", ".join(missing_odfs)])
	if not missing_meshes.is_empty():
		warnings.append("Missing preview mesh(es): %s." % ", ".join(missing_meshes.slice(0, 6)))
	if not missing_textures.is_empty():
		warnings.append("Missing material texture(s): %s." % ", ".join(missing_textures.slice(0, 6)))

	# Check mission DLL identity & Lua companion (unless /noscript)
	if not without_mission_script:
		var dll_st := String(dll_identity["status"])
		if dll_st == "MISSING":
			if validation_status == PLAYTEST_READY:
				validation_status = PLAYTEST_MISSING_DLL
			refusal_reasons.append(String(dll_identity["detail"]))
		elif dll_st in ["HASH_MISMATCH", "HASH_UNVERIFIED"]:
			if validation_status == PLAYTEST_READY:
				validation_status = PLAYTEST_MISSION_UNVERIFIED
			refusal_reasons.append(String(dll_identity["detail"]))
		if not lua_missing.is_empty():
			if validation_status == PLAYTEST_READY:
				validation_status = PLAYTEST_MISSING_ASSETS
			refusal_reasons.append("Missing Lua mission script '%s' required by LuaMission.dll." % lua_missing)
		if not path_errors.is_empty():
			if validation_status == PLAYTEST_READY:
				validation_status = PLAYTEST_MISSION_UNVERIFIED
			for pe in path_errors:
				refusal_reasons.append(pe)
		elif String(mission_block["semantics"]) == "UNKNOWN" and eff_mission == "custom-dll":
			if validation_status == PLAYTEST_READY:
				validation_status = PLAYTEST_MISSION_UNVERIFIED
			refusal_reasons.append("Custom mission DLL '%s' has unverified runtime semantics." % effective_dll)

	# Determine detected/suggested mod honestly
	var detected_mod := "vrv" if not vrv_odfs.is_empty() else ("vsr" if not vsr_odfs.is_empty() else ("custom:unknown" if not unknown_odfs.is_empty() else "stock"))
	var suggested_mod := detected_mod if not incompatible_odfs.is_empty() else eff_mod

	# Honest evidence level (never inflate to INTERACTIVE_GAMEPLAY_VERIFIED automatically)
	var evidence_level := EV_UNKNOWN
	if bzn_version > 0 and route != "refuse":
		evidence_level = EV_FORMAT_VERIFIED
	if validation_status == PLAYTEST_READY and eff_mod in ["stock", "vsr", "vrv"]:
		evidence_level = EV_FORMAT_VERIFIED

	var missing_deps_block := {
		"odfs": missing_odfs,
		"meshes": missing_meshes,
		"textures": missing_textures,
		"sounds": missing_sounds,
		"missionDll": effective_dll if String(dll_identity["status"]) == "MISSING" else "",
		"luaScript": lua_missing,
		"modDeps": missing_mod_deps,
		"disabledDeps": disabled_mod_deps,
		"converter": converter_required and not converter_available,
	}

	var bad_odf_names: Array[String] = []
	for uo in unverified_odfs:
		if not (uo in bad_odf_names):
			bad_odf_names.append(uo)
	for vr in verified_replacements:
		var sn := vr.get_slice(" -> ", 0)
		if not (sn in bad_odf_names):
			bad_odf_names.append(sn)
	for mo in missing_odfs:
		var stem := mo.get_basename()
		if not (stem in bad_odf_names):
			bad_odf_names.append(stem)

	return {
		"schema": SCHEMA,
		"sourceMapIdentity": source_identity,
		"engineProfile": engine_block,
		"modProfile": mod_block,
		"missionProfile": mission_block,
		"formatProfile": {
			"id": layout_id,
			"version": bzn_version,
			"encoding": encoding,
			"playtestRoute": route,
		},
		"resolvedAssets": {
			"odfs": resolved_odfs,
			"meshes": resolved_meshes,
			"sounds": resolved_sounds,
			"luaScript": lua_resolved,
		},
		"missingDependencies": missing_deps_block,
		"ambiguousOverrides": {
			"odfOverrides": placed_overrides,
			"duplicateOdfs": placed_dups,
		},
		"dllIdentity": dll_identity,
		"nativeWriterCapabilities": writer_caps,
		"conversionRequirements": {
			"status": native_conv_status,
			"feasible": unverified_odfs.is_empty() and known_mod and eff_mod != "custom:unknown",
			"verifiedReplacements": verified_replacements,
			"unverifiedOdfs": unverified_odfs,
			"manualMappingRequired": native_conv_status == CONV_MANUAL_REQUIRED,
			"dllChange": dll_change,
			"incompatibleOdfs": incompatible_odfs,
		},
		"playtestRoute": playtest_route_block,
		"environmentSwitchStatus": env_status,
		"nativeConversionStatus": native_conv_status,
		"validationStatus": validation_status,
		"playtestStatus": validation_status,
		"refusalReasons": refusal_reasons,
		"warnings": warnings,
		"evidenceLevel": evidence_level,
		"odfClassifications": odf_classifications,
		# Convenience compatibility fields for UI & callers
		"ok": validation_status == PLAYTEST_READY,
		"profileCompatible": incompatible_odfs.is_empty() and known_mod and eff_mod != "custom:unknown",
		"selectedMod": eff_mod,
		"detectedMod": detected_mod,
		"suggestedMod": suggested_mod,
		"verifiedPlaytestMod": eff_mod if validation_status == PLAYTEST_READY else "",
		"incompatibleOdfs": bad_odf_names,
		"vsrOdfs": vsr_odfs,
		"vrvOdfs": vrv_odfs,
		"unknownOdfs": unknown_odfs,
		"likelyStockOdfs": likely_stock_odfs,
		"error": "; ".join(refusal_reasons),
	}


## Evaluates a raw BZN path on disk (used by NewMapWizard and headless Playtest -ValidateOnly).
static func evaluate_bzn_path(bzn_path: String, registry: ModRegistry, target_mod: String = "", target_mission: String = "", target_engine: String = "bzcc-2.0.185", game_dir: String = "", vrv_dir: String = "", without_mission_script: bool = false, asset_profile: String = "", extra_roots: Array = []) -> Dictionary:
	var clean := bzn_path.strip_edges()
	var reg: ModRegistry = registry if registry != null else ModRegistry.new()
	if clean.is_empty() or not FileAccess.file_exists(clean):
		return {
			"schema": SCHEMA,
			"valid": false,
			"ok": false,
			"profileCompatible": false,
			"validationStatus": PLAYTEST_UNKNOWN,
			"playtestStatus": PLAYTEST_UNKNOWN,
			"environmentSwitchStatus": ENV_INVALID_PROFILE,
			"nativeConversionStatus": CONV_UNKNOWN,
			"refusalReasons": ["Missing source BZN file."],
			"error": "Missing source BZN file.",
			"vsrOdfs": [],
			"vrvOdfs": [],
			"unknownOdfs": [],
			"likelyStockOdfs": [],
			"recommendedMod": "stock",
			"dll": "",
			"conversionPlan": {"ok": false, "unsupported": ["Missing source BZN file."]},
		}
	var bytes := FileAccess.get_file_as_bytes(clean)
	var layout := Layouts.recognize(bytes)
	var ver := int(layout.get("version", 0))
	if ver <= 0:
		return {
			"schema": SCHEMA,
			"valid": false,
			"ok": false,
			"profileCompatible": false,
			"validationStatus": PLAYTEST_FORMAT_UNSUPPORTED,
			"playtestStatus": PLAYTEST_FORMAT_UNSUPPORTED,
			"environmentSwitchStatus": ENV_INVALID_PROFILE,
			"nativeConversionStatus": CONV_UNKNOWN,
			"refusalReasons": [String(layout.get("reason", "Unrecognized BZN layout"))],
			"error": String(layout.get("reason", "Unrecognized BZN layout")),
			"vsrOdfs": [],
			"vrvOdfs": [],
			"unknownOdfs": [],
			"likelyStockOdfs": [],
			"recommendedMod": "stock",
			"dll": "",
			"conversionPlan": {"ok": false, "unsupported": ["Unrecognized BZN layout"]},
		}
	var paths := BznPaths.new()
	if not paths.read(bytes, ver):
		return {
			"schema": SCHEMA,
			"valid": false,
			"ok": false,
			"profileCompatible": false,
			"validationStatus": PLAYTEST_FORMAT_UNSUPPORTED,
			"playtestStatus": PLAYTEST_FORMAT_UNSUPPORTED,
			"refusalReasons": ["Unreadable BZN path table."],
			"error": "Unreadable BZN path table.",
			"vsrOdfs": [],
			"vrvOdfs": [],
			"unknownOdfs": [],
			"likelyStockOdfs": [],
			"recommendedMod": "stock",
			"dll": "",
			"conversionPlan": {"ok": false, "unsupported": ["Unreadable BZN path table."]},
		}
	var objs := BznObjects.new()
	if not objs.read(bytes, ver, paths.table_start):
		return {
			"schema": SCHEMA,
			"valid": false,
			"ok": false,
			"profileCompatible": false,
			"validationStatus": PLAYTEST_FORMAT_UNSUPPORTED,
			"playtestStatus": PLAYTEST_FORMAT_UNSUPPORTED,
			"refusalReasons": ["Unreadable BZN object table."],
			"error": "Unreadable BZN object table.",
			"vsrOdfs": [],
			"vrvOdfs": [],
			"unknownOdfs": [],
			"likelyStockOdfs": [],
			"recommendedMod": "stock",
			"dll": "",
			"conversionPlan": {"ok": false, "unsupported": ["Unreadable BZN object table."]},
		}

	# Build a lightweight package view without requiring a TER (blank templates may lack TER)
	var pkg := MapPackage.new()
	pkg.source_path = clean
	pkg.bzn_name = clean.get_file()
	pkg.bzn_version = ver
	pkg.layout_id = String(layout["profile"])
	pkg.paths = paths.paths
	pkg.objects = objs.objects
	pkg.mission_dll = objs.mission_dll
	pkg.path_codec = paths
	pkg.object_count_offset = objs.count_offset
	pkg.object_insert_offset = objs.insert_offset

	var detected := ModRegistry.detect_map_profiles(pkg, reg)
	var eff_mod := target_mod.strip_edges().to_lower()
	if eff_mod.is_empty():
		eff_mod = String(detected.get("recommendedMod", "stock"))
	var eff_mis := target_mission.strip_edges().to_lower()
	if eff_mis.is_empty():
		eff_mis = String(detected.get("recommendedMission", "blank"))
	var result := evaluate(pkg, reg, eff_mod, eff_mis, target_engine, game_dir, vrv_dir, {}, without_mission_script, MissionProfiles, asset_profile, extra_roots)
	var ptr_counts := paths.pointer_counts(bytes)
	var stock_idx := reg.get_stock_odf_index(game_dir)
	var conv_plan := ModRegistry.plan_bzn_odf_conversion(objs.objects, ptr_counts, eff_mod, {}, false, stock_idx)
	result["valid"] = true
	result["version"] = ver
	result["recommendedMod"] = String(detected.get("recommendedMod", "stock"))
	result["recommendedMission"] = String(detected.get("recommendedMission", "blank"))
	result["dll"] = objs.mission_dll
	result["conversionPlan"] = conv_plan
	result["detected"] = detected
	return result
