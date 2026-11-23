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
const ColorLayers := preload("res://core/color_layers.gd")
const Terrain := preload("res://formats/terrain_v5.gd")

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
	# 1. WAVE 7 + WAVE 2: Native .SKY Layout Admission & Fog Validation Matrix
	# =========================================================================
	var plgr_sky_path := plgr_bzn.get_base_dir().path_join("plgr.SKY")
	var brave_sky_path := brave_bzn.get_base_dir().path_join("braveliltoaster.SKY")
	check(FileAccess.file_exists(plgr_sky_path), "W2/7 fixture plgr.SKY must exist (no silent skip)")
	check(FileAccess.file_exists(brave_sky_path), "W2/7 fixture braveliltoaster.SKY must exist (no silent skip)")
	var plgr_sky_bytes := FileAccess.get_file_as_bytes(plgr_sky_path)
	var brave_sky_bytes := FileAccess.get_file_as_bytes(brave_sky_path)

	# 1a) Known Stock SKY & Known Brave SKY -> READABLE_SKY + KNOWN_LAYOUT + WRITABLE_SKY1 + RUNTIME_VERIFIED
	var dec_plgr := SkyEnv.decode_sky(plgr_sky_bytes)
	check(bool(dec_plgr["ok"]) and bool(dec_plgr["readable"])
		and bool(dec_plgr["knownLayout"]) and bool(dec_plgr["writableSky1"])
		and bool(dec_plgr["runtimeVerified"])
		and String(dec_plgr["capability"]) == SkyEnv.CAP_RUNTIME_VERIFIED
		and SkyEnv.is_writable(dec_plgr)
		and String(dec_plgr["layoutId"]) == SkyEnv.LAYOUT_V1_7068
		and int(dec_plgr["version"]) == 65536
		and int(dec_plgr["sizeBytes"]) == 7068
		and (dec_plgr["chunks"] as Array).size() == 13
		and String(dec_plgr["readOnly"]["domeMesh"]) == "miredome.fbx"
		and is_equal_approx(float(dec_plgr["fields"]["fogStart"]), 300.0)
		and is_equal_approx(float(dec_plgr["fields"]["fogEnd"]), 400.0),
		"W2/7 SkyEnv admits known Stock plgr.SKY (sky-v1-7068, 7068 B, 13 chunks, miredome.fbx, Fog 300..400)")

	var dec_brave := SkyEnv.decode_sky(brave_sky_bytes)
	check(bool(dec_brave["ok"]) and SkyEnv.is_writable(dec_brave)
		and String(dec_brave["layoutId"]) == SkyEnv.LAYOUT_V1_7068
		and String(dec_brave["readOnly"]["domeMesh"]) == "dunedome.fbx"
		and String(dec_brave["readOnly"]["skyTexture"]) == "white_clouds.tga"
		and is_equal_approx(float(dec_brave["fields"]["fogStart"]), 400.0)
		and is_equal_approx(float(dec_brave["fields"]["fogEnd"]), 650.0),
		"W2/7 SkyEnv admits known Brave braveliltoaster.SKY (sky-v1-7068, dunedome.fbx, Fog 400..650)")

	# 1b) No-op byte identity & surgical single-slot write verification
	var noop_sky := SkyEnv.encode_sky(plgr_sky_bytes, {})
	check(noop_sky == plgr_sky_bytes, "W2 SkyEnv no-op encode_sky({}) is 100% byte-identical")
	var single_fog_sky := SkyEnv.encode_sky(plgr_sky_bytes, {"fogStart": 225.0})
	var sky1_off := int(dec_plgr["sky1Offset"])
	var diff_offsets: Array[int] = []
	for bi in plgr_sky_bytes.size():
		if single_fog_sky.size() == plgr_sky_bytes.size() and single_fog_sky[bi] != plgr_sky_bytes[bi]:
			diff_offsets.append(bi)
	var only_fog_start_slot := not diff_offsets.is_empty()
	for doff in diff_offsets:
		if doff < sky1_off + 16 or doff >= sky1_off + 20:
			only_fog_start_slot = false
	check(single_fog_sky.size() == plgr_sky_bytes.size() and only_fog_start_slot,
		"W2 single-field fogStart write mutates ONLY bytes [%d..%d) (changed=%s)" % [sky1_off + 16, sky1_off + 20, str(diff_offsets)])

	# Helper to build synthetic chunk bytes
	var make_chunk := func(tag: String, payload: PackedByteArray) -> PackedByteArray:
		var b := tag.to_ascii_buffer()
		var sz_b := PackedByteArray()
		sz_b.resize(4)
		sz_b.encode_u32(0, payload.size())
		b.append_array(sz_b)
		b.append_array(payload)
		return b
	var hdr_bytes := plgr_sky_bytes.slice(0, 12)
	var sky1_chunk_bytes := plgr_sky_bytes.slice(12, 12 + 8 + 212)

	# 1c) Unknown SKY with valid 1YKS -> READABLE_SKY only, writer REFUSED
	var unknown_valid_sky := hdr_bytes.duplicate()
	unknown_valid_sky.append_array(sky1_chunk_bytes)
	unknown_valid_sky.append_array(make_chunk.call("XTRA", PackedByteArray([1, 2, 3, 4])))
	var dec_unk := SkyEnv.decode_sky(unknown_valid_sky)
	check(bool(dec_unk["readable"]) and not bool(dec_unk["knownLayout"]) and not bool(dec_unk["writableSky1"])
		and String(dec_unk["capability"]) == SkyEnv.CAP_READABLE_SKY
		and SkyEnv.encode_sky(unknown_valid_sky, {"fogStart": 100.0}).is_empty(),
		"W2 unknown SKY with valid 1YKS is READABLE_SKY only and refused by writer")

	# 1d) Duplicate 1YKS chunk -> rejected (unreadable & unwritable)
	var dup_sky1 := hdr_bytes.duplicate()
	dup_sky1.append_array(sky1_chunk_bytes)
	dup_sky1.append_array(sky1_chunk_bytes)
	var dec_dup_sky1 := SkyEnv.decode_sky(dup_sky1)
	check(not bool(dec_dup_sky1["readable"]) and not SkyEnv.is_writable(dec_dup_sky1)
		and SkyEnv.encode_sky(dup_sky1, {"fogStart": 100.0}).is_empty(),
		"W2 duplicate 1YKS chunk is rejected")

	# 1e) Unsupported chunk order (swap EMOD and NIAR from plgr.SKY) -> READABLE_SKY only, writer REFUSED
	var emod_off := 12 + 8 + 212
	var emod_len := 8 + 1808
	var niar_off := emod_off + emod_len
	var niar_len := 8 + 116
	var reordered_sky := plgr_sky_bytes.slice(0, emod_off)
	reordered_sky.append_array(plgr_sky_bytes.slice(niar_off, niar_off + niar_len))
	reordered_sky.append_array(plgr_sky_bytes.slice(emod_off, emod_off + emod_len))
	reordered_sky.append_array(plgr_sky_bytes.slice(niar_off + niar_len))
	var dec_reord := SkyEnv.decode_sky(reordered_sky)
	check(bool(dec_reord["readable"]) and not bool(dec_reord["knownLayout"]) and not SkyEnv.is_writable(dec_reord)
		and SkyEnv.encode_sky(reordered_sky, {"fogStart": 100.0}).is_empty(),
		"W2 unsupported chunk order (EMOD/NIAR swapped) is READABLE_SKY only and refused by writer")

	# 1f) Wrong payload sizes (both 1YKS wrong size and non-1YKS wrong size)
	var bad_sky1_sz := hdr_bytes.duplicate()
	bad_sky1_sz.append_array(make_chunk.call("1YKS", plgr_sky_bytes.slice(20, 20 + 200)))
	var dec_bad_sky1_sz := SkyEnv.decode_sky(bad_sky1_sz)
	check(not bool(dec_bad_sky1_sz["readable"]) and not SkyEnv.is_writable(dec_bad_sky1_sz),
		"W2 wrong 1YKS payload size (200 B != 212 B) is rejected")
	var bad_cvne_sz := plgr_sky_bytes.slice(0, plgr_sky_bytes.size() - 24)
	bad_cvne_sz.append_array(make_chunk.call("CVNE", PackedByteArray([0, 0, 0, 0])))
	var dec_bad_cvne := SkyEnv.decode_sky(bad_cvne_sz)
	check(bool(dec_bad_cvne["readable"]) and not bool(dec_bad_cvne["knownLayout"]) and not SkyEnv.is_writable(dec_bad_cvne)
		and SkyEnv.encode_sky(bad_cvne_sz, {"fogStart": 100.0}).is_empty(),
		"W2 wrong companion chunk payload size (CVNE 4 B != 16 B) is READABLE_SKY only and refused by writer")

	# 1g) Truncated SKY, unknown version, extra trailing data
	check(not bool(SkyEnv.decode_sky(PackedByteArray([1, 2, 3, 4]))["readable"]),
		"W2/7 SkyEnv rejects tiny/non-SKY bytes cleanly")
	check(not bool(SkyEnv.decode_sky(plgr_sky_bytes.slice(0, 500))["readable"]),
		"W2 truncated SKY is rejected")
	var bad_ver := plgr_sky_bytes.duplicate()
	bad_ver.encode_u32(8, 65537)
	check(not bool(SkyEnv.decode_sky(bad_ver)["readable"]),
		"W2 unknown SKY version (65537) is rejected")
	var trailing_sky := plgr_sky_bytes.duplicate()
	trailing_sky.append_array(PackedByteArray([0xde, 0xad, 0xbe, 0xef]))
	check(not bool(SkyEnv.decode_sky(trailing_sky)["readable"]),
		"W2 SKY with extra trailing data is rejected")

	# 1h) Duplicate non-1YKS tags -> knownLayout=false, writer REFUSED
	var dup_tag_sky := plgr_sky_bytes.duplicate()
	dup_tag_sky.append_array(make_chunk.call("CVNE", PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
	var dec_dup_tag := SkyEnv.decode_sky(dup_tag_sky)
	check(bool(dec_dup_tag["readable"]) and not bool(dec_dup_tag["knownLayout"]) and not SkyEnv.is_writable(dec_dup_tag)
		and "CVNE" in (dec_dup_tag["duplicateTags"] as Array)
		and SkyEnv.encode_sky(dup_tag_sky, {"fogStart": 100.0}).is_empty(),
		"W2 duplicate non-1YKS chunk tag (CVNE) is blocked from native write")

	# 1i) Different structurally valid layout (7044 B without CVNE, matching real dawn.sky) -> READABLE_SKY only
	var layout_7044 := plgr_sky_bytes.slice(0, plgr_sky_bytes.size() - 24)
	var dec_7044 := SkyEnv.decode_sky(layout_7044)
	check(bool(dec_7044["readable"]) and not bool(dec_7044["knownLayout"]) and not SkyEnv.is_writable(dec_7044)
		and String(dec_7044["capability"]) == SkyEnv.CAP_READABLE_SKY
		and SkyEnv.encode_sky(layout_7044, {"fogStart": 100.0}).is_empty(),
		"W2 structurally valid 7044-byte 11-chunk SKY layout stays READABLE_SKY only (writer refused)")

	# 1j) Fog Start/End relationship & range validation regressions
	var plgr_fields: Dictionary = dec_plgr["fields"] # fogStart=300, fogEnd=400
	check(not SkyEnv.validate_edits({"domeMesh": "hack.fbx"}, plgr_fields).is_empty(),
		"W7 SkyEnv refuses edits to unverified/read-only property 'domeMesh'")
	check(not SkyEnv.validate_edits({"fogStart": -50.0}, plgr_fields).is_empty(),
		"W7 SkyEnv refuses out-of-range negative fogStart")
	check(SkyEnv.validate_edits({"fogStart": 150.0, "fogEnd": 450.0}, plgr_fields).is_empty(),
		"W2 Fog validation accepts Start < End (150 < 450)")
	check(not SkyEnv.validate_edits({"fogStart": 400.0, "fogEnd": 400.0}, plgr_fields).is_empty(),
		"W2 Fog validation rejects Start == End (400 == 400)")
	check(not SkyEnv.validate_edits({"fogStart": 900.0, "fogEnd": 200.0}, plgr_fields).is_empty(),
		"W2 Fog validation rejects Start > End (900 > 200)")
	check(not SkyEnv.validate_edits({"fogStart": 400.0}, plgr_fields).is_empty(),
		"W2 Fog validation rejects only-Start edit equal to source End (400 >= 400)")
	check(not SkyEnv.validate_edits({"fogStart": 500.0}, plgr_fields).is_empty(),
		"W2 Fog validation rejects only-Start edit greater than source End (500 > 400)")
	check(not SkyEnv.validate_edits({"fogEnd": 300.0}, plgr_fields).is_empty(),
		"W2 Fog validation rejects only-End edit equal to source Start (300 <= 300)")
	check(not SkyEnv.validate_edits({"fogEnd": 200.0}, plgr_fields).is_empty(),
		"W2 Fog validation rejects only-End edit less than source Start (200 < 300)")
	check(SkyEnv.encode_sky(plgr_sky_bytes, {"fogStart": 900.0, "fogEnd": 200.0}).is_empty(),
		"W2 encode_sky refuses Start > End")
	check(SkyEnv.encode_sky(plgr_sky_bytes, {"fogStart": 450.0}).is_empty(),
		"W2 encode_sky refuses only-Start exceeding source End")
	# Native source already has unusual ordering (e.g. fogStart == fogEnd == 1000 like duel_map_27_autosave_01.SKY)
	var unusual_src_fields := plgr_fields.duplicate(true)
	unusual_src_fields["fogStart"] = 1000.0
	unusual_src_fields["fogEnd"] = 1000.0
	check(SkyEnv.validate_edits({"sunColor": [1.0, 0.8, 0.6, 1.0]}, unusual_src_fields).is_empty(),
		"W2 source with unusual fogStart==fogEnd still allows unrelated sunColor edit")
	check(not SkyEnv.validate_edits({"fogStart": 1050.0}, unusual_src_fields).is_empty(),
		"W2 source with unusual fogStart==fogEnd rejects invalid fogStart edit (1050 >= 1000)")
	check(SkyEnv.validate_edits({"fogStart": 800.0}, unusual_src_fields).is_empty(),
		"W2 source with unusual fogStart==fogEnd allows correcting fogStart < fogEnd (800 < 1000)")

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
	# Verify Object Browser lists all 13 as VERIFIED_NEW_CLASS + ENABLED on Stock with honest verification tiers
	editor.open_object_browser()
	var br_map := {}
	for e: Dictionary in editor.object_browser.catalog_entries:
		br_map[String(e["stem"])] = e
	for sp: Dictionary in all_native_specs:
		var st := String(sp["odf"])
		check(br_map.has(st) and String(br_map[st]["placement"]) == "ENABLED" and String(br_map[st]["capability"]) == "VERIFIED_NEW_CLASS"
			and String(br_map[st]["binaryMatch"]) == "BINARY_DIFF_VERIFIED"
			and String(br_map[st]["engineLoad"]) == "ENGINE_LOAD_VERIFIED"
			and not String(br_map[st]["gameplayBehavior"]).is_empty(),
			"W4/5 Object Browser exposes %s as VERIFIED_NEW_CLASS + ENABLED + ENGINE_LOAD_VERIFIED" % st)
	editor.object_browser.hide()

	# =========================================================================
	# 3. WAVE 7 + WAVE 2: Environment Studio edit, Fog Rejection, Unknown Layout, Preview, Undo/Redo, BZMAG, Export
	# =========================================================================
	editor.open_environment_studio()
	var env_dlg = editor.environment_studio
	check("Approximate Editor Preview" in env_dlg.preview_check.text,
		"W2 Environment Studio clearly labels 3D toggle as Approximate Editor Preview")
	check(not env_dlg.apply_button.disabled and env_dlg.fog_start_field.editable,
		"W7 Environment Studio enables verified 1YKS controls on map with verified writable .SKY layout")

	# 3a) Invalid Fog Start/End via Studio & Document MUST be rejected with 0 Undo entries and 0 document mutation
	var hist_before_bad: int = editor.document.undo_stack.size()
	env_dlg.fog_start_field.value = 900.0
	env_dlg.fog_end_field.value = 200.0
	env_dlg.apply_edits()
	check(not editor.document.has_environment_edits()
		and editor.document.undo_stack.size() == hist_before_bad
		and "[ERR]" in env_dlg.status_label.text,
		"W2 invalid Fog Start > End (900 > 200) refused: no edit applied, no Undo entry, error shown")
	check(not editor.document.set_environment_edits({"fogStart": 400.0})
		and editor.document.undo_stack.size() == hist_before_bad,
		"W2 only-Start == source End (400 == 400) refused without mutating document or Undo stack")
	check(not editor.document.set_environment_edits({"fogEnd": 250.0})
		and editor.document.undo_stack.size() == hist_before_bad,
		"W2 only-End < source Start (250 < 300) refused without mutating document or Undo stack")

	# 3b) Valid edit applied -> verify rejected follow-up leaves Undo/Redo intact
	env_dlg.fog_color_picker.color = Color(0.25, 0.45, 0.65, 1.0)
	env_dlg.fog_start_field.value = 180.0
	env_dlg.fog_end_field.value = 520.0
	env_dlg.vis_range_field.value = 720.0
	env_dlg.sun_angle_field.value = 14.5
	env_dlg.sun_color_picker.color = Color(0.95, 0.85, 0.70, 1.0)
	env_dlg.ambient_color_picker.color = Color(0.35, 0.40, 0.50, 1.0)
	env_dlg.apply_edits()
	var hist_after_valid: int = editor.document.undo_stack.size()
	check(editor.document.has_environment_edits()
		and hist_after_valid == hist_before_bad + 1
		and is_equal_approx(float(editor.document.effective_environment()["fogStart"]), 180.0)
		and is_equal_approx(float(editor.document.effective_environment()["fogEnd"]), 520.0),
		"W7 Environment Studio applies valid fog/sun/ambient edits to document (+1 undo step)")
	# Attempt invalid edit after valid edit: must NOT pollute Undo stack or committed values
	check(not editor.document.set_environment_edits({"fogStart": 600.0, "fogEnd": 520.0})
		and editor.document.undo_stack.size() == hist_after_valid
		and is_equal_approx(float(editor.document.effective_environment()["fogStart"]), 180.0)
		and is_equal_approx(float(editor.document.effective_environment()["fogEnd"]), 520.0),
		"W2 rejected follow-up edit preserves committed values and Undo stack")
	# 3D Approximate Editor Preview toggle: preview values MUST match exported values (zero silent clamp)
	env_dlg.preview_check.button_pressed = true
	check(editor.scene_view.env_preview_enabled
		and editor.scene_view.world_env.environment.fog_enabled
		and is_equal_approx(editor.scene_view.world_env.environment.fog_depth_begin, 180.0)
		and is_equal_approx(editor.scene_view.world_env.environment.fog_depth_end, 520.0),
		"W2/7 3D Approximate Editor Preview matches exact fogStart=180 and fogEnd=520 without silent clamp")
	# Verify unusual source ordering (fogStart == fogEnd) in preview disables fog instead of silently clamping fogEnd = fogStart + 1
	editor.scene_view.apply_environment_preview({"fogColor": [0.5, 0.5, 0.5, 1.0], "fogStart": 1000.0, "fogEnd": 1000.0}, true)
	check(not editor.scene_view.world_env.environment.fog_enabled,
		"W2 preview does not silently clamp fogStart==fogEnd into fogEnd=fogStart+1")
	editor.scene_view.apply_environment_preview(editor.document.effective_environment(), true)
	env_dlg.preview_check.button_pressed = false
	check(not editor.scene_view.env_preview_enabled and not editor.scene_view.world_env.environment.fog_enabled,
		"W7 disabling 3D environment preview cleanly restores default editor viewport")
	env_dlg.hide()

	# Undo / Redo on .SKY edits (after rejected edit)
	editor.document.undo()
	check(not editor.document.has_environment_edits(), "W2/7 Undo after rejected edit restores original .SKY values")
	editor.document.redo()
	check(editor.document.has_environment_edits()
		and is_equal_approx(float(editor.document.effective_environment()["fogStart"]), 180.0)
		and is_equal_approx(float(editor.document.effective_environment()["fogEnd"]), 520.0),
		"W2/7 Redo after rejected edit reapplies exact .SKY edits")

	# 3c) Unknown-layout .SKY map: opens cleanly, terrain edits still allowed, read-only inspector shown, writer disabled!
	var unk_sky_dir := scratch.path_join("w2-unknown-sky-map")
	check(writer.create_native_flat_map(plgr_bzn, unk_sky_dir, 512, 100.0, "", {
		"mod_profile": "stock", "mission_profile": "blank", "configure_mission": false, "sync_mission_dll": true, "sanitize_stock_objects": true,
	}), "W2 stage scratch map for unknown SKY layout check")
	var unk_sky_file := unk_sky_dir.path_join("plgr.SKY")
	var wf := FileAccess.open(unk_sky_file, FileAccess.WRITE)
	if wf != null:
		wf.store_buffer(unknown_valid_sky)
		wf.close()
	var unk_doc := Document.new()
	check(unk_doc.open(unk_sky_dir.path_join(plgr_bzn.get_file())),
		"W2 map with unknown-layout .SKY still opens cleanly")
	check(unk_doc.has_readable_environment() and not unk_doc.can_edit_environment(),
		"W2 unknown-layout .SKY map exposes read-only environment without write admission")
	check(not unk_doc.set_environment_edits({"fogStart": 100.0}),
		"W2 MapDocument refuses environment edits on unknown-layout .SKY")
	# Generic terrain sculpting MUST still work on map with unknown .SKY!
	unk_doc.begin_stroke()
	unk_doc.dab(Vector2(64, 64), 24.0, 8.0)
	unk_doc.end_stroke()
	check(not unk_doc.edits.is_empty(), "W2 generic terrain sculpting remains enabled on map with unknown .SKY")
	var unk_exp := scratch.path_join("w2-unknown-sky-export")
	check(writer.export_native(unk_doc, unk_exp) and FileAccess.get_file_as_bytes(unk_exp.path_join("plgr.SKY")) == unknown_valid_sky,
		"W2 terrain export on unknown-layout .SKY map preserves .SKY bytes untouched")
	var prev_doc: Document = editor.document
	editor.environment_studio.begin(unk_doc, false)
	check(editor.environment_studio.apply_button.disabled
		and not editor.environment_studio.fog_start_field.editable
		and "READABLE_SKY" in editor.environment_studio.header_label.text
		and "XTRA" in editor.environment_studio.inspector_text.text,
		"W2 Environment Studio locks writer controls and displays read-only chunk inspector for unknown .SKY")
	editor.environment_studio.hide()
	editor.environment_studio.document = prev_doc

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
		and SkyEnv.is_writable(verify_pkg.sky_env)
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


	# T-47: deterministic Color Layer playtest fixture. One sparse RGB sample is
	# composed over native source RGB and exported without Bake. The game stage
	# must launch THIS map and verify the exact expected RGB bytes.
	var color_doc := Document.new()
	check(color_doc.open(exp_bzn), "T-47 open exported Stock map for color fixture")
	check(color_doc.add_color_layer() == 0, "T-47 add one color layer")
	var color_terrain: Terrain = color_doc.package.terrain
	var fixture_index := 200 * color_terrain.dimensions.x + 200
	var fixture_source := color_terrain.source_material_value(Terrain.Layer.COLOR, fixture_index)
	var fixture_layer: Dictionary = color_doc.color_layers[0]
	fixture_layer["name"] = "Playtest Red"
	fixture_layer["samples"] = {fixture_index: {"rgb": 0xff0000, "coverage": 1.0}}
	fixture_layer["opacity"] = 0.5
	var fixture_rgb := ColorLayers.blend_word(fixture_source, 0xff0000, 0.5)
	var color_dir := scratch.path_join("color-layer-playtest")
	check(writer.export_native(color_doc, color_dir), "T-47 export Color Layer fixture: " + writer.error)
	var color_bzn := color_dir.path_join(color_doc.package.source_path.get_file())
	var color_verify := Package.new()
	check(color_verify.open(color_bzn), "T-47 reimport Color Layer fixture")
	check(color_verify.terrain.material_value(Terrain.Layer.COLOR, fixture_index) == fixture_rgb,
		"T-47 exported native TER contains composed RGB without Bake")
	check(color_doc.package.terrain.color_edits.is_empty(),
		"T-47 color fixture did not mutate committed native RGB")
	print("EXPORTED_COLOR_LAYER_BZN=" + color_bzn)
	print("COLOR_LAYER_EXPECTED_RGB=" + ("%06X" % fixture_rgb))
	print("COLOR_LAYER_SAMPLE_INDEX=%d" % fixture_index)
	print("EXPORTED_W567_PLAYTEST_BZN=" + exp_bzn)
	editor.free()
	print("Waves 5, 6 & 7 Native Builders, Mission Studio & Environment Studio checks complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
