extends VBoxContainer
## Docked Sound Point editor inside Right Attributes Inspector.
## Structured editor for VRV sound points:
## vrvsnd:<sound>:<volume>:<range>:<interval>:<jitter>:<pitch>:<near>
## Strictly gated to verified sound-point-compatible ODF classes (vrv_sndpoint).

const Document := preload("res://core/map_document.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")

signal updated(message: String)
signal sound_point_selected(view_index: int)

var document: Document
var selected_view := -1
var game_dir := ""
var vrv_dir := ""
var extra_sound_roots: Array = []
var target_label := Label.new()
var existing_row := VBoxContainer.new()
var existing_select := ChoiceGroup.new(0)
var select_existing_btn := Button.new()
var editor_fields := VBoxContainer.new()
var sound_field := LineEdit.new()
var volume_spin := SliderField.new()
var range_spin := SliderField.new()
var interval_spin := SliderField.new()
var jitter_spin := SliderField.new()
var pitch_spin := SliderField.new()
var near_spin := SliderField.new()
var asset_status := Label.new()
var apply_btn := Button.new()
var duplicate_btn := Button.new()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(target_label)

	var existing_hdr := HBoxContainer.new()
	var existing_lbl := Label.new()
	existing_lbl.text = "Existing sound points"
	existing_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	existing_hdr.add_child(existing_lbl)
	select_existing_btn.text = "Select"
	select_existing_btn.pressed.connect(select_chosen_sound_point)
	existing_hdr.add_child(select_existing_btn)
	existing_row.add_child(existing_hdr)
	existing_select.item_selected.connect(func(_idx: int): select_chosen_sound_point())
	existing_row.add_child(existing_select)
	existing_row.hide()
	add_child(existing_row)

	editor_fields.add_theme_constant_override("separation", 3)
	add_child(editor_fields)
	var sound_row := HBoxContainer.new()
	editor_fields.add_child(sound_row)
	var slbl := Label.new()
	slbl.text = "Sound file"
	slbl.custom_minimum_size.x = 78
	sound_row.add_child(slbl)
	sound_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_field.text_changed.connect(func(_t): refresh_asset_status())
	sound_row.add_child(sound_field)

	add_spin(editor_fields, "Volume (%)", volume_spin, 0, 100, 70, "%")
	add_spin(editor_fields, "Range (m)", range_spin, 10, 2000, 150, "m")
	add_spin(editor_fields, "Interval (s)", interval_spin, 0, 600, 0, "s")
	add_spin(editor_fields, "Jitter (%)", jitter_spin, 0, 100, 0, "%")
	add_spin(editor_fields, "Pitch (%)", pitch_spin, 25, 200, 100, "%")
	add_spin(editor_fields, "Near vol (%)", near_spin, 0, 90, 20, "%")

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 4)
	add_child(actions)
	apply_btn.text = "Apply Sound Point"
	apply_btn.pressed.connect(apply_sound_point)
	actions.add_child(apply_btn)
	duplicate_btn.text = "Duplicate"
	duplicate_btn.pressed.connect(duplicate_sound_point)
	actions.add_child(duplicate_btn)

	asset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(asset_status)


func get_ok_button() -> Button:
	return apply_btn


func add_spin(parent: Control, caption: String, spin: SliderField, lo: int, hi: int, initial: int, unit: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 78
	row.add_child(lbl)
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	if not unit.is_empty():
		spin.set_unit_suffix(unit)
	spin.set_readout_width(44.0)
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(_v: float): refresh_asset_status())
	row.add_child(spin)


func _refresh_existing_picker() -> void:
	existing_select.clear()
	if document == null:
		existing_row.hide()
		return
	var views := document.sound_point_views()
	for v in views:
		var lbl := document.object_label(v)
		var caption := "#%d (%s)%s" % [v, document.object_odf(v), " · " + lbl if not lbl.is_empty() else ""]
		existing_select.add_item(caption)
		existing_select.set_item_metadata(existing_select.item_count - 1, v)
	existing_row.visible = not views.is_empty()
	if not views.is_empty():
		var idx := views.find(selected_view)
		existing_select.select(idx if idx >= 0 else 0)


