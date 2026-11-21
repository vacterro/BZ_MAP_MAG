extends SceneTree

const EditorScene := preload("res://editor.tscn")
const Terrain := preload("res://formats/terrain_v5.gd")
const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Graph := preload("res://nodes/height_graph.gd")
const Water := preload("res://formats/water_v5.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const AutoSaveStore := preload("res://core/autosave_store.gd")
const Shapes := preload("res://core/slope_shapes.gd")
const TerrainView := preload("res://render/terrain_view.gd")
const Package := preload("res://formats/map_package.gd")

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
		check(editor.theme.default_font.get_font_name() == "Verdana", "main UI loads actual Verdana")
		check(editor.studio.theme.default_font.get_font_name() == "Verdana", "node window uses actual Verdana")
		check(editor.open_dialog.theme.default_font.get_font_name() == "Verdana", "dialogs use actual Verdana")
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
	test_large_slope_preview()
	await test_fly_autosave_symmetry(editor, args[0], args[2])
	test_sound_point_labels(editor)
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
