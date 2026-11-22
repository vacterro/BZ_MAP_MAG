extends VBoxContainer
## Docked Water Editor panel inside Right Attributes Inspector.
## Painting mode is controlled explicitly by paint_toggle + WorkspaceState,
## never tied to modal Window visibility.

const Document := preload("res://core/map_document.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")

signal updated(message: String)
signal painting_changed

var document: Document
var layer_button := ChoiceGroup.new(2, true)
var elevation := SliderField.new()
var radius := SliderField.new()
var paint_toggle := CheckButton.new()
var apply_button := Button.new()
var message := Label.new()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)
	var caption := Label.new()
	caption.text = "Water Layer (8 native WAT layers)"
	add_child(caption)
	add_child(layer_button)
	layer_button.item_selected.connect(func(_index: int): choose_layer())

	elevation.min_value = -100000.0
	elevation.max_value = 100000.0
	elevation.step = 0.1
	elevation.set_slider_range(-100.0, 400.0)
	elevation.set_unit_suffix("m")
	elevation.set_readout_width(48.0)
	elevation.value_changed.connect(func(_value: float): message.text = "Apply Elevation records one undo step.")
	add_field(self, "Elevation (m)", elevation)

	radius.min_value = 1.0
	radius.max_value = 1024.0
	radius.set_slider_range(1.0, 256.0)
	radius.set_unit_suffix("m")
	radius.set_readout_width(48.0)
	radius.value = 32.0
	add_field(self, "Radius (m)", radius)

	paint_toggle.text = "Paint coverage (LMB paint · Shift erase)"
	paint_toggle.toggled.connect(func(_pressed: bool): painting_changed.emit())
	add_child(paint_toggle)

	var actions := HBoxContainer.new()
	add_child(actions)
	apply_button.text = "Apply Elevation"
	apply_button.pressed.connect(apply_elevation)
	actions.add_child(apply_button)

	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)


func add_field(parent: Control, caption: String, field: SliderField) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 84
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)


func begin(value: Document) -> void:
	document = value
	if document == null or document.package == null or document.package.water == null:
		apply_button.disabled = true
		paint_toggle.disabled = true
		paint_toggle.set_pressed_no_signal(false)
		message.text = "This map does not contain a native .WAT water file."
		painting_changed.emit()
		return
	apply_button.disabled = false
	paint_toggle.disabled = false
	var terrain := document.package.terrain
	elevation.set_slider_range(terrain.min_height - 50.0, terrain.max_height + 100.0)
	refresh_layers()
	choose_layer()
	painting_changed.emit()


func set_painting(enabled: bool) -> void:
	paint_toggle.set_pressed_no_signal(enabled)
	painting_changed.emit()


func refresh_layers() -> void:
	if document == null:
		return
	var selected := layer_button.selected
	layer_button.clear()
	for layer in document.WATER_LAYERS:
		layer_button.add_item("L%d · %.1f m (%d)" % [layer + 1, document.water_layer_height(layer), document.water_cover_count(layer)])
	layer_button.select(clampi(selected, 0, layer_button.item_count - 1))


func choose_layer() -> void:
	if document == null:
		return
	elevation.set_value_no_signal(document.water_layer_height(current_layer()))
	message.text = "Left drag paints layer %d coverage in both views. Shift erases." % (current_layer() + 1)


func apply_elevation() -> void:
	if document == null:
		return
	var layer := current_layer()
	if not document.set_water_height(layer, elevation.value):
		message.text = document.error
		return
	updated.emit("Water layer %d elevation set to %.1f m." % [layer + 1, elevation.value])
	refresh_layers()


func current_layer() -> int:
	return maxi(0, layer_button.selected)


func radius_m() -> float:
	return radius.value


func painting() -> bool:
	return paint_toggle.button_pressed and document != null and document.package != null and document.package.water != null
