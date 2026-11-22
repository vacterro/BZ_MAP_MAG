extends VBoxContainer
## Docked Mission & Path Studio inside Right Attributes Inspector.
## Compact single-column collapsible sections keep the 2D/3D viewport open
## while managing mission profiles, presets, multi-path transforms & validation.

const Document := preload("res://core/map_document.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

signal paths_selection_changed(indices: Array[int])
signal path_focused(index: int)
signal snap_toggled(enabled: bool)
signal status_message(text: String)

var document: Document
var anchor := Vector2.INF
var mod_badge := Label.new()
var profile_select := ChoiceGroup.new(0)
var profile_note := Label.new()
var preset_list := ItemList.new()
var preset_detail := Label.new()
var create_preset_button: Button
var generate_profile_button: Button
var propose_edge_button: Button
var path_list := ItemList.new()
var empty_paths_note := Label.new()
var delta_x := SliderField.new()
var delta_z := SliderField.new()
var rotate_deg := SliderField.new()
var spacing_m := SliderField.new()
var snap_check := CheckBox.new()
var translate_rotate_button: Button
var mirror_x_button: Button
var mirror_z_button: Button
var clone_button: Button
var resample_button: Button
var snap_now_button: Button
var validation_label := RichTextLabel.new()
var _rebuilding := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	var mode_sec := CollapsibleSection.new("Mission Profile & Validation", "mission_profile", false)
	add_child(mode_sec)
	for id: String in MissionProfiles.MISSION_MODES:
		profile_select.add_item(String(MissionProfiles.MODE_LABELS.get(id, id)))
		profile_select.set_item_metadata(profile_select.item_count - 1, id)
	profile_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_select.item_selected.connect(_on_mission_mode_selected)
	mode_sec.add_content(profile_select)

	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 4)
	top.add_theme_constant_override("v_separation", 3)
	mode_sec.add_content(top)
	generate_profile_button = add_btn(top, "Generate Required", generate_missing_required)
	propose_edge_button = add_btn(top, "Propose edge_path", create_proposed_edge_path)
	snap_check.text = "Snap drag 2 m"
	snap_check.toggled.connect(func(on: bool): snap_toggled.emit(on))
	top.add_child(snap_check)

	mod_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_sec.add_content(mod_badge)
	profile_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_sec.add_content(profile_note)
	validation_label.fit_content = true
	validation_label.scroll_active = false
	validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_sec.add_content(validation_label)

	var paths_sec := CollapsibleSection.new("Map Paths & Batch Transform", "mission_paths", false)
	add_child(paths_sec)
	empty_paths_note.text = "No paths in map — select a preset or click Generate Required."
	empty_paths_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_paths_note.hide()
	paths_sec.add_content(empty_paths_note)
	path_list.select_mode = ItemList.SELECT_MULTI
	path_list.custom_minimum_size.y = 110
	path_list.multi_selected.connect(func(_i, _s): emit_selection())
	path_list.item_selected.connect(func(_i): emit_selection())
	paths_sec.add_content(path_list)

	add_spin(paths_sec.body, "dX (m)", delta_x, -4096.0, 4096.0, 2.0, 0.0, "m", -512.0, 512.0)
	add_spin(paths_sec.body, "dZ (m)", delta_z, -4096.0, 4096.0, 2.0, 0.0, "m", -512.0, 512.0)
	add_spin(paths_sec.body, "Rot (°)", rotate_deg, -180.0, 180.0, 1.0, 0.0, "°")
	add_spin(paths_sec.body, "Spacing", spacing_m, 2.0, 512.0, 2.0, 32.0, "m")

	var op_row := HFlowContainer.new()
	op_row.add_theme_constant_override("h_separation", 4)
	op_row.add_theme_constant_override("v_separation", 3)
	paths_sec.add_content(op_row)
	translate_rotate_button = add_btn(op_row, "Transform", apply_transform)
	mirror_x_button = add_btn(op_row, "Mirror X", func(): apply_mirror(true, false))
	mirror_z_button = add_btn(op_row, "Mirror Z", func(): apply_mirror(false, true))
	clone_button = add_btn(op_row, "Clone", clone_selected_path)
	resample_button = add_btn(op_row, "Resample", apply_resample)
	snap_now_button = add_btn(op_row, "Snap 2 m", apply_snap_grid)

	var presets_sec := CollapsibleSection.new("Path Presets", "mission_presets", false)
	add_child(presets_sec)
	preset_list.custom_minimum_size.y = 110
	preset_list.item_selected.connect(func(_i): update_preset_detail())
	presets_sec.add_content(preset_list)
	preset_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	presets_sec.add_content(preset_detail)
	create_preset_button = add_btn(presets_sec.body, "Create Selected Preset", create_selected_preset)


