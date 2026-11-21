extends ConfirmationDialog

const Document := preload("res://core/map_document.gd")

signal path_created(index: int)
signal path_removed(label: String)

var document: Document
var route_index := -1
var points := PackedVector2Array()
var path_name := LineEdit.new()
var kind := OptionButton.new()
var list := ItemList.new()
var position_x := SpinBox.new()
var position_z := SpinBox.new()
var message := Label.new()
var selected_point := 0
var showing_fields := false
var insert_button: Button
var remove_button: Button
var earlier_button: Button
var later_button: Button
var delete_path_button: Button


func _ready() -> void:
	title = "Native AI Path"
	ok_button_text = "Apply"
	dialog_hide_on_ok = false
	min_size = Vector2i(440, 395)
	var content := VBoxContainer.new()
	add_child(content)
	var fields := HBoxContainer.new()
	content.add_child(fields)
	label(fields, "Name")
	path_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(path_name)
	label(fields, "Type")
	fields.add_child(kind)
	list.custom_minimum_size.y = 185
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(list)
	list.item_selected.connect(inspect_point)
	var coordinates := HBoxContainer.new()
	content.add_child(coordinates)
	label(coordinates, "X (m)")
	configure_coordinate(coordinates, position_x)
	label(coordinates, "Z (m)")
	configure_coordinate(coordinates, position_z)
	var controls := HBoxContainer.new()
	content.add_child(controls)
	insert_button = button(controls, "Insert After", insert_point)
	remove_button = button(controls, "Remove Point", remove_point)
	earlier_button = button(controls, "Move Up", move_point.bind(-1))
	later_button = button(controls, "Move Down", move_point.bind(1))
	delete_path_button = button(controls, "Remove Path", remove_route)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 31
	content.add_child(message)
	position_x.value_changed.connect(coordinate_changed)
	position_z.value_changed.connect(coordinate_changed)
	confirmed.connect(apply_path)


func show_path(value: Document, index: int) -> void:
	document = value
	route_index = index
	var route := document.path_at(index)
	path_name.text = route["name"]
	points = route["points"].duplicate()
	configure_types(route["type"])
	delete_path_button.disabled = not document.package.path_codec.can_resize
	message.text = "Mission scripts and AI plans may refer to this path by name."
	refresh_points(0)
	popup_centered()


func show_new_path(value: Document, start: Vector2) -> void:
	document = value
	route_index = -1
	path_name.clear()
	points = PackedVector2Array([start])
	configure_types(0)
	delete_path_button.disabled = true
	message.text = "Name the path and set its points."
	refresh_points(0)
	popup_centered()
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
	parent.add_child(control)


func configure_coordinate(parent: Control, control: SpinBox) -> void:
	control.min_value = -65536
	control.max_value = 65536
	control.allow_lesser = true
	control.allow_greater = true
	control.step = 0.0
	control.custom_minimum_size.x = 116
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
	list.select(index)
	list.ensure_current_is_visible()
	inspect_point(index)


func point_label(index: int) -> String:
	var point := points[index]
	return "%d    X %.3f    Z %.3f" % [index + 1, point.x, point.y]


func inspect_point(index: int) -> void:
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
	if showing_fields:
		return
	points[selected_point] = Vector2(position_x.value, position_z.value)
	list.set_item_text(selected_point, point_label(selected_point))


func insert_point() -> void:
	points.insert(selected_point + 1, points[selected_point])
	refresh_points(selected_point + 1)


func remove_point() -> void:
	points.remove_at(selected_point)
	refresh_points(mini(selected_point, points.size() - 1))


func move_point(direction: int) -> void:
	var destination := selected_point + direction
	var moved := points[selected_point]
	points[selected_point] = points[destination]
	points[destination] = moved
	refresh_points(destination)


func apply_path() -> void:
	if route_index < 0:
		var created := document.create_path(path_name.text, points, kind.selected)
		if created < 0:
			message.text = document.error
		else:
			hide()
			path_created.emit(created)
		return
	var type: int = document.path_at(route_index)["type"] if kind.selected == 3 else kind.selected
	if document.edit_path(route_index, path_name.text, points, type):
		hide()
	else:
		message.text = document.error


func remove_route() -> void:
	var label: String = document.path_at(route_index)["name"]
	if document.remove_path(route_index):
		hide()
		path_removed.emit(label)
	else:
		message.text = document.error
