extends PanelContainer

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const WIDTHS := [4, 8, 16, 32, 64, 128]
const PRESSURES := [10, 20, 50, 100]
enum Mode { RAISE, LOWER, BLEND, PAINT, SPRAY, PICK }

signal brush_changed

var radius_m := 32.0
var pressure := 20
var shape := Document.BrushShape.BELL
var mode := Mode.RAISE
var size_buttons: Array[Button] = []
var mode_buttons: Array[Button] = []
var shape_buttons: Array[Button] = []
var pressure_buttons: Array[Button] = []
var pressure_label := Label.new()
var target_label := Label.new()
var target := SpinBox.new()
var surface := OptionButton.new()
var rgb := LineEdit.new()
var texture_slot := SpinBox.new()
var texture_lane := SpinBox.new()


func _ready() -> void:
	custom_minimum_size.x = 156
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["top", "left", "bottom", "right"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	scroll.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	margin.add_child(layout)
	section(layout, "Terrain Brush", "Paint height, native color or tile IDs")
	for name in ["Height", "Color", "Tile"]:
		surface.add_item(name)
	layout.add_child(surface)
	surface.item_selected.connect(func(_index): update_buttons())
	var modes := grid(layout, 2)
	var texts := ["Raise", "Lower", "Blend", "Paint", "Spray", "Pick"]
	var hints := ["Shift+D", "Lower from the current height", "Shift+F", "Shift+A", "Shift+S", "Shift+G"]
	for index in texts.size():
		mode_buttons.append(choice(modes, texts[index], hints[index], set_mode.bind(index)))
	section(layout, "Shape", "Shift+Q/W/E/R")
	var shapes := grid(layout, 2)
	var names := ["Square", "Circle", "Cone", "Bell"]
	var keys := ["Q", "W", "E", "R"]
	for index in names.size():
		shape_buttons.append(choice(shapes, names[index], "Shift+" + keys[index], set_shape.bind(index)))
	section(layout, "Size (2 m cells)", "Shift+1–6. Size is the full width in terrain samples.")
	var sizes := grid(layout, 3)
	for index in WIDTHS.size():
		var width: int = WIDTHS[index]
		size_buttons.append(choice(sizes, str(width), "Shift+%d · %d m wide" % [index + 1, width * 2], set_brush_size.bind(width)))
	layout.add_child(pressure_label)
	var pressures := grid(layout, 2)
	for index in PRESSURES.size():
		var value: int = PRESSURES[index]
		pressure_buttons.append(choice(pressures, "%d%%" % value, "Shift+" + ["Z", "X", "C", "V"][index], set_pressure.bind(value)))
	target_label.text = "Paint height (m)"
	layout.add_child(target_label)
	target.min_value = -3000
	target.max_value = 3000
	target.step = 0.1
	target.value = 100
	target.tooltip_text = "Use Pick and click the terrain to set this height."
	layout.add_child(target)
	var tint := HBoxContainer.new()
	layout.add_child(tint)
	section(tint, "RGB", "Native vertex color as #RRGGBB")
	rgb.text = "#B0A080"
	rgb.max_length = 7
	rgb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tint.add_child(rgb)
	var tiles := HBoxContainer.new()
	layout.add_child(tiles)
	section(tiles, "Slot", "Native TRN texture slot 0–15")
	texture_slot.max_value = 15
	texture_slot.step = 1
	tiles.add_child(texture_slot)
	section(layout, "Tile lane", "0 is base. Lanes 1–3 keep their existing coverage and alpha.")
	texture_lane.max_value = 3
	texture_lane.step = 1
	texture_lane.value_changed.connect(func(_value): brush_changed.emit())
	layout.add_child(texture_lane)
	update_buttons()


func grid(parent: Control, columns: int) -> GridContainer:
	var result := GridContainer.new()
	result.columns = columns
	parent.add_child(result)
	return result


func section(parent: Control, text: String, description: String) -> void:
	var label := Label.new()
	label.text = text
	label.tooltip_text = description
	parent.add_child(label)


func choice(parent: Control, text: String, tip: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.tooltip_text = tip
	control.toggle_mode = true
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.pressed.connect(action)
	parent.add_child(control)
	return control


func set_mode(value: int) -> void:
	mode = value
	update_buttons()


func set_shape(value: int) -> void:
	shape = value
	update_buttons()


func set_brush_size(value: float) -> void:
	radius_m = value
	update_buttons()


func set_pressure(value: int) -> void:
	pressure = value
	update_buttons()


func use_picked_height(height: float) -> void:
	target.value = height
	set_mode(Mode.PAINT)


func update_buttons() -> void:
	var layer := paint_layer()
	for index in size_buttons.size():
		size_buttons[index].set_pressed_no_signal(WIDTHS[index] == radius_m)
	for index in mode_buttons.size():
		mode_buttons[index].set_pressed_no_signal(mode == index)
		mode_buttons[index].disabled = layer != Terrain.Layer.HEIGHT
	for index in shape_buttons.size():
		shape_buttons[index].set_pressed_no_signal(shape == index)
	for index in pressure_buttons.size():
		pressure_buttons[index].set_pressed_no_signal(PRESSURES[index] == pressure)
	pressure_label.text = "Pressure · %d%%" % pressure
	target.editable = layer == Terrain.Layer.HEIGHT and (mode == Mode.PAINT or mode == Mode.SPRAY)
	rgb.editable = layer == Terrain.Layer.COLOR
	texture_slot.editable = layer == Terrain.Layer.TILES
	texture_lane.editable = layer == Terrain.Layer.TILES
	brush_changed.emit()


func paint_layer() -> int:
	return [Terrain.Layer.HEIGHT, Terrain.Layer.COLOR, Terrain.Layer.TILES][maxi(0, surface.selected)]


func valid_rgb() -> bool:
	return rgb.text.length() == 7 and rgb.text.begins_with("#") and Color.html_is_valid(rgb.text)


func apply_dab(document: Document, point: Vector2) -> void:
	var strength := pressure / 100.0
	match paint_layer():
		Terrain.Layer.COLOR:
			if valid_rgb():
				document.dab_material(point, radius_m, Terrain.rgb_word(Color.html(rgb.text)), shape, strength)
			return
		Terrain.Layer.TILES:
			document.dab_material(point, radius_m, int(texture_slot.value), shape, strength, int(texture_lane.value))
			return
	match mode:
		Mode.RAISE:
			document.dab(point, radius_m, 40, Document.Brush.OFFSET, shape, strength)
		Mode.LOWER:
			document.dab(point, radius_m, -40, Document.Brush.OFFSET, shape, strength)
		Mode.BLEND:
			document.dab(point, radius_m, pressure, Document.Brush.SMOOTH, shape)
		Mode.PAINT:
			document.dab(point, radius_m, target.value, Document.Brush.FLATTEN, shape, strength)
		Mode.SPRAY:
			document.dab(point, radius_m, target.value, Document.Brush.SPRAY, shape, strength)


func shortcut(key: Key) -> bool:
	var keys := [KEY_Q, KEY_W, KEY_E, KEY_R]
	if key in keys:
		set_shape(keys.find(key))
		return true
	keys = [KEY_Z, KEY_X, KEY_C, KEY_V]
	if key in keys:
		set_pressure(PRESSURES[keys.find(key)])
		return true
	if key >= KEY_1 and key <= KEY_6:
		set_brush_size(WIDTHS[key - KEY_1])
		return true
	var tool := {KEY_A: Mode.PAINT, KEY_S: Mode.SPRAY, KEY_D: Mode.RAISE, KEY_F: Mode.BLEND, KEY_G: Mode.PICK}
	if tool.has(key):
		set_mode(tool[key])
		return true
	return false