func add_btn(parent: Control, text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn


func add_spin(parent: Control, caption: String, box: SliderField, lo: float, hi: float, step_val: float, initial: float, unit: String = "", slider_lo: float = NAN, slider_hi: float = NAN) -> void:
	var grp := HBoxContainer.new()
	grp.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 60
	grp.add_child(lbl)
	box.min_value = lo
	box.max_value = hi
	box.step = step_val
	if is_finite(slider_lo) and is_finite(slider_hi):
		box.set_slider_range(slider_lo, slider_hi)
	if not unit.is_empty():
		box.set_unit_suffix(unit)
	box.value = initial
	box.set_readout_width(44.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grp.add_child(box)
	parent.add_child(grp)


func current_profile_id() -> String:
	var idx := maxi(profile_select.selected, 0)
	return String(profile_select.get_item_metadata(idx))


func current_mod_id() -> String:
	return document.mod_profile if document != null else "stock"


func _sync_profile_select() -> void:
	if document == null:
		return
	var target := document.mission_profile
	var idx := MissionProfiles.MISSION_MODES.find(target)
	if idx >= 0:
		profile_select.select(idx)


func _on_mission_mode_selected(_idx: int) -> void:
	if _rebuilding or document == null:
		return
	var next_mode := current_profile_id()
	if document.mission_profile != next_mode:
		document.set_target_profile(document.mod_profile, next_mode)
	refresh_all()


func begin(doc: Document, world_anchor: Vector2) -> void:
	document = doc
	anchor = world_anchor
	_sync_profile_select()
	refresh_all()


func refresh_all() -> void:
	if document == null or _rebuilding:
		return
	_rebuilding = true
	_sync_profile_select()
	var profile_id := current_profile_id()
	var mod_id := current_mod_id()
	var validation := MissionProfiles.validate(document, profile_id, mod_id)
	var contract := MissionProfiles.contract_for(profile_id, mod_id)
	var dll_text := String(document.effective_mission_dll()) if document.has_method("effective_mission_dll") else String(document.package.mission_dll)
	if dll_text.is_empty():
		dll_text = "(none in BZN)"
	mod_badge.text = "Mod: %s · DLL: %s · %s" % [
		mod_id, dll_text, String(validation.get("semantics", "UNKNOWN"))]
	profile_note.text = String(validation["dll_note"])

	var active_names := {}
	for idx: int in document.path_indices():
		var p: Dictionary = document.path_at(idx)
		active_names[String(p["name"]).to_lower()] = true

	var prev_preset := preset_list.get_selected_items()[0] if not preset_list.get_selected_items().is_empty() else 0
	preset_list.clear()
	var req_set := {}
	for r: String in contract.get("required", []):
		req_set[r.to_lower()] = true
	var rec_set := {}
	for r: String in contract.get("recommended", []):
		rec_set[r.to_lower()] = true

	for pname: String in MissionProfiles.presets_for(profile_id, mod_id):
		var key := pname.to_lower()
		var badge := "[OK]" if active_names.has(key) else ("[REQ]" if req_set.has(key) else ("[REC]" if rec_set.has(key) else "[OPT]"))
		preset_list.add_item("%s %s (%s)" % [badge, pname, MissionProfiles.PRESETS[pname]["category"]])
		preset_list.set_item_metadata(preset_list.item_count - 1, pname)
	if preset_list.item_count > 0:
		preset_list.select(clampi(prev_preset, 0, preset_list.item_count - 1))
	update_preset_detail()

	var prev_selected := selected_path_indices()
	path_list.clear()
	var type_names: Array[String] = ["One-Way", "Round Trip", "Loop"]
	var indices := document.path_indices()
	empty_paths_note.visible = indices.is_empty()
	for idx: int in indices:
		var p: Dictionary = document.path_at(idx)
		var tname: String = type_names[clampi(int(p["type"]), 0, 2)]
		path_list.add_item("%s · %d pts · %s" % [p["name"], (p["points"] as PackedVector2Array).size(), tname])
		var row := path_list.item_count - 1
		path_list.set_item_metadata(row, idx)
		if idx in prev_selected:
			path_list.select(row, false)

	var can_resize := document.package.path_codec.can_resize
	create_preset_button.disabled = not can_resize
	generate_profile_button.disabled = not can_resize
	propose_edge_button.disabled = not can_resize
	clone_button.disabled = not can_resize

	var lines: Array[String] = []
	if validation["ok"]:
		lines.append("[OK] %s required paths valid." % validation["label"])
	else:
		for err: String in validation["errors"]:
			lines.append("[ERR] " + err)
	for warn: String in validation["warnings"]:
		lines.append("[WARN] " + warn)
	if lines.size() > 4:
		var shown := lines.slice(0, 3)
		shown.append("… (+%d more notice(s))" % (lines.size() - 3))
		validation_label.text = "\n".join(shown)
	else:
		validation_label.text = "\n".join(lines)
	validation_label.visible = not validation_label.text.is_empty()
	_rebuilding = false


func update_preset_detail() -> void:
	var items := preset_list.get_selected_items()
	if items.is_empty():
		preset_detail.text = ""
		preset_detail.hide()
		return
	var pname := String(preset_list.get_item_metadata(items[0]))
	var info: Dictionary = MissionProfiles.PRESETS.get(pname, {})
	preset_detail.text = "%s — %s" % [pname, String(info.get("description", ""))]
	preset_detail.visible = not preset_detail.text.is_empty()


func selected_path_indices() -> Array[int]:
	var result: Array[int] = []
	for row: int in path_list.get_selected_items():
		var meta: Variant = path_list.get_item_metadata(row)
		if meta != null and int(meta) >= 0:
			result.append(int(meta))
	return result


func emit_selection() -> void:
	if _rebuilding:
		return
	var indices := selected_path_indices()
	paths_selection_changed.emit(indices)
	if not indices.is_empty():
		path_focused.emit(indices[0])


func create_selected_preset() -> void:
	if document == null or preset_list.get_selected_items().is_empty():
		return
	var pname := String(preset_list.get_item_metadata(preset_list.get_selected_items()[0]))
	var pts := MissionProfiles.preset_points(pname, document.package.terrain, anchor)
	var ptype := MissionProfiles.preset_type(pname)
	var created := document.create_path(pname, pts, ptype)
	if created < 0:
		status_message.emit(document.error)
		return
	refresh_all()
	path_focused.emit(created)
	status_message.emit("Created path %s (%d pts)." % [pname, pts.size()])


func create_proposed_edge_path() -> void:
	if document == null:
		return
	var pts := MissionProfiles.propose_edge_path(document.package.terrain)
	var existing := -1
	for idx: int in document.path_indices():
		if String(document.path_at(idx)["name"]).nocasecmp_to("edge_path") == 0:
			existing = idx
			break
	if existing >= 0:
		if not document.edit_path(existing, document.path_at(existing)["name"], pts, 2):
			status_message.emit(document.error)
			return
		path_focused.emit(existing)
	else:
		var created := document.create_path("edge_path", pts, 2)
		if created < 0:
			status_message.emit(document.error)
			return
		path_focused.emit(created)
	refresh_all()
	status_message.emit("Proposed edge_path boundary loop.")


func generate_missing_required() -> void:
	if document == null:
		return
	var profile_id := current_profile_id()
	var validation := MissionProfiles.validate(document, profile_id, current_mod_id())
	var missing: Array = validation["missing_required"]
	if missing.is_empty():
		status_message.emit("All required paths for %s already exist." % validation["label"])
		return
	var specs: Array[Dictionary] = []
	for pname: String in missing:
		specs.append({
			"name": pname,
			"points": MissionProfiles.preset_points(pname, document.package.terrain, anchor),
			"type": MissionProfiles.preset_type(pname),
		})
	var created := document.create_paths_batch(specs)
	if created.is_empty():
		status_message.emit(document.error)
		return
	refresh_all()
	path_focused.emit(created[0])
	status_message.emit("Generated %d required paths for %s (1 undo step)." % [created.size(), validation["label"]])


func apply_transform() -> void:
	transform_selected(Vector2(delta_x.value, delta_z.value), rotate_deg.value, false, false)


func apply_mirror(mx: bool, mz: bool) -> void:
	transform_selected(Vector2.ZERO, 0.0, mx, mz)


func transform_selected(delta: Vector2, rot_deg: float, mx: bool, mz: bool) -> void:
	if document == null:
		return
	var indices := selected_path_indices()
	if indices.is_empty():
		status_message.emit("Select one or more paths in Mission Studio first.")
		return
	var terrain := document.package.terrain
	var rect := MissionProfiles.terrain_world_rect(terrain)
	var sym_origin := rect.position + rect.size * 0.5
	var all_pts := PackedVector2Array()
	for idx in indices:
		all_pts.append_array(document.path_at(idx)["points"])
	var pivot := MissionProfiles.centroid(all_pts)
	var changes: Array[Dictionary] = []
	for idx in indices:
		var p: Dictionary = document.path_at(idx)
		var next_pts := MissionProfiles.transform_points(p["points"], delta, rot_deg, pivot, mx, mz, sym_origin, snap_check.button_pressed, terrain)
		if next_pts.is_empty():
			status_message.emit("Invalid transform parameters.")
			return
		changes.append({"index": idx, "name": p["name"], "points": next_pts, "type": int(p["type"])})
	if not document.edit_paths_batch(changes):
		status_message.emit(document.error)
		return
	refresh_all()
	emit_selection()
	status_message.emit("Updated %d path(s) in 1 undo step." % indices.size())


func clone_selected_path() -> void:
	if document == null:
		return
	var indices := selected_path_indices()
	if indices.is_empty():
		status_message.emit("Select a path to clone.")
		return
	var created := document.clone_path(indices[0])
	if created < 0:
		status_message.emit(document.error)
		return
	refresh_all()
	path_focused.emit(created)
	status_message.emit("Cloned path as %s." % document.path_at(created)["name"])


func apply_resample() -> void:
	if document == null:
		return
	var indices := selected_path_indices()
	if indices.is_empty():
		status_message.emit("Select one or more paths to resample.")
		return
	var terrain := document.package.terrain
	var changes: Array[Dictionary] = []
	for idx in indices:
		var p: Dictionary = document.path_at(idx)
		var next_pts := MissionProfiles.resample_points(p["points"], spacing_m.value, int(p["type"]) == 2, snap_check.button_pressed, terrain)
		changes.append({"index": idx, "name": p["name"], "points": next_pts, "type": int(p["type"])})
	if not document.edit_paths_batch(changes):
		status_message.emit(document.error)
		return
	refresh_all()
	emit_selection()
	status_message.emit("Resampled %d path(s) at %.0f m spacing." % [indices.size(), spacing_m.value])


func apply_snap_grid() -> void:
	if document == null:
		return
	var indices := selected_path_indices()
	if indices.is_empty():
		status_message.emit("Select one or more paths to snap.")
		return
	var terrain := document.package.terrain
	var changes: Array[Dictionary] = []
	for idx in indices:
		var p: Dictionary = document.path_at(idx)
		var next_pts := MissionProfiles.transform_points(p["points"], Vector2.ZERO, 0.0, Vector2.ZERO, false, false, Vector2.ZERO, true, terrain)
		changes.append({"index": idx, "name": p["name"], "points": next_pts, "type": int(p["type"])})
	if not document.edit_paths_batch(changes):
		status_message.emit(document.error)
		return
	refresh_all()
	emit_selection()
	status_message.emit("Snapped %d path(s) to the 2 m grid." % indices.size())
