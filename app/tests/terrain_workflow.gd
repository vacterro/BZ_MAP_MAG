extends SceneTree

const EditorScene := preload("res://editor.tscn")
const Terrain := preload("res://formats/terrain_v5.gd")
const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Graph := preload("res://nodes/height_graph.gd")
const Water := preload("res://formats/water_v5.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const BznPaths := preload("res://formats/bzn_paths.gd")
const AutoSaveStore := preload("res://core/autosave_store.gd")
const Shapes := preload("res://core/slope_shapes.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const TerrainView := preload("res://render/terrain_view.gd")
const Package := preload("res://formats/map_package.gd")
const VrvShapes := preload("res://core/vrv_shapes.gd")
const Wintage := preload("res://themes/wintage.gd")
const NativeAssets := preload("res://formats/native_assets.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Pass Brave BZN, blank BZN, and an existing fresh scratch directory.")
		quit(2)
		return
	var writer := Snapshots.new()
	var document := Document.new()
	var timer := Time.get_ticks_usec()
	if not document.open(args[0]):
		printerr(document.error)
		quit(1)
		return
	print("Brave load and validate: %.1f ms" % ((Time.get_ticks_usec() - timer) / 1000.0))
	var terrain := document.package.terrain
	check(terrain.dimensions == Vector2i(1024, 1024) and terrain.origin == Vector2i(-512, -512), "Brave measured TER bounds")
	check(document.package.bzn_version == 1196 and is_equal_approx(document.package.granularity, 0.1), "native metadata")
	check(document.package.paths.size() == 23 and document.package.paths[0]["name"] == "edge_path" and document.package.paths[0]["points"].size() == 13, "Brave path evidence agrees with BZNTools")
	check(document.package.objects.size() == 76, "Brave native object count agrees with BZNTools")
	check(document.package.water != null and document.package.water.first_height == 135.0 and document.package.water.first_tiles.size() == 222, "Brave native water layer and tile mask")
	test_water_layers(document)
	if not document.package.objects.is_empty():
		check(document.package.objects[0]["odf"] == "ivscout_vsr", "first native object ODF")
	check(terrain.heights[0] == 174.90199951171875 or is_equal_approx(terrain.heights[0], 174.90201), "first native height sample")
	var blank := Document.new()
	check(not blank.open(args[1]) and blank.package.bzn_version == 1192 and blank.error.begins_with("No TER"), "blank map missing TER diagnostic")
	check(blank.package.paths.size() == 23 and blank.package.paths[0]["points"].size() == 2, "blank BZN path table available independently of terrain")
	check(blank.package.objects.size() == 1, "blank BZN contains one native craft")
	var bad := Terrain.new()
	check(not bad.decode(terrain.original.slice(0, -1)), "reject truncated TER")
	var wrong_version := terrain.original.duplicate()
	wrong_version.encode_u32(4, 7)
	check(not bad.decode(wrong_version), "reject unsupported TER profile")
	var invalid_height := terrain.original.duplicate()
	invalid_height.encode_float(17, NAN)
	check(not bad.decode(invalid_height), "reject non-finite TER sample")
	var invalid_bounds := terrain.original.duplicate()
	invalid_bounds.encode_s16(12, 32767)
	check(not bad.decode(invalid_bounds), "reject invalid TER dimensions")
	check(writer.export_native(document, args[2].path_join("noop")), writer.error)
	var noop := Document.new()
	check(noop.open(args[2].path_join("noop").path_join(args[0].get_file())) and noop.package.files == document.package.files, "no-op package identity")
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	if OS.get_name() == "Windows":
		check(editor.theme.default_font.get_font_name().begins_with("Verdana"), "main UI loads embedded Verdana_m1: " + editor.theme.default_font.get_font_name())
		check(editor.studio.theme.default_font.get_font_name().begins_with("Verdana"), "node window uses embedded Verdana_m1")
		check(editor.open_dialog.theme.default_font.get_font_name().begins_with("Verdana"), "dialogs use embedded Verdana_m1")
		check(FileAccess.file_exists("res://themes/fonts/Verdana_m1.ttf") and FileAccess.file_exists("res://themes/fonts/Verdana_m1-Bold.ttf"), "embedded Verdana_m1 font files exist in project")
		check(editor.game_picker.use_native_dialog and editor.vrv_picker.use_native_dialog and editor.game_picker.file_mode == FileDialog.FILE_MODE_OPEN_DIR, "native folder pickers in Playtest Setup")
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1120, 690) if DisplayServer.get_name() == "headless" else Vector2(root.size)
	timer = Time.get_ticks_usec()
	check(editor.open_map(args[0]), "open native package in application")
	print("Open plus two views: %.1f ms" % ((Time.get_ticks_usec() - timer) / 1000.0))
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[2].path_join("editor.png")) == OK, "rendered editor capture")
	var screen_sample: Vector2 = editor.top.sample_at(editor.top.view_rect().get_center())
	check(screen_sample.distance_to(Vector2(512, 512)) < 0.1, "top view center reads document grid")
	var view_sample: Vector2 = editor.scene_view.sample_at(editor.scene_view.size * 0.5)
	check(view_sample.distance_to(Vector2(512, 512)) < 2.0, "3D central ray reads document grid: %s, container %s, viewport %s" % [view_sample, editor.scene_view.size, editor.scene_view.viewport.size])
	test_brush_controls(editor)
	editor.select_path(1)
	check(editor.top.path_overlay["name"] == "edge_path" and editor.scene_view.path_mesh.visible, "2D and 3D selected path overlays")
	editor.select_path(0)
	document = editor.document
	terrain = document.package.terrain
	var press := InputEventMouseButton.new()
	press.position = editor.scene_view.size * 0.5
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	editor.view_input(press, editor.scene_view)
	press.pressed = false
	editor.view_input(press, editor.scene_view)
	check(not document.edits.is_empty(), "3D viewport stroke input changes canonical terrain")
	document.undo()
	editor._process(0)
	check(document.edits.is_empty(), "undo 3D viewport stroke")
	var center := 512 * terrain.dimensions.x + 512
	var baseline := terrain.heights[center]
	var mesh: MeshInstance3D = editor.scene_view.meshes[Vector2i(512, 512)]
	var old_mesh := mesh.mesh
	var remote_mesh: MeshInstance3D = editor.scene_view.meshes[Vector2i.ZERO]
	var old_remote := remote_mesh.mesh
	var texture: Texture2D = editor.top.tiles[Vector2i(512, 512)]
	if DisplayServer.get_name() != "headless":
		check(texture.get_image() != null, "GPU elevation texture contains raster data")
	timer = Time.get_ticks_usec()
	document.begin_stroke()
	document.dab(Vector2(512, 512), 48, 24)
	document.end_stroke()
	editor._process(0)
	print("Brush plus dirty view updates: %.1f ms" % ((Time.get_ticks_usec() - timer) / 1000.0))
	check(terrain.heights[center] > baseline + 23.9, "raise native sample")
	check(mesh.mesh != old_mesh and remote_mesh.mesh == old_remote, "only nearby 3D chunks rebuilt")
	check(editor.top.tiles[Vector2i(512, 512)] == texture, "2D chunk texture updated in place")
	var intended := terrain.heights[center]
	document.undo()
	check(document.edits.is_empty() and terrain.encode(document.edits) == terrain.original, "undo recovers exact original binary")
	document.redo()
	check(terrain.heights[center] == intended, "redo recovers edited sample")
	var saved := args[2].path_join("project.bzmag")
	check(writer.save_project(document, saved), writer.error)
	check(not writer.save_project(document, saved), "project collision refused")
	var reopened := Document.new()
	check(reopened.open(saved) and reopened.edits == document.edits, "reopen saved project")
	var target := args[2].path_join("terrain-edit")
	timer = Time.get_ticks_usec()
	check(writer.export_native(document, target), writer.error)
	print("Edited export with reimport: %.1f ms" % ((Time.get_ticks_usec() - timer) / 1000.0))
	check(not writer.export_native(document, target), "export collision refused")
	check(document.package.check_sources(), "source package preserved")
	var edited := Document.new()
	check(edited.open(target.path_join(args[0].get_file())) and edited.package.terrain.heights[center] == intended, "edited TER reopens at intended height")
	edited.begin_stroke()
	edited.dab(Vector2(512, 512), 32, 80, Document.Brush.FLATTEN)
	edited.end_stroke()
	check(edited.package.terrain.heights[center] == 80, "flatten targets the requested physical height")
	edited.begin_stroke()
	edited.dab(Vector2(512, 512), 32, 100, Document.Brush.SMOOTH)
	edited.end_stroke()
	check(edited.package.terrain.heights[center] > 80, "smooth blends the center with nearby samples")
	edited.undo()
	edited.undo()
	for name: String in document.package.files:
		if name != document.package.terrain_name:
			check(document.package.files[name] == edited.package.files.get(name), "unchanged companion " + name)
	var stale := Document.new()
	var copied_bzn := args[2].path_join("noop").path_join(args[0].get_file())
	check(stale.open(copied_bzn), "open external modification fixture")
	var change := FileAccess.open(copied_bzn, FileAccess.READ_WRITE)
	change.seek_end()
	change.store_8(65)
	change.close()
	check(not writer.export_native(stale, args[2].path_join("stale")), "refuse export over changed source revisions")
	test_path_edit(editor, args[2])
	test_path_lifecycle(editor, args[2])
	test_asset_profile(editor, args[2])
	test_material_paint(editor, args[2])
	test_graph(editor, edited, writer, args[2])
	await test_studio(editor)
	test_shape_tools(editor, args[2])
	await test_graph_materials(editor, args[0], args[2])
	await test_object_move(editor, args[0], args[2])
	await test_object_tools(editor, args[0], args[2])
	await test_water_tools(editor, args[0], args[2])
	test_slope_studio(editor, args[0], args[2])
	test_slope_studio_safety(editor)
	test_large_slope_preview()
	await test_adaptive_terrain_lod()
	await test_fly_autosave_symmetry(editor, args[0], args[2])
	test_mission_studio(editor, args[0], args[2])
	test_universal_mod_architecture(editor, args[0], args[1], args[2])
	test_batch_path_collisions(editor, args[0], args[2])
	test_empty_object_table(args[0], args[1], args[2])
	test_sound_point_labels(editor)
	test_vrv_parity_wave7(editor, args[0], args[2])
	await test_hold_ui_font_playtest(editor, args[0], args[1], args[2])
	print("Native height at (0,0): %.4f -> %.4f, changed samples: %d" % [baseline, intended, document.edits.size()])
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func test_path_edit(editor: Control, scratch: String) -> void:
	var document: Document = editor.document
	var package := document.package
	var first := document.path_at(1)
	editor.path_list.select(2)
	editor.select_path(2)
	editor.move_path_button.set_pressed_no_signal(true)
	var pixel: Vector2 = editor.top.path_point_pixel(first["points"][0])
	editor.start_point_drag(editor.top, pixel, false)
	editor.preview_path_point(editor.top.sample_at(pixel + Vector2(5, 3)))
	editor.finish_point_drag(true)
	check(document.path_at(1)["points"][0] != first["points"][0], "dragging a 2D path marker commits world coordinates")
	document.undo()
	editor.move_path_button.set_pressed_no_signal(false)
	editor.inspect_path()
	var inspector = editor.path_inspector
	check(inspector.list.item_count == first["points"].size(), "inspector opens a native route")
	inspector.path_name.text = "11Patrol1 Draft"
	inspector.position_x.value += 1.25
	inspector.apply_path()
	check(document.path_at(1)["name"] == "11Patrol1 Draft" and inspector.visible == false, "inspector commits a native edit")
	check(editor.top.path_overlay["name"] == "11Patrol1 Draft", "path edit updates the 2D and 3D overlay")
	document.undo()
	check(document.path_edits.is_empty(), "undo restores original path bytes")
	document.redo()
	check(document.path_at(1)["points"][0].x != first["points"][0].x, "redo restores updated coordinate")
	document.undo()
	var altered: PackedVector2Array = first["points"].duplicate()
	check(not document.edit_path(1, document.path_at(0)["name"], altered, 0), "duplicate native path labels rejected")
	altered.insert(1, (altered[0] + altered[1]) * 0.5)
	check(document.edit_path(1, first["name"], altered, 2), "insert and close a native route")
	var bridge := Snapshots.new()
	var target := scratch.path_join("path-edit")
	check(bridge.export_native(document, target), bridge.error)
	var project := scratch.path_join("path-edit.bzmag")
	check(bridge.save_project(document, project), bridge.error)
	var restored := Document.new()
	check(restored.open(project) and restored.path_edits == document.path_edits, "project restores authored path")
	var exported := Document.new()
	var bzn := target.path_join(package.bzn_name)
	if not exported.open(bzn):
		check(false, exported.error)
		return
	check(Document.same_path_fields(document.path_at(1), exported.path_at(1)), "exported point count, coordinates, type and ID")
	var before := FileAccess.get_file_as_bytes(package.source_path)
	var after := FileAccess.get_file_as_bytes(bzn)
	var before_route := package.paths[1]
	var after_route := exported.package.paths[1]
	check(after.slice(0, before_route["point_start"]) == before.slice(0, before_route["point_start"]), "byte preservation before edited route points")
	check(after.slice(after_route["end"]) == before.slice(before_route["end"]), "byte preservation after edited route")
	document.undo()
	check(document.path_edits.is_empty(), "native path undo can be exported byte-identically")


func test_path_lifecycle(editor: Control, scratch: String) -> void:
	var document: Document = editor.document
	var original_count := document.package.paths.size()
	var source := FileAccess.get_file_as_bytes(document.package.source_path)
	var codec := document.package.path_codec
	editor.new_path_button.pressed.emit()
	editor.path_inspector.path_name.text = "Audit Route"
	editor.path_inspector.apply_path()
	var added := document.path_at(original_count)
	if added.is_empty():
		check(false, "create a whole path through the inspector: " + document.error)
		return
	check(added["name"] == "Audit Route" and not codec.pointer_counts(source).has(added["id"]), "new path uses a fresh serialized handle")
	check(editor.top.path_overlay["id"] == added["id"], "new path is selected in the editor")
	document.undo()
	check(document.path_at(original_count).is_empty(), "undo whole path creation")
	document.redo()
	check(Document.same_path_fields(document.path_at(original_count), added), "redo restores the same native ID")
	check(not document.remove_path(0) and document.error.contains("edge_path"), "reject removal of the map boundary path")
	var writer := Snapshots.new()
	var added_folder := scratch.path_join("added-path")
	check(writer.export_native(document, added_folder), writer.error)
	var added_path := added_folder.path_join(document.package.bzn_name)
	var added_bytes := FileAccess.get_file_as_bytes(added_path)
	check(added_bytes.size() > codec.table_end and added_bytes.decode_s32(codec.table_start - 4) == original_count + 1, "native path count increases")
	var removed := document.path_at(1)
	var sidecar := FileAccess.open(added_path.get_basename() + ".lua", FileAccess.WRITE)
	if sidecar != null:
		sidecar.store_line("local patrol = '%s'" % removed["name"])
		sidecar.close()
		var referenced := Document.new()
		check(referenced.open(added_path) and not referenced.remove_path(1) and referenced.error.contains(".lua"), "known Lua path reference prevents removal")
	else:
		check(false, "write the path-reference test sidecar")
	editor.path_list.select(2)
	editor.inspect_path()
	editor.path_inspector.delete_path_button.pressed.emit()
	check(not editor.path_inspector.visible, "remove a whole path through the inspector: " + document.error)
	check(document.path_at(1).is_empty() and document.path_at(2)["id"] == document.package.paths[2]["id"], "removal leaves other slots and IDs stable")
	document.undo()
	check(Document.same_path_fields(document.path_at(1), removed), "undo restores the removed path")
	document.redo()
	var project := scratch.path_join("path-lifecycle.bzmag")
	check(writer.save_project(document, project), writer.error)
	var restored := Document.new()
	check(restored.open(project) and restored.path_edits == document.path_edits, "save/reopen preserves the inserted path and removal")
	var folder := scratch.path_join("path-lifecycle")
	check(writer.export_native(document, folder), writer.error)
	var native := Document.new()
	var native_path := folder.path_join(document.package.bzn_name)
	if native.open(native_path):
		var bytes := FileAccess.get_file_as_bytes(native_path)
		check(native.package.paths.size() == original_count and native.package.paths.back()["id"] == added["id"], "new path reopens after removing an earlier record")
		check(bytes.slice(0, codec.table_start) == source.slice(0, codec.table_start), "object and mission prefix stays byte-identical")
		check(bytes.slice(native.package.path_codec.table_end) == source.slice(codec.table_end), "native trailer survives the table resize")
	else:
		check(false, "reopen the resized path table: " + native.error)
	document.undo()
	document.undo()
	check(document.path_edits.is_empty(), "undo restores the original table")


func test_asset_profile(editor: Control, scratch: String) -> void:
	var writer := Snapshots.new()
	var profile := scratch.path_join("assets.json")
	check(writer.write_bytes(profile, '{"folders": []}'.to_utf8_buffer()), "write a linked asset profile")
	var game := scratch.path_join("mock-game")
	DirAccess.make_dir_recursive_absolute(game.path_join("bz2r_res"))
	check(writer.write_bytes(game.path_join("battlezone2.exe"), PackedByteArray([0])), "write a launcher settings fixture")
	editor.settings_path = scratch.path_join("editor.cfg")
	editor.game_path.text = game
	editor.vrv_path.clear()
	editor.asset_profile_path.text = profile
	editor.save_playtest_setup()
	check(editor.document.asset_profile == profile and editor.has_unsaved_changes(), "Playtest Setup links the profile to this project")
	var project := scratch.path_join("linked-profile.bzmag")
	check(writer.save_project(editor.document, project), writer.error)
	var restored := Document.new()
	check(restored.open(project) and restored.asset_profile == profile, "project reload preserves its external profile link")
	editor.asset_profile_path.clear()
	editor.save_playtest_setup()
	check(editor.document.asset_profile.is_empty(), "clearing Setup removes the profile link")


func test_water_layers(document: Document) -> void:
	var package := document.package
	var wat := package.source_path.get_basename() + ".WAT"
	var bytes := FileAccess.get_file_as_bytes(wat)
	var tile := int(package.water.first_tiles[0].y) * package.water.width + int(package.water.first_tiles[0].x)
	bytes[Water.MASK_START + tile] |= 2
	bytes.encode_float(Water.LAYER_START + Water.LAYER_SIZE, 162.5)
	var water := Water.new()
	check(water.decode(bytes, package.terrain) and water.layers.size() == 2, "water masks may overlap at one block")
	if water.layers.size() == 2:
		check(water.layers[1]["height"] == 162.5 and water.layers[1]["tiles"].has(package.water.first_tiles[0]), "second water height and location")
	bytes.encode_float(Water.LAYER_START + Water.LAYER_SIZE, INF)
	check(water.decode(bytes, package.terrain) and water.layers.size() == 1 and water.invalid_layer_flags == 2, "skip a nonfinite active layer and retain valid water")
	check(not water.decode(bytes.slice(0, -1), package.terrain), "reject a truncated water mask")


func test_material_paint(editor: Control, scratch: String) -> void:
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var baseline := Terrain.new()
	if not baseline.decode(terrain.encode(doc.edits)):
		check(false, "decode the pre-paint material baseline")
		return
	var center := terrain.dimensions / 2
	var sample := center.y * terrain.dimensions.x + center.x
	var block := terrain.block_at(center)
	var before_color := terrain.material_value(Terrain.Layer.COLOR, sample)
	var before_tiles := terrain.material_value(Terrain.Layer.TILES, block)
	var brush = editor.brush_panel
	brush.set_pressure(100)
	brush.set_shape(Document.BrushShape.CIRCLE)
	brush.surface.select(1)
	brush.update_buttons()
	brush.rgb.text = "#1537B3"
	dab_main_view(editor)
	check(terrain.material_value(Terrain.Layer.COLOR, sample) == 0x1537b3 and editor.top.preview_layer == Terrain.Layer.COLOR and editor.scene_view.use_vertex_colors, "RGB brush and both native color previews")
	doc.undo()
	check(terrain.material_value(Terrain.Layer.COLOR, sample) == before_color and terrain.color_edits.is_empty(), "undo restores native vertex colors")
	doc.redo()
	brush.surface.select(2)
	brush.update_buttons()
	brush.texture_lane.value = 2
	var slot := (((before_tiles >> 8) & 15) + 1) & 15
	brush.texture_slot.value = slot
	dab_main_view(editor)
	var expected := (before_tiles & ~(15 << 8)) | (slot << 8)
	check(terrain.material_value(Terrain.Layer.TILES, block) == expected and editor.top.preview_layer == Terrain.Layer.TILES, "tile brush updates only the selected slot lane")
	doc.undo()
	check(terrain.material_value(Terrain.Layer.TILES, block) == before_tiles and terrain.tile_edits.is_empty(), "undo restores native tile IDs")
	doc.redo()
	var writer := Snapshots.new()
	var project := scratch.path_join("terrain-materials.bzmag")
	check(writer.save_project(doc, project), writer.error)
	var restored := Document.new()
	check(restored.open(project) and restored.package.terrain.color_edits == terrain.color_edits and restored.package.terrain.tile_edits == terrain.tile_edits, "project stores both native paint channels")
	var target := scratch.path_join("terrain-materials")
	check(writer.export_native(doc, target), writer.error)
	var exported := Document.new()
	if exported.open(target.path_join(doc.package.bzn_name)):
		var result := exported.package.terrain
		check(result.material_value(Terrain.Layer.COLOR, sample) == 0x1537b3 and result.material_value(Terrain.Layer.TILES, block) == expected, "native TER reimports both paint channels")
		check(material_export_preserved(baseline, terrain, result), "all pre-paint bytes outside edited RGB and tile lanes stay unchanged")
	else:
		check(false, "reopen the native material export: " + exported.error)
	doc.undo()
	doc.undo()
	check(not terrain.has_material_edits(), "undo clears both paint channels")
	brush.surface.select(0)
	brush.update_buttons()


