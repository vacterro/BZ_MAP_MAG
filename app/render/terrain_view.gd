extends SubViewportContainer

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const NativeModels := preload("res://render/native_models.gd")
const CHUNK := 64
const STEP := 4
const MIN_STEP := 1
const MAX_STEP := 4
const LOD_NEAR_SAMPLES := 160.0
const LOD_MID_SAMPLES := 384.0
const LOD_BUDGET_PER_MOVE := 16
const LOD_BUDGET_PER_FRAME := 12

var document: Document
var palette: Dictionary
var viewport := SubViewport.new()
var world := Node3D.new()
var camera := Camera3D.new()
var marker := MeshInstance3D.new()
var path_mesh := MeshInstance3D.new()
var object_models := NativeModels.new()
var object_cursor := MeshInstance3D.new()
var object_anchors := MeshInstance3D.new()
var anchor_material := StandardMaterial3D.new()
var water_mesh := MeshInstance3D.new()
var use_vertex_colors := false
var graph_preview_layer := -1
var path_overlay := {}
var extra_paths: Array[Dictionary] = []
var selected_path_point := -1
var terrain_material := StandardMaterial3D.new()
var tile_material: ShaderMaterial
var tile_maps := {}
var textures_visible := false
var meshes := {}
var chunk_steps := {}
var brush_focus := Vector2(-1, -1)
var lod_rebuilds_last := 0
var lod_queue: Array[Vector2i] = []
var lod_revision := 0
var lod_pending_count := 0
var total_chunk_rebuilds := 0
var _last_lod_cam_sample := Vector2(INF, INF)
var _last_lod_brush := Vector2(INF, INF)
var _index_cache := {}
var center := Vector3.ZERO
var yaw := 0.55
var pitch := 0.78
var distance := 1000.0
var radius_m := 32.0
var square_brush := false
var fly := false


func _ready() -> void:
	stretch = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	viewport.add_child(world)
	world.add_child(camera)
	camera.current = true
	camera.far = 30000
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = palette["compareBack"]
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = palette["textPrimary"]
	sky.environment.ambient_light_energy = 0.52
	world.add_child(sky)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-57, -33, 0)
	light.light_energy = 0.85
	world.add_child(light)
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain_material.roughness = 1
	world.add_child(marker)
	world.add_child(path_mesh)
	world.add_child(object_models)
	world.add_child(object_cursor)
	world.add_child(object_anchors)
	world.add_child(water_mesh)
	water_mesh.hide()
	path_mesh.hide()
	marker.hide()
	object_cursor.hide()
	anchor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	anchor_material.albedo_color = palette["borderHighlight"]
	anchor_material.use_point_size = true
	anchor_material.point_size = 6.0
	var outline := BoxMesh.new()
	outline.size = Vector3(3, 3, 3)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = palette["accentTeal"]
	accent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.material = accent
	object_cursor.mesh = outline
	set_process(false)


func _process(_delta: float) -> void:
	if lod_queue.is_empty():
		lod_pending_count = 0
		set_process(false)
		return
	step_lod_queue(LOD_BUDGET_PER_FRAME)


func bind(value: Document) -> void:
	document = value
	object_models.clear_models()
	object_cursor.hide()
	object_anchors.mesh = null
	textures_visible = false
	graph_preview_layer = -1
	tile_material = null
	tile_maps.clear()
	water_mesh.hide()
	water_mesh.mesh = null
	for mesh: MeshInstance3D in meshes.values():
		mesh.hide()
		mesh.queue_free()
	meshes.clear()
	chunk_steps.clear()
	lod_queue.clear()
	lod_pending_count = 0
	lod_revision += 1
	_last_lod_cam_sample = Vector2(INF, INF)
	_last_lod_brush = Vector2(INF, INF)
	brush_focus = Vector2(-1, -1)
	set_process(false)
	var terrain := document.package.terrain
	var size := terrain.dimensions - Vector2i.ONE
	center = point_world(Vector2(size) * 0.5)
	distance = maxf(size.x, size.y) * terrain.SPACING * 1.10
	for z in range(0, size.y, CHUNK):
		for x in range(0, size.x, CHUNK):
			var start := Vector2i(x, z)
			chunk_steps[start] = desired_lod_step(start)
	for z in range(0, size.y, CHUNK):
		for x in range(0, size.x, CHUNK):
			build_chunk(Vector2i(x, z))
	update_camera()


