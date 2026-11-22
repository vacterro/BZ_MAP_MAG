extends VBoxContainer
## Docked Native Sky, Fog & Environment panel inside Right Attributes Inspector.
## - Writable 1YKS Fog & Lighting controls (verified layouts only) on top.
## - Long Read-Only .SKY/.TRN chunk report placed in a collapsible section.

const Document := preload("res://core/map_document.gd")
const SkyEnv := preload("res://formats/sky_env.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

signal updated(message: String)
signal preview_toggled(enabled: bool)

var document: Document
var header_label := Label.new()
var inspector_text := RichTextLabel.new()
var inspector_section: CollapsibleSection
var preview_check := CheckBox.new()
var fog_color_picker := ColorPickerButton.new()
var fog_start_field := SliderField.new()
var fog_end_field := SliderField.new()
var vis_range_field := SliderField.new()
var sun_period_field := SliderField.new()
var sun_angle_field := SliderField.new()
var sun_color_picker := ColorPickerButton.new()
var ambient_color_picker := ColorPickerButton.new()
var apply_button := Button.new()
var reset_button := Button.new()
var status_label := Label.new()
var _rebuilding := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(header_label)

	preview_check.text = "Approximate Editor Preview (3D View Fog & Lighting)"
	preview_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_check.tooltip_text = "Approximate Godot viewport preview of .SKY fog and lighting; visual match to BZCC renderer is approximate."
	preview_check.toggled.connect(func(on: bool): preview_toggled.emit(on))
	add_child(preview_check)

	var fog_sec := CollapsibleSection.new("Fog & Visibility (1YKS)", "env_fog", false)
	add_child(fog_sec)
	_add_color_row(fog_sec.body, "Fog Color", fog_color_picker)
	_add_slider_row(fog_sec.body, "Fog Start", fog_start_field, 0.0, 4000.0, 5.0, 300.0, "m", 0.0, 2000.0)
	_add_slider_row(fog_sec.body, "Fog End", fog_end_field, 0.0, 4000.0, 5.0, 500.0, "m", 0.0, 2000.0)
	_add_slider_row(fog_sec.body, "Visibility", vis_range_field, 50.0, 6000.0, 10.0, 600.0, "m", 100.0, 2500.0)

	var sun_sec := CollapsibleSection.new("Sun & Ambient Lighting (1YKS)", "env_sun", false)
	add_child(sun_sec)
	_add_slider_row(sun_sec.body, "Sun Period", sun_period_field, 1.0, 120.0, 0.5, 24.0, "h", 1.0, 48.0)
	sun_period_field.tooltip_text = "Length of one full day/night cycle in real hours (verified in BZCC 2.0.185)."
	_add_slider_row(sun_sec.body, "Sun Angle", sun_angle_field, 0.0, 24.0, 0.1, 9.0, "h", 0.0, 24.0)
	sun_angle_field.tooltip_text = "Starting time of day in Sun Period hours (0.25*period=sunrise, 0.5*period=noon, 0.75*period=sunset)."
	_add_color_row(sun_sec.body, "Sun Color", sun_color_picker)
	_add_color_row(sun_sec.body, "Ambient", ambient_color_picker)

	var btn_row := HFlowContainer.new()
	btn_row.add_theme_constant_override("h_separation", 4)
	add_child(btn_row)
	apply_button.text = "Apply to .SKY (Undoable)"
	apply_button.pressed.connect(apply_edits)
	btn_row.add_child(apply_button)
	reset_button.text = "Reset"
	reset_button.pressed.connect(reset_edits)
	btn_row.add_child(reset_button)

	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	inspector_section = CollapsibleSection.new("Read-Only Native .SKY & .TRN Data", "env_native_data", true)
	add_child(inspector_section)
	inspector_text.fit_content = true
	inspector_text.scroll_active = false
	inspector_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_section.add_content(inspector_text)


func _add_slider_row(parent: Control, caption: String, field: SliderField, lo: float, hi: float, step_val: float, initial: float, unit: String, slider_lo: float, slider_hi: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 76
	row.add_child(lbl)
	field.min_value = lo
	field.max_value = hi
	field.step = step_val
	field.set_slider_range(slider_lo, slider_hi)
	field.set_unit_suffix(unit)
	field.set_readout_width(48.0)
	field.value = initial
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)


func _add_color_row(parent: Control, caption: String, picker: ColorPickerButton) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 76
	row.add_child(lbl)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(72, 22)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)


