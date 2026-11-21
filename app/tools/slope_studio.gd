extends ConfirmationDialog

const Document := preload("res://core/map_document.gd")
const Shapes := preload("res://core/slope_shapes.gd")

signal updated(message: String)

var document: Document
var anchor := Vector2.INF
var from_x := SpinBox.new()
var from_z := SpinBox.new()
var from_height := SpinBox.new()
var to_x := SpinBox.new()
var to_z := SpinBox.new()
var mode_choice := OptionButton.new()
var target_height := SpinBox.new()
var angle := SpinBox.new()
var width := SpinBox.new()
var falloff := SpinBox.new()
var profile := OptionButton.new()
var amplitude := SpinBox.new()
var terrace_levels := SpinBox.new()
var mask_min := LineEdit.new()
var mask_max := LineEdit.new()
var slope_mask := LineEdit.new()
var batch_mode := OptionButton.new()
var batch_count := SpinBox.new()
var batch_spacing := SpinBox.new()
var mirror_x := CheckBox.new()
var mirror_z := CheckBox.new()
var message := Label.new()
var preview_button: Button


func _ready() -> void:
	title = "Slope Studio"
	ok_button_text = "Apply"
	dialog_hide_on_ok = false
	min_size = Vector2i(430, 470)
	var layout := VBoxContainer.new()
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var fields := VBoxContainer.new()
	scroll.add_child(fields)
	add_pair(fields, "Start X (m)", from_x, 20000.0)
	add_pair(fields, "Start Z (m)", from_z, 20000.0)
	add_pair(fields, "Start height (m)", from_height, 100000.0)
	fields.add_child(separator("Shape"))
	add_pair(fields, "End X (m)", to_x, 20000.0)
	add_pair(fields, "End Z (m)", to_z, 20000.0)
	for name in ["Target elevation", "Exact angle"]:
		mode_choice.add_item(name)
	fields.add_child(mode_choice)
	for name in Shapes.PROFILES:
		profile.add_item(name)
	fields.add_child(profile)
	add_pair(fields, "Width (m)", width, 2048.0)
	add_pair(fields, "Edge falloff (m)", falloff, 1024.0)
	add_pair(fields, "Target height (m)", target_height, 100000.0)
	add_pair(fields, "Angle (degrees)", angle, 90.0)
	# The snap grid must start on the minimum (AGENTS.md gotcha): with step 0.5
	# from -90, integer-half angles like 15.0 stay exactly representable.
	angle.min_value = -90.0
	angle.max_value = 90.0
	angle.step = 0.5
	add_pair(fields, "Amplitude (m)", amplitude, 100000.0)
	add_pair(fields, "Terrace levels", terrace_levels, 64.0)
	fields.add_child(separator("Masks (blank = off)"))
	add_mask(fields, "Height minimum (m)", mask_min)
	add_mask(fields, "Height maximum (m)", mask_max)
	add_mask(fields, "Maximum existing slope (%)", slope_mask)
	fields.add_child(separator("Batch"))
	for name in ["Single", "Linear row", "Radial fan"]:
		batch_mode.add_item(name)
	fields.add_child(batch_mode)
	add_pair(fields, "Instance count", batch_count, 16.0)
	add_pair(fields, "Instance spacing (m)", batch_spacing, 2048.0)
	mirror_x.text = "Mirror X"
	fields.add_child(mirror_x)
	mirror_z.text = "Mirror Z"
	fields.add_child(mirror_z)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 48
	layout.add_child(message)
	preview_button = add_button("Preview", true, "preview")
	custom_action.connect(func(_action: StringName): preview_shape())
	confirmed.connect(apply_shape)
	canceled.connect(func(): if document != null: document.clear_preview())
	profile.item_selected.connect(func(_index): mark_dirty())
	mode_choice.item_selected.connect(func(_index): mark_dirty())
	batch_mode.item_selected.connect(func(_index): mark_dirty())
	for field in [from_x, from_z, from_height, to_x, to_z, target_height, angle, width, falloff, amplitude, terrace_levels, batch_count, batch_spacing]:
		field.value_changed.connect(func(_value): mark_dirty())
	for field in [mask_min, mask_max, slope_mask]:
		field.text_changed.connect(func(_text): mark_dirty())
	mirror_x.toggled.connect(func(_value): mark_dirty())
	mirror_z.toggled.connect(func(_value): mark_dirty())


func add_pair(parent: Control, caption: String, field: SpinBox, limit: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	field.min_value = -limit
	field.max_value = limit
	field.step = 1.0
	field.custom_minimum_size.x = 110
	row.add_child(field)


func add_mask(parent: Control, caption: String, field: LineEdit) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	field.custom_minimum_size.x = 110
	field.placeholder_text = "off"
	row.add_child(field)


func separator(caption: String) -> Control:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 13)
	return label