func dab_main_view(editor: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = editor.top.view_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	editor.view_input(event, editor.top)
	event.pressed = false
	editor.view_input(event, editor.top)


func material_export_preserved(baseline: Terrain, original: Terrain, exported: Terrain, heights := {}) -> bool:
	var changed_blocks := {}
	for layer: int in [Terrain.Layer.HEIGHT, Terrain.Layer.COLOR]:
		var edits: Dictionary = original.color_edits if layer == Terrain.Layer.COLOR else heights
		for index: int in edits:
			var block := original.block_at(original.sample_at(index))
			changed_blocks[block] = changed_blocks.get(block, 0) | (1 << layer)
	for block in original.block_offsets.size() - 1:
		var ignored: int = changed_blocks.get(block, 0)
		if (baseline.original[baseline.block_offsets[block]] & ~ignored) != (exported.original[exported.block_offsets[block]] & ~ignored):
			return false
		for layer in Terrain.SIZES.size():
			if (ignored & (1 << layer)) or (layer == Terrain.Layer.TILES and original.tile_edits.has(block)):
				continue
			var before := baseline.original.slice(baseline.layer_start(block, layer), baseline.layer_start(block, layer + 1))
			var after := exported.original.slice(exported.layer_start(block, layer), exported.layer_start(block, layer + 1))
			if before != after:
				return false
	return true


func test_shape_tools(editor: Control, scratch: String) -> void:
	var original_package = editor.document.package
	var fixture := scratch.path_join("shape-fixture")
	if DirAccess.make_dir_absolute(fixture) != OK:
		check(false, "create the rectangular shape fixture")
		return
	var writer := Snapshots.new()
	for name: String in original_package.files:
		if name != original_package.terrain_name:
			check(DirAccess.copy_absolute(original_package.source_path.get_base_dir().path_join(name), fixture.path_join(name)) == OK, "copy shape companion " + name)
	var bytes := PackedByteArray([84, 69, 82, 82])
	bytes.resize(16 + 8 * 16)
	bytes.encode_u32(4, 5)
	bytes.encode_s16(8, -40)
	bytes.encode_s16(10, -24)
	bytes.encode_s16(12, 24)
	bytes.encode_s16(14, 8)
	for block in 8:
		bytes.encode_float(17 + 16 * block, 20.0 + block * 3.0)
	if not writer.write_bytes(fixture.path_join(original_package.terrain_name), bytes) or not editor.open_map(fixture.path_join(original_package.bzn_name)):
		check(false, "open the rectangular shape fixture")
		return
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var original := terrain.heights.duplicate()
	check(terrain.dimensions == Vector2i(64, 32) and terrain.origin == Vector2i(-40, -24), "rectangular terrain with offset origin")
	check(not doc.preview_slope_plane(Vector2i(-1, 3), 8, 100, Vector2.ZERO) and terrain.heights == original, "slope rejects an invalid anchor without changing terrain")
	editor.last_cursor = Vector2(2, 3)
	editor.brush_panel.set_brush_size(8)
	editor.terrain_tools_button.pressed.emit()
	var shapes = editor.terrain_tools
	shapes.height.value = 100.0
	shapes.grade_x.value = 25.0
	shapes.grade_z.value = -50.0
	check(shapes.preview_plane() and doc.edits.is_empty(), "slope preview is isolated from committed edits")
	check(is_equal_approx(terrain.heights[3 * 64 + 3], 100.5) and is_equal_approx(terrain.heights[4 * 64 + 2], 99.0) and terrain.heights[-1] == original[-1], "slope follows world grades and clips at map bounds")
	check(not writer.export_native(doc, scratch.path_join("unapplied-plane")), "unapplied plane cannot export")
	shapes.clear_preview()
	check(terrain.heights == original, "cancel restores the previewed surface")
	shapes.apply_terrain()
	var plane := terrain.heights.duplicate()
	check(not doc.edits.is_empty() and is_equal_approx(plane[3 * 64 + 3], 100.5), "applying the slope creates committed heights")
	doc.undo()
	check(terrain.heights == original, "undo restores the pre-plane terrain")
	doc.redo()
	check(terrain.heights == plane, "redo restores the slope plane")
	for direction: int in Document.MirrorDirection.values():
		check(doc.mirror_heights(direction) > 0 and symmetric_at(terrain, direction), "mirror writes matching heights for direction %d" % direction)
		doc.undo()
		check(terrain.heights == plane, "mirror undo restores the shaped terrain")
	editor.terrain_tools_button.pressed.emit()
	shapes.operation.select(1)
	shapes.choose_operation(1)
	shapes.direction.select(Document.MirrorDirection.MIN_Z_TO_MAX_Z)
	shapes.apply_terrain()
	check(symmetric_at(terrain, Document.MirrorDirection.MIN_Z_TO_MAX_Z) and terrain.heights[3 * 64 + 3] == plane[3 * 64 + 3], "editor mirror leaves the chosen half intact")
	var target := scratch.path_join("shaped-terrain")
	check(writer.export_native(doc, target), writer.error)
	var reopened := Document.new()
	check(reopened.open(target.path_join(original_package.bzn_name)) and reopened.package.terrain.heights == terrain.heights, "slope and mirror export to native TER and reopen")


func symmetric_at(terrain: Terrain, direction: int) -> bool:
	var size := terrain.dimensions
	for z in size.y:
		for x in size.x:
			var opposite := z * size.x + size.x - 1 - x if direction < 2 else (size.y - 1 - z) * size.x + x
			if terrain.heights[z * size.x + x] != terrain.heights[opposite]:
				return false
	return true


func test_brush_controls(editor: Control) -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.shift_pressed = true
	key.physical_keycode = KEY_5
	editor._shortcut_input(key)
	check(editor.brush_panel.radius_m == 64 and editor.brush_panel.size_buttons[4].button_pressed, "Shift+5 selects the 64-cell brush")
	key.physical_keycode = KEY_Q
	editor._shortcut_input(key)
	check(editor.top.square_brush and editor.scene_view.square_brush, "Shift+Q updates the 2D and 3D square footprint")
	editor.brush_panel.pressure_buttons[2].pressed.emit()
	check(editor.brush_panel.pressure == 50, "pressure button sets 50 percent without typing")
	editor.show_wire(true)
	check(editor.scene_view.viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "Wire displays terrain wireframe")
	editor.show_wire(false)
	editor.scene_view.set_view(true)
	check(editor.scene_view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Top switches to orthographic camera")
	editor.scene_view.set_view(false)
	editor.brush_panel.set_brush_size(32)
	editor.brush_panel.set_shape(Document.BrushShape.BELL)
	editor.brush_panel.set_pressure(20)


func test_graph(editor: Control, exported: Document, writer: Snapshots, scratch: String) -> void:
	var doc: Document = editor.document
	var layers := [Graph.layer(), Graph.layer()]
	layers[1]["seed"] = 109.0
	layers[1]["opacity"] = 0.5
	var graph := Graph.new()
	var cyclic := layers[0]["links"].duplicate(true) as Dictionary
	cyclic[Graph.BLEND][0] = Graph.CLAMP
	check(not graph.validate_links(cyclic) and graph.error.contains("cycle"), "reject DAG cycles")
	var mismatched := layers[0]["links"].duplicate(true) as Dictionary
	mismatched[Graph.BLEND][1] = Graph.INPUT
	check(not graph.validate_links(mismatched), "reject mixing a height port and delta port")
	check(graph.validate_stack(layers), "node stack accepts two configured layers")
	var terrain := doc.package.terrain
	var original := terrain.heights.duplicate()
	var before := doc.edits.duplicate()
	var center := Vector2i(512, 512)
	var result := graph.compute(layers, original, terrain.dimensions, terrain.origin, center, 56, doc.package.granularity)
	check(not result.is_empty(), "real noise graph yields a terrain edit")
	check(result == graph.compute(layers, original, terrain.dimensions, terrain.origin, center, 56, doc.package.granularity), "seeded graph output deterministic")
	doc.show_preview(result)
	check(terrain.heights != original and doc.edits == before, "preview affects display but leaves committed edit set")
	check(not writer.export_native(doc, scratch.path_join("preview")), "native export rejects unbaked preview")
	doc.clear_preview()
	check(terrain.heights == original and doc.edits == before, "clearing preview restores exact state")
	doc.show_preview(result)
	doc.bake_preview()
	doc.layers = layers
	check(terrain.heights != original and doc.edits != before, "bake commits graph output")
	doc.undo()
	check(terrain.heights == original and doc.edits == before, "one undo reverses the entire bake")
	doc.redo()
	var destination := scratch.path_join("graph-bake")
	check(writer.export_native(doc, destination), writer.error)
	var baked := Document.new()
	check(baked.open(destination.path_join(doc.package.source_path.get_file())) and baked.package.terrain.heights == terrain.heights, "baked TER re-import has graph result")
	check(exported.package.terrain.heights != baked.package.terrain.heights, "graph changes reach the native output")
	var project := scratch.path_join("graph.bzmag")
	check(writer.save_project(doc, project), writer.error)
	var saved := Document.new()
	check(saved.open(project) and saved.layers == doc.layers and saved.edits == doc.edits, "project persists Photoshop-style layer settings and baked data")
	doc.undo()


func test_studio(editor: Control) -> void:
	editor.open_studio()
	var studio: Window = editor.studio
	check(studio.nodes.get_connection_list().size() == 4, "studio renders the four default connections")
	studio.preview()
	var deadline := Time.get_ticks_msec() + 10000
	while studio.worker.is_started() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not studio.worker.is_started() and not editor.document.preview_after.is_empty(), "studio interactive preview worker")
	studio.close_studio()
	check(editor.document.preview_after.is_empty(), "closing graph studio clears preview")
	editor.open_studio()
	studio.preview()
	studio.parameters["seed"].value += 1
	await wait_for_graph(studio)
	check(not editor.document.has_preview(), "superseded worker cannot apply its previous parameters")
	studio.preview()
	var previous: Document = editor.document
	check(editor.open_map(previous.package.source_path), "replace active document during worker evaluation")
	await wait_for_graph(studio)
	check(editor.document != previous and not editor.document.has_preview() and not previous.has_preview(), "discard worker from a replaced document")


func test_graph_materials(editor: Control, source: String, scratch: String) -> void:
	test_graph_material_nodes()
	if not editor.open_map(source):
		check(false, "open the native material graph fixture")
		return
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var legacy := Graph.layer()
	for node: String in Graph.MATERIAL_NODES:
		legacy["links"].erase(node)
	for key: String in Graph.MATERIAL_DEFAULTS:
		legacy.erase(key)
	doc.layers = [legacy]
	var writer := Snapshots.new()
	var old_project := scratch.path_join("old-graph.bzmag")
	check(writer.save_project(doc, old_project), writer.error)
	var legacy_hash := FileAccess.get_sha256(old_project)
	var loaded := Document.new()
	check(loaded.open(old_project) and loaded.layers[0]["links"][Graph.COLOR_OUTPUT] == [""], "old height graphs receive disconnected material ports")
	check(FileAccess.get_sha256(old_project) == legacy_hash, "load never rewrites the source project")
	doc.layers = [Graph.layer()]
	var original_heights := terrain.heights.duplicate()
	var focus := Vector2i(520, 520)
	var index := focus.y * terrain.dimensions.x + focus.x
	var block := terrain.block_at(focus)
	var tint := 0x31579a
	var original_tint := terrain.material_value(Terrain.Layer.COLOR, index)
	var original_tiles := terrain.material_value(Terrain.Layer.TILES, block)
	var base_tile := (original_tiles + 1) & 15
	var tile_word := (original_tiles & ~15) | base_tile
	var old_history := doc.undo_stack.size()
	check(not doc.show_preview({index: original_heights[index] + 1.0},
		{Terrain.Layer.COLOR: {index: tint}, Terrain.Layer.TILES: {block: tile_word ^ 0x10}}), "an overlay lane change rejects the whole graph result")
	check(not doc.show_preview({index: NAN}, {Terrain.Layer.COLOR: {index: tint}}), "a non-finite elevation rejects the whole graph result")
	check(not doc.show_preview({index: original_heights[index] + 1.0},
		{Terrain.Layer.COLOR: {index: 0x1000000}}), "an out-of-range RGB word rejects the whole graph result")
	check(not doc.has_preview() and doc.undo_stack.size() == old_history and terrain.encode(doc.edits) == terrain.original, "invalid preview leaves history and native bytes untouched")
	editor.last_cursor = Vector2(focus)
	editor.open_studio()
	var studio = editor.studio
	studio.connect_nodes(Graph.INPUT, 0, Graph.COLOR_OUTPUT, 0)
	check(studio.working[0]["links"][Graph.COLOR_OUTPUT] == [""], "height cannot connect directly to RGB output")
	configure_graph_materials(studio, tint, base_tile)
	studio.disconnect_nodes(Graph.CLAMP, 0, Graph.OUTPUT, 0)
	studio.preview()
	await wait_for_graph(studio)
	check(doc.has_preview() and doc.preview_after.is_empty() and terrain.heights == original_heights, "material-only graph does not alter height")
	check(terrain.material_value(Terrain.Layer.COLOR, index) == tint and terrain.material_value(Terrain.Layer.TILES, block) == tile_word and not terrain.has_material_edits(), "material preview displays both channels without dirtying them")
	check_graph_views(editor, focus, Terrain.Layer.COLOR, Terrain.word_color(tint))
	studio.preview_channel.select(3)
	studio.show_preview_channel()
	check_graph_views(editor, focus, Terrain.Layer.TILES, editor.top.palette["surface"].lerp(editor.top.palette["textPrimary"], base_tile / 15.0))
	studio.preview_channel.select(0)
	check(not writer.export_native(doc, scratch.path_join("material-preview")), "native export refuses material-only previews")
	var preview_project := scratch.path_join("unbaked-graph.bzmag")
	var without_preview := Document.new()
	check(writer.save_project(doc, preview_project) and without_preview.open(preview_project) and
		without_preview.package.terrain.encode(without_preview.edits) == terrain.original, "project save omits unbaked preview channels")
	studio.close_studio()
	check(not doc.has_preview() and terrain.material_value(Terrain.Layer.COLOR, index) == original_tint and terrain.material_value(Terrain.Layer.TILES, block) == original_tiles, "closing graph restores both native material lanes")
	check(editor.scene_view.graph_preview_layer == -1 and terrain.encode(doc.edits) == terrain.original, "cancel restores the selected view and exact native bytes")
	editor.open_studio()
	configure_graph_materials(studio, tint, base_tile)
	studio.preview()
	await wait_for_graph(studio)
	var history_size := doc.undo_stack.size()
	check(not doc.preview_after.is_empty() and not terrain.material_previews.is_empty(), "mixed height and material preview")
	studio.bake()
	check(not doc.has_preview() and doc.undo_stack.size() == history_size + 1 and terrain.heights != original_heights
		and terrain.material_value(Terrain.Layer.COLOR, index) == tint and terrain.material_value(Terrain.Layer.TILES, block) == tile_word, "one graph bake commits all three native outputs")
	doc.undo()
	check(terrain.heights == original_heights and terrain.encode(doc.edits) == terrain.original, "one undo reverses all mixed graph outputs byte for byte")
	doc.redo()
	check(terrain.heights != original_heights and terrain.material_value(Terrain.Layer.COLOR, index) == tint
		and terrain.material_value(Terrain.Layer.TILES, block) == tile_word, "one redo restores all mixed graph outputs")
	var project := scratch.path_join("material-graph.bzmag")
	check(writer.save_project(doc, project), writer.error)
	var reopened := Document.new()
	check(reopened.open(project) and reopened.layers == doc.layers and reopened.package.terrain.color_edits == terrain.color_edits and reopened.package.terrain.tile_edits == terrain.tile_edits, "reopen the linked material graph and its baked channels")
	var target := scratch.path_join("material-graph")
	check(writer.export_native(doc, target), writer.error)
	var native := Document.new()
	if native.open(target.path_join(doc.package.bzn_name)):
		var result := native.package.terrain
		check(result.heights == terrain.heights and result.material_value(Terrain.Layer.COLOR, index) == tint and result.material_value(Terrain.Layer.TILES, block) == tile_word, "graph outputs reach the reimported native TER")
		check(material_export_preserved(terrain, terrain, result, doc.edits), "graph export preserves every unedited native lane, flag and block")
		check(doc.package.check_sources(), "graph changes leave linked source hashes intact")
		for name: String in doc.package.files:
			if name != doc.package.terrain_name:
				check(doc.package.files[name] == native.package.files.get(name), "graph export preserves " + name)
	else:
		check(false, "reopen baked graph export: " + native.error)


func configure_graph_materials(studio: Window, tint: int, tile: int) -> void:
	studio.connect_nodes(Graph.INPUT, 0, Graph.COLOR_RAMP, 0)
	studio.connect_nodes(Graph.EXISTING_COLOR, 0, Graph.COLOR_BLEND, 0)
	studio.connect_nodes(Graph.COLOR_RAMP, 0, Graph.COLOR_BLEND, 1)
	studio.connect_nodes(Graph.SLOPE, 0, Graph.SLOPE_MASK, 0)
	studio.connect_nodes(Graph.SLOPE_MASK, 0, Graph.COLOR_BLEND, 2)
	studio.connect_nodes(Graph.COLOR_BLEND, 0, Graph.COLOR_OUTPUT, 0)
	studio.connect_nodes(Graph.INPUT, 0, Graph.THRESHOLD, 0)
	studio.connect_nodes(Graph.THRESHOLD, 0, Graph.TILE_SELECT, 1)
	studio.connect_nodes(Graph.TILE_SELECT, 0, Graph.TILE_OUTPUT, 0)
	studio.color_parameters["color_low"].color_changed.emit(Terrain.word_color(tint))
	studio.color_parameters["color_high"].color_changed.emit(Terrain.word_color(tint))
	studio.parameters["tile_height"].value = 0.0
	studio.parameters["tile_high"].value = tile
	studio.parameters["slope_low"].value = 0
	studio.parameters["slope_high"].value = 90


func check_graph_views(editor: Control, focus: Vector2i, layer: int, expected: Color) -> void:
	check(editor.top.preview_layer == layer and editor.scene_view.graph_preview_layer == layer, "both viewports select graph channel " + str(layer))
	if DisplayServer.get_name() != "headless":
		var chunk: Vector2i = (focus / editor.scene_view.CHUNK) * editor.scene_view.CHUNK
		var arrays: Array = editor.scene_view.meshes[chunk].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var point: Vector3 = editor.scene_view.point_world(Vector2(focus))
		var vertex := vertices.find(point)
		var tile: Vector2i = (focus / editor.top.TILE) * editor.top.TILE
		var top_image: Image = editor.top.tiles[tile].get_image()
		var pixel := top_image.get_pixelv((focus - tile) / editor.top.STRIDE)
		check(absf(pixel.r - expected.r) < 0.005 and absf(pixel.b - expected.b) < 0.005, "2D graph pixels show the evaluated channel")
		check(vertex >= 0 and absf(colors[vertex].r - expected.r) < 0.005 and absf(colors[vertex].b - expected.b) < 0.005, "3D terrain mesh shows the evaluated channel")


func test_graph_material_nodes() -> void:
	var graph := Graph.new()
	var layer := Graph.layer()
	layer["links"][Graph.OUTPUT] = [""]
	layer["links"][Graph.COLOR_RAMP] = [Graph.INPUT]
	layer["links"][Graph.COLOR_OUTPUT] = [Graph.COLOR_RAMP]
	layer["links"][Graph.TILE_SELECT] = [Graph.INPUT]
	layer["links"][Graph.TILE_OUTPUT] = [Graph.TILE_SELECT]
	layer["low"] = 0.0
	layer["high"] = 100.0
	layer["color_low"] = 0
	layer["color_high"] = 0xffffff
	layer["tile_height"] = 25.0
	layer["tile_low"] = 3
	layer["tile_high"] = 7
	check(graph.validate_stack([layer]), "validate a material-only graph")
	var heights := PackedFloat32Array()
	heights.resize(16 * 32)
	heights.fill(50.0)
	var index := 8 * 16 + 8
	heights[24 * 16 + 8] = 0.0
	var source := {Terrain.Layer.COLOR: {index: 0}, Terrain.Layer.TILES: {0: 0xab20, 1: 0xcde1}}
	var result := graph.compute_channels([layer], heights, Vector2i(16, 32), Vector2i.ZERO, Vector2i(8, 8), 96, 0.1, source)
	var shade: int = result["materials"][Terrain.Layer.COLOR].get(index, 0)
	check(shade == 0x7f7f7f or shade == 0x808080, "color ramp interpolates an intermediate elevation")
	check(result["materials"][Terrain.Layer.TILES] == {0: 0xab27, 1: 0xcde3} and result["heights"].is_empty(), "tile threshold selects both sides and preserves overlay nibbles")
	check(result == graph.compute_channels([layer], heights, Vector2i(16, 32), Vector2i.ZERO, Vector2i(8, 8), 96, 0.1, source), "RGB and base tile outputs are deterministic")
	layer["links"][Graph.COLOR_BLEND] = [Graph.EXISTING_COLOR, Graph.COLOR_RAMP, Graph.SLOPE_MASK]
	layer["links"][Graph.SLOPE_MASK] = [Graph.SLOPE]
	layer["links"][Graph.COLOR_OUTPUT] = [Graph.COLOR_BLEND]
	layer["links"][Graph.TILE_OUTPUT] = [Graph.EXISTING_TILE]
	layer["slope_low"] = 30.0
	layer["slope_high"] = 50.0
	check(graph.validate_stack([layer]), "slope mask feeds the typed RGB blend port")
	result = graph.compute_channels([layer], heights, Vector2i(16, 32), Vector2i.ZERO, Vector2i(8, 8), 96, 0.1, source)
	check(result["materials"][Terrain.Layer.COLOR].is_empty() and result["materials"][Terrain.Layer.TILES].is_empty(), "flat surfaces and unchanged tile inputs yield a no-op")
	heights[index + 1] = 54.0
	result = graph.compute_channels([layer], heights, Vector2i(16, 32), Vector2i.ZERO, Vector2i(8, 8), 96, 0.1, source)
	check(is_equal_approx(Graph.source_slope(heights, Vector2i(16, 32), Vector2i(8, 8)), 45.0)
		and result["materials"][Terrain.Layer.COLOR].has(index), "slope mask blends on a 45 degree native grade")
	layer["links"][Graph.COLOR_BLEND][2] = Graph.HEIGHT_MASK
	layer["links"][Graph.HEIGHT_MASK] = [Graph.INPUT]
	check(graph.validate_stack([layer]), "height range mask can drive a color blend")
	layer["links"][Graph.COLOR_BLEND][2] = Graph.COLOR_RAMP
	check(not graph.validate_stack([layer]), "RGB cannot feed a mask port")
	layer["links"][Graph.COLOR_BLEND] = [Graph.COLOR_BLEND, Graph.COLOR_RAMP, Graph.MASK]
	check(not graph.validate_stack([layer]) and graph.error.contains("cycle"), "reject a cycle through a typed RGB port")


func wait_for_graph(studio: Window) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while studio.worker.is_started() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not studio.worker.is_started(), "graph preview worker finishes")


