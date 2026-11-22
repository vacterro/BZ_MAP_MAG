extends Control

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const TILE := 64
const STRIDE := 2

var document: Document
var tiles := {}
var _tile_images := {}
var cursor := Vector2(-1, -1)
var radius_m := 32.0
var square_brush := false
var palette: Dictionary
var path_overlay := {}
var extra_paths: Array[Dictionary] = []
var selected_path_point := -1
var water_visible := false
var object_marks: Array = []
var objects_visible := false
var move_objects := false
var selected_object := -1
var selected_objects: Array[int] = []
var object_preview := Vector3.INF
var preview_layer := Terrain.Layer.HEIGHT
var preview_tile_lane := 0


func bind(value: Document) -> void:
	document = value
	tiles.clear()
	_tile_images.clear()
	var size := document.package.terrain.dimensions
	for z in range(0, size.y, TILE):
		for x in range(0, size.x, TILE):
			update_tile(Vector2i(x, z))
	queue_redraw()


func refresh(region: Rect2i) -> void:
	var start := (region.position / TILE) * TILE
	for z in range(start.y, region.end.y, TILE):
		for x in range(start.x, region.end.x, TILE):
			update_tile(Vector2i(x, z))
	queue_redraw()


func show_material(layer: int, lane: int) -> void:
	if preview_layer == layer and (layer != Terrain.Layer.TILES or preview_tile_lane == lane):
		return
	preview_layer = layer
	preview_tile_lane = lane
	if document != null:
		refresh(Rect2i(Vector2i.ZERO, document.package.terrain.dimensions))


func update_tile(start: Vector2i) -> void:
	var terrain := document.package.terrain
	var heights := terrain.heights
	var row := terrain.dimensions.x
	var span := (terrain.dimensions - start).min(Vector2i(TILE, TILE))
	var size := span / STRIDE
	var image: Image = _tile_images.get(start, null)
	if image == null or image.get_width() != size.x or image.get_height() != size.y:
		image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
		_tile_images[start] = image
	var amplitude := maxf(0.1, terrain.max_height - terrain.min_height)
	var inv_amp_4 := 0.25 / amplitude
	var min_h := terrain.min_height
	var bg_col: Color = palette["background"]
	var surf_col: Color = palette["surface"]
	var hi_col: Color = palette["textPrimary"]
	var bg_r := bg_col.r
	var bg_g := bg_col.g
	var bg_b := bg_col.b
	var d_bg_r := hi_col.r - bg_r
	var d_bg_g := hi_col.g - bg_g
	var d_bg_b := hi_col.b - bg_b
	for j in size.y:
		var z := start.y + j * STRIDE
		var z0 := z * row
		var z1 := (z + 1) * row
		for i in size.x:
			var x := start.x + i * STRIDE
			if preview_layer == Terrain.Layer.COLOR:
				image.set_pixel(i, j, terrain.color_at(x, z))
				continue
			if preview_layer == Terrain.Layer.TILES:
				var block := terrain.block_at(Vector2i(x, z))
				var slot := (terrain.material_value(Terrain.Layer.TILES, block) >> (preview_tile_lane * 4)) & 15
				image.set_pixel(i, j, surf_col.lerp(hi_col, slot / 15.0))
				continue
			var sum := heights[z0 + x] + heights[z0 + x + 1] + heights[z1 + x] + heights[z1 + x + 1]
			var t := clampf(0.10 + (sum * inv_amp_4 - min_h / amplitude) * 0.83, 0.0, 1.0)
			image.set_pixel(i, j, Color(bg_r + d_bg_r * t, bg_g + d_bg_g * t, bg_b + d_bg_b * t))
	if tiles.has(start):
		tiles[start].update(image)
	else:
		tiles[start] = ImageTexture.create_from_image(image)


func view_rect() -> Rect2:
	if document == null:
		return Rect2()
	var dimensions := Vector2(document.package.terrain.dimensions)
	var available := (size - Vector2(12, 12)).max(Vector2.ONE)
	var scale_factor := minf(available.x / dimensions.x, available.y / dimensions.y)
	var extent := dimensions * scale_factor
	return Rect2((size - extent) * 0.5, extent)