func select_chosen_sound_point() -> void:
	if document == null or existing_select.selected < 0 or existing_select.item_count == 0:
		return
	var chosen := int(existing_select.get_item_metadata(existing_select.selected))
	if not document.object_is_sound_point(chosen):
		return
	sound_point_selected.emit(chosen)
	begin(document, chosen, game_dir, vrv_dir, extra_sound_roots)


func begin(doc: Document, view_index: int, game_path: String = "", vrv_path: String = "", sound_roots: Array = []) -> void:
	document = doc
	selected_view = view_index
	game_dir = game_path
	vrv_dir = vrv_path
	extra_sound_roots = sound_roots.duplicate()
	_refresh_existing_picker()
	if document == null or not document.valid_view_object(selected_view):
		var available := document.sound_point_views().size() if document != null else 0
		target_label.text = "No object selected. Select a %s object in Scene Tree or Move Object." % Document.SOUND_POINT_ODF
		asset_status.text = (
			"[ERR] Select an existing %s sound point above (%d available). Playback requires VRV runtime." % [Document.SOUND_POINT_ODF, available]
			if available > 0 else
			"[ERR] No %s sound points exist in this map. Playback requires VRV runtime." % Document.SOUND_POINT_ODF
		)
		editor_fields.hide()
		ok_button_disabled(true)
		return
	var odf := document.object_odf(selected_view)
	var current := document.object_label(selected_view)
	if not Document.is_sound_point_odf(odf):
		var available := document.sound_point_views().size()
		target_label.text = "Object #%d (%s) is NOT a VRV sound point (%s)." % [selected_view, odf, Document.SOUND_POINT_ODF]
		asset_status.text = (
			"[ERR] Incompatible ODF '%s': its label will not be modified. Pick one of the %d existing %s object(s) above or use Object Attributes for ordinary names." % [odf, available, Document.SOUND_POINT_ODF]
			if available > 0 else
			"[ERR] Incompatible ODF '%s': this map has no %s sound points. Use Object Attributes for ordinary names." % [odf, Document.SOUND_POINT_ODF]
		)
		editor_fields.hide()
		ok_button_disabled(true)
		return
	editor_fields.show()
	ok_button_disabled(false)
	target_label.text = "Sound Point #%d (%s) · Current: %s" % [selected_view, odf, current if not current.is_empty() else "(none)"]
	var parsed := Document.sound_point(current)
	if not parsed.is_empty():
		sound_field.text = String(parsed["sound"])
		volume_spin.value = int(parsed["volume"])
		range_spin.value = int(parsed["range"])
		interval_spin.value = int(parsed["interval"])
		jitter_spin.value = int(parsed["jitter"])
		pitch_spin.value = int(parsed["pitch"])
		near_spin.value = int(parsed["near"])
	else:
		sound_field.text = "ambient.wav"
		volume_spin.value = 70
		range_spin.value = 150
		interval_spin.value = 0
		jitter_spin.value = 0
		pitch_spin.value = 100
		near_spin.value = 20
	refresh_asset_status()


func ok_button_disabled(flag: bool) -> void:
	apply_btn.disabled = flag
	duplicate_btn.disabled = flag


func encoded_label() -> Dictionary:
	return Document.format_sound_point({
		"sound": sound_field.text,
		"volume": int(volume_spin.value),
		"range": int(range_spin.value),
		"interval": int(interval_spin.value),
		"jitter": int(jitter_spin.value),
		"pitch": int(pitch_spin.value),
		"near": int(near_spin.value),
	})


func find_sound_asset(filename: String) -> String:
	if document == null or filename.is_empty():
		return ""
	var candidates := [filename]
	if filename.to_lower().ends_with(".wav"):
		candidates.append(filename.substr(0, filename.length() - 4) + ".ogg")
	var roots: Array[String] = [document.package.source_path.get_base_dir()]
	for r_v in extra_sound_roots:
		var r := String(r_v)
		if not r.is_empty() and not (r in roots):
			roots.append(r)
	if not game_dir.is_empty():
		roots.append(game_dir.path_join("bz2r_res/audio"))
		roots.append(game_dir.path_join("bz2r_res"))
		if document.mod_profile != "stock" and not vrv_dir.is_empty():
			roots.append(game_dir.path_join("VRV/deps/VSR"))
	for root in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		var found := _scan_for_file(root, candidates, 3)
		if not found.is_empty():
			return found
	return ""


