extends SceneTree
## Focused regression suite for Waves 1, 2 & 6:
## - P0 False-positive Stock ODF classification removal (modrock_custom, strategy_override, recycler_custom)
## - P0 Strategy02.dll basename collision without verified Stock ODFs + DLL SHA-256 hash mismatch
## - P0 Real missingOdfs + DOCP v2 .pak resolution + stale cache invalidation + separated statuses
## - P0 Unified bzmag.compatibility-result/1 across Open Map, Wizard, Target Profile, Playtest, -ValidateOnly
## - P0 Stock 1192 decoupling from empty/stale/absent VRV setup + 1196 converter gating
## - P1 Recursive dependency stack (cycles, missing/disabled/duplicate/unavailable deps, ODF overrides)
## - Real installed BZCC + Workshop mods (Stock, VSR, VRV, Forgotten Enemies, TOTAL COOP, Battlezone Classic)

const EditorScene := preload("res://editor.tscn")
const AssetIndex := preload("res://core/asset_index.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const CompatibilityEngine := preload("res://core/compatibility_engine.gd")
const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const BznPaths := preload("res://formats/bzn_paths.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const PlaytestValidation := preload("res://bridge/playtest_validation.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, desc: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + desc)


func _first_dll_dir(profile_root: String, mod_folder: String) -> String:
	if profile_root.is_empty():
		return ""
	var candidates := [profile_root.path_join(mod_folder + "/Missions"), profile_root.path_join("Missions")]
	for dir_path in candidates:
		if DirAccess.dir_exists_absolute(dir_path) and FileAccess.file_exists(dir_path.path_join("Strategy02.dll")):
			return dir_path
	return ""


func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func make_docp_pak(path: String, entry_names: Array[String]) -> void:
	var header := PackedByteArray()
	header.append_array("DOCP".to_ascii_buffer())
	var meta := PackedByteArray()
	meta.resize(28)
	meta.encode_u32(0, 2) # version 2
	meta.encode_u32(12, entry_names.size())
	meta.encode_u32(16, 32) # dirOffset = 32
	header.append_array(meta)
	for en in entry_names:
		var eb := en.to_ascii_buffer()
		var rec := PackedByteArray()
		rec.resize(5)
		rec.encode_u32(0, 1)
		rec[4] = eb.size()
		header.append_array(rec)
		header.append_array(eb)
		var pad := PackedByteArray()
		pad.resize(12)
		header.append_array(pad)
	write_bytes(path, header)


func patch_map_odf_and_dll(src_bzn: String, dst_dir: String, new_odf: String, new_dll: String = "") -> String:
	var writer := Snapshots.new()
	check(writer.create_native_flat_map(src_bzn, dst_dir, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "blank",
		"configure_mission": false,
		"sanitize_stock_objects": true,
	}), "stage synthetic flat map at " + dst_dir + ": " + writer.error)
	var bzn_path := dst_dir.path_join(src_bzn.get_file())
	var raw := FileAccess.get_file_as_bytes(bzn_path)
	var pc := BznPaths.new()
	pc.read(raw, 1192)
	var oc := BznObjects.new()
	oc.read(raw, 1192, pc.table_start)
	if not new_odf.is_empty():
		var patched := BznObjects.patch_objects(raw, oc.objects, {}, [], [], oc.count_offset, oc.insert_offset, {}, {0: new_odf})
		raw = patched["bytes"]
		pc.read(raw, 1192)
		oc.read(raw, 1192, pc.table_start)
	if not new_dll.is_empty():
		raw = BznObjects.patch_mission_dll(raw, oc.insert_offset, pc.table_start, new_dll)
	write_bytes(bzn_path, raw)
	return bzn_path


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("Pass brave_bzn blank_bzn scratch_dir real_game_dir [optional_vrv_dir]")
		quit(2)
		return
	var brave_bzn := args[0]
	var blank_bzn := args[1]
	var scratch := args[2]
	var real_game := args[3]
	var real_vrv := args[4] if args.size() >= 5 else ""

	AssetIndex.clear_cache()

	# =========================================================================
	# 1. P0: False-positive Stock ODF classification (Section 2)
	# =========================================================================
	for fake_stock in ["modrock_custom", "modrock_custom.odf", "strategy_override", "recycler_custom"]:
		check(not ModRegistry.is_verified_stock_odf(fake_stock),
			"is_verified_stock_odf rejects naming-heuristic fake Stock ODF '%s'" % fake_stock)
		var orig := ModRegistry.classify_odf_origin(fake_stock)
		check(String(orig["classification"]) == ModRegistry.ODF_LIKELY_STOCK_NAMING,
			"classify_odf_origin tags '%s' as LIKELY_STOCK_NAMING (not VERIFIED_STOCK_ODF)" % fake_stock)
	check(ModRegistry.is_verified_stock_odf("ivtank") and ModRegistry.is_verified_stock_odf("pspwn_1"),
		"is_verified_stock_odf accepts positively verified Stock ODFs")
	var strict_unk := ModRegistry.classify_odf_origin("zzz_total_mod_unit")
	check(String(strict_unk["classification"]) == ModRegistry.ODF_UNKNOWN,
		"classify_odf_origin tags non-Stock-prefix ODF as UNKNOWN_ODF")

	# Synthetic fixture maps: modrock_custom / strategy_override / recycler_custom WITH Strategy02.dll!
	for idx_name in ["modrock_custom", "strategy_override", "recycler_custom"]:
		var mpath := patch_map_odf_and_dll(blank_bzn, scratch.path_join("fake-stock-" + idx_name), idx_name, "Strategy02.dll")
		var doc := Document.new()
		check(doc.open(mpath), "open synthetic map with %s + Strategy02.dll" % idx_name)
		var det: Dictionary = doc.detected_profile_info
		check(String(det["recommendedMod"]) == "custom:unknown" and bool(det["unknownMod"]),
			"map with Strategy02.dll + %s detects as custom:unknown (NEVER Stock HIGH)" % idx_name)
		var stock_high := false
		for c_v in det["candidates"]:
			var c: Dictionary = c_v
			if String(c["modProfile"]) == "stock" and String(c["confidence"]) == "high":
				stock_high = true
		check(not stock_high, "Strategy02.dll basename + %s never produces Stock HIGH candidate" % idx_name)
		check(idx_name in (det["likelyStockOdfs"] as Array),
			"%s is listed under likelyStockOdfs (hint only), not verifiedStockOdfs" % idx_name)

	# =========================================================================
	# 2. P0: Real missingOdfs, DOCP .pak support, stale cache invalidation,
	#    DLL SHA-256 identity & separate statuses (Section 3)
	# =========================================================================
	var synth_game := scratch.path_join("synth-game")
	DirAccess.make_dir_recursive_absolute(synth_game.path_join("bz2r_res/objects"))
	DirAccess.make_dir_recursive_absolute(synth_game.path_join("bz2r_loc"))
	DirAccess.make_dir_recursive_absolute(synth_game.path_join("Missions"))
	# 8 KB mock battlezone2.exe so engine sees a real-sized install fixture
	var big_exe := PackedByteArray()
	big_exe.resize(8192)
	write_bytes(synth_game.path_join("battlezone2.exe"), big_exe)
	write_text(synth_game.path_join("bz2r_res/objects/ivtank.odf"), "[GameObjectClass]\nclassLabel = \"wingman\"\ngeometryName = \"ivtank00.fbx\"\nunitName = \"Tank\"\n")
	write_bytes(synth_game.path_join("bz2r_res/objects/ivtank00.msh"), PackedByteArray([1, 2, 3, 4]))
	# Put a fake wrong-hash Strategy02.dll in synth_game/Missions
	write_bytes(synth_game.path_join("Missions/Strategy02.dll"), "WRONG_HASH_DLL".to_utf8_buffer())
	# Put a DOCP v2 .pak with a packed ODF inside bz2r_res
	make_docp_pak(synth_game.path_join("bz2r_res/stock_extra.pak"), ["packed_stock_prop.odf"])

	var reg := ModRegistry.new()
	reg.discover_installed(synth_game)
	var stock_idx := reg.get_stock_odf_index(synth_game)
	check(stock_idx.has("packed_stock_prop.odf") and ModRegistry.is_verified_stock_odf("packed_stock_prop", stock_idx),
		"DOCP v2 .pak ODF inside bz2r_res is positively resolved and verified as Stock")

	# Test real missingOdfs & separate statuses on synthetic map with modrock_custom
	var synth_map_path := scratch.path_join("fake-stock-modrock_custom").path_join(blank_bzn.get_file())
	var src_hash_before := FileAccess.get_sha256(synth_map_path)
	var synth_doc := Document.new()
	check(synth_doc.open(synth_map_path), "open modrock_custom map for conversion analysis")
	var conv_to_stock := reg.analyze_conversion(synth_doc, "stock", "strategy", MissionProfiles, {}, synth_game)
	check("modrock_custom.odf" in (conv_to_stock["missingOdfs"] as Array),
		"analyze_conversion populates real missingOdfs with modrock_custom.odf")
	check(String(conv_to_stock["environmentSwitchStatus"]) == CompatibilityEngine.ENV_MISSING_PREVIEW_ASSETS,
		"environmentSwitchStatus reports MISSING_PREVIEW_ASSETS (distinct from Playtest readiness)")
	check(String(conv_to_stock["nativeConversionStatus"]) == CompatibilityEngine.CONV_MANUAL_REQUIRED,
		"nativeConversionStatus reports MANUAL_MAPPING_REQUIRED for unknown ODF")
	check(String(conv_to_stock["playtestStatus"]) == CompatibilityEngine.PLAYTEST_MISSING_ASSETS,
		"playtestStatus refuses Playtest as MISSING_ASSETS (no false READY)")
	check(String(conv_to_stock["dllIdentity"]["status"]) == "HASH_UNVERIFIED",
		"wrong-hash Strategy02.dll is flagged HASH_UNVERIFIED instead of verified Stock")
	check(FileAccess.get_sha256(synth_map_path) == src_hash_before,
		"analyze_conversion never mutates the native map on disk")

	# Conversion matrix checks: Stock->VSR, VSR->Stock, VRV->Stock, Unknown->Stock, Custom->VSR
	var stock_clean_bzn := patch_map_odf_and_dll(blank_bzn, scratch.path_join("stock-clean-ivtank"), "ivtank", "Strategy02.dll")
	var stock_clean_doc := Document.new()
	check(stock_clean_doc.open(stock_clean_bzn), "open clean ivtank Stock map")
	var c_s2v := reg.analyze_conversion(stock_clean_doc, "vsr", "strategy", MissionProfiles, {}, synth_game)
	check(String(c_s2v["playtestStatus"]) != CompatibilityEngine.PLAYTEST_READY and not bool(c_s2v["modInstalled"]),
		"Stock -> uninstalled VSR refuses READY cleanly")
	var brave_doc := Document.new()
	check(brave_doc.open(brave_bzn), "open Brave 1196 for VSR->Stock analysis")
	var c_v2s := reg.analyze_conversion(brave_doc, "stock", "strategy", MissionProfiles, {}, synth_game)
	check(not (c_v2s["missingOdfs"] as Array).is_empty() and String(c_v2s["playtestStatus"]) != CompatibilityEngine.PLAYTEST_READY,
		"VSR -> Stock analysis reports real missing VSR ODFs and refuses READY")
	var c_u2s := reg.analyze_conversion(synth_doc, "stock", "strategy", MissionProfiles, {}, synth_game)
	check(String(c_u2s["playtestStatus"]) != CompatibilityEngine.PLAYTEST_READY, "Unknown -> Stock refuses READY")
	var custom_mod_dir := scratch.path_join("custom-mod-root")
	write_text(custom_mod_dir.path_join("modrock_custom.odf"), "[GameObjectClass]\nclassLabel = \"I76Building\"\ngeometryName = \"rock.fbx\"\n")
	reg.register_custom_mod("my_custom", "My Custom Mod", custom_mod_dir, ["stock"])
	var c_c2v := reg.analyze_conversion(synth_doc, "vsr", "strategy", MissionProfiles, {}, synth_game)
	check("modrock_custom.odf" in (c_c2v["missingOdfs"] as Array), "Custom -> VSR reports modrock_custom.odf missing in VSR")

	# Stale asset cache invalidation test
	var cache_dir := scratch.path_join("cache-test-root")
	write_text(cache_dir.path_join("unit_a.odf"), "[GameObjectClass]\n")
	var idx1 := AssetIndex.get_root_index(cache_dir, true, false)
	var hits_before := int(AssetIndex.cache_stats()["hits"])
	var idx2 := AssetIndex.get_root_index(cache_dir, true, false)
	check(int(AssetIndex.cache_stats()["hits"]) == hits_before + 1 and (idx2["odfs"] as Dictionary).has("unit_a.odf"),
		"AssetIndex reuses warm cache when root stamp is unchanged")
	write_text(cache_dir.path_join("unit_b.odf"), "[GameObjectClass]\n")
	var idx3 := AssetIndex.get_root_index(cache_dir, true, false)
	check((idx3["odfs"] as Dictionary).has("unit_b.odf"),
		"AssetIndex invalidates stale cache immediately when new ODF is added")

	# =========================================================================
	# 3. P1: Deterministic Recursive Dependency Stack (Section 7)
	# =========================================================================
	var fake_ws := scratch.path_join("dep-ws")
	# Chain: 500001 -> 500002 -> 500003 (and 500004 missing), plus cycle 600001 <-> 600002
	write_text(fake_ws.path_join("500001/500001.ini"), "[WORKSHOP]\nmodName = \"Chain Top\"\nmodType = \"config\"\nassetDependencies = \"500002\"\n")
	write_text(fake_ws.path_join("500002/500002.ini"), "[WORKSHOP]\nmodName = \"Chain Mid\"\nmodType = \"asset\"\nassetDependencies = \"500003, 500004\"\n")
	write_text(fake_ws.path_join("500003/500003.ini"), "[WORKSHOP]\nmodName = \"Chain Leaf\"\nmodType = \"asset\"\n")
	write_text(fake_ws.path_join("500003/leaf_unit.odf"), "[GameObjectClass]\nclassLabel = \"wingman\"\n")
	write_text(fake_ws.path_join("500001/ivtank.odf"), "[GameObjectClass]\nclassLabel = \"wingman\"\n") # overrides Stock ivtank.odf!
	write_text(fake_ws.path_join("600001/600001.ini"), "[WORKSHOP]\nmodName = \"Cyc A\"\nmodType = \"config\"\nassetDependencies = \"600002\"\n")
	write_text(fake_ws.path_join("600002/600002.ini"), "[WORKSHOP]\nmodName = \"Cyc B\"\nmodType = \"config\"\nassetDependencies = \"600001\"\n")
	var dep_reg := ModRegistry.new()
	dep_reg.discover_installed(synth_game, "", fake_ws)
	var chain_stack := dep_reg.resolve_dependency_stack("custom:ws-500001", synth_game)
	check((chain_stack["modAssetRoots"] as Array).size() == 3 and "500004" in (chain_stack["missingDependencies"] as Array)
		and not bool(chain_stack["complete"]),
		"recursive dependency traversal resolves 500001->500002->500003, catches missing transitive 500004, and refuses complete=true")
	var cyc_stack := dep_reg.resolve_dependency_stack("custom:ws-600001", synth_game)
	check(not (cyc_stack["dependencyCycles"] as Array).is_empty() and not bool(cyc_stack["complete"]),
		"dependency stack detects Workshop dependency cycle 600001 <-> 600002")
	# Disabled dependency check
	dep_reg.set_mod_enabled("custom:ws-600002", false)
	var dis_stack := dep_reg.resolve_dependency_stack("custom:ws-600001", synth_game)
	check("custom:ws-600002" in (dis_stack["disabledDependencies"] as Array),
		"dependency stack flags disabled dependency profile")
	# ODF override detection (500001/ivtank.odf shadows bz2r_res/objects/ivtank.odf)
	var chain_env := dep_reg.resolve_content_environment(stock_clean_doc, synth_game, "", "custom:ws-500001", "blank")
	var chain_layered := AssetIndex.index_layered_roots(chain_env["layeredRoots"])
	check(not (chain_layered["odfOverrides"] as Array).is_empty(),
		"layered asset index detects cross-root ODF override (mod ivtank.odf shadowing Stock)")

	# =========================================================================
	# 4. P0: Decouple Stock 1192 Playtest from optional/stale VRV setup (Section 5)
	#    & Unified Compatibility Contract across Editor / Wizard / -ValidateOnly (Section 4)
	# =========================================================================
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.settings_path = scratch.path_join("compat-editor.cfg")
	if not real_game.is_empty() and CompatibilityEngine.valid_game_dir(real_game):
		# Build a pure Stock Strategy 1192 map and test ALL Section 5 VRV decoupling cases!
		var stock_strat_dir := scratch.path_join("stock-1192-strat")
		var writer := Snapshots.new()
		check(writer.create_native_flat_map(blank_bzn, stock_strat_dir, 1024, 100.0, "", {
			"mod_profile": "stock",
			"mission_profile": "strategy",
			"configure_mission": true,
			"sanitize_stock_objects": true,
		}), "create native Stock 1192 Strategy map for decoupling tests: " + writer.error)
		var stock_strat_bzn := stock_strat_dir.path_join(blank_bzn.get_file())

		editor.game_path.text = real_game
		editor.mod_registry.discover_installed(real_game, "")
		check(editor.open_map(stock_strat_bzn), "open pure Stock 1192 Strategy map")
		editor.document.mod_profile = "stock"
		editor.document.mission_profile = "strategy"
		editor.document.profile_explicit = true

		# Case 1: Stock 1192, VRV field empty -> READY
		editor.vrv_path.text = ""
		editor.vrv_configured = true
		var plan_empty: Dictionary = editor.playtest_route_plan()
		check(bool(plan_empty["ok"]) and String(plan_empty["route"]) == "native"
			and not bool(plan_empty["needsConverter"]) and String(plan_empty["converterArg"]).is_empty()
			and String(plan_empty["compatibility"]["validationStatus"]) == CompatibilityEngine.PLAYTEST_READY
			and String(plan_empty["compatibility"]["dllIdentity"]["status"]) == AssetIndex.DLL_STATUS_VERIFIED_EXACT,
			"Stock 1192 with empty VRV path is READY with VERIFIED_EXACT Stock Strategy02.dll hash")

		# Case 2: Stock 1192, VRV path STALE/INVALID -> STILL READY with non-blocking warning!
		editor.vrv_path.text = "Z:/nonexistent_stale_vrv_checkout"
		var plan_stale: Dictionary = editor.playtest_route_plan()
		check(bool(plan_stale["ok"]) and String(plan_stale["converterArg"]).is_empty()
			and not String(plan_stale["unusedVrvWarning"]).is_empty(),
			"Stock 1192 with stale invalid VRV path is NOT blocked and emits unused-converter warning")

		# Case 3: PlaytestValidation (-ValidateOnly backend) emits identical bzmag.compatibility-result/1 contract
		var pv := PlaytestValidation.validate(stock_strat_bzn, {
			"game": real_game, "mod": "stock", "mission": "strategy", "vrv": "Z:/nonexistent_stale_vrv_checkout"
		})
		check(pv.has("compatibility") and String(pv["compatibility"]["schema"]) == CompatibilityEngine.SCHEMA
			and String(pv["compatibility"]["validationStatus"]) == CompatibilityEngine.PLAYTEST_READY,
			"PlaytestValidation emits unified bzmag.compatibility-result/1 READY matching editor")

		# Case 4 & 5: 1196 Brave with converter absent vs converter present
		check(editor.open_map(brave_bzn), "open Brave 1196 for converter gating checks")
		editor.document.mod_profile = "vrv"
		editor.document.mission_profile = "strategy"
		editor.vrv_path.text = ""
		editor.vrv_configured = true
		var plan_1196_no_conv: Dictionary = editor.playtest_route_plan()
		check(not bool(plan_1196_no_conv["ok"]) and String(plan_1196_no_conv["compatibility"]["validationStatus"]) == CompatibilityEngine.PLAYTEST_FORMAT_UNSUPPORTED,
			"1196 map refuses Playtest as FORMAT_UNSUPPORTED when converter is absent")
		if not real_vrv.is_empty() and CompatibilityEngine.valid_converter_path(real_vrv):
			editor.vrv_path.text = real_vrv
			var plan_1196_conv: Dictionary = editor.playtest_route_plan()
			check(bool(plan_1196_conv["needsConverter"]) and String(plan_1196_conv["converterArg"]) == real_vrv
				and bool(plan_1196_conv["compatibility"]["playtestRoute"]["converterAvailable"]),
				"1196 map detects available converter adapter cleanly")

		# Case 6: Real installed VSR, VRV, and Custom Workshop mods (Section 7 Acceptance!)
		var real_reg := ModRegistry.new()
		var real_disc := real_reg.discover_installed(real_game, real_vrv)
		check(int(real_disc["count"]) >= 5, "real Workshop discovery finds Stock, VSR, VRV, and custom Workshop mods (%d)" % int(real_disc["count"]))
		var vsr_stack := real_reg.resolve_dependency_stack("vsr", real_game, real_vrv)
		var vrv_stack := real_reg.resolve_dependency_stack("vrv", real_game, real_vrv)
		print("Real VSR stack: installed=%s roots=%d missing=%s complete=%s" % [
			str(vsr_stack["installed"]), (vsr_stack["modAssetRoots"] as Array).size(), str(vsr_stack["missingDependencies"]), str(vsr_stack["complete"])])
		print("Real VRV stack: installed=%s roots=%d missing=%s complete=%s" % [
			str(vrv_stack["installed"]), (vrv_stack["modAssetRoots"] as Array).size(), str(vrv_stack["missingDependencies"]), str(vrv_stack["complete"])])
		# If VSR has missing seasonal dependency 3627212766 on disk, verify it is NOT falsely marked READY!
		if not (vsr_stack["missingDependencies"] as Array).is_empty():
			check(not bool(vsr_stack["complete"]), "real VSR with missing Workshop dependency is NOT falsely marked complete")
		# Check at least 2 real installed custom Workshop mods!
		var custom_ws_checked := 0
		for cid in ["custom:ws-3493433992", "custom:ws-3728347411", "custom:ws-2319244444"]:
			if real_reg.has_profile(cid):
				var cstack := real_reg.resolve_dependency_stack(cid, real_game)
				check(bool(cstack["installed"]) and not (cstack["modAssetRoots"] as Array).is_empty(),
					"real custom Workshop mod %s resolves its dependency stack (%d roots, missing=%s)" % [
						cid, (cstack["modAssetRoots"] as Array).size(), str(cstack["missingDependencies"])])
				custom_ws_checked += 1
		check(custom_ws_checked >= 2, "verified dependency stacks for at least 2 real installed Custom Workshop mods (%d)" % custom_ws_checked)
		# Verify Stock environment NEVER mounts any VRV/VSR/Workshop roots even with all real mods installed!
		var real_stock_env := real_reg.resolve_content_environment(stock_clean_doc, real_game, real_vrv, "stock", "strategy")
		check((real_stock_env["modAssetRoots"] as Array).is_empty(),
			"real Stock environment strictly mounts 0 modAssetRoots with VSR/VRV/Workshop installed")

		# Case 7: Unknown mod refuses unsupported Playtest cleanly
		editor.open_map(synth_map_path)
		var plan_unk: Dictionary = editor.playtest_route_plan()
		check(not bool(plan_unk["ok"]) and String(plan_unk["compatibility"]["validationStatus"]) == CompatibilityEngine.PLAYTEST_UNKNOWN,
			"unknown Workshop mod (custom:unknown) refuses unverified Playtest with status UNKNOWN")

		# =====================================================================
		# 5. WAVE 1 (P0): Mission DLL Truth — ALL 10 Regression Cases
		# =====================================================================
		var stock_missions_dir := real_game.path_join("Missions")
		var stock_strat_dll := stock_missions_dir.path_join("Strategy02.dll")
		var stock_inst_dll := stock_missions_dir.path_join("Instant.dll")
		var stock_lua_dll := stock_missions_dir.path_join("LuaMission.dll")
		var stock_mpi_dll := stock_missions_dir.path_join("mpinstant.dll")

		# 1) Correct Stock Strategy02 -> PASS (VERIFIED_EXACT)
		var id1 := AssetIndex.inspect_dll_identity("Strategy02.dll", [stock_missions_dir], "stock", "Strategy02.dll", "strategy", "Strategy02.dll")
		check(String(id1["status"]) == AssetIndex.DLL_STATUS_VERIFIED_EXACT and bool(id1["verified"]),
			"W1.1 Correct Stock Strategy02.dll -> VERIFIED_EXACT")

		# 2) Correct Stock Instant -> PASS (VERIFIED_EXACT) + full CompatibilityEngine READY
		var stock_inst_dir := scratch.path_join("w1-stock-instant")
		check(writer.create_native_flat_map(blank_bzn, stock_inst_dir, 1024, 100.0, "", {
			"mod_profile": "stock",
			"mission_profile": "instant",
			"configure_mission": true,
			"sync_mission_dll": true,
			"sanitize_stock_objects": true,
		}), "W1.2 stage Stock Instant 1192 map")
		var stock_inst_bzn := stock_inst_dir.path_join(blank_bzn.get_file())
		var inst_doc := Document.new()
		check(inst_doc.open(stock_inst_bzn), "W1.2 open Stock Instant map")
		var inst_eval := CompatibilityEngine.evaluate(inst_doc, real_reg, "stock", "instant", "bzcc-2.0.185", real_game, "")
		check(bool(inst_eval["ok"]) and String(inst_eval["dllIdentity"]["status"]) == AssetIndex.DLL_STATUS_VERIFIED_EXACT,
			"W1.2 Correct Stock Instant -> VERIFIED_EXACT + PLAYTEST_READY")

		# 3) Instant bytes renamed Strategy02.dll -> DLL_NAME_MISMATCH (REFUSE!)
		var renamed_root := scratch.path_join("w1-renamed-dll")
		DirAccess.make_dir_recursive_absolute(renamed_root)
		write_bytes(renamed_root.path_join("Strategy02.dll"), FileAccess.get_file_as_bytes(stock_inst_dll))
		var id3 := AssetIndex.inspect_dll_identity("Strategy02.dll", [renamed_root], "stock", "Strategy02.dll", "strategy", "Strategy02.dll")
		check(String(id3["status"]) == AssetIndex.DLL_STATUS_DLL_NAME_MISMATCH and not bool(id3["verified"]),
			"W1.3 Stock Instant.dll bytes renamed Strategy02.dll -> DLL_NAME_MISMATCH (no false VERIFIED!)")
		# Also verify full CompatibilityEngine refuses when renamed DLL sits beside map!
		var renamed_map_dir := scratch.path_join("w1-renamed-map")
		check(writer.create_native_flat_map(blank_bzn, renamed_map_dir, 1024, 100.0, "", {
			"mod_profile": "stock", "mission_profile": "strategy", "configure_mission": true, "sanitize_stock_objects": true,
		}), "W1.3 stage map with renamed DLL beside it")
		write_bytes(renamed_map_dir.path_join("Strategy02.dll"), FileAccess.get_file_as_bytes(stock_inst_dll))
		var renamed_doc := Document.new()
		check(renamed_doc.open(renamed_map_dir.path_join(blank_bzn.get_file())), "W1.3 open renamed-DLL map")
		var renamed_eval := CompatibilityEngine.evaluate(renamed_doc, real_reg, "stock", "strategy", "bzcc-2.0.185", real_game, "")
		check(not bool(renamed_eval["ok"])
			and String(renamed_eval["dllIdentity"]["status"]) == AssetIndex.DLL_STATUS_DLL_NAME_MISMATCH
			and String(renamed_eval["validationStatus"]) == CompatibilityEngine.PLAYTEST_MISSION_UNVERIFIED,
			"W1.3 CompatibilityEngine refuses Playtest for Instant.dll bytes disguised as Strategy02.dll")

		# 4) Actual Instant.dll + selected Strategy -> MISSION_PROFILE_MISMATCH (REFUSE!)
		var mis_eval := CompatibilityEngine.evaluate(inst_doc, real_reg, "stock", "strategy", "bzcc-2.0.185", real_game, "")
		check(not bool(mis_eval["ok"])
			and String(mis_eval["dllIdentity"]["status"]) == AssetIndex.DLL_STATUS_MISSION_PROFILE_MISMATCH
			and String(mis_eval["validationStatus"]) == CompatibilityEngine.PLAYTEST_MISSION_UNVERIFIED,
			"W1.4 Actual Instant.dll + selected Strategy -> MISSION_PROFILE_MISMATCH refusal")

		# 5) VSR DLL under Stock profile -> HASH_MISMATCH (REFUSE!)
		var vsr_root := String(real_reg.get_profile("vsr").get("gameRoot", ""))
		var vsr_dll_dir := _first_dll_dir(vsr_root, "VSR")
		if not vsr_dll_dir.is_empty():
			var id5 := AssetIndex.inspect_dll_identity("Strategy02.dll", [vsr_dll_dir], "stock", "Strategy02.dll", "strategy", "Strategy02.dll")
			check(String(id5["status"]) == AssetIndex.DLL_STATUS_HASH_MISMATCH and not bool(id5["verified"]),
				"W1.5 VSR Strategy02.dll under Stock profile -> HASH_MISMATCH refusal")

		# 6) VRV DLL under VSR profile -> HASH_MISMATCH (REFUSE!)
		var vrv_root := String(real_reg.get_profile("vrv").get("gameRoot", ""))
		var vrv_dll_dir := _first_dll_dir(vrv_root, "VRV")
		if not vrv_dll_dir.is_empty():
			var id6 := AssetIndex.inspect_dll_identity("Strategy02.dll", [vrv_dll_dir], "vsr", "Strategy02.dll", "strategy", "Strategy02.dll")
			check(String(id6["status"]) in [AssetIndex.DLL_STATUS_HASH_MISMATCH, AssetIndex.DLL_STATUS_HASH_UNVERIFIED] and not bool(id6["verified"]),
				"W1.6 VRV Strategy02.dll under VSR profile -> unverified refusal")

		# 7) Unknown custom DLL -> HASH_UNVERIFIED + UNKNOWN, NOT verified!
		var custom_dll_root := scratch.path_join("w1-unknown-custom-dll")
		write_bytes(custom_dll_root.path_join("MyCustomMode.dll"), "UNKNOWN_CUSTOM_DLL_BYTES_12345".to_utf8_buffer())
		var id7 := AssetIndex.inspect_dll_identity("MyCustomMode.dll", [custom_dll_root], "custom:my_mod", "", "custom-dll", "MyCustomMode.dll")
		check(String(id7["status"]) == AssetIndex.DLL_STATUS_HASH_UNVERIFIED
			and String(id7["semanticState"]) == "UNKNOWN" and not bool(id7["verified"]),
			"W1.7 Unknown custom DLL -> HASH_UNVERIFIED / semanticState=UNKNOWN, not verified")

		# 8) Valid explicit inherited Stock DLL -> VERIFIED_EXPLICIT_INHERITANCE (PASS!)
		var id8_vrv := AssetIndex.inspect_dll_identity("LuaMission.dll", [stock_missions_dir], "vrv", "LuaMission.dll", "lua", "LuaMission.dll")
		check(String(id8_vrv["status"]) == AssetIndex.DLL_STATUS_VERIFIED_EXPLICIT_INHERITANCE and bool(id8_vrv["verified"]),
			"W1.8 Stock LuaMission.dll under VRV -> VERIFIED_EXPLICIT_INHERITANCE")
		var id8_vsr := AssetIndex.inspect_dll_identity("mpinstant.dll", [stock_missions_dir], "vsr", "mpinstant.dll", "mpi", "mpinstant.dll")
		check(String(id8_vsr["status"]) == AssetIndex.DLL_STATUS_VERIFIED_EXPLICIT_INHERITANCE and bool(id8_vsr["verified"]),
			"W1.8 Stock mpinstant.dll under VSR -> VERIFIED_EXPLICIT_INHERITANCE")
		# Verify Stock LuaMission.dll is NOT allowed as inherited under VSR (VSR ships its own!)
		var id8_vsr_lua := AssetIndex.inspect_dll_identity("LuaMission.dll", [stock_missions_dir], "vsr", "LuaMission.dll", "lua", "LuaMission.dll")
		check(String(id8_vsr_lua["status"]) == AssetIndex.DLL_STATUS_HASH_MISMATCH and not bool(id8_vsr_lua["verified"]),
			"W1.8 Stock LuaMission.dll under VSR is refused (VSR ships its own LuaMission.dll)")

		# 9) Correct Strategy02.dll file, but wrong mission contract ('instant' / 'blank') -> MISSION_PROFILE_MISMATCH
		var id9_inst := AssetIndex.inspect_dll_identity("Strategy02.dll", [stock_missions_dir], "stock", "Instant.dll", "instant", "Strategy02.dll")
		check(String(id9_inst["status"]) == AssetIndex.DLL_STATUS_MISSION_PROFILE_MISMATCH and not bool(id9_inst["verified"]),
			"W1.9 Valid Stock Strategy02.dll under Instant mission contract -> MISSION_PROFILE_MISMATCH")
		var id9_blank := AssetIndex.inspect_dll_identity("Strategy02.dll", [stock_missions_dir], "stock", "", "blank", "Strategy02.dll")
		check(String(id9_blank["status"]) == AssetIndex.DLL_STATUS_MISSION_PROFILE_MISMATCH and not bool(id9_blank["verified"]),
			"W1.9 Valid Stock Strategy02.dll under Blank mission contract -> MISSION_PROFILE_MISMATCH")

		# 10) New Map Wizard / profile switch cannot silently preserve stale mission DLL
		var blank_from_strat_dir := scratch.path_join("w1-blank-no-stale-dll")
		check(writer.create_native_flat_map(blank_bzn, blank_from_strat_dir, 1024, 100.0, "", {
			"mod_profile": "stock",
			"mission_profile": "blank",
			"configure_mission": false,
			"sync_mission_dll": true,
			"sanitize_stock_objects": true,
		}), "W1.10 create blank Stock map with sync_mission_dll=true")
		var blank_clean_doc := Document.new()
		check(blank_clean_doc.open(blank_from_strat_dir.path_join(blank_bzn.get_file())), "W1.10 open blank Stock map")
		check(blank_clean_doc.package.mission_dll.is_empty(),
			"W1.10 New Map Wizard blank mode clears template stale Strategy02.dll instead of silently preserving it")
		# Non-destructive switch from Strategy -> Instant surfaces MISSION_PROFILE_MISMATCH; explicit convert aligns DLL + exports natively!
		var switch_doc := Document.new()
		check(switch_doc.open(stock_strat_bzn), "W1.10 open Stock Strategy map for profile switch test")
		check(switch_doc.set_target_profile("stock", "instant"), "W1.10 switch target profile strategy -> instant")
		var sw_eval := CompatibilityEngine.evaluate(switch_doc, real_reg, "stock", "instant", "bzcc-2.0.185", real_game, "")
		check(not bool(sw_eval["ok"]) and String(sw_eval["dllIdentity"]["status"]) == AssetIndex.DLL_STATUS_MISSION_PROFILE_MISMATCH,
			"W1.10 non-destructive profile switch exposes stale Strategy02.dll as MISSION_PROFILE_MISMATCH")
		var conv_res := switch_doc.convert_objects_to_profile("stock", "instant")
		check(bool(conv_res["ok"]) and switch_doc.effective_mission_dll() == "Instant.dll",
			"W1.10 explicit convert_objects_to_profile aligns mission_dll_override to Instant.dll")
		switch_doc.undo()
		check(switch_doc.effective_mission_dll() == "Strategy02.dll", "W1.10 Undo reverts mission DLL override")
		switch_doc.redo()
		check(switch_doc.effective_mission_dll() == "Instant.dll", "W1.10 Redo reapplies mission DLL override")
		var dll_bzmag := scratch.path_join("w1-dll-override.bzmag")
		check(writer.save_project(switch_doc, dll_bzmag), "W1.10 save .bzmag with missionDllOverride")
		var dll_reopen := Document.new()
		check(dll_reopen.open(dll_bzmag) and dll_reopen.effective_mission_dll() == "Instant.dll",
			"W1.10 .bzmag preserves missionDllOverride")
		var dll_exp_dir := scratch.path_join("w1-dll-exported")
		check(writer.export_native(dll_reopen, dll_exp_dir), "W1.10 export native with patched Instant.dll: " + writer.error)
		var dll_reimp := Document.new()
		check(dll_reimp.open(dll_exp_dir.path_join(blank_bzn.get_file())) and dll_reimp.package.mission_dll == "Instant.dll",
			"W1.10 exported native BZN reimports with Instant.dll")

		# Real DOCP v2 zlib decompression proof on installed BZ2R smtex.pak!
		var smtex_pak := real_game.path_join("smtex.pak")
		if FileAccess.file_exists(smtex_pak):
			var sm_dir := AssetIndex.read_docp_pak_directory(smtex_pak)
			check(bool(sm_dir["ok"]) and (sm_dir["entries"] as Dictionary).size() > 100,
				"W2 real BZ2R smtex.pak directory parses cleanly (%d entries)" % (sm_dir["entries"] as Dictionary).size())
			var bane_stored := AssetIndex.read_docp_pak_entry(smtex_pak, "bane.tga")
			var bane_zlib := AssetIndex.read_docp_pak_entry(smtex_pak, "bane2.tga")
			check(bool(bane_stored["ok"]) and String(bane_stored["compression"]) == "stored" and (bane_stored["bytes"] as PackedByteArray).size() == 49196,
				"W2 real BZ2R smtex.pak stored entry bane.tga reads 49196 bytes")
			check(bool(bane_zlib["ok"]) and String(bane_zlib["compression"]) == "zlib" and (bane_zlib["bytes"] as PackedByteArray).size() == 49196,
				"W2 real BZ2R smtex.pak zlib-compressed entry bane2.tga decompresses cleanly to 49196 bytes")

		# Wave 5: Actionable Mod Manager diagnostic for VSR missing dep 3627212766 (Stock unaffected)
		var vsr_diag := real_reg.get_mod_diagnostic("vsr", real_game, real_vrv)
		var stock_diag := real_reg.get_mod_diagnostic("stock", real_game, real_vrv)
		check(String(stock_diag["playtestStatus"]) == "READY" and bool(stock_diag["complete"]),
			"W5 Stock diagnostic stays READY regardless of VSR missing dependency")
		if "3627212766" in (vsr_diag["missingDependencies"] as Array):
			check(String(vsr_diag["playtestStatus"]) == "BLOCKED_MISSING_DEPENDENCY"
				and not (vsr_diag["unresolvedDetails"] as Array).is_empty()
				and not String((vsr_diag["unresolvedDetails"] as Array)[0].get("note", "")).is_empty()
				and bool(vsr_diag["stockUnaffected"]),
				"W5 VSR diagnostic surfaces exact unresolved Workshop ID 3627212766 with seasonal note and safe editing ops")

	# =========================================================================
	# 6. WAVE 2 (P0): Packed ODF Dependency Inspection & DOCP v2 Safety Matrix
	# =========================================================================
	var pak_test_root := scratch.path_join("w2-pak-matrix")
	DirAccess.make_dir_recursive_absolute(pak_test_root)

	# Helper closure via local arrays: build real DOCP v2 archives with payloads (stored & zlib)
	var parent_odf_txt := "[GameObjectClass]\ngeometryName = \"parent_mesh.fbx\"\nunitName = \"Packed Parent\"\nfireSound = \"pew.wav\"\n"
	var child_odf_txt := "[GameObjectClass]\nclassLabel = \"packed_parent\"\nunitName = \"Packed Child\"\n"
	var miss_mesh_txt := "[GameObjectClass]\nclassLabel = \"wingman\"\ngeometryName = \"absent_mesh.fbx\"\n"
	var miss_snd_txt := "[GameObjectClass]\nclassLabel = \"wingman\"\ngeometryName = \"ok_mesh.fbx\"\nfireSound = \"absent_snd.wav\"\n"
	var miss_tex_odf_txt := "[GameObjectClass]\nclassLabel = \"wingman\"\ngeometryName = \"tex_mesh.fbx\"\n"
	var miss_tex_mat_txt := "[Texture]\ndiffuse = \"absent_tex.dds\"\n"
	var loose_vs_pak_packed := "[GameObjectClass]\nclassLabel = \"wingman\"\nunitName = \"FROM_PAK\"\ngeometryName = \"ok_mesh.fbx\"\n"
	var loose_vs_pak_loose := "[GameObjectClass]\nclassLabel = \"wingman\"\nunitName = \"FROM_LOOSE\"\ngeometryName = \"ok_mesh.fbx\"\n"

	var good_pak := pak_test_root.path_join("good_assets.pak")
	_write_docp_v2_pak(good_pak, [
		{"name": "packed_parent.odf", "bytes": parent_odf_txt.to_ascii_buffer(), "compress": true},
		{"name": "packed_child.odf", "bytes": child_odf_txt.to_ascii_buffer(), "compress": false},
		{"name": "parent_mesh.msh", "bytes": PackedByteArray([1, 2, 3, 4]), "compress": false},
		{"name": "pew.wav", "bytes": PackedByteArray([82, 73, 70, 70]), "compress": false},
		{"name": "ok_mesh.msh", "bytes": PackedByteArray([5, 6, 7, 8]), "compress": false},
		{"name": "miss_mesh.odf", "bytes": miss_mesh_txt.to_ascii_buffer(), "compress": false},
		{"name": "miss_snd.odf", "bytes": miss_snd_txt.to_ascii_buffer(), "compress": true},
		{"name": "tex_mesh.msh", "bytes": PackedByteArray([9, 10, 11, 12]), "compress": false},
		{"name": "tex_mesh.material", "bytes": miss_tex_mat_txt.to_ascii_buffer(), "compress": true},
		{"name": "miss_tex.odf", "bytes": miss_tex_odf_txt.to_ascii_buffer(), "compress": false},
		{"name": "both_odf.odf", "bytes": loose_vs_pak_packed.to_ascii_buffer(), "compress": false},
		{"name": "dup_unit.odf", "bytes": loose_vs_pak_packed.to_ascii_buffer(), "compress": false},
		{"name": "dup_unit.odf", "bytes": loose_vs_pak_loose.to_ascii_buffer(), "compress": false},
	])
	write_text(pak_test_root.path_join("both_odf.odf"), loose_vs_pak_loose)
	write_text(pak_test_root.path_join("wingman.odf"), "[GameObjectClass]\ngeometryName = \"ok_mesh.fbx\"\nunitName = \"Wingman Base\"\n")
	write_text(pak_test_root.path_join("loose_unit.odf"), "[GameObjectClass]\nclassLabel = \"packed_parent\"\nunitName = \"Loose Child Of Packed Parent\"\n")

	var override_top := scratch.path_join("w2-override-top")
	write_text(override_top.path_join("packed_child.odf"), "[GameObjectClass]\nclassLabel = \"wingman\"\nunitName = \"TOP_ROOT_WINNER\"\ngeometryName = \"ok_mesh.fbx\"\n")

	var w2_layered := AssetIndex.index_layered_roots([
		{"path": pak_test_root, "source": "base", "recurse": true, "volatile": false},
	])
	# Loose ODF inheriting packed parent ODF
	var d_loose := AssetIndex.inspect_odf_dependencies("loose_unit.odf", w2_layered)
	check(String(d_loose["inspectionStatus"]) == AssetIndex.INSPECT_DEPENDENCIES_RESOLVED
		and String(d_loose["geometryName"]) == "parent_mesh.fbx"
		and (d_loose["parentChain"] as Array) == ["loose_unit.odf", "packed_parent.odf"],
		"W2 loose ODF inheriting zlib-packed parent resolves chain & geometry -> DEPENDENCIES_RESOLVED")
	# Packed ODF + packed parent chain
	var d_packed := AssetIndex.inspect_odf_dependencies("packed_child.odf", w2_layered)
	check(bool(d_packed["packed"]) and String(d_packed["inspectionStatus"]) == AssetIndex.INSPECT_DEPENDENCIES_RESOLVED
		and String(d_packed["geometryName"]) == "parent_mesh.fbx"
		and String(d_packed["meshPath"]).ends_with("::parent_mesh.msh"),
		"W2 packed child -> zlib-packed parent -> packed mesh/sound resolves -> DEPENDENCIES_RESOLVED")
	# Missing mesh, missing sound, missing texture (via packed .material!)
	var d_mmesh := AssetIndex.inspect_odf_dependencies("miss_mesh.odf", w2_layered)
	check(String(d_mmesh["inspectionStatus"]) == AssetIndex.INSPECT_DEPENDENCIES_UNVERIFIED and bool(d_mmesh["meshMissing"]),
		"W2 packed ODF with missing mesh -> DEPENDENCIES_UNVERIFIED + meshMissing=true")
	var d_msnd := AssetIndex.inspect_odf_dependencies("miss_snd.odf", w2_layered)
	check(String(d_msnd["inspectionStatus"]) == AssetIndex.INSPECT_DEPENDENCIES_UNVERIFIED and "absent_snd.wav" in (d_msnd["missingSounds"] as Array),
		"W2 packed ODF with missing sound -> DEPENDENCIES_UNVERIFIED + missingSounds")
	var d_mtex := AssetIndex.inspect_odf_dependencies("miss_tex.odf", w2_layered)
	check(String(d_mtex["inspectionStatus"]) == AssetIndex.INSPECT_DEPENDENCIES_UNVERIFIED and "absent_tex.dds" in (d_mtex["missingTextures"] as Array),
		"W2 packed ODF + zlib-packed .material with missing diffuse texture -> DEPENDENCIES_UNVERIFIED + missingTextures")
	# Loose vs packed precedence inside same root
	var d_both := AssetIndex.inspect_odf_dependencies("both_odf.odf", w2_layered)
	check(not bool(d_both["packed"]) and String(d_both["unitName"]) == "FROM_LOOSE",
		"W2 same ODF loose and packed in same root: loose takes precedence over packed")
	# Cross-root override precedence
	var w2_ovr_layered := AssetIndex.index_layered_roots([
		{"path": override_top, "source": "mod_top", "recurse": true, "volatile": false},
		{"path": pak_test_root, "source": "base", "recurse": true, "volatile": false},
	])
	var d_ovr := AssetIndex.inspect_odf_dependencies("packed_child.odf", w2_ovr_layered)
	check(String(d_ovr["source"]) == "mod_top" and String(d_ovr["unitName"]) == "TOP_ROOT_WINNER",
		"W2 higher root overrides lower packed ODF cleanly")
	# Duplicate entry inside PAK detected
	var good_dir_info := AssetIndex.read_docp_pak_directory(good_pak)
	check("dup_unit.odf" in (good_dir_info["duplicateEntries"] as Array),
		"W2 duplicate entry inside DOCP .pak is detected and recorded")

	# Corrupt offset, truncated archive, unsupported compression, oversized entry
	var bad_pak_dir := scratch.path_join("w2-bad-paks")
	DirAccess.make_dir_recursive_absolute(bad_pak_dir)
	var corrupt_off_pak := bad_pak_dir.path_join("corrupt_offset.pak")
	_write_docp_v2_raw_entry(corrupt_off_pak, "bad_off.odf", 999999, 64, 64, PackedByteArray())
	var r_corrupt := AssetIndex.read_docp_pak_entry(corrupt_off_pak, "bad_off.odf")
	check(not bool(r_corrupt["ok"]) and String(r_corrupt["status"]) == AssetIndex.INSPECT_ENTRY_CORRUPT,
		"W2 corrupt DOCP entry offset -> ENTRY_CORRUPT")

	var trunc_pak := bad_pak_dir.path_join("truncated.pak")
	var full_good := FileAccess.get_file_as_bytes(good_pak)
	write_bytes(trunc_pak, full_good.slice(0, full_good.size() - 24))
	var trunc_dir := AssetIndex.read_docp_pak_directory(trunc_pak)
	check(bool(trunc_dir["truncated"]) and bool(trunc_dir["corrupt"]),
		"W2 truncated DOCP archive is flagged truncated & corrupt")

	var unsup_pak := bad_pak_dir.path_join("unsup_comp.pak")
	var fake_comp := PackedByteArray([0x04, 0x22, 0x4d, 0x18, 0x00, 0x00, 0x00, 0x00]) # LZ4 magic, not zlib!
	_write_docp_v2_raw_entry(unsup_pak, "lz4_unit.odf", 32, fake_comp.size(), 128, fake_comp)
	var r_unsup := AssetIndex.read_docp_pak_entry(unsup_pak, "lz4_unit.odf")
	check(not bool(r_unsup["ok"]) and String(r_unsup["status"]) == AssetIndex.INSPECT_ENTRY_INDEXED and String(r_unsup["compression"]) == "unsupported",
		"W2 unsupported PAK compression -> ENTRY_INDEXED (not false verified, no crash)")

	var over_pak := bad_pak_dir.path_join("oversized.pak")
	var tiny_payload := PackedByteArray([0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01])
	_write_docp_v2_raw_entry(over_pak, "huge_unit.odf", 32, tiny_payload.size(), 16 * 1024 * 1024, tiny_payload)
	var r_over := AssetIndex.read_docp_pak_entry(over_pak, "huge_unit.odf")
	check(not bool(r_over["ok"]) and String(r_over["status"]) == AssetIndex.INSPECT_ENTRY_INDEXED,
		"W2 oversized PAK entry (>4 MiB) refused safely -> ENTRY_INDEXED")

	# =========================================================================
	# 7. WAVE 2 (P0): Asset Cache Invalidation Matrix (13 scenarios)
	# =========================================================================
	var cinv_root := scratch.path_join("w2-cache-inv")
	DirAccess.make_dir_recursive_absolute(cinv_root)
	write_text(cinv_root.path_join("u1.odf"), "[GameObjectClass]\nunitName = \"AAA\"\n")
	write_text(cinv_root.path_join("u1.material"), "[Texture]\ndiffuse = \"a.dds\"\n")
	write_bytes(cinv_root.path_join("u1.msh"), PackedByteArray([1, 2, 3, 4]))
	write_bytes(cinv_root.path_join("CustomMode.dll"), "DLL_BODY_V1".to_utf8_buffer())
	_write_docp_v2_pak(cinv_root.path_join("pack.pak"), [{"name": "p1.odf", "bytes": "[GameObjectClass]\nunitName = \"P1\"\n".to_ascii_buffer(), "compress": false}])

	var st0 := AssetIndex.compute_root_stamp(cinv_root, true)
	var _ci0 := AssetIndex.get_root_index(cinv_root, true, false)
	# 1) Same-size modified ODF (including same-second timestamp collision!)
	write_text(cinv_root.path_join("u1.odf"), "[GameObjectClass]\nunitName = \"BBB\"\n")
	var st1 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st1 != st0, "W2.cache same-size + same-second modified ODF invalidates root stamp immediately")
	# 2) Existing MATERIAL changed (same size)
	write_text(cinv_root.path_join("u1.material"), "[Texture]\ndiffuse = \"b.dds\"\n")
	var st2 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st2 != st1, "W2.cache existing .material same-size change invalidates root stamp")
	# 3) Existing DLL replaced (same size) + live SHA-256 verification
	var dll_before := AssetIndex.inspect_dll_identity("CustomMode.dll", [cinv_root], "custom:test", "", "custom-dll", "CustomMode.dll")
	write_bytes(cinv_root.path_join("CustomMode.dll"), "DLL_BODY_V2".to_utf8_buffer())
	var st3 := AssetIndex.compute_root_stamp(cinv_root, true)
	var dll_after := AssetIndex.inspect_dll_identity("CustomMode.dll", [cinv_root], "custom:test", "", "custom-dll", "CustomMode.dll")
	check(st3 != st2 and String(dll_before["sha256"]) != String(dll_after["sha256"]),
		"W2.cache existing DLL same-size replacement invalidates stamp and re-hashes live bytes")
	# 4) Existing mesh replaced (same size)
	write_bytes(cinv_root.path_join("u1.msh"), PackedByteArray([9, 8, 7, 6]))
	var st4 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st4 != st3, "W2.cache existing .msh same-size replacement invalidates stamp")
	# 5) File renamed
	DirAccess.rename_absolute(cinv_root.path_join("u1.msh"), cinv_root.path_join("u2.msh"))
	var st5 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st5 != st4 and (AssetIndex.get_root_index(cinv_root, true, false)["files"] as Dictionary).has("u2.msh"),
		"W2.cache file rename invalidates stamp and updates index")
	# 6) File deleted
	DirAccess.remove_absolute(cinv_root.path_join("u2.msh"))
	var st6 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st6 != st5 and not (AssetIndex.get_root_index(cinv_root, true, false)["files"] as Dictionary).has("u2.msh"),
		"W2.cache file deletion invalidates stamp and removes entry")
	# 7) File added
	write_text(cinv_root.path_join("added.odf"), "[GameObjectClass]\n")
	var st7 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st7 != st6 and (AssetIndex.get_root_index(cinv_root, true, false)["odfs"] as Dictionary).has("added.odf"),
		"W2.cache file addition invalidates stamp")
	# 8) PAK replaced with same filename (same size)
	_write_docp_v2_pak(cinv_root.path_join("pack.pak"), [{"name": "p2.odf", "bytes": "[GameObjectClass]\nunitName = \"P2\"\n".to_ascii_buffer(), "compress": false}])
	var st8 := AssetIndex.compute_root_stamp(cinv_root, true)
	check(st8 != st7 and (AssetIndex.get_root_index(cinv_root, true, false)["odfs"] as Dictionary).has("p2.odf"),
		"W2.cache PAK replaced with same filename invalidates stamp and reflects p2.odf")
	# 9) Explicit invalidate_root + map-local override
	AssetIndex.invalidate_root(cinv_root)
	var misses_before := int(AssetIndex.cache_stats()["misses"])
	var _rebuilt := AssetIndex.get_root_index(cinv_root, true, false)
	check(int(AssetIndex.cache_stats()["misses"]) == misses_before + 1,
		"W2.cache invalidate_root forces fresh rebuild (superseded worker safety)")

	# =========================================================================
	# 8. WAVE 5 (P1): Custom DLL Basename Collision -> AMBIGUOUS (Section 7)
	# =========================================================================
	var col_ws := scratch.path_join("w5-dll-collision")
	write_text(col_ws.path_join("700001/700001.ini"), "[WORKSHOP]\nmodName = \"Alpha Mod\"\nmodType = \"config\"\n")
	write_bytes(col_ws.path_join("700001/SharedCustom.dll"), "ALPHA_SHARED_DLL_BYTES".to_utf8_buffer())
	write_text(col_ws.path_join("700001/alpha_only.odf"), "[GameObjectClass]\nclassLabel = \"wingman\"\n")
	write_text(col_ws.path_join("700002/700002.ini"), "[WORKSHOP]\nmodName = \"Beta Mod\"\nmodType = \"config\"\n")
	write_bytes(col_ws.path_join("700002/SharedCustom.dll"), "BETA_SHARED_DLL_BYTES!".to_utf8_buffer())
	write_text(col_ws.path_join("700002/beta_only.odf"), "[GameObjectClass]\nclassLabel = \"wingman\"\n")
	var col_reg := ModRegistry.new()
	col_reg.discover_installed(synth_game, "", col_ws)

	var col_map_path := patch_map_odf_and_dll(blank_bzn, scratch.path_join("w5-col-map"), "ivtank", "SharedCustom.dll")
	var col_pkg := Document.new()
	check(col_pkg.open(col_map_path), "W5 open map referencing colliding SharedCustom.dll")
	var col_det := ModRegistry.detect_map_profiles(col_pkg.package, col_reg)
	check(String(col_det["detectionState"]) == "AMBIGUOUS"
		and bool(col_det["ambiguousCollision"])
		and String(col_det["recommendedMod"]) == "custom:unknown"
		and (col_det["collidingMods"] as Array).size() == 2,
		"W5 two custom mods sharing SharedCustom.dll basename -> AMBIGUOUS (never first mod with HIGH confidence)")

	# Disambiguate via map-local DLL SHA-256 matching Beta Mod!
	write_bytes(col_map_path.get_base_dir().path_join("SharedCustom.dll"), "BETA_SHARED_DLL_BYTES!".to_utf8_buffer())
	var col_det_hash := ModRegistry.detect_map_profiles(col_pkg.package, col_reg)
	check(String(col_det_hash["recommendedMod"]) == "custom:ws-700002" and not bool(col_det_hash["ambiguousCollision"]),
		"W5 map-local DLL SHA-256 uniquely disambiguates colliding SharedCustom.dll to Beta Mod")
	DirAccess.remove_absolute(col_map_path.get_base_dir().path_join("SharedCustom.dll"))

	# Disambiguate via unique ODF origin matching Alpha Mod!
	var col_alpha_path := patch_map_odf_and_dll(blank_bzn, scratch.path_join("w5-col-alpha-map"), "alpha_only", "SharedCustom.dll")
	var col_alpha_doc := Document.new()
	check(col_alpha_doc.open(col_alpha_path), "W5 open map with alpha_only + SharedCustom.dll")
	var col_det_odf := ModRegistry.detect_map_profiles(col_alpha_doc.package, col_reg)
	check(String(col_det_odf["recommendedMod"]) == "custom:ws-700001" and not bool(col_det_odf["ambiguousCollision"]),
		"W5 positive ODF origin uniquely disambiguates colliding SharedCustom.dll to Alpha Mod")

	editor.free()
	print("Compatibility truth, DLL identity, DOCP v2 inspection, cache invalidation & collision checks complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func _write_docp_v2_pak(path: String, items: Array) -> void:
	var data_buf := PackedByteArray()
	data_buf.resize(56)
	var metas: Array[Dictionary] = []
	for item_v in items:
		var item: Dictionary = item_v
		var raw: PackedByteArray = item["bytes"]
		var payload := raw.compress(FileAccess.COMPRESSION_DEFLATE) if bool(item.get("compress", false)) else raw
		var offset := data_buf.size()
		data_buf.append_array(payload)
		metas.append({
			"name": String(item["name"]),
			"flags": 1 if bool(item.get("compress", false)) else 0,
			"offset": offset,
			"packed": payload.size(),
			"unpacked": raw.size(),
		})
	var dir_offset := data_buf.size()
	var dir_buf := PackedByteArray()
	for m in metas:
		var nb := String(m["name"]).to_ascii_buffer()
		var hdr := PackedByteArray()
		hdr.resize(5)
		hdr.encode_u32(0, int(m.get("flags", 0)))
		hdr[4] = nb.size()
		dir_buf.append_array(hdr)
		dir_buf.append_array(nb)
		var tail := PackedByteArray()
		tail.resize(12)
		tail.encode_u32(0, int(m["offset"]))
		tail.encode_u32(4, int(m["packed"]))
		tail.encode_u32(8, int(m["unpacked"]))
		dir_buf.append_array(tail)
	var full := PackedByteArray()
	full.append_array(data_buf)
	full.append_array(dir_buf)
	var magic := "DOCP".to_ascii_buffer()
	for i in 4:
		full[i] = magic[i]
	full.encode_u32(4, 2)
	full.encode_u32(12, dir_offset)
	full.encode_u32(16, metas.size())
	full.encode_u32(20, dir_offset)
	write_bytes(path, full)


func _write_docp_v2_raw_entry(path: String, entry_name: String, offset: int, packed: int, unpacked: int, payload: PackedByteArray) -> void:
	var full := PackedByteArray()
	full.resize(32)
	full.append_array(payload)
	var dir_offset := full.size()
	var nb := entry_name.to_ascii_buffer()
	var hdr := PackedByteArray()
	hdr.resize(5)
	hdr.encode_u32(0, 0)
	hdr[4] = nb.size()
	full.append_array(hdr)
	full.append_array(nb)
	var tail := PackedByteArray()
	tail.resize(12)
	tail.encode_u32(0, offset)
	tail.encode_u32(4, packed)
	tail.encode_u32(8, unpacked)
	full.append_array(tail)
	var magic := "DOCP".to_ascii_buffer()
	for i in 4:
		full[i] = magic[i]
	full.encode_u32(4, 2)
	full.encode_u32(16, 1)
	full.encode_u32(20, dir_offset)
	write_bytes(path, full)
