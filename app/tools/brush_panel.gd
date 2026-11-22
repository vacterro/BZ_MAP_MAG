extends PanelContainer

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")
const WIDTHS := [4, 8, 16, 32, 64, 128]
const PRESSURES := [10, 20, 50, 100]
enum Mode { RAISE, LOWER, BLEND, PAINT, SPRAY, PICK }

signal brush_changed

var radius_m := 32.0
var pressure := 20
var shape := Document.BrushShape.BELL
var mode := Mode.RAISE
var mirror_x := false
var mirror_z := false
var mirror_x_button: Button
var mirror_z_button: Button
var size_buttons: Array[Button] = []
var mode_buttons: Array[Button] = []
var shape_buttons: Array[Button] = []
var pressure_buttons: Array[Button] = []
var pressure_label := Label.new()
var target_label := Label.new()
var target := SliderField.new()
var surface := ChoiceGroup.new(3, true)
var rgb := LineEdit.new()
var texture_slot := SliderField.new()
var texture_lane := SliderField.new()

var _modes_grid: GridContainer
var _height_box := VBoxContainer.new()
var _color_box := HBoxContainer.new()
var _tile_box := VBoxContainer.new()


func _ready() -> void:
	custom_minimum_size.x = 176
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["top", "left", "bottom", "right"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 4)
	margin.add_child(layout)
	section(layout, "Terrain Brush", "Paint height, native color or tile IDs")
	for name in ["Height", "Color", "Tile"]:
		surface.add_item(name)
	layout.add_child(surface)
	surface.item_selected.connect(func(_index): update_buttons())
	_modes_grid = grid(layout, 2)
	var texts := ["Raise", "Lower", "Blend", "Paint", "Spray", "Pick"]
	var hints := ["Shift+D", "Lower from the current height", "Shift+F", "Shift+A", "Shift+S", "Shift+G"]
	for index in texts.size():
		mode_buttons.append(choice(_modes_grid, texts[index], hints[index], set_mode.bind(index)))
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
	section(layout, "Symmetry", "Live mirror: every dab also lands on the opposite half")
	var symmetry := grid(layout, 2)
	mirror_x_button = choice(symmetry, "Mirror X", "Mirror every brush dab across the X axis", func(): set_mirror_x(not mirror_x))
	mirror_z_button = choice(symmetry, "Mirror Z", "Mirror every brush dab across the Z axis", func(): set_mirror_z(not mirror_z))

	_height_box.add_theme_constant_override("separation", 2)
	layout.add_child(_height_box)
	target_label.text = "Paint height (m)"
	_height_box.add_child(target_label)
	target.min_value = -3000
	target.max_value = 3000
	target.step = 0.1
	target.set_slider_range(-100.0, 400.0)
	target.set_unit_suffix("m")
	target.set_readout_width(48.0)
	target.value = 100
	target.tooltip_text = "Use Pick and click the terrain to set this height."
	_height_box.add_child(target)

	layout.add_child(_color_box)
	section(_color_box, "RGB", "Native vertex color as #RRGGBB")
	rgb.text = "#B0A080"
	rgb.max_length = 7
	rgb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_box.add_child(rgb)

	_tile_box.add_theme_constant_override("separation", 2)
	layout.add_child(_tile_box)
	section(_tile_box, "Slot (0–15)", "Native TRN texture slot 0–15")
	texture_slot.min_value = 0
	texture_slot.max_value = 15
	texture_slot.step = 1
	texture_slot.set_readout_width(34.0)
	_tile_box.add_child(texture_slot)
	section(_tile_box, "Tile lane (0–3)", "0 is base. Lanes 1–3 keep their existing coverage and alpha.")
	texture_lane.min_value = 0
	texture_lane.max_value = 3
	texture_lane.step = 1
	texture_lane.set_readout_width(34.0)
	texture_lane.value_changed.connect(func(_value): brush_changed.emit())
	_tile_box.add_child(texture_lane)
	update_buttons()