func _scan_for_file(dir_path: String, names: Array, depth: int) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	for file_name: String in dir.get_files():
		for wanted: String in names:
			if file_name.nocasecmp_to(wanted) == 0:
				return dir_path.path_join(file_name)
	if depth <= 0:
		return ""
	for sub: String in dir.get_directories():
		var hit := _scan_for_file(dir_path.path_join(sub), names, depth - 1)
		if not hit.is_empty():
			return hit
	return ""


func refresh_asset_status() -> void:
	if document == null or not document.object_is_sound_point(selected_view):
		return
	var built := encoded_label()
	if not String(built["error"]).is_empty():
		asset_status.text = "[ERR] " + String(built["error"])
		return
	var parsed := Document.sound_point(String(built["label"]))
	var hit := find_sound_asset(String(parsed["sound"]))
	if hit.is_empty():
		asset_status.text = "[WARN] Sound asset '%s' not found in map/local audio folders (may reside in packed game assets). Playback requires VRV runtime." % parsed["sound"]
	else:
		asset_status.text = "[OK] Sound asset found: %s (playback requires VRV runtime)." % hit.get_file()


func _duplicate_position(origin: Vector3) -> Vector3:
	for delta: Vector3 in [Vector3(8.0, 0.0, 8.0), Vector3(-8.0, 0.0, -8.0), Vector3(8.0, 0.0, -8.0), Vector3(-8.0, 0.0, 8.0)]:
		var candidate := origin + delta
		if document.valid_object_position(candidate):
			return candidate
	var terrain := document.package.terrain
	var lo := Vector2(terrain.origin) * terrain.SPACING
	var hi := lo + Vector2(terrain.dimensions - Vector2i.ONE) * terrain.SPACING
	return Vector3(clampf(origin.x, lo.x, hi.x), origin.y, clampf(origin.z, lo.y, hi.y))


func apply_sound_point() -> void:
	if document == null or not document.valid_view_object(selected_view):
		asset_status.text = "[ERR] Select a %s sound point first." % Document.SOUND_POINT_ODF
		return
	if not document.object_is_sound_point(selected_view):
		asset_status.text = "[ERR] Object #%d (%s) is not a %s sound point." % [selected_view, document.object_odf(selected_view), Document.SOUND_POINT_ODF]
		return
	var built := encoded_label()
	if not String(built["error"]).is_empty():
		asset_status.text = "[ERR] " + String(built["error"])
		return
	var lbl := String(built["label"])
	if not document.set_sound_point_label(selected_view, lbl):
		asset_status.text = "[ERR] " + document.error
		return
	target_label.text = "Sound Point #%d (%s) · Current: %s" % [selected_view, document.object_odf(selected_view), lbl]
	updated.emit("Updated sound point label: " + lbl)


func duplicate_sound_point() -> void:
	if document == null or not document.valid_view_object(selected_view):
		asset_status.text = "[ERR] Select a %s sound point first." % Document.SOUND_POINT_ODF
		return
	if not document.object_is_sound_point(selected_view):
		asset_status.text = "[ERR] Object #%d (%s) is not a %s sound point." % [selected_view, document.object_odf(selected_view), Document.SOUND_POINT_ODF]
		return
	var built := encoded_label()
	if not String(built["error"]).is_empty():
		asset_status.text = "[ERR] " + String(built["error"])
		return
	var pos := _duplicate_position(document.object_transform(selected_view).origin)
	var dup := document.duplicate_sound_point(selected_view, pos, String(built["label"]))
	if dup < 0:
		asset_status.text = "[ERR] " + document.error
		return
	selected_view = dup
	_refresh_existing_picker()
	updated.emit("Duplicated sound point #%d with label %s." % [dup, built["label"]])