func test_object_move(editor: Control, source: String, scratch: String) -> void:
	if not editor.open_map(source):
		check(false, "load native object move fixture")
		return
	var doc: Document = editor.document
	var index := 15
	var entry: Dictionary = doc.package.objects[index]
	check(entry["odf"] == "morock03", "select a decorative Brave rock for the private snapshot")
	var original: Transform3D = entry["transform"]
	var model := MeshInstance3D.new()
	model.mesh = BoxMesh.new()
	editor.scene_view.object_models.add_child(model)
	model.transform = original
	editor.scene_view.object_models.instances[index] = model
	editor.move_objects_button.set_pressed_no_signal(true)
	editor.move_objects_button.pressed.emit()
	check(editor.top.move_objects and editor.scene_view.object_anchors.mesh != null, "object mode shows selectable placement markers in both views")

	var top_anchor: Vector2 = editor.top.path_point_pixel(Vector2(original.origin.x, original.origin.z))
	object_mouse_button(editor, editor.top, top_anchor, true)
	check(editor.object_tool.selected == index and editor.top.selected_object == index
		and editor.status.text.contains("morock03") and editor.status.text.contains("Team"), "2D pick selects and describes the native object")
	object_mouse_drag(editor, editor.top, top_anchor + Vector2(-8, 5), false)
	check(doc.object_edits.is_empty() and model.position != original.origin and editor.top.object_preview == model.position,
		"2D drag previews the same transform without committing")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._shortcut_input(escape)
	check(editor.object_tool.drag_view == null and model.position == original.origin and doc.object_edits.is_empty(),
		"Escape restores the native model and leaves history unchanged")

	var view: Control = editor.scene_view
	editor.scene_view.center = original.origin
	editor.scene_view.distance = 100.0
	editor.scene_view.update_camera()
	await process_frame
	var model_pixel: Vector2 = editor.scene_view.camera.unproject_position(model.global_position)
	object_mouse_button(editor, view, model_pixel, true)
	check(editor.object_tool.selected == index and editor.object_tool.drag_view == view and editor.scene_view.object_cursor.visible,
		"3D pick selects the same native object")
	var destination_pixel := model_pixel + Vector2(23, 15)
	object_mouse_drag(editor, view, destination_pixel, true)
	var draft: Vector3 = editor.object_tool.draft
	object_mouse_button(editor, view, destination_pixel, false)
	var moved := doc.object_position(index)
	check(draft.is_finite() and moved == draft and moved != original.origin and model.position == moved and model.basis == original.basis,
		"3D drag commits the selected transform while preserving orientation")
	check(fposmod(moved.x, Terrain.SPACING) == 0.0 and fposmod(moved.z, Terrain.SPACING) == 0.0, "Shift snaps placement to the native grid")
	check(editor.has_unsaved_changes(), "native position edits mark the linked project dirty")
	check_object_shortcut(editor.undo_button, KEY_Z)
	check(not editor.has_unsaved_changes() and doc.object_edits.is_empty() and model.position == original.origin, "Ctrl+Z restores both object views")
	check_object_shortcut(editor.redo_button, KEY_Y)
	check(doc.object_position(index) == moved and model.position == moved, "Ctrl+Y reapplies the native placement")

	var project := scratch.path_join("object-move.bzmag")
	editor.save_project(project)
	check(not editor.has_unsaved_changes(), "Save Project marks the current object placement saved")
	check(editor.open_map(project) and editor.document.object_position(index) == moved, "reopen the committed object placement")
	var writer := Snapshots.new()
	var target := scratch.path_join("object-move")
	check(writer.export_native(editor.document, target), writer.error)
	var exported := target.path_join(doc.package.bzn_name)
	var reopened := Document.new()
	if reopened.open(exported):
		var placement: Transform3D = reopened.package.objects[index]["transform"]
		check(placement.origin == moved and placement.basis == original.basis, "native BZN reimport preserves moved position and original basis")
		var expected := FileAccess.get_file_as_bytes(source)
		var offset: int = entry["position_offset"]
		expected.encode_float(offset, moved.x)
		expected.encode_float(offset + 4, moved.y)
		expected.encode_float(offset + 8, moved.z)
		check(FileAccess.get_file_as_bytes(exported) == expected, "only the three native translation floats can change, including exact suffix preservation")
		check(doc.package.check_sources(), "object editing preserves the original native map hashes")
		print("Object %d %s: (%.6f, %.6f, %.6f) -> (%.6f, %.6f, %.6f)" % [
			index, entry["odf"], original.origin.x, original.origin.y, original.origin.z, moved.x, moved.y, moved.z])
	else:
		check(false, "read exported object position: " + reopened.error)


func object_mouse_button(editor: Control, view: Control, pixel: Vector2, down: bool) -> void:
	var button := InputEventMouseButton.new()
	button.position = pixel
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = down
	editor.view_input(button, view)


