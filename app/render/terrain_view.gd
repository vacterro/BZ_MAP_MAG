extends SubViewportContainer

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const NativeModels := preload("res://render/native_models.gd")
const CHUNK := 64
const STEP := 4

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
var selected_path_point := -1
var terrain_material := StandardMaterial3D.new()
var tile_material: ShaderMaterial
var tile_maps := {}
var textures_visible := false
var meshes := {}
var center := Vector3.ZERO
var yaw := 0.55
var pitch := 0.78
var distance := 1000.0
var radius_m := 32.0
var square_brush := false


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
	var terrain := document.package.terrain
	var size := terrain.dimensions - Vector2i.ONE
	for z in range(0, size.y, CHUNK):
		for x in range(0, size.x, CHUNK):
			build_chunk(Vector2i(x, z))
	center = point_world(Vector2(size) * 0.5)
	distance = maxf(size.x, size.y) * terrain.SPACING * 1.10
	update_camera()


func point_world(point: Vector2) -> Vector3:
	var terrain := document.package.terrain
	var sample := point.clamp(Vector2.ZERO, Vector2(terrain.dimensions - Vector2i.ONE))
	var lo := Vector2i(sample)
	var hi := (lo + Vector2i.ONE).min(terrain.dimensions - Vector2i.ONE)
	var row := terrain.dimensions.x
	var top := lerpf(terrain.heights[lo.y * row + lo.x], terrain.heights[lo.y * row + hi.x], sample.x - lo.x)
	var bottom := lerpf(terrain.heights[hi.y * row + lo.x], terrain.heights[hi.y * row + hi.x], sample.x - lo.x)
	return Vector3((point.x + terrain.origin.x) * terrain.SPACING, lerpf(top, bottom, sample.y - lo.y), (point.y + terrain.origin.y) * terrain.SPACING)


func build_chunk(start: Vector2i) -> void:
	var terrain := document.package.terrain
	var end := (start + Vector2i(CHUNK, CHUNK)).min(terrain.dimensions - Vector2i.ONE)
	var nx := ceili(float(end.x - start.x) / STEP) + 1
	var nz := ceili(float(end.y - start.y) / STEP) + 1
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	points.resize(nx * nz)
	normals.resize(nx * nz)
	colors.resize(nx * nz)
	var amplitude := maxf(0.1, terrain.max_height - terrain.min_height)
	for j in nz:
		var z := mini(start.y + j * STEP, end.y)
		for i in nx:
			var x := mini(start.x + i * STEP, end.x)
			var p := point_world(Vector2(x, z))
			var dx := point_world(Vector2(x + STEP, z)) - point_world(Vector2(x - STEP, z))
			var dz := point_world(Vector2(x, z + STEP)) - point_world(Vector2(x, z - STEP))
			var index := j * nx + i
			points[index] = p
			normals[index] = dz.cross(dx).normalized()
			var fraction := clampf((p.y - terrain.min_height) / amplitude, 0.0, 1.0)
			colors[index] = palette["surface"].lerp(palette["textPrimary"], 0.25 + 0.69 * fraction)
			if graph_preview_layer == Terrain.Layer.TILES:
				var slot := terrain.material_value(Terrain.Layer.TILES, terrain.block_at(Vector2i(x, z))) & 15
				colors[index] = palette["surface"].lerp(palette["textPrimary"], slot / 15.0)
			elif graph_preview_layer == Terrain.Layer.COLOR or (graph_preview_layer < 0 and use_vertex_colors):
				colors[index] = terrain.color_at(x, z)
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			indices.append_array(PackedInt32Array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, active_terrain_material())
	if not meshes.has(start):
		var instance := MeshInstance3D.new()
		world.add_child(instance)
		meshes[start] = instance
	meshes[start].mesh = mesh


func refresh(region: Rect2i) -> void:
	var bounds := Rect2i(Vector2i.ZERO, document.package.terrain.dimensions - Vector2i.ONE)
	var affected := region.grow(STEP + 1).intersection(bounds)
	if not affected.has_area():
		return
	var start := (affected.position / CHUNK) * CHUNK
	for z in range(start.y, affected.end.y, CHUNK):
		for x in range(start.x, affected.end.x, CHUNK):
			build_chunk(Vector2i(x, z))
	if not path_overlay.is_empty():
		show_path(path_overlay)


func update_camera() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = center + offset * distance
	camera.look_at(center)


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
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		pitch = 0.78
		yaw = 0.55
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
	path_mesh.visible = not path.is_empty()
	if not path_mesh.visible:
		return
	var points := PackedVector3Array()
	for point: Vector2 in path["points"]:
		points.append(path_point_world(point))
	var mesh := ImmediateMesh.new()
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
