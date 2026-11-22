extends VBoxContainer
## Docked Native AI Path Inspector inside Right Attributes Inspector.

const Document := preload("res://core/map_document.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")

signal path_created(index: int)
signal path_removed(label: String)
signal path_updated(index: int)

var document: Document
var route_index := -1
var points := PackedVector2Array()
var path_name := LineEdit.new()
var kind := ChoiceGroup.new(0)
var list := ItemList.new()
var position_x := SliderField.new()
var position_z := SliderField.new()
var message := Label.new()
var selected_point := 0
var showing_fields := false
var insert_button: Button
var remove_button: Button
var earlier_button: Button
var later_button: Button
var delete_path_button: Button
var apply_button: Button


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	var fields := HBoxContainer.new()
	add_child(fields)
	label(fields, "Name")
	path_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(path_name)

	var type_row := HBoxContainer.new()
	add_child(type_row)
	label(type_row, "Type")
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(kind)

	list.custom_minimum_size.y = 120
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(list)
	list.item_selected.connect(inspect_point)

	var coord_x_row := HBoxContainer.new()
	add_child(coord_x_row)
	label(coord_x_row, "X (m)")
	configure_coordinate(coord_x_row, position_x)

	var coord_z_row := HBoxContainer.new()
	add_child(coord_z_row)
	label(coord_z_row, "Z (m)")
	configure_coordinate(coord_z_row, position_z)

	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 4)
	controls.add_theme_constant_override("v_separation", 3)
	add_child(controls)
	apply_button = button(controls, "Apply Path", apply_path)
	insert_button = button(controls, "Insert After", insert_point)
	remove_button = button(controls, "Remove Pt", remove_point)
	earlier_button = button(controls, "Up", move_point.bind(-1))
	later_button = button(controls, "Down", move_point.bind(1))
	delete_path_button = button(controls, "Delete Path", remove_route)

	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	position_x.value_changed.connect(coordinate_changed)
	position_z.value_changed.connect(coordinate_changed)


func _sync_coord_bounds() -> void:
	if document == null or document.package == null or document.package.terrain == null:
		return
	var terrain := document.package.terrain
	var lo := Vector2(terrain.origin) * terrain.SPACING
	var hi := Vector2(terrain.origin + terrain.dimensions) * terrain.SPACING
	position_x.set_slider_range(lo.x, hi.x)
	position_z.set_slider_range(lo.y, hi.y)


func show_path(value: Document, index: int) -> void:
	document = value
	route_index = index
	if document == null or route_index < 0:
		message.text = "Select an AI path in the Scene Tree or Mission Studio."
		return
	_sync_coord_bounds()
	var route := document.path_at(index)
	if route.is_empty():
		message.text = "Path not found."
		return
	path_name.text = route["name"]
	points = route["points"].duplicate()
	configure_types(route["type"])
	delete_path_button.disabled = not document.package.path_codec.can_resize
	message.text = "Mission scripts and AI plans refer to this path by name."
	refresh_points(0)


func show_new_path(value: Document, start: Vector2) -> void:
	document = value
	route_index = -1
	_sync_coord_bounds()
	path_name.clear()
	points = PackedVector2Array([start])
	configure_types(0)
	delete_path_button.disabled = true
	message.text = "Name the new native AI path and press Apply Path."
	refresh_points(0)
	path_name.grab_focus()


func configure_types(current: int) -> void:
	kind.clear()
	for type in ["One-Way", "Round Trip", "Loop"]:
		kind.add_item(type)
	if current > 2:
		kind.add_item("Native %d" % current)
		kind.select(3)
	else:
		kind.select(current)


func label(parent: Control, text: String) -> void:
	var control := Label.new()
	control.text = text
	control.custom_minimum_size.x = 46
	parent.add_child(control)


func configure_coordinate(parent: Control, control: SliderField) -> void:
	control.min_value = -65536
	control.max_value = 65536
	control.allow_lesser = true
	control.allow_greater = true
	control.step = 0.0
	control.set_slider_range(-2048.0, 2048.0)
	control.set_unit_suffix("m")
	control.set_readout_width(58.0)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)


func button(parent: Control, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	parent.add_child(control)
	return control


func refresh_points(index: int) -> void:
	list.clear()
	for i in points.size():
		list.add_item(point_label(i))
	if points.is_empty():
		return
	var clamped := clampi(index, 0, points.size() - 1)
	list.select(clamped)
	list.ensure_current_is_visible()
	inspect_point(clamped)


func point_label(index: int) -> String:
	var point := points[index]
	return "%d    X %.3f    Z %.3f" % [index + 1, point.x, point.y]


func inspect_point(index: int) -> void:
	if index < 0 or index >= points.size():
		return
	selected_point = index
	showing_fields = true
	position_x.value = points[index].x
	position_z.value = points[index].y
	showing_fields = false
	insert_button.disabled = points.size() >= 8191
	remove_button.disabled = points.size() == 1
	earlier_button.disabled = index == 0
	later_button.disabled = index == points.size() - 1


func coordinate_changed(_value: float) -> void:
	if showing_fields or selected_point < 0 or selected_point >= points.size():
		return
	points[selected_point] = Vector2(position_x.value, position_z.value)
	list.set_item_text(selected_point, point_label(selected_point))


func insert_point() -> void:
	if points.is_empty():
		return
	points.insert(selected_point + 1, points[selected_point])
	refresh_points(selected_point + 1)


func remove_point() -> void:
	if points.size() <= 1:
		return
	points.remove_at(selected_point)
	refresh_points(mini(selected_point, points.size() - 1))


func move_point(direction: int) -> void:
	var destination := selected_point + direction
	if destination < 0 or destination >= points.size():
		return
	var moved := points[selected_point]
	points[selected_point] = points[destination]
	points[destination] = moved
	refresh_points(destination)


func apply_path() -> void:
	if document == null:
		return
	if route_index < 0:
		var created := document.create_path(path_name.text, points, kind.selected)
		if created < 0:
			message.text = document.error
		else:
			route_index = created
			delete_path_button.disabled = not document.package.path_codec.can_resize
			message.text = "Created path '%s' (%d pts)." % [path_name.text, points.size()]
			path_created.emit(created)
		return
	var type: int = document.path_at(route_index)["type"] if kind.selected == 3 else kind.selected
	if document.edit_path(route_index, path_name.text, points, type):
		message.text = "Updated path '%s' (%d pts)." % [path_name.text, points.size()]
		path_updated.emit(route_index)
	else:
		message.text = document.error


func remove_route() -> void:
	if document == null or route_index < 0:
		return
	var route := document.path_at(route_index)
	if route.is_empty():
		return
	var label_str: String = route["name"]
	if document.remove_path(route_index):
		route_index = -1
		points = PackedVector2Array()
		list.clear()
		path_name.clear()
		delete_path_button.disabled = true
		message.text = "Removed path '%s'." % label_str
		path_removed.emit(label_str)
	else:
		message.text = document.error
