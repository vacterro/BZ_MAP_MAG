extends VBoxContainer
## Reusable docked Slope Studio panel (Cinema 4D / Photoshop Attributes style).
## Hosted directly inside the Right Attributes Inspector with zero modal popup,
## keeping 3D/2D viewports unobstructed for live sculpting preview.

const Document := preload("res://core/map_document.gd")
const Shapes := preload("res://core/slope_shapes.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

signal updated(message: String)
signal preview_state_changed(active: bool)
signal canceled

var document: Document
var anchor := Vector2.INF
var from_x := SliderField.new()
var from_z := SliderField.new()
var from_height := SliderField.new()
var to_x := SliderField.new()
var to_z := SliderField.new()
var mode_choice := ChoiceGroup.new(2, true)
var target_height := SliderField.new()
var angle := SliderField.new()
var width := SliderField.new()
var falloff := SliderField.new()
var profile := ChoiceGroup.new(0)
var amplitude := SliderField.new()
var terrace_levels := SliderField.new()
var mask_min := LineEdit.new()
var mask_max := LineEdit.new()
var slope_mask := LineEdit.new()
var batch_mode := ChoiceGroup.new(3, true)
var batch_count := SliderField.new()
var batch_spacing := SliderField.new()
var mirror_x := CheckBox.new()
var mirror_z := CheckBox.new()
var message := Label.new()
var preview_button := Button.new()
var apply_button := Button.new()
var cancel_button := Button.new()

var _target_height_row: Control
var _angle_row: Control
var _amplitude_row: Control
var _terrace_row: Control
var _batch_count_row: Control
var _batch_spacing_row: Control
var _preview_armed := false
var _initialized := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# 1. Main Geometry Section
	var geo_sec := CollapsibleSection.new("Main Geometry", "slope_geo", false)
	add_child(geo_sec)
	add_pair(geo_sec.body, "Start X (m)", from_x, 20000.0, NAN, NAN, "m")
	add_pair(geo_sec.body, "Start Z (m)", from_z, 20000.0, NAN, NAN, "m")
	add_pair(geo_sec.body, "Start H (m)", from_height, 100000.0, -100.0, 400.0, "m")
	add_pair(geo_sec.body, "End X (m)", to_x, 20000.0, NAN, NAN, "m")
	add_pair(geo_sec.body, "End Z (m)", to_z, 20000.0, NAN, NAN, "m")

	# 2. Shape Profile Section
	var shape_sec := CollapsibleSection.new("Shape Profile", "slope_shape", false)
	add_child(shape_sec)
	for name in ["Target elevation", "Exact angle"]:
		mode_choice.add_item(name)
	shape_sec.add_content(mode_choice)
	for name in Shapes.PROFILES:
		profile.add_item(name)
	shape_sec.add_content(profile)
	add_pair(shape_sec.body, "Width (m)", width, 2048.0, 2.0, 512.0, "m")
	width.min_value = Shapes.SPACING
	add_pair(shape_sec.body, "Falloff (m)", falloff, 1024.0, 0.0, 256.0, "m")
	falloff.min_value = 0.0
	_target_height_row = add_pair(shape_sec.body, "Target H (m)", target_height, 100000.0, -100.0, 400.0, "m")
	_angle_row = add_pair(shape_sec.body, "Angle (°)", angle, 90.0, NAN, NAN, "°")
	# Snap grid must start on minimum (AGENTS.md gotcha): with step 0.5 from -90,
	# integer-half angles like 15.0 stay exactly representable.
	angle.min_value = -90.0
	angle.max_value = 90.0
	angle.step = 0.5
	_amplitude_row = add_pair(shape_sec.body, "Amplitude (m)", amplitude, 100000.0, 0.0, 200.0, "m")
	amplitude.min_value = 0.0
	_terrace_row = add_pair(shape_sec.body, "Terrace levels", terrace_levels, 64.0, 1.0, 32.0)

	# 3. Masks Section (collapsible, compact)
	var mask_sec := CollapsibleSection.new("Masks (blank = off)", "slope_masks", true)
	add_child(mask_sec)
	var masks_row := HBoxContainer.new()
	masks_row.add_theme_constant_override("separation", 4)
	mask_sec.add_content(masks_row)
	add_compact_mask(masks_row, "Min", mask_min)
	add_compact_mask(masks_row, "Max", mask_max)
	add_compact_mask(masks_row, "Slope%", slope_mask)

	# 4. Batch & Symmetry Section (collapsible)
	var batch_sec := CollapsibleSection.new("Batch & Symmetry", "slope_batch", true)
	add_child(batch_sec)
	for name in ["Single", "Linear", "Radial"]:
		batch_mode.add_item(name)
	batch_sec.add_content(batch_mode)
	_batch_count_row = add_pair(batch_sec.body, "Count", batch_count, 16.0, 1.0, 16.0)
	batch_count.min_value = 1.0
	_batch_spacing_row = add_pair(batch_sec.body, "Spacing (m)", batch_spacing, 2048.0, 2.0, 512.0, "m")
	batch_spacing.min_value = Shapes.SPACING
	var sym_row := HBoxContainer.new()
	mirror_x.text = "Mirror X"
	sym_row.add_child(mirror_x)
	mirror_z.text = "Mirror Z"
	sym_row.add_child(mirror_z)
	batch_sec.add_content(sym_row)

	# Actions bar (always visible at bottom of Attributes)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	add_child(actions)
	preview_button.text = "Preview"
	preview_button.tooltip_text = "Preview terrain shape in 3D and 2D without committing"
	preview_button.pressed.connect(preview_shape)
	actions.add_child(preview_button)
	apply_button.text = "Apply"
	apply_button.tooltip_text = "Commit previewed shape to terrain as one undo step"
	apply_button.pressed.connect(apply_shape)
	actions.add_child(apply_button)
	cancel_button.text = "Cancel"
	cancel_button.tooltip_text = "Clear live preview and restore committed heights"
	cancel_button.pressed.connect(cancel_shape)
	actions.add_child(cancel_button)

	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	canceled.connect(clear_preview)

	profile.item_selected.connect(func(_index): mark_dirty())
	mode_choice.item_selected.connect(func(_index): mark_dirty())
	batch_mode.item_selected.connect(func(_index): mark_dirty())
	for field in [from_x, from_z, from_height, to_x, to_z, target_height, angle, width, falloff, amplitude, terrace_levels, batch_count, batch_spacing]:
		field.set_field_role(SliderField.Role.PREVIEW_PARAMETER)
		field.value_changed.connect(func(_value): _on_preview_field_changed())
		field.gesture_cancelled.connect(func(_restored): _on_preview_field_cancelled())
	for field in [mask_min, mask_max, slope_mask]:
		field.text_changed.connect(func(_text): mark_dirty())
	mirror_x.toggled.connect(func(_value): mark_dirty())
	mirror_z.toggled.connect(func(_value): mark_dirty())
	_sync_visible_rows()


func _on_preview_field_changed() -> void:
	if _preview_armed and document != null:
		preview_shape()
	else:
		mark_dirty()


func _on_preview_field_cancelled() -> void:
	if _preview_armed and document != null:
		preview_shape()
	else:
		mark_dirty()


func _sync_visible_rows() -> void:
	var is_angle := (mode_choice.selected == 1)
	if _target_height_row != null:
		_target_height_row.visible = not is_angle
	if _angle_row != null:
		_angle_row.visible = is_angle
	var prof_name := profile.get_item_text(maxi(profile.selected, 0)).to_lower()
	if _terrace_row != null:
		_terrace_row.visible = (prof_name == "terrace")
	if _amplitude_row != null:
		_amplitude_row.visible = not (prof_name in ["flat", "smooth", "terrace"])
	var is_batch := (batch_mode.selected > 0)
	if _batch_count_row != null:
		_batch_count_row.visible = is_batch
	if _batch_spacing_row != null:
		_batch_spacing_row.visible = is_batch


func add_pair(parent: Control, caption: String, field: SliderField, limit: float, slider_lo: float = NAN, slider_hi: float = NAN, unit: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 84
	row.add_child(label)
	field.min_value = -limit
	field.max_value = limit
	field.step = 1.0
	if is_finite(slider_lo) and is_finite(slider_hi):
		field.set_slider_range(slider_lo, slider_hi)
	if not unit.is_empty():
		field.set_unit_suffix(unit)
	field.set_readout_width(48.0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return row


func add_compact_mask(parent: Control, caption: String, field: LineEdit) -> void:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.x = 42
	field.placeholder_text = "off"
	parent.add_child(field)


func begin(value: Document, world_anchor: Vector2, preserve_params: bool = false) -> void:
	var same_doc := (document == value and _initialized)
	document = value
	if document == null:
		_preview_armed = false
		_initialized = false
		return
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
	from_height.step = document.package.granularity
	from_height.set_slider_range(terrain.min_height - 50.0, terrain.max_height + 100.0)
	target_height.step = document.package.granularity
	target_height.set_slider_range(terrain.min_height - 50.0, terrain.max_height + 100.0)
	if not (preserve_params and same_doc):
		if world_anchor.is_finite():
			from_x.set_value_no_signal(world_anchor.x)
			from_z.set_value_no_signal(world_anchor.y)
			to_x.set_value_no_signal(world_anchor.x + 96.0)
			to_z.set_value_no_signal(world_anchor.y)
		var sample := Vector2i((Vector2(world_anchor.x, world_anchor.y) / spacing - Vector2(terrain.origin)).round()) if world_anchor.is_finite() else Vector2i(terrain.dimensions) / 2
		var base_h := terrain.heights[clampi(sample.y, 0, terrain.dimensions.y - 1) * terrain.dimensions.x + clampi(sample.x, 0, terrain.dimensions.x - 1)]
		from_height.set_value_no_signal(base_h)
		target_height.set_value_no_signal(base_h + 24.0)
		angle.set_value_no_signal(5.0)
		width.set_value_no_signal(32.0)
		falloff.set_value_no_signal(8.0)
		amplitude.set_value_no_signal(10.0)
		terrace_levels.min_value = 1.0
		terrace_levels.set_value_no_signal(4.0)
		batch_count.set_value_no_signal(1.0)
		batch_spacing.set_value_no_signal(64.0)
		_preview_armed = false
		_initialized = true
		mark_dirty()
	else:
		_sync_visible_rows()


func mark_dirty() -> void:
	var was_armed := _preview_armed
	_preview_armed = false
	if document != null:
		document.clear_preview()
	if was_armed:
		preview_state_changed.emit(false)
	_sync_visible_rows()
	message.text = "Configure shape and press Preview. Apply commits one undo step."


func clear_preview() -> void:
	var was_armed := _preview_armed
	_preview_armed = false
	if document != null:
		document.clear_preview()
	if was_armed:
		preview_state_changed.emit(false)


func cancel_shape() -> void:
	clear_preview()
	message.text = "Preview cancelled. Committed heights unchanged."
	canceled.emit()


func is_preview_active() -> bool:
	return _preview_armed and document != null and document.has_preview()


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
	_sync_visible_rows()
	mark_dirty_message_free()
	if not document.preview_slope_shape(params(), batch()):
		_preview_armed = false
		preview_state_changed.emit(false)
		message.text = document.error
		return false
	_preview_armed = true
	preview_state_changed.emit(true)
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
	_preview_armed = false
	preview_state_changed.emit(false)
	message.text = "Applied %d terrain samples (1 undo step)." % count
	updated.emit("Shaped %d terrain samples. One undo step." % count)
