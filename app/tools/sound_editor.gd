extends ConfirmationDialog
## Structured editor for VRV sound points:
## vrvsnd:<sound>:<volume>:<range>:<interval>:<jitter>:<pitch>:<near>
## Edits the selected object's label (or duplicates an existing sound point)
## with full numeric validation, sound asset inspection, Undo/Redo, BZMAG
## persistence and native BZN export.

const Document := preload("res://core/map_document.gd")

signal updated(message: String)

var document: Document
var selected_view := -1
var game_dir := ""
var vrv_dir := ""
var target_label := Label.new()
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
	ok_button_text = "Apply Label"
	dialog_hide_on_ok = false
	min_size = Vector2i(460, 390)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(target_label)

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
	asset_status.custom_minimum_size.y = 40
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


func begin(doc: Document, view_index: int, game_path: String = "", vrv_path: String = "") -> void:
	document = doc
	selected_view = view_index
	game_dir = game_path
	vrv_dir = vrv_path
	if document == null or not document.valid_view_object(selected_view):
		target_label.text = "Select an object in Move Object mode first."
		asset_status.text = "Note: stock 185 only plays VRV sound points when VRV runtime is active."
		ok_button_disabled(true)
		popup_centered()
		return
	ok_button_disabled(false)
	var odf := document.object_odf(selected_view)
	var current := document.object_label(selected_view)
	target_label.text = "Object #%d (%s) · Current label: %s" % [selected_view, odf, current if not current.is_empty() else "(none)"]
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


func apply_sound_point() -> void:
	if document == null or not document.valid_view_object(selected_view):
		return
	var built := encoded_label()
	if not String(built["error"]).is_empty():
		asset_status.text = "[ERR] " + String(built["error"])
		return
	var lbl := String(built["label"])
	if not document.set_object_label(selected_view, lbl):
		asset_status.text = "[ERR] " + document.error
		return
	updated.emit("Updated sound point label: " + lbl)
	hide()


func duplicate_sound_point() -> void:
	if document == null or not document.valid_view_object(selected_view):
		return
	var built := encoded_label()
	if not String(built["error"]).is_empty():
		asset_status.text = "[ERR] " + String(built["error"])
		return
	var pos := document.object_transform(selected_view).origin + Vector3(8.0, 0.0, 8.0)
	var dup := document.duplicate_object(selected_view, pos)
	if dup < 0:
		asset_status.text = "[ERR] " + document.error
		return
	if not document.set_object_label(dup, String(built["label"])):
		asset_status.text = "[ERR] " + document.error
		return
	updated.emit("Duplicated sound point #%d with label %s." % [dup, built["label"]])
	hide()