func desired_lod_step(start: Vector2i) -> int:
	if document == null or document.package == null or document.package.terrain == null:
		return MAX_STEP
	var terrain := document.package.terrain
	var chunk_center := Vector2(start) + Vector2(CHUNK, CHUNK) * 0.5
	var cam_sample := Vector2(center.x, center.z) / terrain.SPACING - Vector2(terrain.origin)
	var dist := chunk_center.distance_to(cam_sample)
	if brush_focus.x >= 0.0:
		dist = minf(dist, chunk_center.distance_to(brush_focus))
	if dist <= LOD_NEAR_SAMPLES:
		return MIN_STEP
	if dist <= LOD_MID_SAMPLES:
		return 2
	return MAX_STEP


func effective_chunk_step(start: Vector2i) -> int:
	if chunk_steps.has(start):
		return int(chunk_steps[start])
	return desired_lod_step(start)


func _sample_height(heights: PackedFloat32Array, row: int, max_x: int, max_z: int, x: int, z: int) -> float:
	return heights[clampi(z, 0, max_z) * row + clampi(x, 0, max_x)]


func seam_snapped_height(x: int, z: int, start: Vector2i, end: Vector2i, my_step: int,
		left_step: int, right_step: int, top_step: int, bottom_step: int,
		heights: PackedFloat32Array, row: int) -> float:
	var h := heights[z * row + x]
	if x == start.x and left_step > my_step:
		var z0 := start.y + ((z - start.y) / left_step) * left_step
		var z1 := mini(z0 + left_step, end.y)
		h = heights[z0 * row + x] if z0 == z1 else lerpf(heights[z0 * row + x], heights[z1 * row + x], float(z - z0) / float(z1 - z0))
	elif x == end.x and right_step > my_step:
		var z0 := start.y + ((z - start.y) / right_step) * right_step
		var z1 := mini(z0 + right_step, end.y)
		h = heights[z0 * row + x] if z0 == z1 else lerpf(heights[z0 * row + x], heights[z1 * row + x], float(z - z0) / float(z1 - z0))
	if z == start.y and top_step > my_step:
		var x0 := start.x + ((x - start.x) / top_step) * top_step
		var x1 := mini(x0 + top_step, end.x)
		h = heights[z * row + x0] if x0 == x1 else lerpf(heights[z * row + x0], heights[z * row + x1], float(x - x0) / float(x1 - x0))
	elif z == end.y and bottom_step > my_step:
		var x0 := start.x + ((x - start.x) / bottom_step) * bottom_step
		var x1 := mini(x0 + bottom_step, end.x)
		h = heights[z * row + x0] if x0 == x1 else lerpf(heights[z * row + x0], heights[z * row + x1], float(x - x0) / float(x1 - x0))
	return h


func exact_sample_info(sample: Vector2) -> Dictionary:
	if document == null or sample.x < 0.0:
		return {}
	var terrain := document.package.terrain
	var clamped := sample.clamp(Vector2.ZERO, Vector2(terrain.dimensions - Vector2i.ONE))
	var ix := clampi(int(round(clamped.x)), 0, terrain.dimensions.x - 1)
	var iz := clampi(int(round(clamped.y)), 0, terrain.dimensions.y - 1)
	var chunk := (Vector2i(ix, iz).min(terrain.dimensions - Vector2i(2, 2)) / CHUNK) * CHUNK
	var step := effective_chunk_step(chunk)
	return {
		"sample": Vector2i(ix, iz),
		"height": terrain.heights[iz * terrain.dimensions.x + ix],
		"step": step,
		"resolution_m": step * int(terrain.SPACING),
	}