func begin(doc: Document, preview_enabled: bool = false) -> void:
	document = doc
	preview_check.set_pressed_no_signal(preview_enabled)
	refresh_all()


func refresh_all() -> void:
	if document == null:
		return
	_rebuilding = true
	var sky_info: Dictionary = document.package.sky_env
	var has_sky_file := not document.package.sky_name.is_empty()
	var readable_sky := document.has_readable_environment()
	var writable_sky := document.can_edit_environment()
	var sky_cap := String(sky_info.get("capability", SkyEnv.CAP_UNREADABLE))
	var layout_id := String(sky_info.get("layoutId", ""))
	var trn_env := SkyEnv.inspect_trn_environment(document.package.metadata.get("trn", {}))

	if writable_sky:
		header_label.text = ".SKY: %s (%d B, %s) · %s · Edited: %s" % [
			document.package.sky_name, int(sky_info["sizeBytes"]),
			layout_id, sky_cap, "yes" if document.has_environment_edits() else "no"]
	elif readable_sky:
		header_label.text = ".SKY: %s (%d B, v%d) · %s (Read-Only)" % [
			document.package.sky_name, int(sky_info["sizeBytes"]), int(sky_info["version"]), sky_cap]
	elif has_sky_file:
		header_label.text = ".SKY: %s · %s (Read-Only .TRN Only)" % [document.package.sky_name, sky_cap]
	else:
		header_label.text = ".SKY: (absent) · Read-Only .TRN Only"

	var lines: Array[String] = []
	if readable_sky:
		var ro: Dictionary = sky_info.get("readOnly", {})
		lines.append("=== Binary .SKY (%s) ===" % document.package.sky_name)
		lines.append("Capability: %s | Layout: %s" % [sky_cap, layout_id if not layout_id.is_empty() else "(unverified)"])
		if not writable_sky and not String(sky_info.get("writeRefusalReason", "")).is_empty():
			lines.append("Write Gate: " + String(sky_info["writeRefusalReason"]))
		lines.append("Dome Mesh (EMOD, read-only): %s" % (String(ro.get("domeMesh", "")) if not String(ro.get("domeMesh", "")).is_empty() else "(none)"))
		lines.append("Sky Texture (1YKS, read-only): %s" % (String(ro.get("skyTexture", "")) if not String(ro.get("skyTexture", "")).is_empty() else "(none)"))
		lines.append("Sun Texture (1YKS, read-only): %s" % (String(ro.get("sunTexture", "")) if not String(ro.get("sunTexture", "")).is_empty() else "(none)"))
		lines.append("Sky Height: %.1f m | SkyColor: %s" % [float(ro.get("skyHeight", 0.0)), String(ro.get("skyColorHex", ""))])
		lines.append("Chunks (%d):" % int(ro.get("chunkCount", 0)))
		for ch_v in sky_info.get("chunks", []):
			var ch: Dictionary = ch_v
			lines.append("  • %s (%d B @ %d)" % [String(ch["label"]), int(ch["size"]), int(ch["offset"])])
	else:
		lines.append("No readable binary .SKY file found beside this map.")
		if not String(sky_info.get("error", "")).is_empty():
			lines.append("Decode note: " + String(sky_info["error"]))
	lines.append("")
	lines.append("=== .TRN Sections (read-only) ===")
	for sec_key in ["normalView", "light", "sky", "world"]:
		var sec: Dictionary = trn_env.get(sec_key, {})
		if sec.is_empty():
			continue
		lines.append("[%s]" % sec_key)
		for k: String in sec:
			lines.append("  %s = %s" % [k, String(sec[k])])
	inspector_text.text = "\n".join(lines)

	var eff := document.effective_environment()
	var editable := writable_sky and not eff.is_empty()
	preview_check.disabled = not readable_sky or eff.is_empty()
	for ctrl: Control in [fog_color_picker, fog_start_field, fog_end_field, vis_range_field, sun_period_field, sun_angle_field, sun_color_picker, ambient_color_picker]:
		if ctrl is SliderField:
			(ctrl as SliderField).editable = editable
		elif ctrl is BaseButton:
			(ctrl as BaseButton).disabled = not editable
	apply_button.disabled = not editable
	reset_button.disabled = not editable or not document.has_environment_edits()

	if readable_sky and not eff.is_empty():
		var fc: Array = eff["fogColor"]
		fog_color_picker.color = Color(float(fc[0]), float(fc[1]), float(fc[2]), 1.0)
		fog_start_field.value = float(eff["fogStart"])
		fog_end_field.value = float(eff["fogEnd"])
		vis_range_field.value = float(eff["visibilityRange"])
		sun_period_field.value = float(eff["sunPeriod"])
		sun_angle_field.value = float(eff["sunAngle"])
		var sc: Array = eff["sunColor"]
		sun_color_picker.color = Color(float(sc[0]), float(sc[1]), float(sc[2]), 1.0)
		var ac: Array = eff["ambientColor"]
		ambient_color_picker.color = Color(float(ac[0]), float(ac[1]), float(ac[2]), 1.0)
	if editable:
		status_label.text = "Writes exact 1YKS floats to verified '%s' layout on Export Native (3D toggle = Approximate Editor Preview)." % layout_id
	elif readable_sky:
		status_label.text = "Read-only inspector active: %s" % String(sky_info.get("writeRefusalReason", "unverified SKY layout."))
	else:
		status_label.text = "Writable controls disabled: no verified writable .SKY layout present for native export."
	_rebuilding = false