func object_key(editor: Control, key: Key, shift := false, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.pressed = true
	editor._shortcut_input(event)


func test_object_tools(editor: Control, source: String, scratch: String) -> void:
	check(editor.open_map(source), "load the object tools fixture")
	var doc: Document = editor.document
	var index := 15
	var entry: Dictionary = doc.package.objects[index]
	check(entry["odf"] == "morock03", "object tools use the decorative Brave rock")
	var original: Transform3D = entry["transform"]
	editor.move_objects_button.set_pressed_no_signal(true)
	editor.move_objects_button.pressed.emit()
	editor.object_tool.selected = index
	editor.object_tool.set_active(true)

	object_key(editor, KEY_BRACKETRIGHT)
	var rotated: Transform3D = doc.object_transform(index)
	var plus15 := original.basis.rotated(Vector3.UP, deg_to_rad(15.0))
	check(rotated.basis == plus15 and rotated.origin == original.origin,
		"the ] hotkey rotates the selection 15° around the world up axis in place")
	check(editor.status.text.contains("Heading"), "the status line reports the native heading")
	object_key(editor, KEY_BRACKETLEFT, true)
	check(doc.object_transform(index).basis == plus15.rotated(Vector3.UP, deg_to_rad(-1.0)),
		"Shift+[ applies a one degree counter-rotation")
	check(doc.object_transform(index).basis != original.basis, "the net rotation differs from the source basis")
	doc.undo()
	check(doc.object_transform(index).basis == plus15, "undo cancels the last rotation step only")
	doc.undo()
	check(doc.object_transform(index) == original, "undo restores the exact native basis floats")
	doc.redo()
	doc.redo()
	print("Object %d heading test euler: %s" % [index, doc.object_transform(index).basis.get_euler()])

	var writer := Snapshots.new()
	var rotate_target := scratch.path_join("object-rotate")
	check(writer.export_native(doc, rotate_target), writer.error)
	var rotated_map := Document.new()
	check(rotated_map.open(rotate_target.path_join(doc.package.bzn_name)), "reopen rotation-only export")
	if rotated_map.package.objects.size() == doc.object_count():
		check(rotated_map.package.objects[index]["transform"] == doc.object_transform(index), "exported rotation round-trips exactly")
		var exported_bytes := FileAccess.get_file_as_bytes(rotate_target.path_join(doc.package.bzn_name))
		var source_bytes := FileAccess.get_file_as_bytes(source)
		check(exported_bytes.size() == source_bytes.size(), "rotation edits rewrite the BZN in place without shifting any records")

	var offset := Vector3(8.0, 0.0, 8.0)
	var added := doc.duplicate_object(index, original.origin + offset)
	check(added == doc.object_count() - 1 and doc.object_count() == doc.package.objects.size() + 1,
		"duplicating appends a native object record after the existing stream")
	var addition := doc.object_addition(added)
	var base_sequences := {}
	for record in doc.package.objects:
		base_sequences[int(record["sequence"])] = true
	check(doc.object_odf(added) == entry["odf"] and not base_sequences.has(int(addition["sequence"]))
		and doc.object_transform(added).origin == original.origin + offset, "the duplicate keeps the class and gains an unused sequence")
	object_key(editor, KEY_D, false, true)
	check(doc.object_count() == doc.package.objects.size() + 2, "Ctrl+D duplicates the current selection through the editor tool")
	doc.undo()
	check(doc.object_count() == doc.package.objects.size() + 1, "undo removes one duplicate and restores the previous count")

	var duplicate_target := scratch.path_join("object-duplicate")
	check(writer.export_native(doc, duplicate_target), writer.error)
	var duplicated_map := Document.new()
	check(duplicated_map.open(duplicate_target.path_join(doc.package.bzn_name)), "reopen the duplicated export")
	if duplicated_map.package.objects.size() == doc.object_count():
		var view_added := doc.object_count() - 1
		check(duplicated_map.package.objects[view_added]["odf"] == entry["odf"]
			and duplicated_map.package.objects[view_added]["transform"] == doc.object_transform(view_added)
			and duplicated_map.package.objects[view_added]["sequence"] == int(addition["sequence"]),
			"the duplicated native record re-imports with the kept class, transform and sequence")
		var suffix_source := FileAccess.get_file_as_bytes(source).slice(doc.package.path_codec.table_end)
		var suffix_export := FileAccess.get_file_as_bytes(duplicate_target.path_join(doc.package.bzn_name)).slice(duplicated_map.package.path_codec.table_end)
		check(suffix_source == suffix_export, "the untouched original trailer rides along after the resized path region")
		check(duplicated_map.package.object_insert_offset < duplicated_map.package.path_codec.table_start - 7,
			"the duplicated object inserts before the 640-byte groupTargets mission boundary")
		var pointer_ids := {}
		for obj in duplicated_map.package.objects:
			var pid: int = obj["flag8"]
			check(pid > 0 and not pointer_ids.has(pid), "object pointer ID %d is positive and unique" % pid)
			pointer_ids[pid] = true
		for path_item in duplicated_map.package.paths:
			var pid: int = path_item["id"]
			check(pid > 0 and not pointer_ids.has(pid), "path pointer ID %d stays distinct from object pointer IDs" % pid)
			pointer_ids[pid] = true

	var removed_view := doc.object_count() - 1
	check(doc.remove_object(removed_view), "removing the appended duplicate reduces the count")
	check(doc.object_count() == doc.package.objects.size(), "the duplicate removal leaves the original 76 native records")
	doc.undo()
	check(doc.object_count() == doc.package.objects.size() + 1, "undo restores the removed duplicate from history")

	var labeled := -1
	for view in doc.package.objects.size():
		if String(doc.package.objects[view]["label"]) != "":
			labeled = view
			break
	if labeled >= 0:
		var label_before: String = doc.package.objects[labeled]["label"]
		var labeled_duplicate := doc.duplicate_object(labeled, doc.object_position(labeled))
		check(doc.object_label(labeled_duplicate) == label_before + "_2", "a labeled duplicate gains a fresh native label")
		doc.undo()
	else:
		check(doc.object_label(doc.object_count() - 1) == "", "unlabeled duplicates stay unlabeled in the native stream")

	var removed_base := -1
	for view in doc.object_count():
		if not doc.object_is_added(view) and int(doc.object_entry(view)["base"]) != index:
			removed_base = view
			break
	check(doc.remove_object(removed_base), "remove a decorative source object")
	check(doc.object_count() == doc.package.objects.size(), "the view count follows the ordered base and added entries")

	var project := scratch.path_join("object-tools.bzmag")
	editor.save_project(project)
	check(not editor.has_unsaved_changes(), "saving the project clears the dirty flag for all object edits")
	var reopened := Document.new()
	check(reopened.open(project), "reopen the object project file")
	print("Project reopen compares: rotation edits %d, removals %d, additions %d" % [
		reopened.object_edits.size(), reopened.object_removals.size(), reopened.object_additions.size()])
	check(reopened.object_edits.keys() == doc.object_edits.keys() and reopened.object_removals.keys() == doc.object_removals.keys()
		and reopened.object_additions.size() == doc.object_additions.size(), "the project round-trips every transform, removal and insertion")
	check(reopened.object_transform(index) == doc.object_transform(index), "the rotated transform survives the project round trip")

	var final_target := scratch.path_join("object-tools")
	check(writer.export_native(reopened, final_target), writer.error)
	var final_map := Document.new()
	check(final_map.open(final_target.path_join(reopened.package.bzn_name)), "reopen the full object-tools export")
	if final_map.package.objects.size() == reopened.object_count():
		for view in final_map.package.objects.size():
			if BznObjects.fields(final_map.package.objects[view]) != Snapshots.expected_object_fields(reopened, view):
				check(false, "exported object %d matches the document fields" % view)
				break
		check(true, "every exported object re-imports with the edited class, label, sequence and transform")
	var clean := Document.new()
	check(clean.open(source), "open a fresh document for the identity export")
	var clean_target := scratch.path_join("object-clean")
	check(writer.export_native(clean, clean_target), writer.error)
	check(FileAccess.get_file_as_bytes(clean_target.path_join(clean.package.bzn_name)) == FileAccess.get_file_as_bytes(source),
		"an unedited document exports a byte-identical native BZN")
	print("Object tools: rotation, duplicate, label copy and removal verified for %s." % entry["odf"])


func object_mouse_drag(editor: Control, view: Control, pixel: Vector2, snap: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.shift_pressed = snap
	editor.view_input(motion, view)


func check_object_shortcut(button: Button, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = true
	event.pressed = true
	check(button.shortcut.matches_event(event) and not button.disabled, "object history shortcut is enabled")
	button.pressed.emit()


func test_water_tools(editor: Control, source: String, scratch: String) -> void:
	check(editor.open_map(source), "load the water tools fixture")
	var doc: Document = editor.document
	var water: Water = doc.package.water
	check(water.width == 64 and water.depth == 64, "the water codec measures the 64 × 64 Brave block grid")
	check(doc.water_layer_height(0) == 135.0 and doc.water_cover_count(0) == 222, "layer 0 decodes at 135 m covering 222 blocks")
	check(doc.water_layers_effective().size() == 1 and doc.water_layers_effective()[0]["index"] == 0, "only layer 0 carries coverage")
	check(not doc.set_water_height(8, 10.0) and not doc.set_water_height(0, 150000.0) and not doc.error.is_empty(),
		"elevation edits reject invalid layers and heights")
	doc.error = ""
	check(doc.set_water_height(0, 147.5) and doc.water_layer_height(0) == 147.5, "set elevation records the new height")
	doc.undo()
	check(doc.water_layer_height(0) == 135.0, "undo restores the native elevation")
	doc.redo()
	check(doc.water_layer_height(0) == 147.5, "redo restores the edited elevation")
	doc.undo()

	editor.water_edit_button.pressed.emit()
	check(editor.water_tools.visible, "the Edit Water button opens the dialog")
	check(editor.water_tools.current_layer() == 0, "the dialog starts on the coastal layer 0")
	editor.water_tools.radius.value = 1.0
	editor.water_tools.paint_toggle.button_pressed = true
	check(editor.painting_water_active(), "enabling coverage paint arms the water brush")
	var pixel: Vector2 = editor.top.view_rect().get_center()
	var sample: Vector2 = editor.top.sample_at(pixel)
	var block: int = (int(sample.y) / doc.WATER_BLOCK) * water.width + int(sample.x) / doc.WATER_BLOCK
	check(not doc.water_effective_cover(0).has(block), "the painted block starts uncovered")
	var press := InputEventMouseButton.new()
	press.position = pixel
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	editor.view_input(press, editor.top)
	check(doc.water_stroke_active and editor.paint_view == editor.top, "a left press starts a coverage stroke in the 2D view")
	check(doc.water_cover_count(0) == 226 and doc.water_effective_cover(0).has(block), "the stroke paints the four blocks meeting at the map centre sample")
	check(editor.has_unsaved_changes(), "water coverage marks the document dirty")
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor.view_input(motion, editor.top)
	editor.view_input(press, editor.top)
	press.pressed = false
	editor.view_input(press, editor.top)
	check(not doc.water_stroke_active and editor.paint_view == null, "releasing the button ends the water stroke")
	check(editor.status.text.contains("Water stroke done"), "the status line reports the finished stroke")
	doc.undo()
	check(doc.water_cover_count(0) == 222, "undo removes the painted coverage")
	doc.redo()
	check(doc.water_cover_count(0) == 226, "redo re-applies the painted coverage")
	doc.undo()
	editor.water_tools.elevation.value = 150.5
	editor.water_tools.apply_elevation()
	check(doc.water_layer_height(0) == 150.5, "Apply Elevation records the dialog value")
	check(editor.status.text.contains("Water layer 1 elevation set"), "the dialog reports the elevation change")
	editor.water_tools.paint_toggle.button_pressed = false
	editor.water_tools.hide()
	check(not editor.painting_water_active(), "closing the dialog stops coverage painting")

	var base_tile: Vector2 = water.first_tiles[0]
	var base_block := int(base_tile.y) * water.width + int(base_tile.x)
	var base_sample := Vector2(int(base_tile.x) * doc.WATER_BLOCK + 8, int(base_tile.y) * doc.WATER_BLOCK + 8)
	doc.begin_water_stroke()
	doc.water_dab(base_sample, 1.0, 0, false)
	doc.end_water_stroke(0)
	check(not doc.water_effective_cover(0).has(base_block) and doc.water_cover_count(0) == 221, "erase stroke removes native coverage")
	doc.undo()
	check(doc.water_effective_cover(0).has(base_block) and doc.water_cover_count(0) == 222, "undo restores the erased native coverage")

	doc.begin_water_stroke()
	doc.water_dab(base_sample, 1.0, 0, false)
	doc.end_water_stroke(0)
	doc.begin_water_stroke()
	doc.water_dab(Vector2(520.0, 520.0), 1.0, 2, true)
	doc.end_water_stroke(2)
	check(doc.water_cover_count(2) == 1 and doc.water_layer_height(2) == 0.0, "layer 2 gains coverage at its default elevation")
	check(doc.water_layers_effective().size() == 2, "the effective layers now include layer 2")
	check(doc.set_water_height(2, 90.0), "raise the second layer elevation")

	var writer := Snapshots.new()
	var project := scratch.path_join("water-tools.bzmag")
	editor.save_project(project)
	check(not editor.has_unsaved_changes(), "saving the project clears the water dirty flag")
	var reopened := Document.new()
	check(reopened.open(project), "reopen the water project file")
	check(reopened.water_heights.keys() == doc.water_heights.keys() and absf(reopened.water_layer_height(2) - 90.0) < 0.0005,
		"the project round-trips every edited elevation")
	check(reopened.water_effective_cover(0) == doc.water_effective_cover(0) and reopened.water_effective_cover(2) == doc.water_effective_cover(2),
		"the project round-trips every coverage edit")

	var target := scratch.path_join("water-tools")
	check(writer.export_native(reopened, target), writer.error)
	var exported := Document.new()
	check(exported.open(target.path_join(reopened.package.bzn_name)), "reopen the water export")
	check(exported.package.water.layers.size() == 2, "the exported mask decodes both layers")
	check(exported.water_layers_effective() == reopened.water_layers_effective(), "the exported mask re-imports as the document coverage")
	check(exported.package.water.layers[1]["height"] == 90.0 and exported.package.water.layers[0]["height"] == 150.5,
		"the exported heights re-import at the edited elevations")
	var wat_expected := Water.encode(doc.package.water_bytes, doc.water_edits, doc.water_heights)
	var wat_actual := FileAccess.get_file_as_bytes(target.path_join(doc.package.water_name))
	check(wat_actual == wat_expected and wat_actual.size() == 6512, "the exported WAT matches the codec byte for byte")

	var text: String = FileAccess.get_file_as_string(project)
	var data: Dictionary = JSON.parse_string(text)
	data["waterEdits"] = {"9": {"height": 5.0}}
	var bad_path := scratch.path_join("water-bad.bzmag")
	var output := FileAccess.open(bad_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(data, "", true, true))
	output.close()
	var bad := Document.new()
	check(not bad.open(bad_path) and bad.error == "Invalid project water layer.", "the project loader rejects out-of-range water layers")
	print("Water tools: coverage, elevation, project and export verified on layer 0 and 2.")


func test_fly_autosave_symmetry(editor: Control, source: String, scratch: String) -> void:
	check(editor.open_map(source), "load the fly, autosave and symmetry fixture")
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var view: TerrainView = editor.scene_view
	view.set_view(false)

	var center_before: Vector3 = view.center
	editor.fly_button.set_pressed_no_signal(true)
	editor.toggle_fly()
	check(view.fly, "the Fly button arms the free-flight camera")
	view.fly_step(1.0, 0.0, 0.0, 0.25)
	var heading := Vector3(-sin(view.yaw), 0, -cos(view.yaw))
	check(view.center.distance_to(center_before + heading * (view.distance * 0.6 * 0.25)) < 0.01, "W moves the camera forward along the look heading")
	view.fly_step(0.0, 1.0, 1.0, 0.5)
	var right := Vector3(cos(view.yaw), 0, -sin(view.yaw))
	var expected := center_before + heading * (view.distance * 0.6 * 0.25) + right * (view.distance * 0.6 * 0.5) + Vector3.UP * (view.distance * 0.6 * 0.5 * 0.5)
	check(view.center.distance_to(expected) < 0.01, "strafe and rise move the camera sideways and up")
	editor.fly_button.set_pressed_no_signal(false)
	editor.toggle_fly()
	check(not view.fly, "toggle off disarms flight")
	view.set_view(true)
	check(not view.fly, "the top view disarms flight")
	editor.fly_button.set_pressed_no_signal(true)
	editor.toggle_fly()
	check(view.fly and view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "entering flight from the top view returns to perspective")
	editor.fly_button.set_pressed_no_signal(false)
	editor.toggle_fly()
	object_key(editor, KEY_F)
	check(view.fly and editor.fly_button.button_pressed, "the F hotkey toggles the fly camera on")
	object_key(editor, KEY_F)
	check(not view.fly, "the F hotkey toggles the fly camera off")

	check(not editor.autosave_now(scratch), "autosave skips a clean document")
	doc.begin_stroke()
	doc.dab(Vector2(512.0, 512.0), 48, 24)
	doc.end_stroke()
	var first_count := doc.edits.size()
	var project := AutoSaveStore.project_dir(scratch, doc.package.source_path)
	check(editor.autosave_now(scratch) and FileAccess.file_exists(editor.last_autosave), "autosave publishes a verified slot outside the map folder")
	var source_dir := doc.package.source_path.get_base_dir()
	var leaked := 0
	for name in DirAccess.get_files_at(source_dir):
		if "autosave" in name.to_lower() and name.get_extension().to_lower() == "bzmag":
			leaked += 1
	check(leaked == 0, "the map source folder carries no autosave files")
	doc.begin_stroke()
	doc.dab(Vector2(360.0, 512.0), 24, 30)
	doc.end_stroke()
	check(editor.autosave_now(scratch), "a second autosave publishes a new slot")
	var newest := Document.new()
	check(newest.open(AutoSaveStore.latest(project)) and newest.edits.size() == doc.edits.size(), "the newest autosave reopens with every current edit")
	var found := AutoSaveStore.slots(project)
	check(found.size() == 2, "two dabs publish two slots")
	var older := Document.new()
	check(older.open(found[0]) and older.edits.size() == first_count, "the previous autosave keeps its own older state")
	editor.autosave_now(scratch)
	editor.autosave_now(scratch)
	var after := AutoSaveStore.slots(project)
	check(after.size() == 3, "the rolling store keeps exactly three autosaves")
	check(AutoSaveStore.latest(project) == editor.last_autosave, "the newest slot is the last published file")
	check(editor.has_unsaved_changes(), "autosaving does not clear the unsaved marker")
	var recovered := Document.new()
	check(recovered.open(AutoSaveStore.latest(project)) and recovered.edits.size() == doc.edits.size(), "a fresh recovery store finds the newest slot after a restart")

	editor.brush_panel.mirror_x_button.pressed.emit()
	check(editor.brush_panel.mirror_x, "the Mirror X toggle arms live symmetry")
	var index_a := 512 * terrain.dimensions.x + 100
	var index_b := 512 * terrain.dimensions.x + 923
	var base_a: float = terrain.heights[index_a]
	var base_b: float = terrain.heights[index_b]
	doc.begin_stroke()
	editor.brush_panel.apply_dab(doc, Vector2(100.0, 512.0))
	doc.end_stroke()
	check(terrain.heights[index_a] > base_a + 0.1 and terrain.heights[index_b] > base_b + 0.1, "one mirrored dab raises both halves")
	check(absf(terrain.heights[index_a] - base_a - (terrain.heights[index_b] - base_b)) <= doc.package.granularity + 0.001, "the mirrored half changes within one native height step")
	doc.undo()
	check(terrain.heights[index_a] == base_a and terrain.heights[index_b] == base_b, "one undo restores both mirrored halves")
	editor.brush_panel.set_mirror_x(false)
	check(not editor.brush_panel.mirror_x, "the mirror toggle turns off")
	check(editor.brush_panel.mirrored(doc, Vector2(100.0, 200.0), true) == Vector2(923.0, 200.0)
		and editor.brush_panel.mirrored(doc, Vector2(100.0, 200.0), false) == Vector2(100.0, 823.0), "mirror points compute the opposite samples")
	print("Fly camera, rolling autosave and live symmetry verified.")


func sample_of_world(terrain: Terrain, world: Vector2) -> Vector2i:
	var point: Vector2 = Vector2(world.x, world.y) / terrain.SPACING - Vector2(terrain.origin)
	return Vector2i(point.round()).clamp(Vector2i.ZERO, terrain.dimensions - Vector2i.ONE)


func test_slope_studio(editor: Control, source: String, scratch: String) -> void:
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var granularity: float = doc.package.granularity
	var writer := Snapshots.new()
	var before_ramp := terrain.heights.duplicate()
	editor.last_cursor = Vector2(512.0, 512.0)
	editor.slope_studio_button.pressed.emit()
	var studio = editor.slope_studio
	var anchor: Vector3 = editor.scene_view.point_world(Vector2(512.0, 512.0))
	var anchor_world := Vector2(anchor.x, anchor.z)
	check(absf(studio.from_x.value - anchor_world.x) < 0.001 and absf(studio.from_z.value - anchor_world.y) < 0.001,
		"the studio opens at the terrain cursor in world metres")
	check(absf(studio.from_height.value - before_ramp[512 * terrain.dimensions.x + 512]) < 0.001,
		"the ramp start height reads the current terrain")
	var span := 200.0
	studio.to_x.value = studio.from_x.value + span
	studio.to_z.value = studio.from_z.value
	studio.mode_choice.select(1)
	studio.angle.value = 15.0
	studio.width.value = 32.0
	studio.falloff.value = 0.0
	studio.profile.select(Shapes.PROFILES.find("flat"))
	var ramp_ready: bool = studio.preview_shape() and doc.has_preview()
	if not ramp_ready:
		check(false, "the exact-angle 15 degree ramp previews on 2D and 3D")
		return
	check(true, "the exact-angle 15 degree ramp previews on 2D and 3D")
	check(studio.message.text.contains("15.0 degrees"), "the status names the exact angle")
	var expected_end := snappedf(studio.from_height.value + span * tan(deg_to_rad(15.0)), granularity)
	var index := sample_of_world(terrain, Vector2(studio.to_x.value, studio.to_z.value))
	var end_height: float = terrain.heights[index.y * terrain.dimensions.x + index.x]
	check(absf(end_height - expected_end) <= granularity, "the ramp reaches h = start + distance * tan(15 degrees)")
	var middle := sample_of_world(terrain, Vector2((studio.from_x.value + studio.to_x.value) * 0.5, studio.from_z.value))
	var middle_height: float = terrain.heights[middle.y * terrain.dimensions.x + middle.x]
	check(absf(middle_height - lerpf(studio.from_height.value, expected_end, 0.5)) <= granularity, "the flat ramp profile is linear at mid-span")
	# Edge falloff blends the ramp into the existing surface: at 24 m lateral
	# the weight is exactly mid-falloff, so the blended sample must land on the
	# midpoint between the original surface and the ramp height.
	var edge := sample_of_world(terrain, Vector2(studio.to_x.value, studio.to_z.value + 24.0))
	studio.falloff.value = 16.0
	if not studio.preview_shape():
		check(false, "the widened falloff previews")
		return
	check(true, "the widened falloff previews")
	var edge_index := edge.y * terrain.dimensions.x + edge.x
	var blended: float = terrain.heights[edge_index]
	var edge_original: float = before_ramp[edge_index]
	check(absf(blended - lerpf(edge_original, expected_end, 0.5)) <= granularity + 0.05,
		"the falloff edge blends halfway between the original surface and the ramp")
	check(not writer.export_native(doc, scratch.path_join("unapplied-ramp")), "an unapplied ramp cannot export")
	# Apply is one undo step; undo and redo are exact.
	var stack_before := doc.undo_stack.size()
	studio.apply_shape()
	check(doc.undo_stack.size() == stack_before + 1 and not doc.has_preview(), "the ramp commits as exactly one undo step")
	var ramped := terrain.heights.duplicate()
	check(ramped != before_ramp, "the commit changed terrain heights")
	doc.undo()
	check(terrain.heights == before_ramp, "undo restores the exact pre-ramp heights")
	doc.redo()
	check(terrain.heights == ramped, "redo re-applies the ramp exactly")
	# Terrace profile quantizes the climb.
	studio.profile.select(Shapes.PROFILES.find("terrace"))
	studio.terrace_levels.value = 4.0
	if studio.preview_shape():
		var quarter := sample_of_world(terrain, Vector2(studio.from_x.value + span * 0.28, studio.from_z.value))
		var stepped: float = terrain.heights[quarter.y * terrain.dimensions.x + quarter.x]
		var level_one := snappedf(studio.from_height.value + (expected_end - studio.from_height.value) * 0.25, granularity)
		check(absf(stepped - level_one) <= granularity, "the terrace quantizes to the second level near 25 percent")
	else:
		check(false, "the terrace profile previews")
	studio.profile.select(Shapes.PROFILES.find("flat"))
	studio.preview_shape()
	studio.apply_shape()
	# Batch: two linear ramps mirrored across the start axis.
	studio.batch_mode.select(1)
	studio.batch_count.value = 2.0
	studio.batch_spacing.value = 96.0
	# Mirror across X: the mirrored ramp runs on the opposite side of the start
	# point, so its footprint is disjoint from the original.
	studio.mirror_x.button_pressed = true
	var mirror_previewed: bool = studio.preview_shape()
	check(mirror_previewed, "the mirrored linear batch previews")
	if mirror_previewed:
		var mirrored_values := doc.preview_after.size()
		studio.mirror_x.button_pressed = false
		studio.preview_shape()
		# The mirrored ramps run on the far side of the symmetry point, so their
		# footprints stay nearly disjoint; only the falloff tails overlap.
		check(mirrored_values >= doc.preview_after.size() * 7 / 4,
			"the mirror adds a near-complete copy of the batch despite the falloff-tail overlap")
		studio.apply_shape()
	# Masks: a height maximum below the current surface shapes nothing.
	studio.mask_max.text = "-100000"
	check(not studio.preview_shape(), "a height mask excluding every sample refuses the shape")
	studio.mask_max.text = ""
	# Project round-trip: save, reopen, verify the ramp survives.
	var saved := scratch.path_join("slope-project.bzmag")
	check(writer.save_project(doc, saved), "save the ramp project")
	var reopened := Document.new()
	var reopened_ok := reopened.open(saved) and reopened.edits.size() == doc.edits.size()
	check(reopened_ok, "the ramp project reopens with the same edit count")
	if reopened_ok:
		check(reopened.package.terrain.heights == terrain.heights, "the reopened heights equal the applied ramp")
	# Native export plus independent VRV decoder agreement.
	var export_target := scratch.path_join("slope-ramp")
	check(writer.export_native(doc, export_target), "export the ramp natively: " + writer.error)
	var exported_ter := export_target.path_join(doc.package.terrain_name)
	var original_ter := doc.package.source_path.get_base_dir().path_join(doc.package.terrain_name)
	var oracle := ProjectSettings.globalize_path("res://").path_join("../build/terrain_oracle.exe")
	var output: Array = []
	var code := OS.execute(oracle, [original_ter, exported_ter, "--heights-only"], output, true)
	var report := str(output[0]).strip_edges() if not output.is_empty() else ""
	check(code == 0 and report.contains("non-height layers identical"),
		"the independent VRV decoder sees only height changes: " + report)
	var changed_count := doc.edits.size()
	check(report.contains("changed %d" % changed_count),
		"the independent decoder counts the same changed samples (%d): %s" % [changed_count, report])
	studio.batch_mode.select(0)
	studio.batch_count.value = 1.0


func test_slope_studio_safety(editor: Control) -> void:
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var heights_before := terrain.heights.duplicate()
	var edits_before := doc.edits.size()
	var undo_before := doc.undo_stack.size()
	var valid := {
		"start": Vector2(0.0, 0.0),
		"end": Vector2(64.0, 0.0),
		"start_height": 100.0,
		"mode": "elevation",
		"target_height": 110.0,
		"width_m": 16.0,
		"falloff_m": 4.0,
	}
	var cases := [
		["start equals end", {"start": Vector2(10.0, 10.0), "end": Vector2(10.0, 10.0)}, {}],
		["sub-grid segment", {"start": Vector2(10.0, 10.0), "end": Vector2(11.0, 10.0)}, {}],
		["NaN position", {"start": Vector2(NAN, 0.0)}, {}],
		["infinite input", {"end": Vector2(INF, 0.0)}, {}],
		["infinite height", {"start_height": INF}, {}],
		["negative width", {"width_m": -8.0}, {}],
		["negative falloff", {"falloff_m": -2.0}, {}],
		["90 degree angle", {"mode": "angle", "angle_deg": 90.0}, {}],
		["-90 degree angle", {"mode": "angle", "angle_deg": -90.0}, {}],
		["excessive height angle", {"mode": "angle", "angle_deg": 89.5, "end": Vector2(1000.0, 0.0)}, {}],
		["excessive batch count", {}, {"mode": "linear", "count": 999999}],
		["mirror X degenerate", {"start": Vector2(10.0, 10.0), "end": Vector2(10.0, 10.0)}, {"mode": "single", "mirror_x": true}],
		["mirror Z degenerate", {"start": Vector2(10.0, 10.0), "end": Vector2(11.0, 10.0)}, {"mode": "single", "mirror_z": true}],
		["radial fan zero-length base", {"start": Vector2(10.0, 10.0), "end": Vector2(10.0, 10.0)}, {"mode": "radial", "count": 4}],
	]
	for entry in cases:
		var case_name: String = entry[0]
		var params: Dictionary = valid.duplicate()
		for k in (entry[1] as Dictionary):
			params[k] = entry[1][k]
		var batch: Dictionary = entry[2]
		var checked := Shapes.instances_checked(params, batch)
		check(not String(checked["error"]).is_empty() and (checked["instances"] as Array).is_empty(),
			"Shapes rejects %s before materialization" % case_name)
		check(Shapes.instances(params, batch).is_empty(), "Shapes.instances returns empty for %s" % case_name)
		if batch.is_empty():
			var evaluated := Shapes.evaluate(params, terrain.dimensions, terrain.origin, terrain.heights)
			check(not String(evaluated["error"]).is_empty() and (evaluated["values"] as Dictionary).is_empty(),
				"Shapes.evaluate rejects %s cleanly" % case_name)
		check(not doc.preview_slope_shape(params, batch) and not doc.error.is_empty() and not doc.has_preview(),
			"document preview rejects %s with actionable error" % case_name)
	check(terrain.heights == heights_before and doc.edits.size() == edits_before and doc.undo_stack.size() == undo_before,
		"rejected slope studio inputs leave terrain, edits and undo stack unchanged")
	# Valid preview followed by cancel via dialog must also leave zero committed changes.
	var studio = editor.slope_studio
	studio.begin(doc, Vector2(0.0, 0.0))
	studio.to_x.value = studio.from_x.value + 32.0
	studio.to_z.value = studio.from_z.value
	studio.mode_choice.select(1)
	studio.angle.value = 15.0
	check(studio.preview_shape() and doc.has_preview(), "valid studio preview activates before cancel")
	studio.canceled.emit()
	studio.hide()
	check(not doc.has_preview() and terrain.heights == heights_before and doc.edits.size() == edits_before and doc.undo_stack.size() == undo_before,
		"canceling slope studio preview restores heights and commits nothing")
	print("Slope Studio safety checks verified.")


func test_large_slope_preview() -> void:
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	var doc := Document.new()
	doc.package = Package.new()
	var terrain := Terrain.new()
	terrain.dimensions = Vector2i(2048, 2048)
	terrain.origin = Vector2i(-1024, -1024)
	terrain.heights.resize(terrain.dimensions.x * terrain.dimensions.y)
	terrain.heights.fill(100.0)
	terrain.min_height = 100.0
	terrain.max_height = 200.0
	doc.package.terrain = terrain
	doc.base_heights = terrain.heights.duplicate()
	editor.document = doc
	editor.top.document = doc
	editor.scene_view.document = doc
	doc.terrain_changed.connect(editor.mark_refresh)

	# Prime one nearby chunk and one distant chunk. A full rebuild would
	# populate the rest of the cache and replace the distant 3D mesh.
	var near := Vector2i(1024, 1024)
	var far := Vector2i.ZERO
	editor.scene_view.build_chunk(near)
	editor.scene_view.build_chunk(far)
	editor.top.update_tile(far)
	var near_mesh: Mesh = editor.scene_view.meshes[near].mesh
	var far_mesh: Mesh = editor.scene_view.meshes[far].mesh
	var started := Time.get_ticks_usec()
	var accepted := doc.preview_slope_shape({
		"start": Vector2.ZERO, "end": Vector2(200.0, 0.0), "start_height": 100.0,
		"mode": "angle", "angle_deg": 15.0, "width_m": 32.0, "falloff_m": 8.0,
	})
	check(accepted and doc.has_preview(), "4096 m terrain accepts the local slope preview")
	var dirty: Rect2i = editor.pending_refresh
	check(dirty.has_area() and dirty.get_area() < 4096, "the preview emits a bounded refresh on the 2048-sample grid")
	editor._process(0.0)
	check(editor.top.tiles.has(near) and editor.top.tiles.size() < 16, "2D refresh updates only the affected tiles")
	check(editor.scene_view.meshes[near].mesh != near_mesh and editor.scene_view.meshes[far].mesh == far_mesh
		and editor.scene_view.meshes.size() < 16, "3D refresh rebuilds near meshes and keeps the distant mesh")
	var preview_ms := (Time.get_ticks_usec() - started) / 1000.0
	var peak := 1024 * terrain.dimensions.x + 1124
	check(terrain.heights[peak] > 150.0, "the large-map preview changes the ramp end")
	doc.clear_preview()
	editor._process(0.0)
	check(not doc.has_preview() and terrain.heights[peak] == 100.0 and doc.edits.is_empty()
		and doc.undo_stack.is_empty(), "cancel restores the large terrain without a committed edit")
	print("4096 m slope preview: %d × %d dirty samples, %d tiles, %d meshes, %.1f ms" % [
		dirty.size.x, dirty.size.y, editor.top.tiles.size(), editor.scene_view.meshes.size(), preview_ms])
	# Dispose of the synthetic editor before its deferred command-line map open.
	editor.free()


func test_adaptive_terrain_lod() -> void:
	var editor := EditorScene.instantiate()
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1120, 690)
	root.add_child(editor)
	var doc := Document.new()
	doc.package = Package.new()
	var terrain := Terrain.new()
	terrain.dimensions = Vector2i(2048, 2048)
	terrain.origin = Vector2i(-1024, -1024)
	terrain.heights.resize(terrain.dimensions.x * terrain.dimensions.y)
	terrain.heights.fill(100.0)
	terrain.min_height = 100.0
	terrain.max_height = 140.0
	# Build five native 2 m features near chunk (1024, 1024) on the 4096 m map:
	# 1) One-sample ridge at (1035, 1035)
	terrain.heights[1035 * 2048 + 1035] = 118.0
	# 2) Narrow 2 m trench along x = 1039, z = 1030..1040
	for z in range(1030, 1041):
		terrain.heights[z * 2048 + 1039] = 92.0
	# 3) Sharp step for x >= 1045, z = 1030..1040
	for z in range(1030, 1041):
		for x in range(1045, 1052):
			terrain.heights[z * 2048 + x] = 112.0
	# 4) Two-metre-wide slope transition (1055 -> 1056)
	for z in range(1030, 1041):
		terrain.heights[z * 2048 + 1055] = 104.0
		terrain.heights[z * 2048 + 1056] = 108.0
	doc.package.terrain = terrain
	doc.base_heights = terrain.heights.duplicate()
	editor.document = doc
	editor.top.document = doc
	editor.scene_view.document = doc
	doc.terrain_changed.connect(editor.mark_refresh)

	var started := Time.get_ticks_usec()
	editor.scene_view.bind(doc)
	editor.scene_view.center = editor.scene_view.point_world(Vector2(1035, 1035))
	editor.scene_view.distance = 120.0
	editor.scene_view.update_camera()
	editor.scene_view.update_lod(0)
	var bind_ms := (Time.get_ticks_usec() - started) / 1000.0

	var near := Vector2i(1024, 1024)
	var mid := Vector2i(1024 + 256, 1024)
	var far := Vector2i(0, 0)
	check(editor.scene_view.effective_chunk_step(near) == 1, "near chunk uses 2 m native resolution (step 1)")
	check(editor.scene_view.effective_chunk_step(mid) == 2, "mid-range chunk uses 4 m resolution (step 2)")
	check(editor.scene_view.effective_chunk_step(far) == 4, "distant chunk uses 8 m resolution (step 4)")

	# Deferred LOD queue convergence: a single large camera jump queues > 16 chunks,
	# then stationary frames drain the entire queue until every chunk matches desired LOD.
	editor.scene_view.center = editor.scene_view.point_world(Vector2(192, 192))
	editor.scene_view.update_camera()
	var pending_after_jump: int = editor.scene_view.lod_pending_count
	check(pending_after_jump > 0, "large camera jump bounds immediate work and leaves pending LOD chunks queued")
	var rev_before_cancel: int = editor.scene_view.lod_revision
	editor.scene_view.center = editor.scene_view.point_world(Vector2(1035, 1035))
	editor.scene_view.update_camera()
	check(editor.scene_view.lod_revision > rev_before_cancel, "second camera jump supersedes outdated LOD queue revision")
	var drain_frames := 0
	while editor.scene_view.lod_pending_count > 0 and drain_frames < 128:
		editor._process(0.016)
		drain_frames += 1
	check(editor.scene_view.lod_pending_count == 0, "stationary camera drains all pending LOD chunks cleanly")
	var stale_chunks := 0
	for start: Vector2i in editor.scene_view.meshes:
		if editor.scene_view.effective_chunk_step(start) != editor.scene_view.desired_lod_step(start):
			stale_chunks += 1
	check(stale_chunks == 0, "zero stale LOD chunks remain after deferred convergence")
	var rebuilds_before_orbit: int = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.orbit(Vector2(14.0, -6.0))
	editor.scene_view.zoom(0.92)
	check(editor.scene_view.total_chunk_rebuilds == rebuilds_before_orbit, "pure orbit and zoom around stationary focus trigger zero LOD rebuilds")

	# Verify exact native vertices exist in the near 2 m ArrayMesh
	var near_inst: MeshInstance3D = editor.scene_view.meshes[near]
	var arrays: Array = near_inst.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(verts.size() == 65 * 65, "near 2 m chunk has full 65x65 native vertex grid")
	var ridge_v := verts[(1035 - 1024) * 65 + (1035 - 1024)]
	var trench_v := verts[(1035 - 1024) * 65 + (1039 - 1024)]
	var step_v := verts[(1035 - 1024) * 65 + (1046 - 1024)]
	var trans_a := verts[(1035 - 1024) * 65 + (1055 - 1024)]
	var trans_b := verts[(1035 - 1024) * 65 + (1056 - 1024)]
	check(absf(ridge_v.y - 118.0) < 0.01 and absf(trench_v.y - 92.0) < 0.01
		and absf(step_v.y - 112.0) < 0.01 and absf(trans_a.y - 104.0) < 0.01 and absf(trans_b.y - 108.0) < 0.01,
		"near 3D preview geometry preserves 1-sample ridge, 2 m trench, sharp step and 2 m transition")

	# 5) Ordinary 32 m ramp via SlopeShapes on top of the 4096 m LOD terrain (kept clear of (1035, 1035))
	var ramp_ok := doc.preview_slope_shape({
		"start": Vector2(-128.0, -128.0), "end": Vector2(-64.0, -128.0), "start_height": 100.0,
		"mode": "angle", "angle_deg": 15.0, "width_m": 32.0, "falloff_m": 8.0,
	})
	check(ramp_ok, "32 m ramp previews on 4096 m adaptive LOD terrain")
	doc.bake_preview()
	editor._process(0.0)

	# Seam continuity check between a step=1 chunk and an adjacent step=2 chunk
	var fine_chunk := Vector2i(1152, 1024)
	var coarse_chunk := Vector2i(1216, 1024)
	editor.scene_view.chunk_steps[fine_chunk] = 1
	editor.scene_view.chunk_steps[coarse_chunk] = 2
	editor.scene_view.build_chunk(coarse_chunk, 2)
	editor.scene_view.build_chunk(fine_chunk, 1)
	var fine_inst: MeshInstance3D = editor.scene_view.meshes[fine_chunk]
	var coarse_inst: MeshInstance3D = editor.scene_view.meshes[coarse_chunk]
	var fine_verts: PackedVector3Array = fine_inst.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var coarse_verts: PackedVector3Array = coarse_inst.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	# Check odd z=1 along x=1216 (right edge of fine_chunk = index 64) matches midpoint of z=0 and z=2 on coarse_chunk left edge
	var y_mid_fine := fine_verts[1 * 65 + 64].y
	var y_mid_expected := lerpf(coarse_verts[0 * 33 + 0].y, coarse_verts[1 * 33 + 0].y, 0.5)
	check(absf(y_mid_fine - y_mid_expected) < 0.001, "neighbor LOD boundary seam snaps cleanly without cracks")

	# Exact-height inspection and wireframe toggle
	var info: Dictionary = editor.scene_view.exact_sample_info(Vector2(1035.0, 1035.0))
	check(int(info["resolution_m"]) == 2 and absf(float(info["height"]) - 118.0) < 0.01,
		"exact-height inspection reports 2 m LOD and exact native sample height")
	editor.scene_view.set_wireframe(true)
	check(editor.scene_view.viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "wireframe toggle activates")
	editor.scene_view.set_wireframe(false)

	var frame_started := Time.get_ticks_usec()
	await process_frame
	var frame_ms := (Time.get_ticks_usec() - frame_started) / 1000.0
	var mem_mib := OS.get_static_memory_usage() / 1048576.0
	print("4096 m adaptive LOD: bind+focus %.1f ms, frame %.1f ms, static mem %.1f MiB, viewport %s" % [
		bind_ms, frame_ms, mem_mib, str(editor.scene_view.size)])
	editor.free()


func test_sound_point_labels(editor: Control) -> void:
	var point := Document.sound_point("vrvsnd:ding.wav:70:150:0:0:100:20")
	check(point["odf"] == "vrv_sndpoint" and point["sound"] == "ding.wav" and point["volume"] == 70 and point["range"] == 150
		and point["interval"] == 0 and point["jitter"] == 0 and point["pitch"] == 100 and point["near"] == 20,
		"VRV sound labels parse into their seven settings")
	check(Document.sound_point("vrvsnd:bad name.wav:70:150:0:0:100:20").is_empty()
		and Document.sound_point("vrvsnd:ding.mp3:70:150:0:0:100:20").is_empty()
		and Document.sound_point("vrvsnd:ding.wav:70:150:0:0:100").is_empty()
		and Document.sound_point("vrvsnd:ding.wav:seventy:150:0:0:100:20").is_empty()
		and Document.sound_point("sp_farm").is_empty() and Document.sound_point("").is_empty(),
		"sound inspection rejects unsafe names, extensions, partial and non-integer labels")
	check(editor.object_tool.label_suffix("vrvsnd:ding.wav:70:150:0:0:100:20").contains("ding.wav")
		and editor.object_tool.label_suffix("vrvsnd:ding.wav:70:150:0:0:100:20").contains("range 150 m"),
		"the object status renders sound settings")
	check(editor.object_tool.label_suffix("sp_farm") == " · sp_farm", "ordinary labels keep their plain rendering")
	print("VRV sound point inspection verified.")


func test_mission_studio(editor: Control, source: String, scratch: String) -> void:
	check(editor.open_map(source), "reopen Brave for Mission Studio vertical slice")
	var doc: Document = editor.document
	var writer := Snapshots.new()
	var studio = editor.mission_studio
	editor.mission_studio_button.pressed.emit()
	check(studio.visible, "Mission Studio opens from toolbar")
	# 1. Verify decoupled Mod x Mission validation on Brave (VRV Strategy vs Stock Strategy vs VSR Duel)
	var val_vrv: Dictionary = MissionProfiles.validate(doc, "strategy", "vrv")
	var val_stock: Dictionary = MissionProfiles.validate(doc, "strategy", "stock")
	check(val_vrv.has("missing_required") and val_vrv.has("warnings") and val_stock["ok"],
		"Mission validation returns decoupled per-mod profile checks")
	var strat_idx := MissionProfiles.MISSION_MODES.find("strategy")
	studio.profile_select.select(strat_idx)
	studio.refresh_all()
	# 2. Create a missing preset (e.g., Stage1 or unique custom preset) + propose edge_path + clone + multi-select transform + resample + snap.
	var base_count := doc.path_indices().size()
	var stage_idx := -1
	for i in studio.preset_list.item_count:
		if String(studio.preset_list.get_item_metadata(i)) == "Stage1":
			stage_idx = i
			break
	if stage_idx >= 0 and not doc.path_indices().any(func(i: int): return String(doc.path_at(i)["name"]).nocasecmp_to("Stage1") == 0):
		studio.preset_list.select(stage_idx)
		studio.create_selected_preset()
	else:
		studio.create_proposed_edge_path()
	var after_create := doc.path_indices().size()
	check(after_create >= base_count, "Mission Studio creates or updates preset path on native AiPath stream")
	# Multi-select two paths, transform (translate + rotate) in 1 undo step, and verify 2D/3D extra_paths render.
	studio.refresh_all()
	check(studio.path_list.item_count >= 2, "Mission Studio lists map paths")
	studio.path_list.select(0, true)
	studio.path_list.select(1, false)
	studio.emit_selection()
	check(editor.top.extra_paths.size() >= 1 and editor.scene_view.extra_paths.size() >= 1,
		"multi-selected secondary path renders in both 2D and 3D views")
	var first_idx: int = studio.selected_path_indices()[0]
	var pts_before: PackedVector2Array = doc.path_at(first_idx)["points"].duplicate()
	var stack_before := doc.undo_stack.size()
	studio.delta_x.value = 16.0
	studio.delta_z.value = -8.0
	studio.rotate_deg.value = 15.0
	studio.apply_transform()
	check(doc.undo_stack.size() == stack_before + 1, "multi-path transform commits as one undo step")
	check(doc.path_at(first_idx)["points"] != pts_before, "multi-path transform updates points")
	doc.undo()
	check(doc.path_at(first_idx)["points"] == pts_before, "undo restores pre-transform path points")
	doc.redo()
	check(doc.path_at(first_idx)["points"] != pts_before, "redo re-applies multi-path transform")
	# Mirror, clone, resample, snap
	studio.apply_mirror(true, false)
	studio.clone_selected_path()
	var cloned_count := doc.path_indices().size()
	check(cloned_count == after_create + 1, "cloning selected path adds a unique native AiPath")
	studio.spacing_m.value = 48.0
	studio.apply_resample()
	studio.apply_snap_grid()
	var snapped_pts: PackedVector2Array = doc.path_at(first_idx)["points"]
	for pt in snapped_pts:
		check(absf(pt.x - snappedf(pt.x, 2.0)) < 0.001 and absf(pt.y - snappedf(pt.y, 2.0)) < 0.001,
			"2 m grid snap aligns path coordinates")
		break
	# Validation catches missing spawns & team mismatch on VSR Duel profile
	var duel_val: Dictionary = MissionProfiles.validate(doc, "duel", "vsr")
	check(not duel_val["ok"] and not (duel_val["missing_required"] as Array).is_empty(),
		"VSR Duel profile reports missing Player_2 spawn on Strategy map")
	# BZMAG save/reopen + native export + independent reimport
	var proj := scratch.path_join("mission-studio.bzmag")
	check(writer.save_project(doc, proj), "save Mission Studio project")
	var reopened := Document.new()
	check(reopened.open(proj) and reopened.path_indices().size() == cloned_count,
		"reopen Mission Studio project with identical path count")
	var exp_dir := scratch.path_join("mission-studio-export")
	check(writer.export_native(reopened, exp_dir), "export Mission Studio BZN: " + writer.error)
	var reimported := Document.new()
	check(reimported.open(exp_dir.path_join(reopened.package.bzn_name)) and reimported.path_indices().size() == cloned_count,
		"independently reimport exported Mission Studio BZN")
	studio.hide()
	print("Mission & Path Studio vertical slice verified (%d paths)." % cloned_count)


func test_vrv_parity_wave7(editor: Control, source: String, scratch: String) -> void:
	check(editor.open_map(source), "reopen Brave for Wave 7 parity suite")
	var doc: Document = editor.document
	var writer := Snapshots.new()
	var terrain := doc.package.terrain
	var w := terrain.dimensions.x
	var d := terrain.dimensions.y

	# 1. VRV Smooth / Rough / Relief parity + deterministic seed + symmetry + Undo/Redo + native TER export
	var h0 := terrain.heights.duplicate()
	var tools = editor.terrain_tools
	tools.begin(doc, Vector2i(w / 2, d / 2), 64.0)
	tools.operation.select(2) # VRV Smooth
	tools.choose_operation(2)
	tools.vrv_scope.select(1) # Whole map
	tools.vrv_strength.value = 50.0
	tools.vrv_grain.value = 16.0
	check(tools.preview_plane() and doc.has_preview() and not doc.preview_after.is_empty(),
		"VRV Smooth produces non-empty preview")
	var stack_before := doc.undo_stack.size()
	tools.apply_terrain()
	check(doc.undo_stack.size() == stack_before + 1 and not doc.has_preview(),
		"VRV Smooth applies in 1 undo step and clears preview")
	check(terrain.heights != h0, "VRV Smooth updates heightfield")
	doc.undo()
	check(terrain.heights == h0, "Undo restores pre-Smooth heightfield cleanly")
	doc.redo()
	check(terrain.heights != h0, "Redo re-applies VRV Smooth")

	# Rough +/- determinism + XZ symmetry on a flat buffer
	var flat := PackedFloat32Array()
	flat.resize(32 * 32)
	flat.fill(10.0)
	var r1: Dictionary = VrvShapes.rough(flat, Vector2i(32, 32), Vector2i.ZERO, Rect2i(), 60, 16, 50, 35, 42, 1, "xz", 0.1, 1000.0)
	var r2: Dictionary = VrvShapes.rough(flat, Vector2i(32, 32), Vector2i.ZERO, Rect2i(), 60, 16, 50, 35, 42, 1, "xz", 0.1, 1000.0)
	var r_diff: Dictionary = VrvShapes.rough(flat, Vector2i(32, 32), Vector2i.ZERO, Rect2i(), 60, 16, 50, 35, 99, 1, "xz", 0.1, 1000.0)
	var r_neg: Dictionary = VrvShapes.rough(flat, Vector2i(32, 32), Vector2i.ZERO, Rect2i(), 60, 16, 50, 35, 42, -1, "xz", 0.1, 1000.0)
	check(not r1.is_empty() and r1 == r2 and r1 != r_diff and r1 != r_neg,
		"VRV Rough +/- is deterministic by seed and flips sign cleanly")
	var sym_ok := true
	for z in 16:
		for x in 16:
			var a: float = float(r1.get(z * 32 + x, 10.0))
			var b: float = float(r1.get(z * 32 + (31 - x), 10.0))
			var c: float = float(r1.get((31 - z) * 32 + x, 10.0))
			if absf(a - b) > 0.001 or absf(a - c) > 0.001:
				sym_ok = false
				break
		if not sym_ok:
			break
	check(sym_ok, "VRV Rough XZ symmetry mirrors noise cleanly across both axes")

	# Rough + and Relief +/- through document preview/bake on Brave (cursor region keeps test fast)
	var sub_region := Rect2i(maxi(0, w / 2 - 32), maxi(0, d / 2 - 32), mini(64, w), mini(64, d))
	check(doc.preview_vrv_shape("rough_plus", {"strength": 30, "grain_m": 16, "seed": 7, "symmetry": "none"}, sub_region),
		"Document VRV Rough + previews cleanly")
	doc.bake_preview()
	var after_rough := terrain.heights[w / 2 * w + w / 2]
	check(doc.preview_vrv_shape("relief_plus", {"strength": 40}, sub_region),
		"Document VRV Relief + previews cleanly on sub-region")
	doc.bake_preview()
	check(doc.preview_vrv_shape("relief_minus", {"strength": 25}, sub_region),
		"Document VRV Relief - previews cleanly on sub-region")
	doc.bake_preview()
	tools.hide()
	check(is_finite(after_rough), "VRV shapes leave finite terrain samples")

	# 2. Sound Point semantic gating, Generic Object Label Editor, atomic Sound Point duplication
	check(Document.format_sound_point({"sound": "bad name.wav", "volume": 70, "range": 150, "interval": 0, "jitter": 0, "pitch": 100, "near": 20})["label"] == "",
		"format_sound_point rejects unsafe spaces")
	var fmt := Document.format_sound_point({"sound": "ambient.wav", "volume": 80, "range": 300, "interval": 15, "jitter": 10, "pitch": 110, "near": 25})
	check(fmt["label"] == "vrvsnd:ambient.wav:80:300:15:10:110:25", "format_sound_point builds exact vrvsnd label")
	check(Document.is_sound_point_odf("vrv_sndpoint") and Document.is_sound_point_odf("VRV_SNDPOINT.odf")
		and not Document.is_sound_point_odf("morock03") and not Document.is_sound_point_odf("ivscout_vsr"),
		"is_sound_point_odf accepts only vrv_sndpoint")

	# 2a. Opening Sound Editor with NO selection never substitutes object 0
	editor.object_tool.selected = -1
	editor.open_sound_editor()
	var se = editor.sound_editor
	check(se.selected_view == -1 and se.get_ok_button().disabled and se.duplicate_btn.disabled,
		"open_sound_editor without selection never auto-selects object 0")
	se.hide()

	# 2b. Selecting an ordinary non-sound-point object refuses Sound Point edits and duplication
	var non_snd_view := 0
	var orig_label := doc.object_label(non_snd_view)
	var base_objs := doc.object_count()
	var undo_before_refuse := doc.undo_stack.size()
	se.begin(doc, non_snd_view)
	check(se.get_ok_button().disabled and se.duplicate_btn.disabled and se.asset_status.text.contains("Incompatible ODF"),
		"Sound Point dialog disables apply/duplicate on non-vrv_sndpoint object")
	se.sound_field.text = "ambient.wav"
	se.apply_sound_point()
	se.duplicate_sound_point()
	check(doc.object_label(non_snd_view) == orig_label and doc.object_count() == base_objs and doc.undo_stack.size() == undo_before_refuse,
		"Sound Point dialog never modifies or duplicates an incompatible object")
	check(not doc.set_sound_point_label(non_snd_view, "vrvsnd:ambient.wav:80:300:15:10:110:25"),
		"MapDocument.set_sound_point_label refuses non-vrv_sndpoint object")
	check(doc.duplicate_sound_point(non_snd_view, doc.object_position(non_snd_view) + Vector3(8, 0, 8), "vrvsnd:ambient.wav:80:300:15:10:110:25") < 0,
		"MapDocument.duplicate_sound_point refuses non-vrv_sndpoint object")
	se.hide()

	# 2c. Generic Object Label Editor edits ordinary object names cleanly with Undo/Redo
	editor.object_tool.selected = non_snd_view
	editor.open_object_label_editor()
	editor.object_label_field.text = "scout_alpha"
	editor.apply_object_label_dialog()
	check(doc.object_label(non_snd_view) == "scout_alpha", "Generic Object Label editor updates ordinary object label")
	doc.undo()
	check(doc.object_label(non_snd_view) == orig_label, "Undo restores ordinary object label")
	doc.redo()
	check(doc.object_label(non_snd_view) == "scout_alpha", "Redo re-applies ordinary object label")

	# 2d. Real vrv_sndpoint fixture: structured Sound Point edit, atomic duplicate, picker, BZMAG & native BZN reimport
	var snd_dir := scratch.path_join("wave7-sndpoint-src")
	DirAccess.make_dir_recursive_absolute(snd_dir)
	var src_folder := source.get_base_dir()
	for member: String in doc.package.files:
		DirAccess.copy_absolute(src_folder.path_join(member), snd_dir.path_join(member))
	var snd_bzn_path := snd_dir.path_join(doc.package.bzn_name)
	var raw_bzn := FileAccess.get_file_as_bytes(snd_bzn_path)
	var raw_paths := BznPaths.new()
	check(raw_paths.read(raw_bzn, 1196), "read Brave paths to craft private vrv_sndpoint fixture")
	var raw_objs := BznObjects.new()
	check(raw_objs.read(raw_bzn, 1196, raw_paths.table_start), "read Brave objects to craft private vrv_sndpoint fixture")
	var tpl_entry: Dictionary = raw_objs.objects[15].duplicate()
	tpl_entry["odf"] = "vrv_sndpoint"
	var ptr_counts := raw_paths.pointer_counts(raw_bzn)
	var snd_ptr := Snapshots.allocate_unique_pointer_id(ptr_counts, 900000)
	var snd_seq := (int(tpl_entry["sequence"]) & ~0x800000) + 100
	var snd_block := BznObjects.build_block(raw_bzn, tpl_entry, snd_seq, "vrvsnd:wind.wav:60:120:0:0:100:20", tpl_entry["transform"], snd_ptr)
	var snd_patch := BznObjects.patch_objects(raw_bzn, raw_objs.objects, {}, [], [snd_block], raw_objs.count_offset, raw_objs.insert_offset)
	check(not snd_patch.is_empty(), "patch private Brave copy with one vrv_sndpoint object")
	var snd_out := FileAccess.open(snd_bzn_path, FileAccess.WRITE)
	snd_out.store_buffer(snd_patch["bytes"])
	snd_out.close()

	var snd_doc := Document.new()
	check(snd_doc.open(snd_bzn_path), "open private map containing genuine vrv_sndpoint: " + snd_doc.error)
	var snd_views := snd_doc.sound_point_views()
	check(snd_views.size() == 1, "sound_point_views discovers exactly the vrv_sndpoint object")
	var snd_view := snd_views[0]
	var snd_base_count := snd_doc.object_count()
	var snd_base_paths := snd_doc.path_indices().size()

	# Incompatible selection offers picker to switch to existing sound point
	se.begin(snd_doc, 0)
	check(se.get_ok_button().disabled and se.existing_row.visible and se.existing_select.item_count == 1,
		"incompatible selection offers picker for existing vrv_sndpoint")
	se.select_chosen_sound_point()
	check(se.selected_view == snd_view and not se.get_ok_button().disabled and not se.duplicate_btn.disabled,
		"selecting existing sound point enables Sound Point editor")
	se.sound_field.text = "ambient.wav"
	se.volume_spin.value = 80
	se.range_spin.value = 300
	se.interval_spin.value = 15
	se.jitter_spin.value = 10
	se.pitch_spin.value = 110
	se.near_spin.value = 25
	se.apply_sound_point()
	check(snd_doc.object_label(snd_view) == "vrvsnd:ambient.wav:80:300:15:10:110:25",
		"Sound Point dialog updates vrv_sndpoint label cleanly")
	snd_doc.undo()
	check(snd_doc.object_label(snd_view) == "vrvsnd:wind.wav:60:120:0:0:100:20", "Undo restores original vrv_sndpoint label")
	snd_doc.redo()
	check(snd_doc.object_label(snd_view) == "vrvsnd:ambient.wav:80:300:15:10:110:25", "Redo re-applies vrv_sndpoint label")

	# Failed atomic duplicate leaves zero orphan objects and zero history entries
	var stack_before_bad_dup := snd_doc.undo_stack.size()
	check(snd_doc.duplicate_sound_point(snd_view, snd_doc.object_position(snd_view) + Vector3(8, 0, 8), "not_a_sound_label") < 0,
		"duplicate_sound_point rejects invalid sound label syntax")
	check(snd_doc.object_count() == snd_base_count and snd_doc.undo_stack.size() == stack_before_bad_dup,
		"failed duplicate_sound_point leaves no partial object or history entry")

	# Atomic valid duplicate commits in ONE undo step and preserves vrv_sndpoint class
	var stack_before_dup := snd_doc.undo_stack.size()
	se.begin(snd_doc, snd_view)
	se.sound_field.text = "rain.ogg"
	se.duplicate_sound_point()
	check(snd_doc.object_count() == snd_base_count + 1 and snd_doc.undo_stack.size() == stack_before_dup + 1,
		"Duplicate Sound Point commits object + label in one atomic undo step")
	check(snd_doc.object_odf(snd_base_count) == "vrv_sndpoint"
		and snd_doc.object_label(snd_base_count) == "vrvsnd:rain.ogg:80:300:15:10:110:25",
		"duplicated sound point preserves vrv_sndpoint class and requested vrvsnd label")
	# Duplicating an already-added sound point also works cleanly (regression for entry['template'] bug)
	var dup2 := snd_doc.duplicate_sound_point(snd_base_count, snd_doc.object_position(snd_base_count) + Vector3(8, 0, 8),
		"vrvsnd:wind.wav:50:100:0:0:100:20")
	check(dup2 == snd_base_count + 1 and snd_doc.object_odf(dup2) == "vrv_sndpoint",
		"duplicating an already-added sound point preserves its base template")
	snd_doc.undo()
	check(snd_doc.object_count() == snd_base_count + 1, "single Undo removes second duplicated sound point")
	snd_doc.undo()
	check(snd_doc.object_count() == snd_base_count, "single Undo atomically removes first duplicated sound point")
	snd_doc.redo()
	check(snd_doc.object_count() == snd_base_count + 1 and snd_doc.object_label(snd_base_count) == "vrvsnd:rain.ogg:80:300:15:10:110:25",
		"single Redo restores duplicated sound point and its label")
	se.hide()

	var proj := scratch.path_join("wave7-sound.bzmag")
	check(writer.save_project(snd_doc, proj), "save Wave 7 sound point BZMAG project")
	var reopened := Document.new()
	check(reopened.open(proj) and reopened.object_label(snd_view) == "vrvsnd:ambient.wav:80:300:15:10:110:25"
		and reopened.object_count() == snd_base_count + 1 and reopened.object_label(snd_base_count) == "vrvsnd:rain.ogg:80:300:15:10:110:25",
		"BZMAG project round-trips edited and duplicated Sound Point labels")
	var exp_dir := scratch.path_join("wave7-export")
	check(writer.export_native(reopened, exp_dir), "export Wave 7 native TER+BZN: " + writer.error)
	var reimported := Document.new()
	check(reimported.open(exp_dir.path_join(reopened.package.bzn_name)),
		"independently reimport Wave 7 native package")
	check(reimported.object_count() == snd_base_count + 1 and reimported.path_indices().size() == snd_base_paths,
		"native BZN export preserves duplicated sound point count and shifted AiPath stream")
	check(reimported.object_odf(snd_view) == "vrv_sndpoint" and reimported.object_odf(snd_base_count) == "vrv_sndpoint"
		and reimported.object_label(snd_view) == "vrvsnd:ambient.wav:80:300:15:10:110:25"
		and reimported.object_label(snd_base_count) == "vrvsnd:rain.ogg:80:300:15:10:110:25",
		"native BZN export round-trips both vrv_sndpoint records and labels")

	# Regression (T-19): duplicating a labeled object and clearing its label exports and re-imports cleanly
	var clear_doc := Document.new()
	check(clear_doc.open(snd_bzn_path), "reopen vrv_sndpoint fixture for empty-label addition check")
	var dup_clear := clear_doc.duplicate_object(snd_view, clear_doc.object_position(snd_view) + Vector3(8, 0, 8))
	check(dup_clear >= 0 and clear_doc.set_object_label(dup_clear, ""), "duplicate labeled object and clear its label")
	check((clear_doc.object_sequence(dup_clear) & 0x800000) != 0, "empty-label added object sets 0x800000 sequence bit")
	var clear_exp := scratch.path_join("wave7-clear-added-label")
	check(writer.export_native(clear_doc, clear_exp), "export added object with cleared label: " + writer.error)
	var clear_reimp := Document.new()
	check(clear_reimp.open(clear_exp.path_join(clear_doc.package.bzn_name)) and clear_reimp.object_label(dup_clear) == "",
		"reimport added object with cleared label intact")

	# 3. Wintage theme registry + compact mode + ConfigFile persistence + toolbar search
	var saved_cfg_path: String = editor.settings_path
	editor.settings_path = scratch.path_join("wave7-editor.cfg")
	for slug: String in Wintage.theme_slugs():
		editor.set_wintage_theme(slug, true)
		check(editor.theme_slug == slug and editor.ui_compact and editor.backdrop.color == Wintage.palette(slug)["background"],
			"Wintage theme '%s' updates palette and compact state" % slug)
	var cfg := ConfigFile.new()
	check(cfg.load(editor.settings_path) == OK and String(cfg.get_value("ui", "theme", "")) == "nord"
		and bool(cfg.get_value("ui", "compact", false)),
		"Wintage theme choice persists to ConfigFile")
	editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
	editor.settings_path = saved_cfg_path

	editor.filter_toolbar("Slope")
	check(editor.slope_studio_button.visible and not editor.undo_button.visible,
		"toolbar search narrows visible commands")
	editor.filter_toolbar("")
	check(editor.slope_studio_button.visible and editor.undo_button.visible,
		"clearing toolbar search restores all toolbar buttons")
	print("Wave 7 VRV shapes, Sound Point editor & Wintage UI polish verified.")


func test_batch_path_collisions(editor: Control, source: String, scratch: String) -> void:
	check(editor.open_map(source), "reopen Brave for batch path collision checks")
	var doc: Document = editor.document
	var writer := Snapshots.new()
	var idx_a := doc.create_path("BatchAlpha", PackedVector2Array([Vector2(10.0, 10.0), Vector2(30.0, 10.0)]), 0)
	var idx_b := doc.create_path("BatchBeta", PackedVector2Array([Vector2(10.0, 30.0), Vector2(30.0, 30.0)]), 0)
	check(idx_a >= 0 and idx_b >= 0, "create two fresh paths for batch collision tests")
	var p_a := doc.path_at(idx_a)
	var p_b := doc.path_at(idx_b)
	var stack_before := doc.undo_stack.size()

	# 1. Two paths renamed to same target name -> REFUSE
	check(not doc.edit_paths_batch([
		{"index": idx_a, "name": "BatchGamma", "points": p_a["points"], "type": 0},
		{"index": idx_b, "name": "BatchGamma", "points": p_b["points"], "type": 0},
	]), "batch refuses renaming two paths to the same target name")
	check(doc.undo_stack.size() == stack_before and doc.path_at(idx_a)["name"] == "BatchAlpha" and doc.path_at(idx_b)["name"] == "BatchBeta",
		"refused identical-name batch leaves document and history untouched")

	# 2. Case-insensitive collision -> REFUSE
	check(not doc.edit_paths_batch([
		{"index": idx_a, "name": "BatchGamma", "points": p_a["points"], "type": 0},
		{"index": idx_b, "name": "batchgamma", "points": p_b["points"], "type": 0},
	]), "batch refuses case-insensitive target name collision")
	check(doc.undo_stack.size() == stack_before, "refused case-insensitive collision adds no history entry")

	# 3. Duplicate index in batch -> REFUSE
	check(not doc.edit_paths_batch([
		{"index": idx_a, "name": "BatchAlpha1", "points": p_a["points"], "type": 0},
		{"index": idx_a, "name": "BatchAlpha2", "points": p_a["points"], "type": 0},
	]), "batch refuses duplicate path index")
	check(doc.undo_stack.size() == stack_before and doc.path_at(idx_a)["name"] == "BatchAlpha",
		"refused duplicate-index batch leaves document untouched")

	# 4. Invalid point rejects entire batch
	check(not doc.edit_paths_batch([
		{"index": idx_a, "name": "BatchValid", "points": p_a["points"], "type": 0},
		{"index": idx_b, "name": "BatchInvalid", "points": PackedVector2Array([Vector2(NAN, 0.0)]), "type": 0},
	]), "batch with one invalid point rejects the entire batch")
	check(doc.undo_stack.size() == stack_before and doc.path_at(idx_a)["name"] == "BatchAlpha",
		"rejected invalid-point batch leaves first item untouched")

	# 5. Dropping a mission-referenced source path name (edge_path) -> REFUSE
	var edge := doc.path_at(0)
	check(edge["name"] == "edge_path", "path 0 is mission-referenced edge_path")
	check(not doc.edit_paths_batch([
		{"index": 0, "name": "renamed_edge_missing", "points": edge["points"], "type": int(edge["type"])},
	]), "batch refuses dropping mission-referenced edge_path")
	check(doc.undo_stack.size() == stack_before and doc.path_at(0)["name"] == "edge_path",
		"refused mission-reference drop leaves edge_path intact")

	# 6. Swapping names between two paths in one batch -> ALLOW + atomic Undo/Redo + BZMAG + native BZN reimport
	check(doc.edit_paths_batch([
		{"index": idx_a, "name": "BatchBeta", "points": p_a["points"], "type": 0},
		{"index": idx_b, "name": "BatchAlpha", "points": p_b["points"], "type": 0},
	]), "batch allows two paths to swap names atomically: " + doc.error)
	check(doc.undo_stack.size() == stack_before + 1 and doc.path_at(idx_a)["name"] == "BatchBeta" and doc.path_at(idx_b)["name"] == "BatchAlpha",
		"swapped path names commit as one undo entry")
	doc.undo()
	check(doc.path_at(idx_a)["name"] == "BatchAlpha" and doc.path_at(idx_b)["name"] == "BatchBeta",
		"single Undo reverses swapped path names")
	doc.redo()
	check(doc.path_at(idx_a)["name"] == "BatchBeta" and doc.path_at(idx_b)["name"] == "BatchAlpha",
		"single Redo re-applies swapped path names")

	var proj := scratch.path_join("batch-swap.bzmag")
	check(writer.save_project(doc, proj), "save batch-swap BZMAG project")
	var reopened := Document.new()
	check(reopened.open(proj) and reopened.path_at(idx_a)["name"] == "BatchBeta" and reopened.path_at(idx_b)["name"] == "BatchAlpha",
		"BZMAG round-trips swapped path names")
	var exp_dir := scratch.path_join("batch-swap-export")
	check(writer.export_native(reopened, exp_dir), "export batch-swap native BZN: " + writer.error)
	var reimported := Document.new()
	check(reimported.open(exp_dir.path_join(reopened.package.bzn_name)), "reimport batch-swap native BZN")
	var names := {}
	for i in reimported.path_indices():
		names[String(reimported.path_at(i)["name"])] = true
	check(names.has("BatchBeta") and names.has("BatchAlpha"), "native BZN reimport preserves swapped path names")
	print("Batch path collision and swap checks verified.")


func test_empty_object_table(brave_source: String, blank_source: String, scratch: String) -> void:
	# Build a genuinely framed 1-object 1192 package (blank BZN + companion TER) and remove its last object
	# through the real codec/exporter to obtain an organically framed 0-object BZN.
	var one_dir := scratch.path_join("empty-obj-one")
	DirAccess.make_dir_recursive_absolute(one_dir)
	var blank_folder := blank_source.get_base_dir()
	var blank_stem := blank_source.get_file().get_basename()
	for ext in ["bzn", "trn", "inf"]:
		DirAccess.copy_absolute(blank_folder.path_join("%s.%s" % [blank_stem, ext]), one_dir.path_join("%s.%s" % [blank_stem, ext]))
	var brave_ter := brave_source.get_base_dir().path_join(brave_source.get_file().get_basename() + ".ter")
	DirAccess.copy_absolute(brave_ter, one_dir.path_join("%s.ter" % blank_stem))

	var one_bzn_path := one_dir.path_join(blank_source.get_file())
	var one_doc := Document.new()
	check(one_doc.open(one_bzn_path) and one_doc.object_count() == 1, "open private 1-object 1192 fixture: " + one_doc.error)
	var orig_bzn_bytes := FileAccess.get_file_as_bytes(one_bzn_path)
	var orig_entry: Dictionary = one_doc.package.objects[0]
	var orig_paths_count := one_doc.path_indices().size()

	# 1. Remove last object -> export genuinely framed 0-object BZN -> reimport
	check(one_doc.remove_object(0) and one_doc.object_count() == 0, "remove the last object from 1-object 1192 map")
	var writer := Snapshots.new()
	var zero_dir := scratch.path_join("empty-obj-zero")
	check(writer.export_native(one_doc, zero_dir), "export 0-object 1192 BZN: " + writer.error)
	var zero_bzn_path := zero_dir.path_join(blank_source.get_file())
	var zero_bytes := FileAccess.get_file_as_bytes(zero_bzn_path)
	var zero_paths := BznPaths.new()
	check(zero_paths.read(zero_bytes, 1192) and zero_paths.paths.size() == orig_paths_count,
		"0-object BZN preserves all 23 native paths")
	var zero_objs := BznObjects.new()
	check(zero_objs.read(zero_bytes, 1192, zero_paths.table_start) and zero_objs.object_count == 0 and zero_objs.objects.is_empty(),
		"BznObjects.read accepts genuinely framed 0-object BZN")

	# 2. Open 0-object package + no-op export (byte-identical)
	var zero_doc := Document.new()
	check(zero_doc.open(zero_bzn_path) and zero_doc.object_count() == 0, "MapDocument opens 0-object BZN cleanly")
	var zero_noop_dir := scratch.path_join("empty-obj-zero-noop")
	check(writer.export_native(zero_doc, zero_noop_dir), "no-op export on 0-object BZN: " + writer.error)
	check(FileAccess.get_file_as_bytes(zero_noop_dir.path_join(blank_source.get_file())) == zero_bytes,
		"0-object no-op export is byte-identical")

	# 3. Direct patch_objects on 0-object BZN: add first object -> prefix, header, count, groupTargets, paths preserved!
	var first_block := BznObjects.build_block(orig_bzn_bytes, orig_entry, int(orig_entry["sequence"]), String(orig_entry["label"]), orig_entry["transform"], int(orig_entry["flag8"]))
	var patched_zero := BznObjects.patch_objects(zero_bytes, zero_objs.objects, {}, [], [first_block], zero_objs.count_offset, zero_objs.insert_offset)
	check(not patched_zero.is_empty(), "patch_objects inserts first object into an empty object table")
	var rebuilt_bytes: PackedByteArray = patched_zero["bytes"]
	check(rebuilt_bytes.slice(0, zero_objs.count_offset) == zero_bytes.slice(0, zero_objs.count_offset),
		"empty-table insertion preserves BZN header and mission prefix byte-for-byte")
	check(rebuilt_bytes.decode_u32(zero_objs.count_offset) == 1, "empty-table insertion patches object count 0 -> 1")
	var rebuilt_paths := BznPaths.new()
	check(rebuilt_paths.read(rebuilt_bytes, 1192) and rebuilt_paths.paths.size() == orig_paths_count,
		"empty-table insertion preserves AiPath table and trailer")
	var rebuilt_objs := BznObjects.new()
	check(rebuilt_objs.read(rebuilt_bytes, 1192, rebuilt_paths.table_start) and rebuilt_objs.objects.size() == 1
		and rebuilt_objs.objects[0]["odf"] == orig_entry["odf"],
		"re-inserted first object round-trips cleanly through BznObjects.read")
	check(rebuilt_bytes.slice(rebuilt_objs.insert_offset, rebuilt_paths.table_start) == zero_bytes.slice(zero_objs.insert_offset, zero_paths.table_start),
		"empty-table insertion preserves 640-byte groupTargets and mission DLL framing")

	# 4. Add after remove-all (duplicate template 0 then remove base 0) + BZMAG + native export/reimport
	var add_after_doc := Document.new()
	check(add_after_doc.open(one_bzn_path), "reopen 1-object map for add-after-remove-all check")
	var dup_view := add_after_doc.duplicate_object(0, add_after_doc.object_position(0) + Vector3(8, 0, 8))
	check(dup_view == 1 and add_after_doc.remove_object(0) and add_after_doc.object_count() == 1,
		"duplicate then remove original base object leaves 1 added object")
	var aar_proj := scratch.path_join("empty-obj-aar.bzmag")
	check(writer.save_project(add_after_doc, aar_proj), "save BZMAG with added object whose base template was removed")
	var aar_reopened := Document.new()
	check(aar_reopened.open(aar_proj) and aar_reopened.object_count() == 1,
		"reopen BZMAG with added object whose base template was removed")
	var aar_exp := scratch.path_join("empty-obj-aar-export")
	check(writer.export_native(aar_reopened, aar_exp), "export add-after-remove-all BZN: " + writer.error)
	var aar_reimp := Document.new()
	check(aar_reimp.open(aar_exp.path_join(blank_source.get_file())) and aar_reimp.object_count() == 1,
		"reimport add-after-remove-all native BZN")

	# 5. Empty path table + object table insertion/removal
	var empty_paths_bzn := zero_bytes.duplicate()
	var ep_codec := BznPaths.new()
	check(ep_codec.read(empty_paths_bzn, 1192), "read paths for empty-path-table test")
	var rm_all_paths := {}
	for i in ep_codec.paths.size():
		rm_all_paths[i] = {}
	var zero_both := ep_codec.patch(empty_paths_bzn, rm_all_paths)
	var zb_paths := BznPaths.new()
	var zb_objs := BznObjects.new()
	check(zb_paths.read(zero_both, 1192) and zb_paths.paths.is_empty(), "empty path table reads cleanly with 0 paths")
	check(zb_objs.read(zero_both, 1192, zb_paths.table_start) and zb_objs.objects.is_empty(),
		"0-object + 0-path BZN reads cleanly")
	var zb_patched := BznObjects.patch_objects(zero_both, zb_objs.objects, {}, [], [first_block], zb_objs.count_offset, zb_objs.insert_offset)
	var zb_paths2 := BznPaths.new()
	var zb_objs2 := BznObjects.new()
	check(not zb_patched.is_empty() and zb_paths2.read(zb_patched["bytes"], 1192) and zb_paths2.paths.is_empty()
		and zb_objs2.read(zb_patched["bytes"], 1192, zb_paths2.table_start) and zb_objs2.objects.size() == 1,
		"inserting first object on 0-object + 0-path BZN re-reads cleanly")

	# 6. Pointer ID exhaustion / wraparound and MAX_OBJECTS limit checks
	var full_used := {4294967294: 1, 4294967295: 1, 1: 1}
	check(Snapshots.allocate_unique_pointer_id(full_used, 4294967294, 16) == 2,
		"pointer ID allocator wraps cleanly past u32 max and skips used IDs")
	var exhausted := {1: 1, 2: 1, 3: 1, 4: 1}
	check(Snapshots.allocate_unique_pointer_id(exhausted, 1, 4) == -1,
		"pointer ID allocator reports exhaustion cleanly instead of colliding")
	var too_many: Array = []
	for _i in range(BznObjects.MAX_OBJECTS + 1):
		too_many.append(PackedByteArray([1]))
	check(BznObjects.patch_objects(zero_bytes, zero_objs.objects, {}, [], too_many, zero_objs.count_offset, zero_objs.insert_offset).is_empty(),
		"patch_objects refuses exceeding MAX_OBJECTS")
	print("Empty object table, empty path table and pointer exhaustion checks verified.")


func test_universal_mod_architecture(editor: Control, brave_source: String, blank_source: String, scratch: String) -> void:
	# 1. Built-in ModRegistry manifests keep Stock, VSR (1325933293) and VRV (3820486276) strictly separate
	var reg := ModRegistry.new()
	check(reg.has_profile("stock") and reg.has_profile("vsr") and reg.has_profile("vrv"),
		"ModRegistry provides separate stock, vsr and vrv profiles")
	check(String(reg.get_profile("vsr")["workshopId"]) == "1325933293"
		and String(reg.get_profile("vrv")["workshopId"]) == "3820486276",
		"VSR and VRV carry distinct verified Workshop IDs")
	check(ModRegistry.validate_manifest(reg.get_profile("stock")).is_empty()
		and ModRegistry.validate_manifest(reg.get_profile("vsr")).is_empty()
		and ModRegistry.validate_manifest(reg.get_profile("vrv")).is_empty(),
		"built-in mod profiles pass schema validation")

	# 2. Synthetic Workshop discovery (VSR + VRV + Unknown custom Workshop mod) + cycle detection
	var fake_ws := scratch.path_join("fake-workshop")
	for spec in [
		{"id": "1325933293", "name": "Vet Strat Recycler Variant", "type": "config", "deps": "3532748119", "dll": "Strategy02.dll"},
		{"id": "3532748119", "name": "VSR Asset Pack", "type": "asset", "deps": "", "dll": ""},
		{"id": "3820486276", "name": "VRV - Vacuum Recycler Variant", "type": "config", "deps": "3532748119", "dll": "Strategy02.dll"},
		{"id": "9990001111", "name": "Custom Arena Mod", "type": "config", "deps": "", "dll": "ArenaCustom.dll"},
	]:
		var d := fake_ws.path_join(String(spec["id"]))
		DirAccess.make_dir_recursive_absolute(d)
		var f := FileAccess.open(d.path_join(String(spec["id"]) + ".ini"), FileAccess.WRITE)
		f.store_string("[WORKSHOP]\nmodName = \"%s\"\nmodType = \"%s\"\nassetDependencies = \"%s\"\n" % [
			spec["name"], spec["type"], spec["deps"]])
		f.close()
		if not String(spec["dll"]).is_empty():
			var mdir := d.path_join("Missions")
			DirAccess.make_dir_recursive_absolute(mdir)
			var df := FileAccess.open(mdir.path_join(String(spec["dll"])), FileAccess.WRITE)
			df.store_buffer(PackedByteArray([77, 90]))
			df.close()
	var disc := reg.discover_installed("", "", fake_ws)
	check(int(disc["count"]) >= 4 and (disc["cycles"] as Array).is_empty(),
		"Workshop discovery finds built-ins plus unknown Workshop mod with zero cycles")
	check(bool(reg.get_profile("vsr")["installed"]) and bool(reg.get_profile("vrv")["installed"])
		and reg.has_profile("custom:ws-9990001111"),
		"discovery populates VSR, VRV and custom Workshop mod independently")
	var custom_res := reg.register_custom_mod("cycle_a", "Cycle A", fake_ws, ["custom:cycle_b"])
	var custom_res2 := reg.register_custom_mod("cycle_b", "Cycle B", fake_ws, ["custom:cycle_a"])
	check(not custom_res.has("error") and not custom_res2.has("error") and not reg.detect_dependency_cycles().is_empty(),
		"dependency graph detects cycles cleanly")

	# 3. Stock-first native flat map creation WITHOUT VRV templates
	var flat_bytes := Terrain.create_flat(Vector2i(-256, -256), Vector2i(512, 512), 100.0, 0)
	var flat_ter := Terrain.new()
	check(flat_ter.decode(flat_bytes) and flat_ter.dimensions == Vector2i(512, 512) and absf(flat_ter.min_height - 100.0) < 0.001,
		"Terrain.create_flat generates a valid native TER v5 without VRV")
	var stock_out := scratch.path_join("stock-native-new")
	var writer := Snapshots.new()
	check(writer.create_native_flat_map(blank_source, stock_out, 1024, 100.0),
		"create_native_flat_map creates a verified 1024 m map without VRV template: " + writer.error)
	var stock_bzn := stock_out.path_join(blank_source.get_file())
	var stock_doc := Document.new()
	check(stock_doc.open(stock_bzn) and stock_doc.package.terrain.dimensions == Vector2i(512, 512),
		"native-generated flat map opens and validates cleanly")

	# 3b. Missing .inf stock template synthesizes valid .inf, and non-square TER preserves Width and Depth in TRN (T-18)
	var no_inf_src := scratch.path_join("no-inf-template")
	DirAccess.make_dir_recursive_absolute(no_inf_src)
	var blank_stem := blank_source.get_file().get_basename()
	var blank_dir := blank_source.get_base_dir()
	for fn in DirAccess.get_files_at(blank_dir):
		if fn.to_lower().get_basename() == blank_stem.to_lower() and fn.get_extension().to_lower() in ["bzn", "trn"]:
			DirAccess.copy_absolute(blank_dir.path_join(fn), no_inf_src.path_join(fn))
	var no_inf_out := scratch.path_join("stock-no-inf-out")
	check(writer.create_native_flat_map(no_inf_src.path_join(blank_source.get_file()), no_inf_out, 1024, 100.0),
		"create_native_flat_map synthesizes missing .inf for stock templates: " + writer.error)
	var synth_inf_text := FileAccess.get_file_as_string(no_inf_out.path_join(blank_stem + ".inf"))
	var no_inf_doc := Document.new()
	check(synth_inf_text.contains("[DESCRIPTION]") and no_inf_doc.open(no_inf_out.path_join(blank_source.get_file()))
		and no_inf_doc.package.terrain.dimensions == Vector2i(512, 512),
		"synthesized .inf map opens and validates cleanly")
	var rect_ter_path := scratch.path_join("rect-template.ter")
	var rf := FileAccess.open(rect_ter_path, FileAccess.WRITE)
	rf.store_buffer(Terrain.create_flat(Vector2i(-128, -64), Vector2i(256, 128), 50.0, 0))
	rf.close()
	var rect_out := scratch.path_join("rect-ter-out")
	check(writer.create_native_flat_map(blank_source, rect_out, 2048, 100.0, rect_ter_path),
		"create_native_flat_map accepts non-square TER template: " + writer.error)
	var rect_trn_text := FileAccess.get_file_as_string(rect_out.path_join(blank_stem + ".trn"))
	var rect_doc := Document.new()
	check(rect_trn_text.contains("Width = 512") and rect_trn_text.contains("Depth = 256")
		and rect_doc.open(rect_out.path_join(blank_source.get_file()))
		and rect_doc.package.terrain.dimensions == Vector2i(256, 128),
		"non-square TER template preserves exact Width and Depth in TRN and reopens cleanly")

	# 4. Open-map auto-detection: Stock-only 0-object map detects 'stock' (NEVER VRV!), Brave detects VSR/Strategy02
	check(stock_doc.remove_object(0), "remove VSR craft to form a clean Stock-only map")
	var pure_stock_dir := scratch.path_join("pure-stock-map")
	check(writer.export_native(stock_doc, pure_stock_dir), "export pure Stock map: " + writer.error)
	var pure_stock_bzn := pure_stock_dir.path_join(blank_source.get_file())
	var pure_doc := Document.new()
	check(pure_doc.open(pure_stock_bzn), "open pure Stock map")
	check(pure_doc.mod_profile == "stock" and String(pure_doc.detected_profile_info["recommendedMod"]) == "stock",
		"pure Stock map auto-detects as 'stock' and never silently selects VRV")

	check(editor.open_map(brave_source), "open Brave to verify auto-detection and profile switching")
	var brave_doc: Document = editor.document
	check(brave_doc.package.mission_dll.to_lower() == "strategy02.dll"
		and brave_doc.mod_profile in ["vsr", "vrv"] and brave_doc.mission_profile == "strategy",
		"Brave auto-detects strategy02.dll and VSR/VRV candidate from real BZN evidence")

	# 5. Hot-swappable Stock -> VSR -> Stock editing environment: undoable, non-destructive, Mission Studio synced
	var src_bzn_hash := FileAccess.get_sha256(brave_source)
	var orig_mod := brave_doc.mod_profile
	var orig_mis := brave_doc.mission_profile
	var stack_before := brave_doc.undo_stack.size()
	check(not brave_doc.set_target_profile("INVALID MOD!", "strategy"), "reject invalid mod profile ID without mutating")
	check(not brave_doc.set_target_profile("stock", "nonexistent_mode"), "reject invalid mission profile ID without mutating")
	check(brave_doc.undo_stack.size() == stack_before, "rejected profile switches add zero history entries")

	check(brave_doc.set_target_profile("stock", "instant"), "switch editing environment to Stock / Instant")
	check(brave_doc.mod_profile == "stock" and brave_doc.mission_profile == "instant" and brave_doc.profile_explicit,
		"document records explicit Stock / Instant target profile")
	check(FileAccess.get_sha256(brave_source) == src_bzn_hash, "switching profile never alters native source BZN bytes")
	editor.mission_studio.begin(brave_doc, Vector2.ZERO)
	check(editor.mission_studio.current_profile_id() == "instant" and editor.mission_studio.mod_badge.text.contains("stock"),
		"Mission Studio binds to active document profile instead of hardcoded Strategy default")
	var stock_inst_val := MissionProfiles.validate(brave_doc, "instant", "stock")
	check("RecyclerEnemy" in stock_inst_val["missing_required"],
		"Stock Instant rules require RecyclerEnemy (distinct from VRV Strategy rules)")
	editor.mission_studio.hide()

	check(brave_doc.set_target_profile("vsr", "strategy"), "switch editing environment to VSR / Strategy")
	var conv_report := reg.analyze_conversion(brave_doc, "stock", "strategy", MissionProfiles)
	check(not (conv_report["incompatibleOdfs"] as Array).is_empty() and bool(conv_report["requiresExplicitSaveAs"]),
		"dry-run VSR -> Stock conversion analysis reports incompatible _vsr ODFs without mutating map")
	check(brave_doc.mod_profile == "vsr" and FileAccess.get_sha256(brave_source) == src_bzn_hash,
		"dry-run analysis never mutates document or source files")

	brave_doc.undo()
	check(brave_doc.mod_profile == "stock" and brave_doc.mission_profile == "instant", "Undo reverses target profile switch")
	brave_doc.undo()
	check(brave_doc.mod_profile == orig_mod and brave_doc.mission_profile == orig_mis, "second Undo restores auto-detected profile")
	brave_doc.redo()
	check(brave_doc.mod_profile == "stock" and brave_doc.mission_profile == "instant", "Redo restores explicit target profile")

	# 6. BZMAG target profile persistence + backward-compatible legacy BZMAG migration
	var new_proj := scratch.path_join("universal-target.bzmag")
	check(writer.save_project(brave_doc, new_proj), "save BZMAG with target profile metadata")
	var reopened_target := Document.new()
	check(reopened_target.open(new_proj) and reopened_target.mod_profile == "stock"
		and reopened_target.mission_profile == "instant" and reopened_target.profile_explicit,
		"BZMAG round-trips explicit target engine/mod/mission profile")

	# Legacy schema-1 BZMAG without 'target' block (with legacy assetProfile)
	var legacy_proj := scratch.path_join("legacy-no-target.bzmag")
	var pure_json_path := scratch.path_join("legacy-base.bzmag")
	var dummy_profile := scratch.path_join("legacy-assets.json")
	var pf := FileAccess.open(dummy_profile, FileAccess.WRITE)
	pf.store_string("{\"folders\":[]}")
	pf.close()
	pure_doc.asset_profile = dummy_profile
	check(writer.save_project(pure_doc, pure_json_path), "save base project to strip into legacy format")
	var parsed_legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pure_json_path))
	parsed_legacy.erase("target")
	parsed_legacy.erase("dependencies")
	var lf := FileAccess.open(legacy_proj, FileAccess.WRITE)
	lf.store_string(JSON.stringify(parsed_legacy, "", true, true))
	lf.close()
	var migrated := Document.new()
	check(migrated.open(legacy_proj) and migrated.asset_profile == dummy_profile
		and migrated.mod_profile == "stock" and not migrated.profile_explicit,
		"legacy BZMAG migrates cleanly, preserves assetProfile and infers Stock without auto-selecting VRV")
	print("Universal mod-agnostic architecture, Stock-first New Map, profile switching & legacy migration verified.")