func schedule_lod(force := false) -> int:
	if document == null or meshes.is_empty():
		lod_queue.clear()
		lod_pending_count = 0
		set_process(false)
		return 0
	var terrain := document.package.terrain
	var cam_sample := Vector2(center.x, center.z) / terrain.SPACING - Vector2(terrain.origin)
	if not force and _last_lod_cam_sample.is_finite():
		var cam_moved := cam_sample.distance_squared_to(_last_lod_cam_sample) >= float(CHUNK * CHUNK) * 0.0625
		var brush_moved := (brush_focus.x >= 0.0) != (_last_lod_brush.x >= 0.0) or (brush_focus.x >= 0.0 and brush_focus.distance_squared_to(_last_lod_brush) >= float(CHUNK * CHUNK) * 0.0625)
		if not cam_moved and not brush_moved:
			return lod_queue.size()
	_last_lod_cam_sample = cam_sample
	_last_lod_brush = brush_focus
	lod_revision += 1
	var queued: Array[Vector2i] = []
	for start: Vector2i in meshes:
		var wanted := desired_lod_step(start)
		if int(chunk_steps.get(start, -1)) != wanted:
			queued.append(start)
	if queued.is_empty():
		lod_queue.clear()
		lod_pending_count = 0
		set_process(false)
		return 0
	queued.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ca := Vector2(a) + Vector2(CHUNK, CHUNK) * 0.5
		var cb := Vector2(b) + Vector2(CHUNK, CHUNK) * 0.5
		var da := ca.distance_squared_to(cam_sample)
		var db := cb.distance_squared_to(cam_sample)
		if brush_focus.x >= 0.0:
			da = minf(da, ca.distance_squared_to(brush_focus))
			db = minf(db, cb.distance_squared_to(brush_focus))
		return da < db
	)
	lod_queue = queued
	lod_pending_count = lod_queue.size()
	set_process(true)
	return lod_pending_count


func step_lod_queue(budget: int = LOD_BUDGET_PER_FRAME) -> int:
	if document == null or meshes.is_empty() or lod_queue.is_empty():
		lod_queue.clear()
		lod_pending_count = 0
		lod_rebuilds_last = 0
		set_process(false)
		return 0
	var limit := budget if budget > 0 else lod_queue.size()
	var dirty_neighbors := {}
	var processed := 0
	var cursor := 0
	while cursor < lod_queue.size() and processed < limit:
		var start: Vector2i = lod_queue[cursor]
		cursor += 1
		if not meshes.has(start):
			continue
		var wanted := desired_lod_step(start)
		if int(chunk_steps.get(start, -1)) == wanted:
			continue
		chunk_steps[start] = wanted
		dirty_neighbors[start] = true
		for offset: Vector2i in [Vector2i(-CHUNK, 0), Vector2i(CHUNK, 0), Vector2i(0, -CHUNK), Vector2i(0, CHUNK)]:
			var nb := start + offset
			if meshes.has(nb):
				dirty_neighbors[nb] = true
		processed += 1
	if cursor >= lod_queue.size():
		lod_queue.clear()
	else:
		lod_queue = lod_queue.slice(cursor)
	lod_pending_count = lod_queue.size()
	set_process(lod_pending_count > 0)
	for start: Vector2i in dirty_neighbors:
		build_chunk(start)
	lod_rebuilds_last = dirty_neighbors.size()
	return lod_rebuilds_last


func update_lod(budget: int = LOD_BUDGET_PER_MOVE) -> int:
	if document == null or meshes.is_empty():
		return 0
	schedule_lod(true)
	return step_lod_queue(budget)


