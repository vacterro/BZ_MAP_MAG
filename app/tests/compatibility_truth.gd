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
	if args.size() < 3:
		printerr("Pass brave_bzn blank_bzn scratch_dir [optional_game_dir] [optional_vrv_dir]")
		quit(2)
		return
	var brave_bzn := args[0]
	var blank_bzn := args[1]
	var scratch := args[2]
	var real_game := args[3] if args.size() >= 4 else ""
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
			and String(plan_empty["compatibility"]["dllIdentity"]["status"]) == "VERIFIED",
			"Stock 1192 with empty VRV path is READY with verified Stock Strategy02.dll hash")

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

	editor.free()
	print("Compatibility truth, dependency stack & Playtest decoupling checks complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
