extends SceneTree
## Focused Acceptance Suite for Waves 5, 6 & 7:
## - Wave 5: All 13 differentially verified native Stock BZN object builders
##   (6 original + 7 bit-for-bit verified additions), Undo/Redo, BZMAG, Export/Reimport.
## - Wave 6: Mission Studio native checks (required paths, duplicates, missing spawnpoints,
##   invalid mission DLL, profile switch, BZMAG, native export/reimport).
## - Wave 7: Native .SKY binary decoder, Environment Studio read-only inspector +
##   surgical 1YKS Fog/Lighting writer, Undo/Redo, BZMAG, byte-exact preservation
##   outside 1YKS, 3D preview toggle, and staged map for real BZCC Playtest!

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")
const Package := preload("res://formats/map_package.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const SkyEnv := preload("res://formats/sky_env.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const CompatibilityEngine := preload("res://core/compatibility_engine.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, desc: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + desc)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("Pass plgr_bzn brave_bzn game_dir scratch_dir [optional_vrv_dir]")
		quit(2)
		return
	var plgr_bzn := args[0]
	var brave_bzn := args[1]
	var game_dir := args[2]
	var scratch := args[3]
	var vrv_dir := args[4] if args.size() >= 5 else ""

	# =========================================================================
	# 1. WAVE 7: Native .SKY Binary Decoder across real Stock & VRV fixtures
	# =========================================================================
	var plgr_sky_path := plgr_bzn.get_base_dir().path_join("plgr.SKY")
	var brave_sky_path := brave_bzn.get_base_dir().path_join("braveliltoaster.SKY")
	if FileAccess.file_exists(plgr_sky_path):
		var dec_plgr := SkyEnv.decode_sky(FileAccess.get_file_as_bytes(plgr_sky_path))
		check(bool(dec_plgr["ok"]) and int(dec_plgr["version"]) == 65536
			and int(dec_plgr["sizeBytes"]) == 7068
			and (dec_plgr["chunks"] as Array).size() == 13
			and String(dec_plgr["readOnly"]["domeMesh"]) == "miredome.fbx"
			and is_equal_approx(float(dec_plgr["fields"]["fogStart"]), 300.0)
			and is_equal_approx(float(dec_plgr["fields"]["fogEnd"]), 400.0),
			"W7 SkyEnv decodes real BZ2R plgr.SKY (7068 B, 13 chunks, miredome.fbx, FogStart=300, FogEnd=400)")
	if FileAccess.file_exists(brave_sky_path):
		var dec_brave := SkyEnv.decode_sky(FileAccess.get_file_as_bytes(brave_sky_path))
		check(bool(dec_brave["ok"])
			and String(dec_brave["readOnly"]["domeMesh"]) == "dunedome.fbx"
			and String(dec_brave["readOnly"]["skyTexture"]) == "white_clouds.tga"
			and is_equal_approx(float(dec_brave["fields"]["fogStart"]), 400.0)
			and is_equal_approx(float(dec_brave["fields"]["fogEnd"]), 650.0),
			"W7 SkyEnv decodes real braveliltoaster.SKY (dunedome.fbx, white_clouds.tga, FogStart=400, FogEnd=650)")
	# Reject corrupt/truncated SKY and read-only field edits
	check(not bool(SkyEnv.decode_sky(PackedByteArray([1, 2, 3, 4]))["ok"]),
		"W7 SkyEnv rejects truncated/non-SKY bytes cleanly")
	check(not SkyEnv.validate_edits({"domeMesh": "hack.fbx"}).is_empty(),
		"W7 SkyEnv refuses edits to unverified/read-only property 'domeMesh'")
	check(not SkyEnv.validate_edits({"fogStart": -50.0}).is_empty(),
		"W7 SkyEnv refuses out-of-range negative fogStart")

	# =========================================================================
	# 2. Stage clean Stock 1192 Strategy map & test ALL 13 native object builders + .SKY writer
	# =========================================================================
	var base_dir := scratch.path_join("stock-w567-base")
	var writer := Snapshots.new()
	check(writer.create_native_flat_map(plgr_bzn, base_dir, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "strategy",
		"configure_mission": true,
		"sync_mission_dll": true,
		"sanitize_stock_objects": true,
	}), "stage clean Stock 1192 Strategy map: " + writer.error)
	var base_bzn := base_dir.path_join(plgr_bzn.get_file())

	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.settings_path = scratch.path_join("w567-editor.cfg")
	editor.game_path.text = game_dir
	editor.vrv_path.text = vrv_dir
	editor.mod_registry.discover_installed(game_dir, vrv_dir)
	check(editor.open_map(base_bzn), "open staged Stock 1192 Strategy map")
	editor.document.mod_profile = "stock"
	editor.document.mission_profile = "strategy"
	editor.document.profile_explicit = true

	# Place ALL 13 differentially verified native Stock classes!
	var all_native_specs := [
		{"odf": "uepool01", "team": 0, "pos": Vector3(-80.0, 100.0, -80.0), "label": "w5_pool"},
		{"odf": "npscrx",   "team": 0, "pos": Vector3(-60.0, 100.0, -80.0), "label": ""},
		{"odf": "morock03", "team": 0, "pos": Vector3(-40.0, 100.0, -80.0), "label": ""},
		{"odf": "morock01", "team": 0, "pos": Vector3(-20.0, 100.0, -80.0), "label": "w5_giant_rock"},
		{"odf": "mopalm02", "team": 0, "pos": Vector3(0.0,   100.0, -80.0), "label": "w5_palm"},
		{"odf": "ibpgen",   "team": 1, "pos": Vector3(40.0,  100.0, -40.0), "label": "w5_pgen"},
		{"odf": "iblite",   "team": 0, "pos": Vector3(60.0,  100.0, -40.0), "label": ""},
		{"odf": "ibsbay",   "team": 1, "pos": Vector3(80.0,  100.0, -40.0), "label": "w5_sbay"},
		{"odf": "ibtcen",   "team": 1, "pos": Vector3(110.0, 100.0, -40.0), "label": "w5_tcen"},
		{"odf": "ibtrain",  "team": 1, "pos": Vector3(140.0, 100.0, -40.0), "label": "w5_train"},
		{"odf": "ibwseg",   "team": 1, "pos": Vector3(40.0,  100.0, 0.0),   "label": ""},
		{"odf": "ibwstr",   "team": 1, "pos": Vector3(60.0,  100.0, 0.0),   "label": ""},
		{"odf": "pspwn_1",  "team": 0, "pos": Vector3(0.0,   100.0, 40.0),  "label": "w5_spawn"},
	]
	var count_before: int = editor.document.object_count()
	for sp: Dictionary in all_native_specs:
		var v: int = editor.document.place_native_object(String(sp["odf"]), sp["pos"], int(sp["team"]), String(sp["label"]))
		check(v >= count_before, "W5 place native class %s" % sp["odf"])
	check(editor.document.object_count() == count_before + 13,
		"W5 all 13 verified native classes added (%d -> %d)" % [count_before, editor.document.object_count()])
	# Verify Object Browser lists all 13 as VERIFIED_NEW_CLASS + ENABLED on Stock
	editor.open_object_browser()
	var br_map := {}
	for e: Dictionary in editor.object_browser.catalog_entries:
		br_map[String(e["stem"])] = e
	for sp: Dictionary in all_native_specs:
		var st := String(sp["odf"])
		check(br_map.has(st) and String(br_map[st]["placement"]) == "ENABLED" and String(br_map[st]["capability"]) == "VERIFIED_NEW_CLASS",
			"W5 Object Browser exposes %s as VERIFIED_NEW_CLASS + ENABLED" % st)
	editor.object_browser.hide()

	# =========================================================================
	# 3. WAVE 7: Environment Studio edit -> 3D preview -> Undo/Redo -> BZMAG -> Export
	# =========================================================================
	editor.open_environment_studio()
	var env_dlg = editor.environment_studio
	check(not env_dlg.apply_button.disabled and env_dlg.fog_start_field.editable,
		"W7 Environment Studio enables verified 1YKS controls on map with native .SKY")
	env_dlg.fog_color_picker.color = Color(0.25, 0.45, 0.65, 1.0)
	env_dlg.fog_start_field.value = 180.0
	env_dlg.fog_end_field.value = 520.0
	env_dlg.vis_range_field.value = 720.0
	env_dlg.sun_angle_field.value = 14.5
	env_dlg.sun_color_picker.color = Color(0.95, 0.85, 0.70, 1.0)
	env_dlg.ambient_color_picker.color = Color(0.35, 0.40, 0.50, 1.0)
	env_dlg.apply_edits()
	check(editor.document.has_environment_edits()
		and is_equal_approx(float(editor.document.effective_environment()["fogStart"]), 180.0)
		and is_equal_approx(float(editor.document.effective_environment()["fogEnd"]), 520.0),
		"W7 Environment Studio applies fog/sun/ambient edits to document")
	# 3D preview toggle
	env_dlg.preview_check.button_pressed = true
	check(editor.scene_view.env_preview_enabled
		and editor.scene_view.world_env.environment.fog_enabled
		and is_equal_approx(editor.scene_view.world_env.environment.fog_depth_begin, 180.0),
		"W7 3D viewport applies live Fog & Lighting preview from .SKY edits")
	env_dlg.preview_check.button_pressed = false
	check(not editor.scene_view.env_preview_enabled and not editor.scene_view.world_env.environment.fog_enabled,
		"W7 disabling 3D environment preview cleanly restores default editor viewport")
	env_dlg.hide()

	# Undo / Redo on .SKY edits
	editor.document.undo()
	check(not editor.document.has_environment_edits(), "W7 Undo restores original .SKY values")
	editor.document.redo()
	check(editor.document.has_environment_edits()
		and is_equal_approx(float(editor.document.effective_environment()["fogStart"]), 180.0),
		"W7 Redo reapplies .SKY edits")

	# BZMAG Save & Reopen
	var bzmag_path := scratch.path_join("w567-combined.bzmag")
	check(writer.save_project(editor.document, bzmag_path), "W5/7 save combined .bzmag: " + writer.error)
	var reopened := Document.new()
	check(reopened.open(bzmag_path)
		and reopened.object_count() == count_before + 13
		and reopened.has_environment_edits()
		and is_equal_approx(float(reopened.effective_environment()["fogStart"]), 180.0)
		and is_equal_approx(float(reopened.effective_environment()["vis_range" if false else "visibilityRange"]), 720.0),
		"W5/7 reopened .bzmag preserves all 13 native objects and .SKY environment edits")

	# Native Export + Re-import + Byte-Exact Verification outside 1YKS
	var exp_dir := scratch.path_join("w567-exported-stock")
	check(writer.export_native(reopened, exp_dir), "W5/7 export native BZN + .SKY: " + writer.error)
	var exp_bzn := exp_dir.path_join(plgr_bzn.get_file())
	var exp_sky := exp_dir.path_join(reopened.package.sky_name)
	var orig_sky_bytes := reopened.package.sky_bytes
	var exp_sky_bytes := FileAccess.get_file_as_bytes(exp_sky)
	check(exp_sky_bytes.size() == orig_sky_bytes.size()
		and exp_sky_bytes.slice(0, 20) == orig_sky_bytes.slice(0, 20)
		and exp_sky_bytes.slice(232) == orig_sky_bytes.slice(232)
		and exp_sky_bytes != orig_sky_bytes,
		"W7 exported .SKY modifies ONLY 1YKS bytes while preserving header and all 11 other chunks 100% byte-identical")
	var verify_pkg := Package.new()
	check(verify_pkg.open(exp_bzn)
		and verify_pkg.objects.size() == count_before + 13
		and bool(verify_pkg.sky_env["ok"])
		and is_equal_approx(float(verify_pkg.sky_env["fields"]["fogStart"]), 180.0)
		and is_equal_approx(float(verify_pkg.sky_env["fields"]["fogEnd"]), 520.0)
		and is_equal_approx(float(verify_pkg.sky_env["fields"]["visibilityRange"]), 720.0)
		and is_equal_approx(float(verify_pkg.sky_env["fields"]["sunAngle"]), 14.5),
		"W5/7 reimported native package contains all 13 new objects and exact edited .SKY values")

	# =========================================================================
	# 4. WAVE 6: Mission Studio Native Validation Tests
	# =========================================================================
	# 4a) Duplicate path name refusal
	var dup_idx: int = editor.document.create_path("edge_path", PackedVector2Array([Vector2(0, 0), Vector2(64, 64)]), 2)
	check(dup_idx < 0, "W6 MapDocument refuses creating duplicate path name 'edge_path'")

	# 4b) Missing required paths in Instant profile -> errors, then Generate Required fixes them in 1 undo step
	check(editor.document.set_target_profile("stock", "instant"), "W6 switch target profile to Stock Instant")
	var inst_val_before := MissionProfiles.validate(editor.document, "instant", "stock")
	check(not bool(inst_val_before["ok"])
		and "Recycler" in (inst_val_before["missing_required"] as Array)
		and "RecyclerEnemy" in (inst_val_before["missing_required"] as Array),
		"W6 Stock Instant validation detects missing Recycler and RecyclerEnemy paths")
	editor.open_mission_studio()
	editor.mission_studio.generate_missing_required()
	var inst_val_after := MissionProfiles.validate(editor.document, "instant", "stock")
	check(bool(inst_val_after["ok"]), "W6 Mission Studio Generate Required creates Recycler & RecyclerEnemy and passes validation")
	editor.mission_studio.hide()
	# Profile switch without explicit DLL conversion STILL refuses Playtest (MISSION_PROFILE_MISMATCH)
	var pre_dll_compat := CompatibilityEngine.evaluate(editor.document, editor.mod_registry, "stock", "instant", "bzcc-2.0.185", game_dir, "")
	check(not bool(pre_dll_compat["ok"]) and String(pre_dll_compat["dllIdentity"]["status"]) == "MISSION_PROFILE_MISMATCH",
		"W6 switching to Stock Instant without converting DLL refuses Playtest with MISSION_PROFILE_MISMATCH")
	# Explicit set_mission_dll aligns DLL -> READY!
	check(editor.document.set_mission_dll("Instant.dll"), "W6 set_mission_dll('Instant.dll')")
	var post_dll_compat := CompatibilityEngine.evaluate(editor.document, editor.mod_registry, "stock", "instant", "bzcc-2.0.185", game_dir, "")
	check(bool(post_dll_compat["ok"]) and String(post_dll_compat["validationStatus"]) == CompatibilityEngine.PLAYTEST_READY,
		"W6 after explicit Instant.dll alignment + required paths, Stock Instant is PLAYTEST_READY")
	# Invalid mission DLL name refused
	check(not editor.document.set_mission_dll("../bad.exe"), "W6 set_mission_dll refuses invalid/traversal filename")

	# 4c) Missing spawnpoints warning check
	var no_spwn_dir := scratch.path_join("w6-no-spawn")
	check(writer.create_native_flat_map(plgr_bzn, no_spwn_dir, 1024, 100.0, "", {
		"mod_profile": "stock", "mission_profile": "blank", "configure_mission": false, "sync_mission_dll": true, "sanitize_stock_objects": true,
	}), "W6 stage blank map with no spawnpoints")
	var no_spwn_doc := Document.new()
	check(no_spwn_doc.open(no_spwn_dir.path_join(plgr_bzn.get_file())), "W6 open blank map")
	var spwn_eval := CompatibilityEngine.evaluate(no_spwn_doc, editor.mod_registry, "stock", "strategy", "bzcc-2.0.185", game_dir, "")
	var has_spwn_warn := false
	for w_v in spwn_eval.get("warnings", []):
		if "pspwn_1" in String(w_v):
			has_spwn_warn = true
	check(has_spwn_warn, "W6 missing pspwn_1 spawnpoint emits clear warning for Stock Strategy")

	# 4d) Custom unknown DLL stays generic/UNKNOWN (never inherits Stock requirements)
	var custom_contract := MissionProfiles.contract_for("custom-dll", "custom:unknown_mod")
	check(String(custom_contract["semantics"]) == "UNKNOWN" and (custom_contract["required"] as Array).is_empty(),
		"W6 unknown custom DLL keeps UNKNOWN semantics with zero fabricated required paths")

	print("EXPORTED_W567_PLAYTEST_BZN=" + exp_bzn)
	editor.free()
	print("Waves 5, 6 & 7 Native Builders, Mission Studio & Environment Studio checks complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