func _cached_indices(nx: int, nz: int) -> PackedInt32Array:
	var key := Vector2i(nx, nz)
	if _index_cache.has(key):
		return _index_cache[key]
	var indices := PackedInt32Array()
	indices.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + nx
			indices[k + 3] = a + 1
			indices[k + 4] = a + nx + 1
			indices[k + 5] = a + nx
			k += 6
	_index_cache[key] = indices
	return indices


func point_world(point: Vector2) -> Vector3:
	var terrain := document.package.terrain
	var sample := point.clamp(Vector2.ZERO, Vector2(terrain.dimensions - Vector2i.ONE))
	var lo := Vector2i(sample)
	var hi := (lo + Vector2i.ONE).min(terrain.dimensions - Vector2i.ONE)
	var row := terrain.dimensions.x
	var top := lerpf(terrain.heights[lo.y * row + lo.x], terrain.heights[lo.y * row + hi.x], sample.x - lo.x)
	var bottom := lerpf(terrain.heights[hi.y * row + lo.x], terrain.heights[hi.y * row + hi.x], sample.x - lo.x)
	return Vector3((point.x + terrain.origin.x) * terrain.SPACING, lerpf(top, bottom, sample.y - lo.y), (point.y + terrain.origin.y) * terrain.SPACING)


func build_chunk(start: Vector2i, step_override: int = 0) -> void:
	var terrain := document.package.terrain
	var heights := terrain.heights
	var row := terrain.dimensions.x
	var max_coord := terrain.dimensions - Vector2i.ONE
	var max_x := max_coord.x
	var max_z := max_coord.y
	var spacing := terrain.SPACING
	var ox := terrain.origin.x
	var oz := terrain.origin.y
	var end := (start + Vector2i(CHUNK, CHUNK)).min(max_coord)
	var step := step_override if step_override > 0 else desired_lod_step(start)
	chunk_steps[start] = step
	var left_step := effective_chunk_step(start + Vector2i(-CHUNK, 0)) if start.x > 0 else step
	var right_step := effective_chunk_step(start + Vector2i(CHUNK, 0)) if end.x < max_x else step
	var top_step := effective_chunk_step(start + Vector2i(0, -CHUNK)) if start.y > 0 else step
	var bottom_step := effective_chunk_step(start + Vector2i(0, CHUNK)) if end.y < max_z else step
	var nx := ceili(float(end.x - start.x) / step) + 1
	var nz := ceili(float(end.y - start.y) / step) + 1
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	points.resize(nx * nz)
	normals.resize(nx * nz)
	colors.resize(nx * nz)
	var amplitude := maxf(0.1, terrain.max_height - terrain.min_height)
	var inv_amplitude := 1.0 / amplitude
	var need_seam := (left_step > step) or (right_step > step) or (top_step > step) or (bottom_step > step)
	var color_preview := graph_preview_layer == Terrain.Layer.COLOR or (graph_preview_layer < 0 and use_vertex_colors)
	var tile_preview := graph_preview_layer == Terrain.Layer.TILES
	var base_col: Color = palette["surface"]
	var hi_col: Color = palette["textPrimary"]
	var min_h := terrain.min_height
	var last_i := nx - 1
	var last_j := nz - 1
	for j in nz:
		var z := mini(start.y + j * step, end.y)
		var z_lo := maxi(z - step, 0)
		var z_hi := mini(z + step, max_z)
		var dz_world := float(z_hi - z_lo) * spacing
		var z_row := z * row
		var z_lo_row := z_lo * row
		var z_hi_row := z_hi * row
		var on_z_edge := (j == 0 or j == last_j)
		var row_base := j * nx
		for i in nx:
			var x := mini(start.x + i * step, end.x)
			var x_lo := maxi(x - step, 0)
			var x_hi := mini(x + step, max_x)
			var dx_world := float(x_hi - x_lo) * spacing
			var py := seam_snapped_height(x, z, start, end, step, left_step, right_step, top_step, bottom_step, heights, row) if (need_seam and (on_z_edge or i == 0 or i == last_i)) else heights[z_row + x]
			var index := row_base + i
			points[index] = Vector3(float(x + ox) * spacing, py, float(z + oz) * spacing)
			var dhy := heights[z_row + x_hi] - heights[z_row + x_lo]
			var dhz := heights[z_hi_row + x] - heights[z_lo_row + x]
			normals[index] = Vector3(-dhy * dz_world, dx_world * dz_world, -dhz * dx_world).normalized()
			if tile_preview:
				var slot := terrain.material_value(Terrain.Layer.TILES, terrain.block_at(Vector2i(x, z))) & 15
				colors[index] = base_col.lerp(hi_col, slot / 15.0)
			elif color_preview:
				colors[index] = terrain.color_at(x, z)
			else:
				var fraction := clampf((py - min_h) * inv_amplitude, 0.0, 1.0)
				colors[index] = base_col.lerp(hi_col, 0.25 + 0.69 * fraction)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _cached_indices(nx, nz)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, active_terrain_material())
	if not meshes.has(start):
		var instance := MeshInstance3D.new()
		world.add_child(instance)
		meshes[start] = instance
	meshes[start].mesh = mesh
	total_chunk_rebuilds += 1