func _collect_form_edits() -> Dictionary:
	var base: Dictionary = document.package.sky_env.get("fields", {}) if document != null else {}
	var fc := fog_color_picker.color
	var sc := sun_color_picker.color
	var ac := ambient_color_picker.color
	var all_vals := {
		"fogColor": [fc.r, fc.g, fc.b, 1.0],
		"fogStart": fog_start_field.value,
		"fogEnd": fog_end_field.value,
		"visibilityRange": vis_range_field.value,
		"sunPeriod": sun_period_field.value,
		"sunAngle": sun_angle_field.value,
		"sunColor": [sc.r, sc.g, sc.b, 1.0],
		"ambientColor": [ac.r, ac.g, ac.b, 1.0],
	}
	var changed := {}
	for k: String in all_vals:
		var val: Variant = all_vals[k]
		var base_val: Variant = base.get(k, null)
		if val is Array and base_val is Array and (val as Array).size() == 4 and (base_val as Array).size() == 4:
			for i in 4:
				if absf(float(val[i]) - float(base_val[i])) > 0.0005:
					changed[k] = val
					break
		elif (val is float or val is int) and (base_val is float or base_val is int):
			if absf(float(val) - float(base_val)) > 0.0005:
				changed[k] = float(val)
		else:
			changed[k] = val
	return changed


func apply_edits() -> void:
	if _rebuilding or document == null:
		return
	var next := _collect_form_edits()
	if not document.set_environment_edits(next):
		status_label.text = "[ERR] " + document.error
		return
	refresh_all()
	updated.emit("Updated native .SKY fog & lighting settings (undoable).")


func reset_edits() -> void:
	if _rebuilding or document == null:
		return
	if not document.set_environment_edits({}):
		status_label.text = "[ERR] " + document.error
		return
	refresh_all()
	updated.emit("Reset .SKY fog & lighting to source map values.")
