extends VBoxContainer
## Docked Right-Inspector Attributes panel for the currently selected BZN object.
## Replaces the old modal Object Label dialog and exposes transform, team,
## label, native capability, and safe actions right beside the viewport.

const Document := preload("res://core/map_document.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

signal updated(message: String)
signal focus_requested(view_index: int)
signal sound_edit_requested(view_index: int)
signal selection_cleared

var document: Document
var selected_view := -1
var header_label := Label.new()
var pos_x := SliderField.new()
var pos_y := SliderField.new()
var pos_z := SliderField.new()
var yaw_deg := SliderField.new()
var apply_xform_btn := Button.new()
var focus_btn := Button.new()
var label_field := LineEdit.new()
var apply_label_btn := Button.new()
var dup_btn := Button.new()
var remove_btn := Button.new()
var sound_btn := Button.new()
var meta_label := Label.new()
var status_label := Label.new()
var _rebuilding := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_label.text = "No object selected. Click an object in the Scene Tree or viewport (Move Object)."
	add_child(header_label)

	var xform_sec := CollapsibleSection.new("Transform", "obj_transform", false)
	add_child(xform_sec)
	_add_coord_row(xform_sec.body, "X (m)", pos_x, -65536.0, 65536.0, 0.5, "m")
	_add_coord_row(xform_sec.body, "Y (m)", pos_y, -10000.0, 10000.0, 0.1, "m")
	_add_coord_row(xform_sec.body, "Z (m)", pos_z, -65536.0, 65536.0, 0.5, "m")
	_add_coord_row(xform_sec.body, "Yaw (°)", yaw_deg, -180.0, 180.0, 1.0, "°")
	var xform_btns := HFlowContainer.new()
	xform_btns.add_theme_constant_override("h_separation", 4)
	xform_sec.add_content(xform_btns)
	apply_xform_btn.text = "Apply Transform"
	apply_xform_btn.pressed.connect(apply_transform)
	xform_btns.add_child(apply_xform_btn)
	focus_btn.text = "Focus Camera"
	focus_btn.pressed.connect(func():
		if selected_view >= 0:
			focus_requested.emit(selected_view))
	xform_btns.add_child(focus_btn)

	var id_sec := CollapsibleSection.new("Label & Actions", "obj_identity", false)
	add_child(id_sec)
	var lbl_row := HBoxContainer.new()
	lbl_row.add_theme_constant_override("separation", 4)
	id_sec.add_content(lbl_row)
	var ll := Label.new()
	ll.text = "Label"
	ll.custom_minimum_size.x = 46
	lbl_row.add_child(ll)
	label_field.placeholder_text = "ASCII label (empty clears)"
	label_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_field.text_submitted.connect(func(_t: String): apply_label())
	lbl_row.add_child(label_field)
	apply_label_btn.text = "Set"
	apply_label_btn.pressed.connect(apply_label)
	lbl_row.add_child(apply_label_btn)

	var act_row := HFlowContainer.new()
	act_row.add_theme_constant_override("h_separation", 4)
	act_row.add_theme_constant_override("v_separation", 3)
	id_sec.add_content(act_row)
	dup_btn.text = "Duplicate"
	dup_btn.pressed.connect(duplicate_selected)
	act_row.add_child(dup_btn)
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(remove_selected)
	act_row.add_child(remove_btn)
	sound_btn.text = "Sound Point…"
	sound_btn.pressed.connect(func():
		if selected_view >= 0:
			sound_edit_requested.emit(selected_view))
	act_row.add_child(sound_btn)

	var cap_sec := CollapsibleSection.new("Native Metadata & Capabilities", "obj_meta", false)
	add_child(cap_sec)
	meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap_sec.add_content(meta_label)

	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	refresh(null, -1)


func _add_coord_row(parent: Control, caption: String, field: SliderField, lo: float, hi: float, step_val: float, unit: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 54
	row.add_child(lbl)
	field.min_value = lo
	field.max_value = hi
	field.step = step_val
	field.set_unit_suffix(unit)
	field.set_readout_width(52.0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)


func refresh(doc: Document, view_index: int) -> void:
	_rebuilding = true
	document = doc
	selected_view = view_index
	var valid := document != null and document.valid_view_object(selected_view)
	for ctrl in [pos_x, pos_y, pos_z, yaw_deg]:
		(ctrl as SliderField).editable = valid
	for btn in [apply_xform_btn, focus_btn, apply_label_btn, dup_btn, remove_btn]:
		(btn as Button).disabled = not valid
	label_field.editable = valid
	if not valid:
		header_label.text = "No object selected. Pick an object in Scene Tree or viewport (Move Object)."
		label_field.text = ""
		meta_label.text = ""
		sound_btn.disabled = true
		sound_btn.visible = false
		status_label.text = ""
		_rebuilding = false
		return

	var odf := document.object_odf(selected_view)
	var team := document.object_team(selected_view)
	var xform := document.object_transform(selected_view)
	var lbl := document.object_label(selected_view)
	var terrain := document.package.terrain
	var lo := Vector2(terrain.origin) * terrain.SPACING
	var hi := lo + Vector2(terrain.dimensions) * terrain.SPACING
	pos_x.set_slider_range(lo.x, hi.x)
	pos_z.set_slider_range(lo.y, hi.y)
	pos_y.set_slider_range(terrain.min_height - 50.0, terrain.max_height + 100.0)
	pos_x.set_value_no_signal(xform.origin.x)
	pos_y.set_value_no_signal(xform.origin.y)
	pos_z.set_value_no_signal(xform.origin.z)
	yaw_deg.set_value_no_signal(rad_to_deg(xform.basis.get_euler().y))
	label_field.text = lbl

	header_label.text = "Object #%d  |  %s  |  Team %d" % [selected_view, odf, team]
	var is_snd := Document.is_sound_point_odf(odf)
	sound_btn.visible = is_snd
	sound_btn.disabled = not is_snd

	var stem := odf.get_basename().to_lower()
	var cap_lines: Array[String] = [
		"ODF: %s | Mod Profile: %s | BZN %d" % [odf, document.mod_profile, document.package.bzn_version],
	]
	if BznObjects.VERIFIED_NATIVE_CLASSES.has(stem):
		var spec: Dictionary = BznObjects.VERIFIED_NATIVE_CLASSES[stem]
		cap_lines.append("Class: %s (%s)" % [String(spec.get("classLabel", "")), String(spec.get("category", ""))])
		cap_lines.append("Tiers: Binary=%s | Engine=%s | Gameplay=%s" % [
			String(spec.get("binaryMatch", "")), String(spec.get("engineLoad", "")), String(spec.get("gameplayBehavior", ""))])
	else:
		cap_lines.append("Serialization: In-map native record (Move/Rotate/Label/Clone supported)")
	meta_label.text = "\n".join(cap_lines)
	status_label.text = ""
	_rebuilding = false


func apply_transform() -> void:
	if _rebuilding or document == null or not document.valid_view_object(selected_view):
		return
	var target_pos := Vector3(pos_x.value, pos_y.value, pos_z.value)
	var cur := document.object_transform(selected_view)
	var cur_yaw := rad_to_deg(cur.basis.get_euler().y)
	var moved := false
	if cur.origin.distance_to(target_pos) > 0.001:
		if not document.move_object(selected_view, target_pos):
			status_label.text = "[ERR] " + document.error
			return
		moved = true
	var dyaw := yaw_deg.value - cur_yaw
	if absf(dyaw) > 0.05:
		if not document.rotate_object(selected_view, deg_to_rad(dyaw)):
			status_label.text = "[ERR] " + document.error
			return
		moved = true
	if moved:
		status_label.text = "[OK] Updated object #%d transform." % selected_view
		updated.emit("Updated object #%d (%s) transform." % [selected_view, document.object_odf(selected_view)])
	else:
		status_label.text = "Transform unchanged."


func apply_label() -> void:
	if _rebuilding or document == null or not document.valid_view_object(selected_view):
		return
	var next_label := label_field.text.strip_edges()
	if not document.set_object_label(selected_view, next_label):
		status_label.text = "[ERR] " + document.error
		return
	status_label.text = "[OK] Updated label."
	updated.emit("Updated object #%d label: %s" % [selected_view, next_label if not next_label.is_empty() else "(cleared)"])


func duplicate_selected() -> void:
	if document == null or not document.valid_view_object(selected_view):
		return
	var origin := document.object_position(selected_view)
	var dup := document.duplicate_object(selected_view, origin + Vector3(4.0, 0.0, 4.0))
	if dup < 0:
		status_label.text = "[ERR] " + document.error
		return
	refresh(document, dup)
	updated.emit("Duplicated object as #%d (%s)." % [dup, document.object_odf(dup)])


func remove_selected() -> void:
	if document == null or not document.valid_view_object(selected_view):
		return
	var removed_odf := document.object_odf(selected_view)
	if not document.remove_object(selected_view):
		status_label.text = "[ERR] " + document.error
		return
	refresh(document, -1)
	selection_cleared.emit()
	updated.emit("Removed %s. Undo restores it." % removed_odf)