func sync_height_range(min_h: float, max_h: float) -> void:
	var lo := minf(min_h - 50.0, target.value - 20.0)
	var hi := maxf(max_h + 100.0, target.value + 20.0)
	if hi - lo < 100.0:
		hi = lo + 100.0
	target.set_slider_range(lo, hi)


func grid(parent: Control, columns: int) -> GridContainer:
	var result := GridContainer.new()
	result.columns = columns
	result.add_theme_constant_override("h_separation", 4)
	result.add_theme_constant_override("v_separation", 4)
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


func set_mirror_x(value: bool) -> void:
	mirror_x = value
	update_buttons()


func set_mirror_z(value: bool) -> void:
	mirror_z = value
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
	mirror_x_button.set_pressed_no_signal(mirror_x)
	mirror_z_button.set_pressed_no_signal(mirror_z)
	pressure_label.text = "Pressure · %d%%" % pressure
	if _modes_grid != null:
		_modes_grid.visible = (layer == Terrain.Layer.HEIGHT)
	_height_box.visible = (layer == Terrain.Layer.HEIGHT)
	_color_box.visible = (layer == Terrain.Layer.COLOR)
	_tile_box.visible = (layer == Terrain.Layer.TILES)
	target.editable = (layer == Terrain.Layer.HEIGHT)
	rgb.editable = layer == Terrain.Layer.COLOR
	texture_slot.editable = layer == Terrain.Layer.TILES
	texture_lane.editable = layer == Terrain.Layer.TILES
	brush_changed.emit()


func paint_layer() -> int:
	return [Terrain.Layer.HEIGHT, Terrain.Layer.COLOR, Terrain.Layer.TILES][maxi(0, surface.selected)]


func valid_rgb() -> bool:
	return rgb.text.length() == 7 and rgb.text.begins_with("#") and Color.html_is_valid(rgb.text)


func apply_dab(document: Document, point: Vector2, hold_scale: float = 1.0, accumulate: bool = false) -> void:
	dab_at(document, point, hold_scale, accumulate)
	if mirror_x:
		dab_at(document, mirrored(document, point, true), hold_scale, accumulate)
	if mirror_z:
		dab_at(document, mirrored(document, point, false), hold_scale, accumulate)


func mirrored(document: Document, point: Vector2, across_x: bool) -> Vector2:
	var dimensions := document.package.terrain.dimensions
	return Vector2(dimensions.x - 1 - point.x, point.y) if across_x else Vector2(point.x, dimensions.y - 1 - point.y)


func dab_at(document: Document, point: Vector2, hold_scale: float = 1.0, accumulate: bool = false) -> void:
	if point.x < 0 or point.y < 0:
		return
	var strength := (pressure / 100.0) * hold_scale
	match paint_layer():
		Terrain.Layer.COLOR:
			if valid_rgb():
				document.dab_material(point, radius_m, Terrain.rgb_word(Color.html(rgb.text)), shape, strength, 0, accumulate)
			return
		Terrain.Layer.TILES:
			document.dab_material(point, radius_m, int(texture_slot.value), shape, strength, int(texture_lane.value), accumulate)
			return
	match mode:
		Mode.RAISE:
			document.dab(point, radius_m, 40, Document.Brush.OFFSET, shape, strength, accumulate)
		Mode.LOWER:
			document.dab(point, radius_m, -40, Document.Brush.OFFSET, shape, strength, accumulate)
		Mode.BLEND:
			document.dab(point, radius_m, pressure * hold_scale, Document.Brush.SMOOTH, shape, 1.0, accumulate)
		Mode.PAINT:
			document.dab(point, radius_m, target.value, Document.Brush.FLATTEN, shape, strength, accumulate)
		Mode.SPRAY:
			document.dab(point, radius_m, target.value, Document.Brush.SPRAY, shape, strength, accumulate)


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