func refresh(region: Rect2i) -> void:
	var bounds := Rect2i(Vector2i.ZERO, document.package.terrain.dimensions - Vector2i.ONE)
	var affected := region.grow(MAX_STEP + 1).intersection(bounds)
	if not affected.has_area():
		return
	var start := (affected.position / CHUNK) * CHUNK
	for z in range(start.y, affected.end.y, CHUNK):
		for x in range(start.x, affected.end.x, CHUNK):
			build_chunk(Vector2i(x, z))
	if not path_overlay.is_empty() or not extra_paths.is_empty():
		show_path(path_overlay)


func update_camera() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = center + offset * distance
	camera.look_at(center)
	if schedule_lod() > 0:
		step_lod_queue(LOD_BUDGET_PER_MOVE)


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * 0.01
	pitch = clampf(pitch + relative.y * 0.01, 0.13, 1.54)
	update_camera()


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, 20, 14000)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = clampf(camera.size * factor, 20, 14000)
	update_camera()


func set_view(overhead: bool) -> void:
	if overhead:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(document.package.terrain.dimensions.x, document.package.terrain.dimensions.y) * 2.2
		pitch = 1.54
		yaw = 0.0
		fly = false
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		pitch = 0.78
		yaw = 0.55
	update_camera()


func set_fly(enabled: bool) -> void:
	fly = enabled
	if fly and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		set_view(false)


func fly_step(forward: float, side: float, rise: float, delta: float) -> void:
	if not fly or document == null or delta <= 0.0:
		return
	var terrain := document.package.terrain
	var speed := distance * 0.6 * delta
	var heading := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	center += heading * (forward * speed) + right * (side * speed) + Vector3.UP * (rise * speed * 0.5)
	center.x = clampf(center.x, Vector2(terrain.origin).x * terrain.SPACING, (terrain.origin.x + terrain.dimensions.x) * terrain.SPACING)
	center.z = clampf(center.z, Vector2(terrain.origin).y * terrain.SPACING, (terrain.origin.y + terrain.dimensions.y) * terrain.SPACING)
	center.y = clampf(center.y, terrain.min_height - 500.0, terrain.max_height + 3000.0)
	update_camera()


func set_wireframe(enabled: bool) -> void:
	viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if enabled else Viewport.DEBUG_DRAW_DISABLED


func show_vertex_colors(enabled: bool) -> void:
	use_vertex_colors = enabled
	for start: Vector2i in meshes:
		build_chunk(start)


func show_graph_channel(layer: int) -> void:
	if graph_preview_layer == layer:
		return
	graph_preview_layer = layer
	for start: Vector2i in meshes:
		build_chunk(start)


