extends SceneTree

const Document := preload("res://core/map_document.gd")
const Models := preload("res://render/native_models.gd")
const EditorScene := preload("res://editor.tscn")
const Terrain := preload("res://formats/terrain_v5.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(2)
		return
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	await process_frame
	if editor.document == null and not editor.open_map(args[0]):
		quit(1)
		return
	editor.game_path.text = args[1]
	var document: Document = editor.document
	var models: Models = editor.scene_view.object_models
	editor.objects_button.set_pressed_no_signal(true)
	editor.toggle_objects()
	await wait_for_assets(editor)
	print(editor.status.text)
	var displayed := models.get_child_count()
	var shown_pools := 0
	var first_pool := Vector3.ZERO
	for model: MeshInstance3D in models.get_children():
		if model.get_meta("native_pool"):
			if shown_pools == 0:
				first_pool = model.position
				var terrain := document.package.terrain
				var point := Vector2(first_pool.x, first_pool.z) / terrain.SPACING - Vector2(terrain.origin)
				print("First pool at %s, terrain %.3f, mesh bounds %s." % [
					first_pool, editor.scene_view.point_world(point).y, model.get_aabb()])
			shown_pools += 1
	print("Rendered instances: %d. Rendered native scrap pools: %d." % [displayed, shown_pools])
	if displayed == 0 or not editor.top.objects_visible or editor.top.object_marks.size() != displayed:
		quit(1)
		return
	editor.texture_button.set_pressed_no_signal(true)
	editor.toggle_textures()
	await wait_for_assets(editor)
	var textured: bool = editor.scene_view.textures_visible
	print(editor.status.text)
	if not textured or not await verify_live_material_maps(editor, document):
		printerr("Native material textures did not update after an edit.")
		quit(1)
		return
	var painted_surfaces := 0
	for material: StandardMaterial3D in models.materials.values():
		if material.albedo_texture:
			painted_surfaces += 1
	print("Native object diffuse texture materials: %d." % painted_surfaces)
	if DisplayServer.get_name() != "headless" and textured:
		editor.water_button.set_pressed_no_signal(true)
		editor.toggle_water()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[2].path_join("native-surface.png"))
		var craft: MeshInstance3D = models.get_child(0)
		editor.scene_view.center = craft.position + Vector3.UP * 1.0
		editor.scene_view.distance = 50
		editor.scene_view.update_camera()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[2].path_join("native-objects.png"))
		editor.scene_view.center = first_pool + Vector3.UP * 1.0
		editor.scene_view.distance = 55
		editor.scene_view.update_camera()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[2].path_join("native-pool.png"))
	quit(0 if displayed == 76 and shown_pools == 8 and painted_surfaces > 0 and textured else 1)


func wait_for_assets(editor: Control) -> void:
	var expires := Time.get_ticks_msec() + 15000
	while editor.object_thread.is_started() and Time.get_ticks_msec() < expires:
		await create_timer(0.1).timeout


func verify_live_material_maps(editor: Control, document: Document) -> bool:
	var terrain := document.package.terrain
	var sample := terrain.dimensions / 2
	var index := sample.y * terrain.dimensions.x + sample.x
	var block := terrain.block_at(sample)
	var before_color := terrain.material_value(Terrain.Layer.COLOR, index)
	var before_tiles := terrain.material_value(Terrain.Layer.TILES, block)
	var color := before_color ^ 0xffffff
	var tiles := before_tiles ^ 15
	document.apply_materials(Terrain.Layer.COLOR, {index: color})
	document.apply_materials(Terrain.Layer.TILES, {block: tiles})
	await process_frame
	await process_frame
	var tints: Image = editor.scene_view.tile_maps["colors"]
	var slots: Image = editor.scene_view.tile_maps["slots"]
	var grid := terrain.block_origin(block) / Terrain.BLOCK
	if DisplayServer.get_name() != "headless":
		tints = editor.scene_view.tile_material.get_shader_parameter("tints").get_image()
		slots = editor.scene_view.tile_material.get_shader_parameter("tile_slots").get_image()
	var updated := Terrain.rgb_word(tints.get_pixelv(sample)) == color and slots.get_pixelv(grid).r8 == (tiles & 15)
	document.apply_materials(Terrain.Layer.COLOR, {index: before_color})
	document.apply_materials(Terrain.Layer.TILES, {block: before_tiles})
	await process_frame
	await process_frame
	return updated
