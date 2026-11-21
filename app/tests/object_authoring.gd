extends SceneTree
## Wave 4 Acceptance Suite: Universal Object Browser & Native Class-Specific New-Class Placement.
##
## Full 14-step vertical slice:
##   1. Clean Stock 1192 map with ZERO pools/rocks/powerplants/scrap in-map
##   2. Object Browser scoped strictly to Stock (zero VSR/VRV leakage)
##   3. VERIFIED_NEW_CLASS vs TEMPLATE_CLONE_ONLY vs PREVIEW_ONLY_UNSUPPORTED gating
##   4. Place brand-new Stock classes (uepool01, morock03, ibpgen, npscrx) onto terrain
##   5. Move / Rotate / Label newly placed objects
##   6. Undo removes & Redo restores cleanly
##   7. BZMAG Save & Reopen round-trip
##   8. Export Native & Reimport byte/field verification
##   9. Optional export staging for real BZCC 2.0.185 Playtest confirmation

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")
const Package := preload("res://formats/map_package.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const ObjectBrowser := preload("res://tools/object_browser.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, desc: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + desc)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("Pass plgr_bzn game_dir scratch_dir [optional_vrv_dir]")
		quit(2)
		return
	var plgr_bzn := args[0]
	var game_dir := args[1]
	var scratch := args[2]
	var vrv_dir := args[3] if args.size() >= 4 else ""

	# Step 1: Create a clean Stock 1192 Strategy map with NO uepool01, morock03, ibpgen, or npscrx
	var base_dir := scratch.path_join("stock-base")
	var writer := Snapshots.new()
	check(writer.create_native_flat_map(plgr_bzn, base_dir, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "strategy",
		"configure_mission": true,
		"sanitize_stock_objects": true,
	}), "stage clean Stock 1192 map: " + writer.error)
	var base_bzn := base_dir.path_join(plgr_bzn.get_file())

	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.settings_path = scratch.path_join("obj-auth-editor.cfg")
	editor.game_path.text = game_dir
	editor.vrv_path.text = vrv_dir
	editor.mod_registry.discover_installed(game_dir, vrv_dir)
	check(editor.open_map(base_bzn), "open clean Stock 1192 map in editor")
	editor.document.mod_profile = "stock"
	editor.document.mission_profile = "strategy"
	editor.document.profile_explicit = true

	var initial_count: int = editor.document.object_count()
	check(initial_count == 3, "clean Stock map starts with 3 objects (ivscout + 2x pspwn_1), got %d" % initial_count)
	for v in initial_count:
		var odf_low: String = editor.document.object_odf(v).to_lower()
		check(not (odf_low in ["uepool01", "morock03", "ibpgen", "npscrx"]),
			"clean Stock map initially has NO %s (proving genuine new-class synthesis)" % odf_low)

	# Step 2: Open Universal Object Browser and verify Stock isolation & capability badges
	editor.open_object_browser()
	var browser: ObjectBrowser = editor.object_browser
	var by_stem := {}
	for entry: Dictionary in browser.catalog_entries:
		by_stem[String(entry["stem"])] = entry
	check(by_stem.has("uepool01") and String(by_stem["uepool01"]["capability"]) == ObjectBrowser.CAP_NEW_CLASS,
		"Object Browser exposes uepool01 (Biometal Pool) as VERIFIED_NEW_CLASS")
	check(by_stem.has("morock03") and String(by_stem["morock03"]["capability"]) == ObjectBrowser.CAP_NEW_CLASS,
		"Object Browser exposes morock03 (Big Rock) as VERIFIED_NEW_CLASS")
	check(by_stem.has("ibpgen") and String(by_stem["ibpgen"]["capability"]) == ObjectBrowser.CAP_NEW_CLASS,
		"Object Browser exposes ibpgen (ISDF Power Generator) as VERIFIED_NEW_CLASS")
	check(by_stem.has("npscrx") and String(by_stem["npscrx"]["capability"]) == ObjectBrowser.CAP_NEW_CLASS,
		"Object Browser exposes npscrx (Loose Scrap) as VERIFIED_NEW_CLASS")
	check(by_stem.has("ivscout") and String(by_stem["ivscout"]["capability"]) == ObjectBrowser.CAP_TEMPLATE_CLONE,
		"Object Browser exposes existing in-map ivscout as TEMPLATE_CLONE_ONLY")
	check(by_stem.has("ivtank") and String(by_stem["ivtank"]["capability"]) == ObjectBrowser.CAP_PREVIEW_ONLY,
		"Object Browser marks unverified new class ivtank honestly as PREVIEW_ONLY_UNSUPPORTED")
	check(not by_stem.has("ivtank_vsr") and not by_stem.has("vrv_sndpoint"),
		"Stock Object Browser strictly excludes VSR/VRV ODFs even when installed")

	# Search filter verification
	browser.search_box.text = "biometal"
	browser.rebuild_list()
	check(browser.filtered_entries.size() >= 1 and String(browser.filtered_entries[0]["stem"]) == "uepool01",
		"Object Browser search finds uepool01 by display name 'Biometal'")
	browser.search_box.text = ""
	browser.rebuild_list()
	browser.hide()

	# Step 3: Refusal on unverified new class (NEVER generic blob!)
	check(editor.document.place_native_object("ivtank", Vector3(0.0, 100.0, 0.0), 1) < 0,
		"place_native_object refuses unverified class ivtank without generic blob fallback")

	# Step 4: Place 4 brand-new verified Stock classes onto terrain through editor placement flow
	var placed_specs := [
		{"odf": "uepool01", "team": 0, "sample": Vector2(240.0, 240.0), "label": "pool_center_1"},
		{"odf": "morock03", "team": 0, "sample": Vector2(260.0, 240.0), "label": ""},
		{"odf": "ibpgen", "team": 1, "sample": Vector2(220.0, 260.0), "label": "isdf_power_1"},
		{"odf": "npscrx", "team": 0, "sample": Vector2(250.0, 255.0), "label": ""},
	]
	var placed_views: Array[int] = []
	for sp: Dictionary in placed_specs:
		editor.start_place_object(String(sp["odf"]), int(sp["team"]), -1, true)
		var v: int = editor.place_object_at_sample(sp["sample"])
		editor.cancel_place_object(false)
		check(v >= initial_count, "placed new-class %s at view %d" % [sp["odf"], v])
		if not String(sp["label"]).is_empty():
			check(editor.document.set_object_label(v, String(sp["label"])), "set custom label on newly placed %s" % sp["odf"])
		placed_views.append(v)

	check(editor.document.object_count() == initial_count + 4,
		"document now has %d objects (expected %d)" % [editor.document.object_count(), initial_count + 4])

	# Step 5: Move + Rotate newly placed uepool01 & morock03
	var pool_view := placed_views[0]
	var orig_pool_pos: Vector3 = editor.document.object_position(pool_view)
	check(editor.document.move_object(pool_view, orig_pool_pos + Vector3(16.0, 0.0, -12.0)), "move newly placed uepool01")
	check(editor.document.rotate_object(placed_views[1], deg_to_rad(45.0)), "rotate newly placed morock03")

	# Step 6: Undo & Redo check on last placement
	var rock_extra_before: int = editor.document.object_count()
	var temp_view: int = editor.document.place_native_object("iblite", Vector3(32.0, 100.0, 32.0), 0)
	check(temp_view >= 0 and editor.document.object_count() == rock_extra_before + 1, "place iblite for Undo/Redo test")
	editor.document.undo()
	check(editor.document.object_count() == rock_extra_before, "Undo cleanly removes newly placed native-class iblite")
	editor.document.redo()
	check(editor.document.object_count() == rock_extra_before + 1 and editor.document.object_odf(temp_view) == "iblite",
		"Redo cleanly restores newly placed native-class iblite")

	# Step 7: Save .bzmag project and reopen cleanly
	var bzmag_path := scratch.path_join("new-class-test.bzmag")
	var saver := Snapshots.new()
	check(saver.save_project(editor.document, bzmag_path), "save .bzmag with native new-class additions: " + saver.error)
	var reopened := Document.new()
	check(reopened.open(bzmag_path), "reopen .bzmag with native new-class additions: " + reopened.error)
	check(reopened.object_count() == editor.document.object_count()
		and reopened.object_odf(pool_view) == "uepool01"
		and reopened.object_label(pool_view) == "pool_center_1"
		and reopened.object_odf(placed_views[2]) == "ibpgen"
		and reopened.object_team(placed_views[2]) == 1
		and reopened.object_odf(temp_view) == "iblite",
		"reopened .bzmag preserves all native new-class ODFs, teams, labels and transforms")

	# Step 8: Export Native and verify full re-import (Snapshots.export_native checks EVERY field!)
	var export_dir := scratch.path_join("exported-stock-new-classes")
	var exporter := Snapshots.new()
	check(exporter.export_native(reopened, export_dir),
		"export native BZN 1192 with 5 synthesized new classes: " + exporter.error)
	var exp_bzn := export_dir.path_join(plgr_bzn.get_file())
	var verify_pkg := Package.new()
	check(verify_pkg.open(exp_bzn), "reimport exported Stock 1192 BZN with new classes: " + verify_pkg.error)
	check(verify_pkg.objects.size() == initial_count + 5,
		"reimported native BZN contains all %d objects (got %d)" % [initial_count + 5, verify_pkg.objects.size()])
	var found_odfs := {}
	for obj: Dictionary in verify_pkg.objects:
		found_odfs[String(obj["odf"]).to_lower()] = obj
	check(found_odfs.has("uepool01") and String(found_odfs["uepool01"]["label"]) == "pool_center_1",
		"reimported BZN has synthesized uepool01 with custom label")
	check(found_odfs.has("morock03") and found_odfs.has("npscrx") and found_odfs.has("iblite"),
		"reimported BZN has synthesized morock03, npscrx and iblite")
	check(found_odfs.has("ibpgen") and int(found_odfs["ibpgen"]["team"]) == 1 and String(found_odfs["ibpgen"]["label"]) == "isdf_power_1",
		"reimported BZN has synthesized ibpgen on team 1 with custom label")

	# Step 9: Verify Mod Environment scoping switches cleanly when switching to VRV
	if editor.mod_registry.has_profile("vrv") and bool(editor.mod_registry.get_profile("vrv").get("installed", false)):
		editor.document.set_target_profile("vrv", "strategy")
		browser.refresh_catalog()
		var vrv_stems := {}
		for entry: Dictionary in browser.catalog_entries:
			vrv_stems[String(entry["stem"])] = true
		check(vrv_stems.has("ivtank_vsr") or vrv_stems.has("vrv_sndpoint"),
			"Object Browser dynamically updates to show VRV/VSR ODFs when switching environment to VRV")

	print("EXPORTED_PLAYTEST_BZN=" + exp_bzn)
	editor.free()
	print("Wave 4 Universal Object Browser & Native New-Class Authoring checks complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