func active_terrain_material() -> Material:
	return tile_material if textures_visible and graph_preview_layer < 0 else terrain_material


func show_textures(enabled: bool) -> void:
	textures_visible = enabled and tile_material != null
	for instance: MeshInstance3D in meshes.values():
		instance.mesh.surface_set_material(0, active_terrain_material())


func show_object_anchors(points: PackedVector3Array) -> void:
	if points.is_empty():
		object_anchors.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_POINTS, anchor_material)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	object_anchors.mesh = mesh


func refresh_material(region: Rect2i, layer: int) -> void:
	if layer == graph_preview_layer or (layer == Terrain.Layer.COLOR and use_vertex_colors):
		refresh(region)
	if tile_material == null or tile_maps.is_empty():
		return
	var terrain := document.package.terrain
	if layer == Terrain.Layer.TILES:
		var slots: Image = tile_maps["slots"]
		var start := region.position / Terrain.BLOCK
		var last := (region.end - Vector2i.ONE) / Terrain.BLOCK
		for y in range(start.y, last.y + 1):
			for x in range(start.x, last.x + 1):
				slots.set_pixel(x, y, terrain.slot_color(y * slots.get_width() + x))
		var texture: ImageTexture = tile_material.get_shader_parameter("tile_slots")
		texture.update(slots)
	else:
		var colors: Image = tile_maps["colors"]
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				colors.set_pixel(x, y, terrain.color_at(x, y))
		var texture: ImageTexture = tile_material.get_shader_parameter("tints")
		texture.update(colors)


func show_water(enabled: bool) -> void:
	water_mesh.visible = enabled
	if not enabled or water_mesh.mesh:
		return
	var water := document.package.water
	if not water or water.layers.is_empty():
		return
	build_water_mesh()


func rebuild_water() -> void:
	water_mesh.mesh = null
	if water_mesh.visible:
		build_water_mesh()


func build_water_mesh() -> void:
	var water := document.package.water
	if not water or document.water_layers_effective().is_empty():
		return
	var terrain := document.package.terrain
	var size := terrain.BLOCK * terrain.SPACING
	var base := Vector2(terrain.origin) * terrain.SPACING
	var mesh := ImmediateMesh.new()
	var ink := StandardMaterial3D.new()
	ink.albedo_color = palette["accentTeal"]
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ink)
	mesh.surface_set_normal(Vector3.UP)
	for layer: Dictionary in document.water_layers_effective():
		for tile: Vector2 in layer["tiles"]:
			var origin := base + tile * size
			for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
				var point := origin + corner * size
				mesh.surface_add_vertex(Vector3(point.x, layer["height"], point.y))
	mesh.surface_end()
	water_mesh.mesh = mesh


func pan(relative: Vector2) -> void:
	var scale_factor := distance / maxf(size.y, 1.0)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var backwards := Vector3(sin(yaw), 0, cos(yaw))
	center += (-right * relative.x - backwards * relative.y) * scale_factor
	update_camera()


