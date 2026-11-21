extends RefCounted

const Document := preload("res://core/map_document.gd")
const TopView := preload("res://render/top_view.gd")
const TerrainView := preload("res://render/terrain_view.gd")

var document: Document
var top: TopView
var scene: TerrainView
var drag_view: Control
var selected := -1
var active := false
var draft := Vector3.INF
var grab_pixel := Vector2.ZERO
var grab_offset := Vector2.ZERO
var height_offset := 0.0


func bind(value: Document, map: TopView, view: TerrainView) -> void:
	document = value
	top = map
	scene = view
	selected = -1
	drag_view = null
	draft = Vector3.INF
	set_active(false)


func set_active(value: bool) -> void:
	active = value
	top.move_objects = value
	refresh_marker()


func start(panel: Control, pixel: Vector2) -> void:
	selected = -1
	var distance := 14.0
	for i in document.package.objects.size():
		var position := document.object_position(i)
		var anchor := top.path_point_pixel(Vector2(position.x, position.z))
		if panel == scene:
			var model: MeshInstance3D = scene.object_models.instances.get(i)
			if model and model.is_visible_in_tree():
				position = model.to_global(model.get_aabb().get_center())
			if scene.camera.is_position_behind(position):
				continue
			anchor = scene.camera.unproject_position(position)
		var current := pixel.distance_to(anchor)
		if current < distance:
			distance = current
			selected = i
	refresh_marker()
	if selected < 0:
		return
	var sample: Vector2 = panel.sample_at(pixel)
	if sample.x < 0:
		return
	var original := document.object_position(selected)
	var terrain := document.package.terrain
	var sample_of_object := Vector2(original.x, original.z) / terrain.SPACING - Vector2(terrain.origin)
	grab_offset = sample_of_object - sample
	height_offset = original.y - scene.point_world(sample_of_object).y
	grab_pixel = pixel
	drag_view = panel


func preview(pixel: Vector2, sample: Vector2, snap: bool) -> void:
	if sample.x < 0 or (not draft.is_finite() and pixel.distance_to(grab_pixel) < 3):
		return
	var limit := Vector2(document.package.terrain.dimensions - Vector2i.ONE)
	var target := sample + grab_offset
	if snap:
		target = target.round()
	target = target.clamp(Vector2.ZERO, limit)
	draft = scene.point_world(target)
	draft.y += height_offset
	scene.object_models.move_instance(selected, draft)
	refresh_marker()


func finish(commit: bool) -> bool:
	var position := draft
	drag_view = null
	draft = Vector3.INF
	var success := true
	if commit and position.is_finite():
		success = document.move_object(selected, position)
	scene.object_models.move_instance(selected, document.object_position(selected))
	refresh_marker()
	return success


func position_changed(index: int) -> void:
	scene.object_models.move_instance(index, document.object_position(index))
	refresh_marker()


func refresh_marker() -> void:
	top.selected_object = selected if active else -1
	top.object_preview = draft
	top.queue_redraw()
	scene.object_cursor.visible = active and selected >= 0
	if scene.object_cursor.visible:
		scene.object_cursor.position = (draft if draft.is_finite() else document.object_position(selected)) + Vector3.UP * 2


func description() -> String:
	var position := draft if draft.is_finite() else document.object_position(selected)
	var entry := document.package.objects[selected]
	return "%s · Team %d · X %.1f · Y %.1f · Z %.1f" % [
		entry["odf"], entry["team"], position.x, position.y, position.z]