func sample_at(pixel: Vector2) -> Vector2:
	var rect := view_rect()
	if not rect.has_point(pixel):
		return Vector2(-1, -1)
	return ((pixel - rect.position) / rect.size * Vector2(document.package.terrain.dimensions)).clamp(Vector2.ZERO, Vector2(document.package.terrain.dimensions - Vector2i.ONE))


func path_point_pixel(point: Vector2) -> Vector2:
	var terrain := document.package.terrain
	var rect := view_rect()
	return rect.position + (point / terrain.SPACING - Vector2(terrain.origin)) * rect.size / Vector2(terrain.dimensions)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), palette.get("compareBack", Color.BLACK))
	if document == null:
		return
	var rect := view_rect()
	var dimensions := Vector2(document.package.terrain.dimensions)
	var pixel_scale := rect.size / dimensions
	for start: Vector2i in tiles:
		var texture: ImageTexture = tiles[start]
		draw_texture_rect(texture, Rect2(rect.position + Vector2(start) * pixel_scale, texture.get_size() * STRIDE * pixel_scale), false)
	draw_rect(rect.grow(1), palette["bevelLight"], false, 1.0)
	if water_visible and document.package.water:
		var water := document.package.water
		var tile_size := rect.size / Vector2(water.width, water.depth)
		for layer: Dictionary in document.water_layers_effective():
			for tile: Vector2 in layer["tiles"]:
				draw_rect(Rect2(rect.position + tile * tile_size, tile_size), palette["accentTeal"])
	if objects_visible or move_objects:
		var pools := {}
		for marker: Dictionary in object_marks:
			if marker["pool"]:
				pools[marker["index"]] = true
		var sel_set := {}
		if move_objects:
			if selected_object >= 0:
				sel_set[selected_object] = true
			for sv in selected_objects:
				sel_set[sv] = true
		var group_delta := Vector3.ZERO
		if move_objects and selected_object >= 0 and object_preview.is_finite():
			group_delta = object_preview - document.object_position(selected_object)
		for index in document.object_count():
			var selected: bool = sel_set.has(index)
			var world := (document.object_position(index) + group_delta) if (selected and object_preview.is_finite()) else document.object_position(index)
			var pixel := path_point_pixel(Vector2(world.x, world.z))
			if rect.has_point(pixel):
				var pool := pools.has(document.object_pool_reference(index)) or ("pool" in document.object_odf(index).to_lower())
				var radius := 6.0 if selected else (4.0 if pool else 1.5)
				draw_circle(pixel, radius, palette["accentTeal"] if selected else palette["borderHighlight"], not pool and not selected)
	for secondary: Dictionary in extra_paths:
		var spts := PackedVector2Array()
		for pt: Vector2 in secondary["points"]:
			var px := path_point_pixel(pt)
			spts.append(px)
			draw_circle(px, 2.5, palette["accentTeal"])
		if spts.size() > 1:
			if int(secondary["type"]) == 2:
				spts.append(spts[0])
			draw_polyline(spts, palette["accentTeal"], 1.0)
	if not path_overlay.is_empty():
		var terrain := document.package.terrain
		var points := PackedVector2Array()
		for point: Vector2 in path_overlay["points"]:
			var pixel := path_point_pixel(point)
			var selected := points.size() == selected_path_point
			points.append(pixel)
			draw_circle(pixel, 5.0 if selected else 3.0, palette["accentTeal"] if selected else palette["borderHighlight"])
		if points.size() > 1:
			if path_overlay["type"] == 2:
				points.append(points[0])
			draw_polyline(points, palette["borderHighlight"], 1.0)
	if cursor.x >= 0:
		var center := rect.position + cursor * pixel_scale
		var radius := radius_m / document.package.terrain.SPACING * pixel_scale.x
		if square_brush:
			draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), palette["borderHighlight"], false, 1.0)
		else:
			draw_arc(center, radius, 0, TAU, 48, palette["borderHighlight"], 1.0)
		draw_circle(center, 2, palette["borderHighlight"])