func sample_at(pixel: Vector2) -> Vector2:
	if document == null or not Rect2(Vector2.ZERO, size).has_point(pixel):
		return Vector2(-1, -1)
	var terrain := document.package.terrain
	var first := Vector2(terrain.origin) * terrain.SPACING
	var last := Vector2(terrain.origin + terrain.dimensions - Vector2i.ONE) * terrain.SPACING
	var from := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var near := 0.0
	var far := camera.far
	for axis in [0, 2]:
		var ix: int = 0 if axis == 0 else 1
		if absf(ray[axis]) < 0.000001:
			if from[axis] < first[ix] or from[axis] > last[ix]:
				return Vector2(-1, -1)
			continue
		var a: float = (first[ix] - from[axis]) / ray[axis]
		var b: float = (last[ix] - from[axis]) / ray[axis]
		near = maxf(near, minf(a, b))
		far = minf(far, maxf(a, b))
	if near > far:
		return Vector2(-1, -1)
	var length := terrain.SPACING * 0.75 / maxf(0.01, Vector2(ray.x, ray.z).length())
	var t := near
	var previous := near
	while true:
		var p := from + ray * t
		var sample := Vector2(p.x, p.z) / terrain.SPACING - Vector2(terrain.origin)
		if p.y <= point_world(sample).y:
			var lower := previous
			var upper := t
			for iteration in 9:
				var mid := (lower + upper) * 0.5
				var hit := from + ray * mid
				var grid := Vector2(hit.x, hit.z) / terrain.SPACING - Vector2(terrain.origin)
				if hit.y > point_world(grid).y:
					lower = mid
				else:
					upper = mid
			p = from + ray * upper
			return (Vector2(p.x, p.z) / terrain.SPACING - Vector2(terrain.origin)).clamp(Vector2.ZERO, Vector2(terrain.dimensions - Vector2i.ONE))
		if t >= far:
			break
		previous = t
		t = minf(far, t + length)
	return Vector2(-1, -1)


func show_cursor(point: Vector2) -> void:
	if point.x >= 0.0:
		var moved := brush_focus.distance_to(point) >= CHUNK * 0.5 or brush_focus.x < 0.0
		brush_focus = point
		if moved and schedule_lod() > 0:
			step_lod_queue(8)
	marker.visible = point.x >= 0
	if not marker.visible:
		return
	var mesh := ImmediateMesh.new()
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = palette["borderHighlight"]
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ink)
	for i in 49:
		var offset := Vector2.from_angle(TAU * i / 48.0) * (radius_m / document.package.terrain.SPACING)
		if square_brush:
			offset /= maxf(absf(cos(TAU * i / 48.0)), absf(sin(TAU * i / 48.0)))
		var p := point_world(point + offset)
		p.y += 1.5
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	marker.mesh = mesh


func show_path(path: Dictionary) -> void:
	path_overlay = path
	path_mesh.visible = not path.is_empty() or not extra_paths.is_empty()
	if not path_mesh.visible:
		return
	var mesh := ImmediateMesh.new()
	var sec_ink := StandardMaterial3D.new()
	sec_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sec_ink.albedo_color = palette["accentTeal"]
	for secondary: Dictionary in extra_paths:
		var spts := PackedVector3Array()
		for pt: Vector2 in secondary["points"]:
			spts.append(path_point_world(pt))
		if spts.size() > 1:
			mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, sec_ink)
			for pt in spts:
				mesh.surface_add_vertex(pt)
			if int(secondary["type"]) == 2:
				mesh.surface_add_vertex(spts[0])
			mesh.surface_end()
	if not path.is_empty():
		var points := PackedVector3Array()
		for point: Vector2 in path["points"]:
			points.append(path_point_world(point))
		var ink := StandardMaterial3D.new()
		ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ink.albedo_color = palette["borderHighlight"]
		if points.size() > 1:
			mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ink)
			for point in points:
				mesh.surface_add_vertex(point)
			if path["type"] == 2:
				mesh.surface_add_vertex(points[0])
			mesh.surface_end()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, ink)
		for i in points.size():
			var point := points[i]
			for axis in [Vector3.RIGHT, Vector3.FORWARD, Vector3.UP]:
				var radius := 14.0 if i == selected_path_point else 8.0
				mesh.surface_add_vertex(point - axis * radius)
				mesh.surface_add_vertex(point + axis * radius)
		mesh.surface_end()
	path_mesh.mesh = mesh


func path_point_world(point: Vector2) -> Vector3:
	var terrain := document.package.terrain
	return point_world(point / terrain.SPACING - Vector2(terrain.origin)) + Vector3.UP * 4


func path_point_pixel(point: Vector2) -> Vector2:
	var world_point := path_point_world(point)
	return Vector2(-INF, -INF) if camera.is_position_behind(world_point) else camera.unproject_position(world_point)