func begin(value: Document, world_anchor: Vector2) -> void:
	document = value
	anchor = world_anchor
	var terrain := document.package.terrain
	var spacing: float = terrain.SPACING
	var bounds_min := Vector2(terrain.origin) * spacing
	var bounds_max := Vector2(terrain.origin + terrain.dimensions) * spacing
	from_x.min_value = bounds_min.x
	from_x.max_value = bounds_max.x
	from_z.min_value = bounds_min.y
	from_z.max_value = bounds_max.y
	to_x.min_value = bounds_min.x
	to_x.max_value = bounds_max.x
	to_z.min_value = bounds_min.y
	to_z.max_value = bounds_max.y
	if world_anchor.is_finite():
		from_x.value = world_anchor.x
		from_z.value = world_anchor.y
		to_x.value = world_anchor.x + 96.0
		to_z.value = world_anchor.y
	var sample := Vector2i((Vector2(world_anchor.x, world_anchor.y) / spacing - Vector2(terrain.origin)).round()) if world_anchor.is_finite() else Vector2i(terrain.dimensions) / 2
	from_height.step = document.package.granularity
	from_height.value = terrain.heights[clampi(sample.y, 0, terrain.dimensions.y - 1) * terrain.dimensions.x + clampi(sample.x, 0, terrain.dimensions.x - 1)]
	target_height.step = document.package.granularity
	target_height.value = from_height.value + 24.0
	angle.value = 5.0
	width.value = 32.0
	falloff.value = 8.0
	amplitude.value = 10.0
	terrace_levels.min_value = 1.0
	terrace_levels.value = 4.0
	batch_count.value = 1.0
	batch_spacing.value = 64.0
	mark_dirty()
	popup_centered()


func mark_dirty() -> void:
	if document != null:
		document.clear_preview()
	message.text = "Choose the shape and press Preview. Apply commits it as one undo step."


func params() -> Dictionary:
	var result := {
		"start": Vector2(from_x.value, from_z.value),
		"end": Vector2(to_x.value, to_z.value),
		"start_height": from_height.value,
		"mode": "angle" if mode_choice.selected == 1 else "elevation",
		"target_height": target_height.value,
		"angle_deg": angle.value,
		"width_m": width.value,
		"falloff_m": falloff.value,
		"profile": profile.get_item_text(maxi(profile.selected, 0)),
		"amplitude_m": amplitude.value,
		"terrace_levels": int(terrace_levels.value),
		"granularity": document.package.granularity,
	}
	var minimum := parse_mask(mask_min)
	if not is_nan(minimum):
		result["height_min"] = minimum
	var maximum := parse_mask(mask_max)
	if not is_nan(maximum):
		result["height_max"] = maximum
	var slope := parse_mask(slope_mask)
	if not is_nan(slope):
		result["slope_max_percent"] = slope
	return result


func batch() -> Dictionary:
	var result := {"mode": ["single", "linear", "radial"][batch_mode.selected]}
	result["count"] = int(batch_count.value)
	result["spacing_m"] = batch_spacing.value
	result["mirror_x"] = mirror_x.button_pressed
	result["mirror_z"] = mirror_z.button_pressed
	if mirror_x.button_pressed or mirror_z.button_pressed:
		result["symmetry_origin"] = Vector2(from_x.value, from_z.value)
	return result


func parse_mask(field: LineEdit) -> float:
	var text := field.text.strip_edges()
	if text.is_empty() or not text.is_valid_float():
		return NAN
	return text.to_float()


func preview_shape() -> bool:
	if document == null:
		return false
	mark_dirty_message_free()
	if not document.preview_slope_shape(params(), batch()):
		message.text = document.error
		return false
	var count := document.preview_after.size()
	var span: float = Vector2(to_x.value - from_x.value, to_z.value - from_z.value).length()
	var shaping := "%s spanning %.0f m" % [profile.get_item_text(maxi(profile.selected, 0)), span]
	if mode_choice.selected == 1:
		shaping += " at %.1f degrees (target height %.2f m)" % [angle.value, from_height.value + span * tan(deg_to_rad(angle.value))]
	else:
		shaping += " to %.2f m" % target_height.value
	message.text = "Previewing %d samples: %s. Apply commits one undo step." % [count, shaping]
	return true


func mark_dirty_message_free() -> void:
	message.text = "Computing preview…"


func apply_shape() -> void:
	if not preview_shape():
		return
	var count: int = document.preview_after.size()
	document.bake_preview()
	updated.emit("Shaped %d terrain samples. One undo step." % count)
	hide()