func test_hold_ui_font_playtest(editor: Control, brave_source: String, blank_source: String, scratch: String) -> void:
	# 1. Continuous hold brush application (Raise, Smooth, Flatten, Color, Mirror X, 1-step Undo)
	check(editor.open_map(brave_source), "open map for continuous hold brush test")
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	var brush = editor.brush_panel
	brush.surface.select(0)
	brush.set_mode(brush.Mode.RAISE)
	brush.set_shape(Document.BrushShape.BELL)
	brush.set_brush_size(32)
	brush.set_pressure(20)
	var idx := 512 * terrain.dimensions.x + 512
	var base_h: float = terrain.heights[idx]
	var press := InputEventMouseButton.new()
	press.position = editor.top.view_rect().get_center()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	editor.view_input(press, editor.top)
	var after_click: float = terrain.heights[idx]
	check(after_click > base_h + 7.5, "initial click raises terrain")
	check(editor.step_hold_paint(0.25), "continuous hold ticks while stationary")
	var after_hold: float = terrain.heights[idx]
	check(after_hold > after_click + 4.0, "holding button continuously raises terrain without mouse motion")
	editor.finish_stroke()
	check(doc.undo_stack.size() == 1, "click plus continuous hold records one undo entry")
	doc.undo()
	check(is_equal_approx(terrain.heights[idx], base_h), "one undo reverses full click plus continuous hold stroke")

	# Sub-granularity continuous hold at low pressure on soft brush edge
	brush.set_pressure(10)
	doc.begin_stroke()
	var edge_idx := 512 * terrain.dimensions.x + 526 # near bell edge (low weight)
	var edge_base: float = terrain.heights[edge_idx]
	for _i in 20:
		brush.apply_dab(doc, Vector2(512.0, 512.0), editor.HOLD_DAB_SCALE, true)
	doc.end_stroke()
	check(terrain.heights[edge_idx] > edge_base, "sub-granularity hold accumulates cleanly on soft edges")
	doc.undo()

	# Continuous hold Smooth iterates across ticks
	doc.begin_stroke()
	doc.dab(Vector2(512.0, 512.0), 8.0, 30.0)
	doc.end_stroke()
	var spike_h: float = terrain.heights[idx]
	brush.set_mode(brush.Mode.BLEND)
	brush.set_pressure(50)
	doc.begin_stroke()
	brush.apply_dab(doc, Vector2(512.0, 512.0), editor.HOLD_DAB_SCALE, true)
	var smooth1: float = terrain.heights[idx]
	for _i in 8:
		brush.apply_dab(doc, Vector2(512.0, 512.0), editor.HOLD_DAB_SCALE, true)
	var smooth2: float = terrain.heights[idx]
	doc.end_stroke()
	check(smooth2 < smooth1 and smooth1 <= spike_h, "continuous hold Smooth progressively blends spikes")
	doc.undo()
	doc.undo()

	# Continuous hold Color builds up at low pressure
	brush.surface.select(1)
	brush.update_buttons()
	brush.set_pressure(20)
	brush.rgb.text = "#1537B3"
	var orig_col := terrain.material_value(Terrain.Layer.COLOR, idx)
	var target_col := Color.html("#1537B3")
	doc.begin_stroke(Terrain.Layer.COLOR)
	brush.apply_dab(doc, Vector2(512.0, 512.0))
	var col1 := Terrain.word_color(terrain.material_value(Terrain.Layer.COLOR, idx))
	for _i in 15:
		brush.apply_dab(doc, Vector2(512.0, 512.0), editor.HOLD_DAB_SCALE, true)
	var col2 := Terrain.word_color(terrain.material_value(Terrain.Layer.COLOR, idx))
	doc.end_stroke()
	var dist1 := Vector3(col1.r - target_col.r, col1.g - target_col.g, col1.b - target_col.b).length()
	var dist2 := Vector3(col2.r - target_col.r, col2.g - target_col.g, col2.b - target_col.b).length()
	check(dist2 < dist1, "continuous hold Color progressively tints toward target RGB (%.3f -> %.3f)" % [dist1, dist2])
	doc.undo()
	check(terrain.material_value(Terrain.Layer.COLOR, idx) == orig_col, "one undo restores continuous hold Color")
	brush.surface.select(0)
	brush.update_buttons()

	# 2. Crisp embedded Verdana_m1 bitmap strikes + ChoiceGroup overflow + compact dialogs + Houdini SliderField matrix
	var def_font: Font = editor.theme.default_font
	if def_font is FontFile:
		var ff := def_font as FontFile
		check(not ff.disable_embedded_bitmaps and ff.antialiasing == TextServer.FONT_ANTIALIASING_NONE
			and ff.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED,
			"Verdana_m1 FontFile enables embedded 1-bit bitmap strikes with AA and subpixel positioning off")
	check(not (brush.surface is OptionButton) and brush.surface.item_count == 3, "Terrain Brush surface uses buttons instead of combobox")
	check(not (brush.target is SpinBox) and not (brush.texture_slot is SpinBox) and not (brush.texture_lane is SpinBox), "Brush panel uses sliders instead of SpinBox arrows")
	check(not (editor.terrain_tools.operation is OptionButton) and not (editor.terrain_tools.height is SpinBox), "Shape Terrain uses buttons and sliders")

	# Dynamic BrushPanel layer visibility
	brush.surface.select(0)
	brush.update_buttons()
	check(brush._height_box.visible and not brush._color_box.visible and not brush._tile_box.visible,
		"BrushPanel shows only height controls in Height mode")
	brush.surface.select(1)
	brush.update_buttons()
	check(not brush._height_box.visible and brush._color_box.visible and not brush._tile_box.visible,
		"BrushPanel shows only RGB controls in Color mode")
	brush.surface.select(2)
	brush.update_buttons()
	check(not brush._height_box.visible and not brush._color_box.visible and brush._tile_box.visible,
		"BrushPanel shows only slot/lane controls in Tile mode")
	brush.surface.select(0)
	brush.update_buttons()

	# Houdini-style SliderField & Value Ladder regression matrix across subsystems
	var sf = brush.target
	sf.value = 100.0
	sf.set_default_value(100.0)
	var started_count := [0]
	var preview_count := [0]
	var committed_count := [0]
	var cancelled_count := [0]
	var on_start := func(_v: float): started_count[0] += 1
	var on_prev := func(_v: float): preview_count[0] += 1
	var on_commit := func(_i: float, _f: float): committed_count[0] += 1
	var on_cancel := func(_r: float): cancelled_count[0] += 1
	sf.gesture_started.connect(on_start)
	sf.preview_changed.connect(on_prev)
	sf.value_committed.connect(on_commit)
	sf.gesture_cancelled.connect(on_cancel)

	# 2a. MMB Value Ladder: vertical rung selection + horizontal scrubbing + single commit on release
	var ladder_steps: Array = sf.get_ladder_steps()
	check(ladder_steps.has(100.0) and ladder_steps.has(10.0) and ladder_steps.has(1.0) and ladder_steps.has(0.1),
		"Height SliderField (step 0.1) provides 100, 10, 1, 0.1 m Value Ladder rungs")
	sf.begin_ladder(Vector2(200.0, 200.0))
	check(sf.is_ladder_active() and started_count[0] == 1, "MMB press starts Value Ladder gesture")
	var one_idx: int = ladder_steps.find(1.0)
	for _tick in 15:
		sf.step_ladder_by(1, one_idx)
	var point_one_idx: int = ladder_steps.find(0.1)
	for _tick in 5:
		sf.step_ladder_by(1, point_one_idx)
	check(is_equal_approx(sf.value, 115.5) and preview_count[0] == 20 and committed_count[0] == 0,
		"20 ladder scrub steps update live value to 115.5 m with 0 premature commit events")
	sf.end_ladder(true)
	check(not sf.is_ladder_active() and committed_count[0] == 1 and is_equal_approx(sf.value, 115.5),
		"MMB release commits Value Ladder gesture as exactly 1 commit event")

	# 2b. MMB Value Ladder cancellation (Escape / RMB) restores exact initial value with 0 commits
	sf.begin_ladder(Vector2(200.0, 200.0))
	sf.step_ladder_by(8, ladder_steps.find(10.0))
	check(is_equal_approx(sf.value, 195.5), "ladder scrub previews 195.5 m before cancel")
	sf.end_ladder(false)
	check(not sf.is_ladder_active() and is_equal_approx(sf.value, 115.5) and cancelled_count[0] == 1 and committed_count[0] == 1,
		"cancelling Value Ladder restores 115.5 m and emits 0 additional commits")

	# 2c. Direct numeric entry: out-of-slider-range value, locale comma, unit suffix stripping, invalid input rejection
	sf._commit_text("1250,4 m")
	check(is_equal_approx(sf.value, 1250.4) and sf.slider.max_value >= 1250.4,
		"direct typing accepts locale comma, unit suffix, and values above slider display range within native max")
	sf._commit_text("-45,2 m")
	check(is_equal_approx(sf.value, -45.2), "direct typing accepts negative floats with locale comma")
	sf._commit_text("not_a_number")
	check(is_equal_approx(sf.value, -45.2) and sf.readout.text == "-45.2",
		"invalid text input is rejected and restores previous readout")
	sf._commit_text("nan")
	sf._commit_text("inf")
	sf._commit_text("-inf")
	check(is_equal_approx(sf.value, -45.2), "NaN and Infinity text inputs are rejected")
	sf.reset_to_default()
	check(is_equal_approx(sf.value, 100.0), "reset_to_default restores 100.0 m")

	# 2c-real: Real Godot InputEvent integration testing (MMB press, vertical rung switch accumulator reset, horizontal scrub, Escape/RMB cancel, Ctrl+MMB reset, context menu, focus loss, dialog close, map switch, 3D camera isolation)
	var cam_center_before: Vector3 = editor.scene_view.center
	var mmb_press := InputEventMouseButton.new()
	mmb_press.button_index = MOUSE_BUTTON_MIDDLE
	mmb_press.pressed = true
	mmb_press.position = Vector2(10.0, 8.0)
	mmb_press.global_position = Vector2(220.0, 220.0)
	sf._on_readout_gui_input(mmb_press)
	check(sf.is_ladder_active() and sf._ladder_layer != null and sf._ladder_layer.visible,
		"real InputEventMouseButton MMB press on readout activates Value Ladder and shows CanvasLayer")
	# Partial horizontal motion (5 px < 8 px tick) followed by vertical rung change must reset accumulator
	var motion_partial := InputEventMouseMotion.new()
	motion_partial.global_position = Vector2(225.0, 220.0)
	motion_partial.relative = Vector2(5.0, 0.0)
	sf._input(motion_partial)
	check(is_equal_approx(sf.value, 100.0) and sf._ladder_accum_x > 0.0,
		"sub-tick horizontal motion accumulates without premature step")
	var motion_rung := InputEventMouseMotion.new()
	motion_rung.global_position = Vector2(225.0, 220.0 - 36.0) # shift up 2 rungs to larger magnitude
	motion_rung.relative = Vector2(2.0, -36.0)
	sf._input(motion_rung)
	check(is_equal_approx(sf._ladder_accum_x, 0.0) and is_equal_approx(sf.value, 100.0),
		"vertical rung switch resets horizontal accumulator so sub-tick jitter never causes a large magnitude jump")
	# Scrub horizontally on active rung via real InputEventMouseMotion
	var active_step_mag: float = sf.active_ladder_step()
	var motion_scrub := InputEventMouseMotion.new()
	motion_scrub.global_position = Vector2(245.0, 220.0 - 36.0)
	motion_scrub.relative = Vector2(16.0, 0.0) # 2 ticks
	sf._input(motion_scrub)
	check(is_equal_approx(sf.value, 100.0 + 2.0 * active_step_mag),
		"real InputEventMouseMotion scrubs Value Ladder by 2 ticks on selected rung")
	check(editor.scene_view.center == cam_center_before,
		"MMB Value Ladder gesture on SliderField never moves 3D viewport camera")
	var mmb_release := InputEventMouseButton.new()
	mmb_release.button_index = MOUSE_BUTTON_MIDDLE
	mmb_release.pressed = false
	mmb_release.global_position = Vector2(245.0, 184.0)
	sf._input(mmb_release)
	check(not sf.is_ladder_active() and not sf._ladder_layer.visible,
		"real InputEventMouseButton MMB release commits Value Ladder and hides CanvasLayer")
	# RMB cancel via real InputEventMouseButton (scrub horizontally on active rung)
	var motion_same_rung := InputEventMouseMotion.new()
	motion_same_rung.global_position = Vector2(245.0, 220.0)
	motion_same_rung.relative = Vector2(16.0, 0.0)
	var pre_rmb_val: float = sf.value
	sf._on_readout_gui_input(mmb_press)
	sf._input(motion_same_rung)
	check(not is_equal_approx(sf.value, pre_rmb_val), "value changes during ladder scrub before RMB cancel")
	var rmb_cancel := InputEventMouseButton.new()
	rmb_cancel.button_index = MOUSE_BUTTON_RIGHT
	rmb_cancel.pressed = true
	sf._input(rmb_cancel)
	check(not sf.is_ladder_active() and is_equal_approx(sf.value, pre_rmb_val),
		"real InputEventMouseButton RMB press cancels Value Ladder and restores initial value")
	# Escape cancel via real InputEventKey
	sf._on_readout_gui_input(mmb_press)
	sf._input(motion_same_rung)
	var esc_key := InputEventKey.new()
	esc_key.keycode = KEY_ESCAPE
	esc_key.pressed = true
	sf._input(esc_key)
	check(not sf.is_ladder_active() and is_equal_approx(sf.value, pre_rmb_val),
		"real InputEventKey Escape cancels Value Ladder and restores initial value")
	# Ctrl+MMB reset via real InputEventMouseButton
	var ctrl_mmb := InputEventMouseButton.new()
	ctrl_mmb.button_index = MOUSE_BUTTON_MIDDLE
	ctrl_mmb.pressed = true
	ctrl_mmb.ctrl_pressed = true
	sf._on_readout_gui_input(ctrl_mmb)
	check(is_equal_approx(sf.value, 100.0), "Ctrl+MMB press resets SliderField to default value 100.0 m")
	# Context menu Copy / Paste / Reset
	sf.value = 142.5
	sf._on_context_menu_id(0) # Copy
	sf.value = 100.0
	sf._on_context_menu_id(1) # Paste
	check(is_equal_approx(sf.value, 142.5), "context menu Copy & Paste round-trips numeric readout value via clipboard")
	sf._on_context_menu_id(2) # Reset
	check(is_equal_approx(sf.value, 100.0), "context menu Reset restores default value")
	# Window focus loss during active gesture cancels cleanly
	sf._on_readout_gui_input(mmb_press)
	sf._input(motion_same_rung)
	sf.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not sf.is_ladder_active() and is_equal_approx(sf.value, 100.0) and not sf._ladder_layer.visible,
		"window focus loss during Value Ladder gesture cancels and hides CanvasLayer")
	# Direct-document-edit role binding test (Class C: 20 scrub steps -> 0 undo on cancel, 1 undo on commit)
	var direct_sf := preload("res://themes/slider_field.gd").new()
	direct_sf.min_value = 0.0
	direct_sf.max_value = 500.0
	direct_sf.step = 1.0
	direct_sf.value = 50.0
	editor.add_child(direct_sf)
	var direct_undo_commits := [0]
	var direct_preview_val := [50.0]
	direct_sf.bind_direct_edit(
		func(init_v: float): direct_preview_val[0] = init_v,
		func(prev_v: float): direct_preview_val[0] = prev_v,
		func(_init_v: float, final_v: float): direct_preview_val[0] = final_v; direct_undo_commits[0] += 1,
		func(rest_v: float): direct_preview_val[0] = rest_v
	)
	direct_sf.begin_ladder(Vector2(100.0, 100.0))
	for _t in 20:
		direct_sf.step_ladder_by(1, 0)
	check(direct_undo_commits[0] == 0 and direct_preview_val[0] > 50.0,
		"Class C direct-edit SliderField updates live preview across 20 steps with 0 premature undo commits")
	direct_sf.end_ladder(false)
	check(direct_undo_commits[0] == 0 and is_equal_approx(direct_preview_val[0], 50.0),
		"Class C direct-edit SliderField cancel restores initial state with 0 undo commits")
	direct_sf.begin_ladder(Vector2(100.0, 100.0))
	for _t in 20:
		direct_sf.step_ladder_by(1, 0)
	direct_sf.end_ladder(true)
	check(direct_undo_commits[0] == 1,
		"Class C direct-edit SliderField commit records exactly 1 undo command after 20 scrub steps")
	direct_sf.queue_free()

	sf.gesture_started.disconnect(on_start)
	sf.preview_changed.disconnect(on_prev)
	sf.value_committed.disconnect(on_commit)
	sf.gesture_cancelled.disconnect(on_cancel)

	# 2d. Integer-only fields never allow fractional ladder steps
	for int_field: Control in [brush.texture_slot, brush.texture_lane, editor.sound_editor.volume_spin, editor.terrain_tools.vrv_seed]:
		var isf = int_field
		var steps: Array = isf.get_ladder_steps()
		var has_frac: bool = steps.any(func(s: float): return s < 1.0 or not is_equal_approx(s, roundf(s)))
		check(isf.is_integer_field() and not steps.is_empty() and not has_frac,
			"integer SliderField provides only whole-number ladder steps: " + str(steps))

	# 2e. Verify all subsystem SliderFields respond to direct entry, slider, and Value Ladder
	var all_fields: Array = [
		brush.target, brush.texture_slot, brush.texture_lane,
		editor.water_tools.elevation, editor.water_tools.radius,
		editor.terrain_tools.height, editor.terrain_tools.grade_x, editor.terrain_tools.vrv_strength,
		editor.slope_studio.from_height, editor.slope_studio.target_height, editor.slope_studio.angle,
		editor.slope_studio.width, editor.slope_studio.batch_spacing,
		editor.mission_studio.delta_x, editor.mission_studio.rotate_deg, editor.mission_studio.spacing_m,
		editor.path_inspector.position_x,
		editor.sound_editor.volume_spin, editor.sound_editor.range_spin, editor.sound_editor.pitch_spin,
		editor.studio.range_field, editor.studio.parameters["opacity"], editor.studio.parameters["amplitude"],
	]
	var all_ok := true
	for f in all_fields:
		var orig_v: float = f.value
		f.begin_ladder(Vector2(100.0, 100.0))
		f.step_ladder_by(1, 0)
		f.end_ladder(false)
		if not is_equal_approx(f.value, orig_v):
			all_ok = false
			break
	check(all_ok, "all 23 subsystem SliderField instances support Value Ladder scrub and clean cancel")

	# 3. Dialog layout compactness, dynamic section collapse, ChoiceGroup overflow, 10 mandatory screenshots, and multi-resolution / theme matrix
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1120, 690)
		editor.size = Vector2(1120, 690)
		await process_frame
	editor.last_cursor = Vector2(512.0, 512.0)

	# 3.0 Terrain Commands (Shape Terrain) dialog + screenshot #7
	editor.open_terrain_tools()
	var ttools = editor.terrain_tools
	var ttools_cmin: Vector2 = ttools.get_contents_minimum_size()
	check(ttools.size.y < 360 and ttools.size.x >= int(ttools_cmin.x) and not ttools.get_ok_button().disabled,
		"Shape Terrain dialog fits tightly without empty void or clipping: size=%s content=%s" % [str(ttools.size), str(ttools_cmin)])
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("terrain-commands.png")) == OK, "capture Terrain Commands (Shape Terrain) screenshot")
	ttools.hide()

	# 3a. Slope Studio dynamic row visibility, live preview scrubbing (Class B: 0 undo entries during drag), dialog-close gesture cancel & screenshots #4 and #5
	editor.open_slope_studio()
	var sstudio = editor.slope_studio
	sstudio.mode_choice.select(0)
	sstudio.profile.select(0) # flat
	sstudio.batch_mode.select(0) # single
	sstudio._sync_visible_rows()
	check(sstudio._target_height_row.visible and not sstudio._angle_row.visible
		and not sstudio._terrace_row.visible and not sstudio._amplitude_row.visible
		and not sstudio._batch_count_row.visible and not sstudio._batch_spacing_row.visible,
		"Slope Studio hides angle, terrace, amplitude and batch rows when flat/elevation/single is active")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("slope-studio.png")) == OK, "capture compact Slope Studio screenshot")
	var slope_size_before: Vector2i = sstudio.size
	var undo_before_slope_scrub: int = editor.document.undo_stack.size()
	check(sstudio.preview_shape() and sstudio._preview_armed and editor.document.has_preview(),
		"Slope Studio arms live preview without adding an undo entry")
	sstudio.target_height.begin_ladder(Vector2(280.0, 260.0))
	for _t in 10:
		sstudio.target_height.step_ladder_by(1, sstudio.target_height.get_ladder_steps().find(1.0))
	check(sstudio.size == slope_size_before and editor.document.has_preview() and editor.document.undo_stack.size() == undo_before_slope_scrub,
		"Class B Slope Studio live preview scrubbing updates terrain preview across 10 ticks with 0 undo entries and 0 dialog displacement")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("slope-studio-ladder.png")) == OK, "capture Slope Studio with active Value Ladder")
	sstudio.target_height.end_ladder(false)
	check(editor.document.undo_stack.size() == undo_before_slope_scrub,
		"cancelling Slope Studio Value Ladder restores initial preview height with 0 undo entries")
	# Dialog close while Value Ladder is active must cancel gesture and hide CanvasLayer
	var th_before_close: float = sstudio.target_height.value
	sstudio.target_height.begin_ladder(Vector2(280.0, 260.0))
	sstudio.target_height.step_ladder_by(5, 0)
	sstudio.hide()
	editor.document.clear_preview()
	check(not sstudio.target_height.is_ladder_active() and is_equal_approx(sstudio.target_height.value, th_before_close)
		and (sstudio.target_height._ladder_layer == null or not sstudio.target_height._ladder_layer.visible),
		"closing dialog during active Value Ladder gesture cancels gesture, restores value, and hides CanvasLayer")
	editor.open_slope_studio()
	sstudio.mode_choice.select(1) # exact angle
	sstudio.profile.select(Shapes.PROFILES.find("terrace"))
	sstudio.batch_mode.select(1) # linear
	sstudio._sync_visible_rows()
	check(not sstudio._target_height_row.visible and sstudio._angle_row.visible
		and sstudio._terrace_row.visible and sstudio._batch_count_row.visible,
		"Slope Studio reveals angle, terrace and batch rows when selected")
	sstudio.mode_choice.select(0)
	sstudio.profile.select(0)
	sstudio.batch_mode.select(0)
	sstudio._sync_visible_rows()
	sstudio.hide()
	editor.document.clear_preview()

	# 3b. Target Profile Dialog dynamic analysis collapse + screenshot #2
	editor.open_target_profile(0)
	var tpd = editor.target_profile_dialog
	check(not tpd.analysis_output.visible and tpd.size.y < 420,
		"Target Profile dialog starts compact with empty conversion analysis collapsed: y=%d" % tpd.size.y)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("target-profile-compact.png")) == OK, "capture compact Target Profile dialog")
	tpd.run_conversion_analysis()
	check(tpd.analysis_output.visible and not tpd.analysis_output.text.is_empty(),
		"Target Profile dialog expands conversion analysis when run")
	tpd.hide()

	# 3b-extra: Mission Studio (#3), Node Studio (#6), Water (#8), Sound (#9) layout & screenshot acceptance
	editor.open_mission_studio()
	var mstudio = editor.mission_studio
	check(mstudio.size.x <= 1100 and mstudio.size.y <= 650 and not mstudio.get_ok_button().disabled,
		"Mission Studio dialog fits compactly with accessible controls: size=%s" % str(mstudio.size))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("mission-studio.png")) == OK, "capture Mission Studio screenshot")
	mstudio.hide()

	editor.open_studio()
	var nstudio = editor.studio
	check(nstudio.size.x <= 1100 and nstudio.size.y <= 650,
		"Node Studio window fits compactly: size=%s" % str(nstudio.size))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("node-studio.png")) == OK, "capture Node Studio screenshot")
	nstudio.close_studio()

	editor.toggle_water_edit()
	var wtools = editor.water_tools
	check(wtools.size.y < 340 and not wtools.get_ok_button().disabled,
		"Edit Water dialog fits compactly without empty void: size=%s" % str(wtools.size))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("water-commands.png")) == OK, "capture Edit Water screenshot")
	wtools.hide()

	editor.open_sound_editor()
	var sedit = editor.sound_editor
	check(sedit.size.y < 420,
		"Sound Point Editor dialog fits compactly: size=%s" % str(sedit.size))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("sound-editor.png")) == OK, "capture Sound Point Editor screenshot")
	sedit.hide()

	editor.open_object_browser()
	var obrowser = editor.object_browser
	check(obrowser.size.x <= 1100 and obrowser.size.y <= 620 and not obrowser.catalog_entries.is_empty(),
		"Object Browser dialog fits compactly with populated catalog: size=%s count=%d" % [str(obrowser.size), obrowser.catalog_entries.size()])
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("object-browser.png")) == OK, "capture Object Browser screenshot")
	obrowser.hide()

	# 3c. New Map Wizard with 22+ Workshop mods: ChoiceGroup overflow + compact summary + fits 640x540, 1120x690, 1280x720, 1920x1080, 2560x1440 (#1)
	var many_reg := ModRegistry.new()
	for i in 20:
		many_reg.register_custom_mod("ws_mod_%02d" % i, "Workshop Mod %02d" % i, scratch, ["stock"])
	var wiz = editor.new_map_wizard
	wiz.begin(many_reg, editor.game_path.text.strip_edges(), "stock", scratch, blank_source)
	check(wiz.mod_select.item_count >= 23 and wiz.mod_select._header_row.visible and wiz.mod_select._scroll.custom_minimum_size.y <= 60,
		"New Map Wizard activates compact searchable overflow for 23+ mod profiles")
	wiz.mod_select.filter_options("Mod 15")
	check(wiz.mod_select.button_at(0).visible and not wiz.mod_select.button_at(5).visible,
		"ChoiceGroup filter narrows mod buttons while keeping active selection visible")
	wiz.mod_select.filter_options("")
	check(wiz.size.y <= 520 and not wiz.status_label.visible,
		"New Map Wizard with 23+ mods fits comfortably within 520 px height without clipping: y=%d" % wiz.size.y)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("wizard-720p.png")) == OK, "capture compact New Map Wizard at 1120x690")
		root.size = Vector2i(1920, 1080)
		editor.size = Vector2(1920, 1080)
		wiz.popup_centered(wiz.size)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("wizard-1080p.png")) == OK, "capture compact New Map Wizard at 1920x1080")
		root.size = Vector2i(1120, 690)
		editor.size = Vector2(1120, 690)
		await process_frame

	# 4. P0 New Map Wizard Stock Safety: Refuse incompatible Stock source unless verified conversion is explicitly enabled (Section 4)
	wiz.source_bzn_field.text = blank_source # contains ivtank_vsr
	wiz.output_parent_field.text = scratch
	wiz.sanitize_stock_check.set_pressed_no_signal(false)
	wiz.refresh_summary()
	var doc_before_refusal = editor.document
	wiz.create_selected_map()
	check(wiz.visible and wiz.status_label.visible and "[ERR] Cannot create Stock map" in wiz.status_label.text
		and editor.document == doc_before_refusal,
		"New Map Wizard refuses Stock map creation from VSR source when conversion checkbox is off")
	wiz.hide()

	# 3d. Resolution, Font Size (10..24) & All-Theme (Golden Default, Vintage Dark, Vintage Classic, Nord) matrix verification (#10)
	var orig_editor_size: Vector2 = editor.size
	var orig_font_size: int = editor.ui_font_size
	for slug in Wintage.theme_slugs():
		editor.set_wintage_theme(slug, false, false)
		Wintage.shrink_dialog(editor.slope_studio, 480)
		check(editor.theme != null and editor.slope_studio.size.x >= 300 and editor.slope_studio.size.y < 520,
			"Wintage theme '%s' sizes dialogs compactly without hardcoded theme drift" % slug)
		if DisplayServer.get_name() != "headless" and slug != Wintage.DEFAULT_THEME:
			await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(scratch.path_join("theme-%s.png" % slug)) == OK,
				"capture Wintage theme '%s' screenshot" % slug)
	editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
	for res: Vector2 in [Vector2(640, 540), Vector2(1120, 690), Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440)]:
		editor.size = res
		if DisplayServer.get_name() != "headless" and int(res.x) in [1280, 1920, 2560]:
			root.size = Vector2i(int(res.x), int(res.y))
		await process_frame
		check(editor.scene_view.size.x > 100 and editor.top.size.x > 80,
			"2D and 3D viewports retain usable workspace at %dx%d" % [int(res.x), int(res.y)])
		if DisplayServer.get_name() != "headless" and int(res.x) in [1280, 1920, 2560]:
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(scratch.path_join("editor-%dx%d.png" % [int(res.x), int(res.y)])) == OK,
				"capture main editor at %dx%d" % [int(res.x), int(res.y)])
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(int(orig_editor_size.x), int(orig_editor_size.y))
	for fsz in [10, 12, 16, 24]:
		editor.ui_font_size = fsz
		editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
		check(editor.theme.default_font_size == fsz, "font scaling applies %d px cleanly" % fsz)
	editor.ui_font_size = orig_font_size
	editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
	editor.size = orig_editor_size
	await process_frame
	check(editor.empty_state_hint != null and not editor.empty_state_hint.visible,
		"empty-state hint stays hidden while a map document is open")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(scratch.path_join("editor-verdana-m1.png")) == OK, "capture crisp Verdana_m1 main editor")

	# Map switch while Value Ladder gesture is active cancels cleanly
	brush.target.value = 100.0
	brush.target.begin_ladder(Vector2(120.0, 420.0))
	brush.target.step_ladder_by(5, 0)
	check(brush.target.is_ladder_active(), "Value Ladder active on BrushPanel before map switch")

	# 4b. Product regression safeguard: Explicit Stock + VSR ODF must NEVER silently become VSR
	var writer := Snapshots.new()
	var vsr_flat := scratch.path_join("playtest-vsr-blank")
	check(writer.create_native_flat_map(blank_source, vsr_flat, 1024, 100.0), "create blank VSR fixture")
	var vsr_flat_bzn := vsr_flat.path_join(blank_source.get_file())
	editor._on_wizard_map_created(vsr_flat_bzn, "bzcc-2.0.185", "stock", "blank")
	check(not brush.target.is_ladder_active() and is_equal_approx(brush.target.value, 100.0),
		"switching map while Value Ladder gesture is active cancels gesture and restores value")
	check(editor.document.mod_profile == "stock" and editor.document.profile_explicit,
		"New Map Wizard preserves explicit 'stock' selection even when template contains VSR ODF")
	check(editor._effective_playtest_mod() == "stock",
		"_effective_playtest_mod never silently overrides explicit 'stock' with 'vsr'")
	var pt_compat: Dictionary = editor.validate_playtest_profile()
	check(not bool(pt_compat["ok"]) and String(pt_compat["selectedMod"]) == "stock"
		and String(pt_compat["suggestedMod"]) == "vsr" and not (pt_compat["incompatibleOdfs"] as Array).is_empty(),
		"Playtest preflight detects Stock vs VSR contradiction and refuses unsafe route without mutating mod_profile")

	# 5. P0 Semantic ODF Conversion Matrix (Section 5: known valid, unknown _vsr, missing Stock counterpart, different classes, VRV sound point, duplicate IDs, invalid refs, mixed map, undoable document conversion & native reimport)
	var conv_valid := ModRegistry.lookup_verified_odf_conversion("ivtank_vsr", "stock")
	check(String(conv_valid["status"]) == "verified" and String(conv_valid["targetOdf"]) == "ivtank"
		and String(conv_valid["classFamily"]) == "craft" and String(conv_valid["geometry"]) == "ivtank00.fbx",
		"known valid VSR->Stock replacement carries verified class, geometry and evidence")
	var conv_unknown := ModRegistry.lookup_verified_odf_conversion("unknown_custom_vsr", "stock")
	check(String(conv_unknown["status"]) == "unverified" and String(conv_unknown["targetOdf"]).is_empty(),
		"unknown _vsr ODF is refused instead of heuristically stripping _vsr")
	var conv_missing := ModRegistry.lookup_verified_odf_conversion("sepool01_vsr", "stock")
	check(String(conv_missing["status"]) == "unverified" and String(conv_missing["targetOdf"]).is_empty(),
		"VSR-only pool ODF without Stock counterpart (sepool01_vsr) is refused")
	var conv_bad_class := ModRegistry.lookup_verified_odf_conversion("ivtank_vsr", "stock", {"ivtank_vsr": "ibgtow"})
	check(String(conv_bad_class["status"]) == "incompatible_class",
		"manual replacement across different object classes (craft ivtank_vsr -> building ibgtow) is refused")
	var conv_snd := ModRegistry.lookup_verified_odf_conversion("vrv_sndpoint", "stock")
	check(String(conv_snd["status"]) == "unsupported_vrv",
		"VRV sound point (vrv_sndpoint) is refused as unsupported in Stock")

	# Plan-level checks: duplicate pointer IDs, duplicate sequences, pointer-referenced VRV sound point, and mixed Stock/VSR object list
	var dup_ptr_entries := [
		{"odf": "ivtank_vsr", "label": "", "flag8": 5, "sequence": 100},
		{"odf": "ivscout", "label": "", "flag8": 5, "sequence": 101},
	]
	var dup_ptr_plan := ModRegistry.plan_bzn_odf_conversion(dup_ptr_entries, {5: 1}, "stock")
	check(not bool(dup_ptr_plan["ok"]) and String(dup_ptr_plan["unsupported"][0]).contains("Duplicate object pointer ID"),
		"ODF conversion refuses object tables with duplicate pointer IDs")
	var dup_seq_entries := [
		{"odf": "ivtank_vsr", "label": "", "flag8": 5, "sequence": 100},
		{"odf": "ivscout", "label": "", "flag8": 6, "sequence": 100},
	]
	var dup_seq_plan := ModRegistry.plan_bzn_odf_conversion(dup_seq_entries, {5: 1, 6: 1}, "stock")
	check(not bool(dup_seq_plan["ok"]) and String(dup_seq_plan["unsupported"][0]).contains("Duplicate object sequence"),
		"ODF conversion refuses object tables with duplicate sequence numbers")
	var ref_vrv_entries := [
		{"odf": "vrv_sndpoint", "label": "vrvsnd:amb.wav:70:150:0:0:100:20", "flag8": 9, "sequence": 200},
	]
	var ref_vrv_plan := ModRegistry.plan_bzn_odf_conversion(ref_vrv_entries, {9: 2}, "stock", {}, true)
	check(not bool(ref_vrv_plan["ok"]) and String(ref_vrv_plan["unsupported"][0]).contains("Invalid reference"),
		"ODF conversion refuses to remove a VRV sound point referenced by another BZN record")
	var mixed_entries := [
		{"odf": "ivscout", "label": "", "flag8": 1, "sequence": 10},
		{"odf": "ivtank_vsr", "label": "", "flag8": 2, "sequence": 11},
		{"odf": "fvscout_vsr", "label": "", "flag8": 3, "sequence": 12},
	]
	var mixed_plan := ModRegistry.plan_bzn_odf_conversion(mixed_entries, {1: 1, 2: 1, 3: 1}, "stock")
	check(bool(mixed_plan["ok"]) and (mixed_plan["odfEdits"] as Dictionary).size() == 2
		and String(mixed_plan["odfEdits"][1]) == "ivtank" and String(mixed_plan["odfEdits"][2]) == "fvscout"
		and not (mixed_plan["odfEdits"] as Dictionary).has(0),
		"mixed Stock/VSR object list converts only VSR ODFs with verified mappings while leaving native Stock ODFs untouched")

	# Undoable semantic conversion on open MapDocument + BZMAG save/reopen + Native export reimport
	check(editor.document.object_odf(0) == "ivtank_vsr", "open map starts with ivtank_vsr before semantic conversion")
	var bad_doc_conv: Dictionary = editor.document.convert_objects_to_profile("stock", "strategy", {"ivtank_vsr": "ibgtow"})
	check(not bool(bad_doc_conv["ok"]) and editor.document.object_odf(0) == "ivtank_vsr",
		"MapDocument refuses incompatible-class manual conversion and preserves original ODF")
	var undo_before_conv: int = editor.document.undo_stack.size()
	var ok_doc_conv: Dictionary = editor.document.convert_objects_to_profile("stock", "strategy")
	check(bool(ok_doc_conv["ok"]) and int(ok_doc_conv["replacedCount"]) == 1
		and editor.document.object_odf(0) == "ivtank" and editor.document.mod_profile == "stock"
		and editor.document.undo_stack.size() == undo_before_conv + 1,
		"MapDocument.convert_objects_to_profile converts ivtank_vsr -> ivtank in 1 undo step")
	editor.document.undo()
	check(editor.document.object_odf(0) == "ivtank_vsr", "Undo restores original ivtank_vsr ODF")
	editor.document.redo()
	var redo_compat: Dictionary = editor.validate_playtest_profile()
	check(editor.document.object_odf(0) == "ivtank" and bool(redo_compat["profileCompatible"])
		and (redo_compat["incompatibleOdfs"] as Array).is_empty(),
		"Redo reapplies semantic ivtank conversion and passes profile ODF compatibility check")
	var conv_bzmag := scratch.path_join("converted-stock.bzmag")
	check(writer.save_project(editor.document, conv_bzmag), "save converted Stock project to .bzmag")
	var reopened_conv := Document.new()
	check(reopened_conv.open(conv_bzmag) and reopened_conv.object_odf(0) == "ivtank" and reopened_conv.mod_profile == "stock",
		"reopening .bzmag preserves semantic objectOdfEdits and Stock profile")
	var conv_export_dir := scratch.path_join("converted-stock-export")
	check(writer.export_native(reopened_conv, conv_export_dir), "export converted Stock map to native BZN and verify reimport: " + writer.error)
	var reimported_conv := Document.new()
	check(reimported_conv.open(conv_export_dir.path_join(blank_source.get_file()))
		and reimported_conv.object_odf(0) == "ivtank"
		and int(reimported_conv.package.objects[0]["flag8"]) == 1,
		"native exported BZN reimports with converted Stock ivtank and preserved player pointer ID 1")

	# Negative test: NewMapWizard and Snapshots refuse template containing unverified _vsr ODF even with sanitize_stock_objects=true
	var unverified_src_dir := scratch.path_join("unverified-vsr-tpl")
	check(writer.create_native_flat_map(blank_source, unverified_src_dir, 1024, 100.0), "stage template for unverified _vsr ODF test")
	var unv_bzn := unverified_src_dir.path_join(blank_source.get_file())
	var unv_bytes := FileAccess.get_file_as_bytes(unv_bzn)
	var unv_pc := BznPaths.new()
	unv_pc.read(unv_bytes, 1192)
	var unv_oc := BznObjects.new()
	unv_oc.read(unv_bytes, 1192, unv_pc.table_start)
	var unv_patched := BznObjects.patch_objects(unv_bytes, unv_oc.objects, {}, [], [], unv_oc.count_offset, unv_oc.insert_offset, {}, {0: "sepool01_vsr"})
	check(writer.write_bytes(unv_bzn, unv_patched["bytes"]), "write unverified sepool01_vsr ODF into test template")
	var refused_out := scratch.path_join("refused-unverified-stock")
	check(not writer.create_native_flat_map(unv_bzn, refused_out, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "strategy",
		"configure_mission": true,
		"sanitize_stock_objects": true,
	}) and not DirAccess.dir_exists_absolute(refused_out),
		"Snapshots.create_native_flat_map refuses to convert unverified sepool01_vsr ODF to Stock")

	# 6. Real Stock Strategy & Stock Instant native mission creation + asset isolation + unknown mod detection
	var stock_strat_dir := scratch.path_join("stock-strategy-native")
	check(writer.create_native_flat_map(blank_source, stock_strat_dir, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "strategy",
		"configure_mission": true,
		"sanitize_stock_objects": true,
	}), "create native Stock Strategy mission with DLL, paths and sanitized Stock objects: " + writer.error)
	var stock_strat_doc := Document.new()
	check(stock_strat_doc.open(stock_strat_dir.path_join(blank_source.get_file())), "open native Stock Strategy mission")
	check(stock_strat_doc.package.mission_dll == "Strategy02.dll"
		and stock_strat_doc.mod_profile == "stock"
		and stock_strat_doc.mission_profile == "strategy"
		and stock_strat_doc.object_count() == 3
		and stock_strat_doc.object_odf(0) == "ivtank"
		and int(stock_strat_doc.package.objects[0]["flag8"]) == 1
		and stock_strat_doc.object_odf(1) == "pspwn_1"
		and stock_strat_doc.object_odf(2) == "pspwn_1"
		and MissionProfiles.validate(stock_strat_doc, "strategy", "stock")["ok"],
		"Stock Strategy new map writes Strategy02.dll, required edge_path, pure Stock ivtank (ptr 1) and 2 pspwn_1 spawnpoints")

	var stock_inst_dir := scratch.path_join("stock-instant-native")
	check(writer.create_native_flat_map(blank_source, stock_inst_dir, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "instant",
		"configure_mission": true,
		"sanitize_stock_objects": true,
	}), "create native Stock Instant mission with Instant.dll and Recycler/RecyclerEnemy paths: " + writer.error)
	var stock_inst_doc := Document.new()
	check(stock_inst_doc.open(stock_inst_dir.path_join(blank_source.get_file())), "open native Stock Instant mission")
	check(stock_inst_doc.package.mission_dll == "Instant.dll"
		and stock_inst_doc.object_count() == 3
		and stock_inst_doc.object_odf(0) == "ivtank"
		and int(stock_inst_doc.package.objects[0]["flag8"]) == 1
		and MissionProfiles.validate(stock_inst_doc, "instant", "stock")["ok"],
		"Stock Instant new map writes Instant.dll, preserves player pointer ID 1, adds pspwn_1 spawnpoints and passes Stock Instant path validation")

	# 6b. ResolvedContentEnvironment, NativeAssets strict Stock isolation & Stock -> VSR -> VRV -> Stock switching matrix (Section 8)
	var fake_game := scratch.path_join("fake-bz2r")
	DirAccess.make_dir_recursive_absolute(fake_game.path_join("bz2r_res"))
	DirAccess.make_dir_recursive_absolute(fake_game.path_join("VRV/Core"))
	DirAccess.make_dir_recursive_absolute(fake_game.path_join("VRV/deps/VSR"))
	var src_bzn_hash_before := FileAccess.get_sha256(stock_strat_doc.package.source_path)
	editor.open_map(stock_strat_doc.package.source_path)
	var sw_doc: Document = editor.document
	var env_stock_1: Dictionary = editor.mod_registry.resolve_content_environment(sw_doc, fake_game, fake_game)
	check((env_stock_1["modAssetRoots"] as Array).is_empty(),
		"Stock profile environment mounts 0 modAssetRoots")
	check(sw_doc.set_target_profile("vsr", "strategy"), "switch profile Stock -> VSR")
	var env_vsr: Dictionary = editor.mod_registry.resolve_content_environment(sw_doc, fake_game, fake_game)
	var vsr_roots: Array = env_vsr["modAssetRoots"]
	check(not vsr_roots.is_empty() and not vsr_roots.any(func(r: String): return r.ends_with("VRV/Core")),
		"VSR profile environment mounts VSR dependency roots without VRV/Core")
	check(sw_doc.set_target_profile("vrv", "strategy"), "switch profile VSR -> VRV")
	var env_vrv: Dictionary = editor.mod_registry.resolve_content_environment(sw_doc, fake_game, fake_game)
	var vrv_roots: Array = env_vrv["modAssetRoots"]
	check(vrv_roots.any(func(r: String): return r.ends_with("VRV/Core")) and vrv_roots.any(func(r: String): return r.ends_with("VRV/deps/VSR")),
		"VRV profile environment mounts both VRV/Core and VSR dependency roots")
	check(sw_doc.set_target_profile("stock", "strategy"), "switch profile VRV -> Stock")
	var env_stock_2: Dictionary = editor.mod_registry.resolve_content_environment(sw_doc, fake_game, fake_game)
	check((env_stock_2["modAssetRoots"] as Array).is_empty() and editor.loaded_objects == null and editor.scene_view.tile_material == null,
		"switching back to Stock clears cached mod assets/materials and restores strict 0-modAssetRoots isolation")
	sw_doc.undo()
	check(sw_doc.mod_profile == "vrv", "Undo reverses Stock -> VRV profile switch")
	sw_doc.undo()
	check(sw_doc.mod_profile == "vsr", "Undo reverses VRV -> VSR profile switch")
	sw_doc.undo()
	check(sw_doc.mod_profile == "stock", "Undo reverses VSR -> Stock profile switch")
	sw_doc.redo()
	sw_doc.redo()
	sw_doc.redo()
	check(sw_doc.mod_profile == "stock" and FileAccess.get_sha256(sw_doc.package.source_path) == src_bzn_hash_before,
		"Redo chain restores final profile and native source BZN bytes remain 100% unchanged across all switches")

	var na := NativeAssets.new()
	na.index_game(fake_game, stock_strat_dir, env_stock_2["modAssetRoots"], "stock")
	var has_vrv_root := na.indexed_roots.any(func(r: String): return "vrv" in r.to_lower())
	check(not has_vrv_root, "NativeAssets.index_game never mounts VRV/Core or VRV/deps for Stock profile")

	# 6c. Unknown mod detection never silently classifies custom DLL as high-confidence Stock
	var custom_dll_dir := scratch.path_join("unknown-mod-map")
	check(writer.create_native_flat_map(blank_source, custom_dll_dir, 1024, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "blank",
		"configure_mission": false,
		"sanitize_stock_objects": true,
	}), "create base map for unknown mod detection test")
	var c_bzn_path := custom_dll_dir.path_join(blank_source.get_file())
	var c_raw := FileAccess.get_file_as_bytes(c_bzn_path)
	var c_paths := BznPaths.new()
	c_paths.read(c_raw, 1192)
	var c_objs := BznObjects.new()
	c_objs.read(c_raw, 1192, c_paths.table_start)
	var patched_custom_dll := BznObjects.patch_mission_dll(c_raw, c_objs.insert_offset, c_paths.table_start, "UnknownTotalMod.dll")
	check(writer.write_bytes(c_bzn_path, patched_custom_dll), "write UnknownTotalMod.dll into test BZN")
	var unk_doc := Document.new()
	check(unk_doc.open(c_bzn_path), "open UnknownTotalMod.dll map")
	check(unk_doc.mod_profile == "custom:unknown" and bool(unk_doc.detected_profile_info.get("unknownMod", false)),
		"unknown custom DLL detects as 'custom:unknown' instead of falsely claiming high-confidence Stock")

	print("Continuous hold brush, crisp Verdana_m1 bitmaps, Houdini Value Ladder, compact dialogs, Stock safety & Universal Authoring verified.")
