extends ConfirmationDialog
## Structured editor for VRV sound points:
## vrvsnd:<sound>:<volume>:<range>:<interval>:<jitter>:<pitch>:<near>
## Strictly gated to verified sound-point-compatible ODF classes (vrv_sndpoint).
## Ordinary object names belong in the generic Object Label editor.

const Document := preload("res://core/map_document.gd")

signal updated(message: String)
signal sound_point_selected(view_index: int)

var document: Document
var selected_view := -1
var game_dir := ""
var vrv_dir := ""
var target_label := Label.new()
var existing_row := HBoxContainer.new()
var existing_select := OptionButton.new()
var select_existing_btn := Button.new()
var sound_field := LineEdit.new()
var volume_spin := SpinBox.new()
var range_spin := SpinBox.new()
var interval_spin := SpinBox.new()
var jitter_spin := SpinBox.new()
var pitch_spin := SpinBox.new()
var near_spin := SpinBox.new()
var asset_status := Label.new()
var duplicate_btn: Button


func _ready() -> void:
	title = "Sound Point Editor"
	ok_button_text = "Apply Sound Point"
	dialog_hide_on_ok = false
	min_size = Vector2i(480, 420)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(target_label)

	var existing_lbl := Label.new()
	existing_lbl.text = "Existing sound points"
	existing_row.add_child(existing_lbl)
	existing_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	existing_row.add_child(existing_select)
	select_existing_btn.text = "Select"
	select_existing_btn.pressed.connect(select_chosen_sound_point)
	existing_row.add_child(select_existing_btn)
	existing_row.hide()
	layout.add_child(existing_row)

	var sound_row := HBoxContainer.new()
	layout.add_child(sound_row)
	var slbl := Label.new()
	slbl.text = "Sound file (.wav/.ogg)"
	slbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_row.add_child(slbl)
	sound_field.custom_minimum_size.x = 200
	sound_field.text_changed.connect(func(_t): refresh_asset_status())
	sound_row.add_child(sound_field)

	add_spin(layout, "Volume (%)", volume_spin, 0, 100, 70)
	add_spin(layout, "Range (m)", range_spin, 10, 2000, 150)
	add_spin(layout, "Interval (s, 0=loop)", interval_spin, 0, 600, 0)
	add_spin(layout, "Jitter (%)", jitter_spin, 0, 100, 0)
	add_spin(layout, "Pitch (%)", pitch_spin, 25, 200, 100)
	add_spin(layout, "Near full-vol (%)", near_spin, 0, 90, 20)

	asset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	asset_status.custom_minimum_size.y = 48
	layout.add_child(asset_status)

	duplicate_btn = add_button("Duplicate Sound Point", true, "dup")
	custom_action.connect(func(action: StringName):
		if action == &"dup":
			duplicate_sound_point()
	)
	confirmed.connect(apply_sound_point)


func add_spin(parent: Control, caption: String, spin: SpinBox, lo: int, hi: int, initial: int) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	spin.min_value = lo
	spin.max_value = hi
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size.x = 120
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
	begin(document, chosen, game_dir, vrv_dir)


func begin(doc: Document, view_index: int, game_path: String = "", vrv_path: String = "") -> void:
	document = doc
	selected_view = view_index
	game_dir = game_path
	vrv_dir = vrv_path
	_refresh_existing_picker()
	if document == null or not document.valid_view_object(selected_view):
		var available := document.sound_point_views().size() if document != null else 0
		target_label.text = "No object selected. Select a %s object in Move Object mode first." % Document.SOUND_POINT_ODF
		asset_status.text = (
			"[ERR] Select an existing %s sound point above (%d available). Playback requires VRV runtime." % [Document.SOUND_POINT_ODF, available]
			if available > 0 else
			"[ERR] No %s sound points exist in this map. Playback requires VRV runtime." % Document.SOUND_POINT_ODF
		)
		ok_button_disabled(true)
		popup_centered()
		return
	var odf := document.object_odf(selected_view)
	var current := document.object_label(selected_view)
	if not Document.is_sound_point_odf(odf):
		var available := document.sound_point_views().size()
		target_label.text = "Object #%d (%s) is NOT a VRV sound point (%s)." % [selected_view, odf, Document.SOUND_POINT_ODF]
		asset_status.text = (
			"[ERR] Incompatible ODF '%s': its label will not be modified. Pick one of the %d existing %s object(s) above or use Object Label for ordinary names." % [odf, available, Document.SOUND_POINT_ODF]
			if available > 0 else
			"[ERR] Incompatible ODF '%s': this map has no %s sound points. Use Object Label for ordinary object names." % [odf, Document.SOUND_POINT_ODF]
		)
		ok_button_disabled(true)
		popup_centered()
		return
	ok_button_disabled(false)
	target_label.text = "Sound Point #%d (%s) · Current label: %s" % [selected_view, odf, current if not current.is_empty() else "(none)"]
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
	popup_centered()


func ok_button_disabled(flag: bool) -> void:
	get_ok_button().disabled = flag
	if duplicate_btn != null:
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
	if not game_dir.is_empty():
		roots.append(game_dir.path_join("bz2r_res/audio"))
		roots.append(game_dir.path_join("bz2r_res"))
		if not vrv_dir.is_empty():
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
	updated.emit("Updated sound point label: " + lbl)
	hide()


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
	updated.emit("Duplicated sound point #%d with label %s." % [dup, built["label"]])
	hide()
