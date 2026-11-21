extends ConfirmationDialog

const Document := preload("res://core/map_document.gd")

signal updated(message: String)
signal painting_changed

var document: Document
var layer_button := OptionButton.new()
var elevation := SpinBox.new()
var radius := SpinBox.new()
var paint_toggle := CheckButton.new()
var message := Label.new()


func _ready() -> void:
	title = "Edit Water"
	ok_button_text = "Apply Elevation"
	dialog_hide_on_ok = false
	min_size = Vector2i(430, 290)
	var layout := VBoxContainer.new()
	add_child(layout)
	var caption := Label.new()
	caption.text = "Water layer"
	layout.add_child(caption)
	layout.add_child(layer_button)
	layer_button.item_selected.connect(func(_index: int): choose_layer())
	elevation.min_value = -100000.0
	elevation.max_value = 100000.0
	elevation.step = 0.1
	elevation.value_changed.connect(func(_value: float): message.text = "Apply keeps the new elevation and records one undo step.")
	add_field(layout, "Elevation (m)", elevation)
	radius.min_value = 1.0
	radius.max_value = 1024.0
	radius.value = 32.0
	add_field(layout, "Coverage brush radius (m)", radius)
	paint_toggle.text = "Paint coverage with left drag (Shift erases)"
	paint_toggle.toggled.connect(func(_pressed: bool): painting_changed.emit())
	layout.add_child(paint_toggle)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 36
	layout.add_child(message)
	confirmed.connect(apply_elevation)
	canceled.connect(func(): hide())
	visibility_changed.connect(func(): painting_changed.emit())


func add_field(parent: Control, caption: String, field: SpinBox) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	field.custom_minimum_size.x = 110
	row.add_child(field)


func begin(value: Document) -> void:
	document = value
	refresh_layers()
	choose_layer()
	popup_centered()
	painting_changed.emit()


func refresh_layers() -> void:
	var selected := layer_button.selected
	layer_button.clear()
	for layer in document.WATER_LAYERS:
		layer_button.add_item("Layer %d · %.1f m · %d blocks" % [layer + 1, document.water_layer_height(layer), document.water_cover_count(layer)])
	layer_button.select(clampi(selected, 0, layer_button.item_count - 1))


func choose_layer() -> void:
	if document == null:
		return
	elevation.set_value_no_signal(document.water_layer_height(current_layer()))
	message.text = "Left drag paints layer %d coverage in both views. Shift erases." % (current_layer() + 1)


func apply_elevation() -> void:
	var layer := current_layer()
	if not document.set_water_height(layer, elevation.value):
		message.text = document.error
		return
	updated.emit("Water layer %d elevation set to %.1f m." % [layer + 1, elevation.value])
	refresh_layers()


func current_layer() -> int:
	return layer_button.selected


func radius_m() -> float:
	return radius.value


func painting() -> bool:
	return visible and paint_toggle.button_pressed and document != null
