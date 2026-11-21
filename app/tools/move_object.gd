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
	update_anchors()


func start(panel: Control, pixel: Vector2) -> void:
	selected = -1
	var distance := 14.0
	for i in document.object_count():
		var position := document.object_position(i)
		var anchor := top.path_point_pixel(Vector2(position.x, position.z))
		if panel == scene:
			position = pick_anchor(i)
			if scene.camera.is_position_behind(position):
				continue
			anchor = scene.camera.unproject_position(position)
		var current := pixel.distance_to(anchor)
		if current < distance:
			distance = current
			selected = i
	refresh_marker()
	update_anchors()
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
	if selected < 0 or selected >= document.object_count():
		return
	var limit := Vector2(document.package.terrain.dimensions - Vector2i.ONE)
	var target := sample + grab_offset
	if snap:
		target = target.round()
	target = target.clamp(Vector2.ZERO, limit)
	draft = scene.point_world(target)
	draft.y += height_offset
	if scene.object_models.instances.has(selected):
		scene.object_models.move_instance(selected, draft)
	refresh_marker()


func finish(commit: bool) -> bool:
	var position := draft
	drag_view = null
	draft = Vector3.INF
	var success := true
	if commit and selected >= 0 and selected < document.object_count() and position.is_finite():
		success = document.move_object(selected, position)
	if selected >= 0 and selected < document.object_count():
		scene.object_models.set_instance_transform(selected, document.object_transform(selected))
	refresh_marker()
	return success


func position_changed(index: int) -> void:
	scene.object_models.set_instance_transform(index, document.object_transform(index))
	refresh_marker()
	if active:
		update_anchors()


func pick_anchor(index: int) -> Vector3:
	var model: MeshInstance3D = scene.object_models.instances.get(index)
	if model and model.is_visible_in_tree():
		return model.to_global(model.get_aabb().get_center())
	return document.object_position(index) + Vector3.UP * 2.0


func update_anchors() -> void:
	var points := PackedVector3Array()
	if active:
		for index in document.object_count():
			if index == selected:
				continue
			var model: MeshInstance3D = scene.object_models.instances.get(index)
			if not model or not model.is_visible_in_tree():
				points.append(pick_anchor(index))
	scene.show_object_anchors(points)


func refresh_marker() -> void:
	top.selected_object = selected if active else -1
	top.object_preview = draft
	top.queue_redraw()
	scene.object_cursor.visible = active and selected >= 0 and selected < document.object_count()
	if scene.object_cursor.visible:
		scene.object_cursor.position = (draft if draft.is_finite() else document.object_position(selected)) + Vector3.UP * 2


func description() -> String:
	if selected < 0 or selected >= document.object_count():
		return "Select an object in either view."
	var position := draft if draft.is_finite() else document.object_position(selected)
	var degrees := rad_to_deg(heading(document.object_transform(selected).basis))
	return "%s%s · Team %d · X %.1f · Y %.1f · Z %.1f · Heading %.0f°" % [
		document.object_odf(selected), label_suffix(document.object_label(selected)), document.object_team(selected),
		position.x, position.y, position.z, degrees]


func label_suffix(label: String) -> String:
	if document != null:
		var point: Dictionary = document.sound_point(label)
		if not point.is_empty():
			return " · Sound %s · vol %d%% · range %d m · interval %d s · jitter %d%% · pitch %d%% · near %d%%" % [
				point["sound"], point["volume"], point["range"], point["interval"], point["jitter"], point["pitch"], point["near"]]
	return " · %s" % label if label != "" else ""


static func heading(basis: Basis) -> float:
	# Facing angle of the engine's front axis, degrees counter-clockwise from +Z in the Godot preview.
	var front := basis.z
	return atan2(front.x, front.z)
