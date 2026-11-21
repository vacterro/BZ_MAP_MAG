extends ConfirmationDialog
## Stock-first Universal New Map Wizard.
## Step 1: Target Engine -> Step 2: Mod/Content Profile (Stock default) ->
## Step 3: Mission Mode -> Step 4: Terrain & Source -> Step 5: Summary -> Create.
## Stock maps generate native TER v5 directly without requiring VRV or VSR.

const ModRegistry := preload("res://core/mod_registry.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const Snapshots := preload("res://bridge/snapshots.gd")

signal map_created(bzn_path: String, engine_id: String, mod_id: String, mission_id: String)

var registry: ModRegistry
var game_dir := ""
var default_mod_id := "stock"
var default_parent_dir := ""
var fallback_blank_bzn := ""

var engine_select := OptionButton.new()
var mod_select := OptionButton.new()
var mission_select := OptionButton.new()
var size_select := OptionButton.new()
var height_spin := SpinBox.new()
var source_bzn_field := LineEdit.new()
var template_ter_field := LineEdit.new()
var output_parent_field := LineEdit.new()
var summary_text := RichTextLabel.new()
var status_label := Label.new()
var source_picker := FileDialog.new()
var ter_picker := FileDialog.new()
var output_picker := FileDialog.new()


func _ready() -> void:
	title = "New Map Wizard"
	ok_button_text = "Create Map"
	dialog_hide_on_ok = false
	min_size = Vector2i(620, 520)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	# Step 1 — Target Engine
	_add_row(layout, "1. Target Game / Engine", engine_select)
	for eid: String in ["bzcc-2.0.185", "bzcc-auto-detected", "bzcc-unknown-readonly"]:
		engine_select.add_item(String(ModRegistry.ENGINE_PROFILES[eid]["displayName"]))
		engine_select.set_item_metadata(engine_select.item_count - 1, eid)
	engine_select.item_selected.connect(func(_i): refresh_summary())

	# Step 2 — Content / Mod Profile
	_add_row(layout, "2. Content Profile (Mod)", mod_select)
	mod_select.item_selected.connect(func(_i): _on_mod_changed())

	# Step 3 — Mission Mode
	_add_row(layout, "3. Mission Mode", mission_select)
	mission_select.item_selected.connect(func(_i): refresh_summary())

	# Step 4 — Terrain & Base Files
	for sz in [1024, 2048, 4096]:
		size_select.add_item("%d × %d m" % [sz, sz])
		size_select.set_item_metadata(size_select.item_count - 1, sz)
	size_select.select(1) # 2048 m default
	size_select.item_selected.connect(func(_i): refresh_summary())
	_add_row(layout, "4a. Terrain Size", size_select)

	height_spin.min_value = -1000.0
	height_spin.max_value = 5000.0
	height_spin.step = 1.0
	height_spin.value = 100.0
	height_spin.value_changed.connect(func(_v): refresh_summary())
	_add_row(layout, "4b. Initial Height (m)", height_spin)

	source_bzn_field.placeholder_text = "Blank BZN source (auto-selected for Stock if BZCC installed)"
	source_bzn_field.text_changed.connect(func(_t): refresh_summary())
	_add_browse_row(layout, "4c. Blank BZN Source", source_bzn_field, source_picker, FileDialog.FILE_MODE_OPEN_FILE, ["*.bzn ; Battlezone mission"])

	template_ter_field.placeholder_text = "(Optional) External .ter template — leave blank to generate native flat TER"
	template_ter_field.text_changed.connect(func(_t): refresh_summary())
	_add_browse_row(layout, "4d. TER Template (Optional)", template_ter_field, ter_picker, FileDialog.FILE_MODE_OPEN_FILE, ["*.ter ; Terrain v5"])

	output_parent_field.placeholder_text = "Parent folder for the new map package"
	output_parent_field.text_changed.connect(func(_t): refresh_summary())
	_add_browse_row(layout, "4e. Output Parent Folder", output_parent_field, output_picker, FileDialog.FILE_MODE_OPEN_DIR, [])

	# Step 5 — Summary
	var sum_lbl := Label.new()
	sum_lbl.text = "5. Summary & Capabilities"
	layout.add_child(sum_lbl)
	summary_text.custom_minimum_size.y = 125
	summary_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(summary_text)

	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)

	confirmed.connect(create_selected_map)


func _add_row(parent: Control, caption: String, widget: Control) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 190
	row.add_child(lbl)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(widget)


func _add_browse_row(parent: Control, caption: String, field: LineEdit, picker: FileDialog, mode: FileDialog.FileMode, filters: PackedStringArray) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 190
	row.add_child(lbl)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = mode
	picker.filters = filters
	add_child(picker)
	if mode == FileDialog.FILE_MODE_OPEN_DIR:
		picker.dir_selected.connect(func(d: String): field.text = d; refresh_summary())
	else:
		picker.file_selected.connect(func(f: String): field.text = f; refresh_summary())
	var btn := Button.new()
	btn.text = "Browse…"
	btn.pressed.connect(func(): picker.popup_centered_ratio(0.72))
	row.add_child(btn)


func begin(mod_reg: ModRegistry, game_path: String, preferred_mod: String = "stock", parent_dir: String = "", fallback_bzn: String = "") -> void:
	registry = mod_reg
	game_dir = game_path
	default_mod_id = preferred_mod if mod_reg.has_profile(preferred_mod) else "stock"
	default_parent_dir = parent_dir
	fallback_blank_bzn = fallback_bzn
	status_label.text = ""

	mod_select.clear()
	var selected_idx := 0
	for mid: String in registry.enabled_profile_ids():
		var prof := registry.get_profile(mid)
		var tag := "" if bool(prof.get("installed", false)) or mid == "stock" else " (not installed)"
		mod_select.add_item("%s%s" % [String(prof.get("displayName", mid)), tag])
		var idx := mod_select.item_count - 1
		mod_select.set_item_metadata(idx, mid)
		if mid == default_mod_id:
			selected_idx = idx
	if mod_select.item_count > 0:
		mod_select.select(selected_idx)
	if output_parent_field.text.strip_edges().is_empty() and not default_parent_dir.is_empty():
		output_parent_field.text = default_parent_dir
	_on_mod_changed()
	popup_centered()


func selected_engine_id() -> String:
	return String(engine_select.get_item_metadata(maxi(engine_select.selected, 0)))


func selected_mod_id() -> String:
	return String(mod_select.get_item_metadata(maxi(mod_select.selected, 0))) if mod_select.item_count > 0 else "stock"


func selected_mission_id() -> String:
	return String(mission_select.get_item_metadata(maxi(mission_select.selected, 0))) if mission_select.item_count > 0 else "blank"


func selected_size_m() -> int:
	return int(size_select.get_item_metadata(maxi(size_select.selected, 0)))


func _on_mod_changed() -> void:
	var mid := selected_mod_id()
	var prof := registry.get_profile(mid) if registry != null else {}
	var modes: Array = prof.get("missionModes", MissionProfiles.MISSION_MODES)
	mission_select.clear()
	for mode_v in modes:
		var mode := String(mode_v)
		mission_select.add_item(String(MissionProfiles.MODE_LABELS.get(mode, mode)))
		mission_select.set_item_metadata(mission_select.item_count - 1, mode)
	if mission_select.item_count > 0:
		mission_select.select(0) # Blank default
	# Auto-populate a compatible blank BZN without requiring VRV for Stock!
	var templates: Array = prof.get("templates", [])
	var auto_bzn := ""
	for t_v in templates:
		var t := String(t_v)
		if t.get_extension().to_lower() == "bzn" and FileAccess.file_exists(t):
			auto_bzn = t
			break
	if auto_bzn.is_empty() and mid == "stock":
		var stock_tpls := ModRegistry.discover_stock_templates(game_dir)
		if not stock_tpls.is_empty():
			auto_bzn = stock_tpls[0]
	if auto_bzn.is_empty() and not fallback_blank_bzn.is_empty() and FileAccess.file_exists(fallback_blank_bzn):
		auto_bzn = fallback_blank_bzn
	if not auto_bzn.is_empty():
		source_bzn_field.text = auto_bzn
	template_ter_field.text = ""
	refresh_summary()


func refresh_summary() -> void:
	var eng := selected_engine_id()
	var mid := selected_mod_id()
	var mis := selected_mission_id()
	var contract := MissionProfiles.contract_for(mis, mid)
	var prof := registry.get_profile(mid) if registry != null else {}
	var installed := bool(prof.get("installed", mid == "stock"))
	var req_paths: Array = contract.get("required", [])
	var lines: Array[String] = [
		"Target: %s | Mod: %s | Mission: %s" % [eng, String(prof.get("displayName", mid)), String(contract.get("label", mis))],
		"Terrain: %d × %d m at %.1f m (%s)" % [
			selected_size_m(), selected_size_m(), height_spin.value,
			"Native flat TER v5 (zero VRV dependency)" if template_ter_field.text.strip_edges().is_empty() else template_ter_field.text.get_file()],
		"Expected DLL: %s | Semantics: %s" % [
			String(contract.get("dll", "(none)")) if not String(contract.get("dll", "")).is_empty() else "(none / source BZN)",
			String(contract.get("semantics", "UNKNOWN"))],
		"Required paths: %s" % (", ".join(req_paths) if not req_paths.is_empty() else "(none)"),
	]
	if mid == "stock":
		lines.append("[OK] Stock BZCC requires NO VRV or VSR installation.")
	elif not installed:
		lines.append("[WARN] Mod '%s' is not installed locally; generic terrain tools remain available, but mod Playtest assets may be missing." % mid)
	else:
		var missing_deps: Array = prof.get("missingDependencies", [])
		if not missing_deps.is_empty():
			lines.append("[WARN] Missing Workshop dependencies: " + ", ".join(missing_deps))
	summary_text.text = "\n".join(lines)


func create_selected_map() -> void:
	var src_bzn := source_bzn_field.text.strip_edges()
	var parent := output_parent_field.text.strip_edges()
	var tpl_ter := template_ter_field.text.strip_edges()
	if src_bzn.is_empty() or not FileAccess.file_exists(src_bzn):
		status_label.text = "[ERR] Choose an existing blank BZN source file."
		return
	if parent.is_empty() or not DirAccess.dir_exists_absolute(parent):
		status_label.text = "[ERR] Choose an existing output parent folder."
		return
	var writer := Snapshots.new()
	var stem := src_bzn.get_file().get_basename()
	var mod_tag := selected_mod_id().replace(":", "_")
	var target := parent.path_join("%s-%s-%s" % [stem, mod_tag, writer.nonce().left(8)])
	if not writer.create_native_flat_map(src_bzn, target, selected_size_m(), height_spin.value, tpl_ter):
		status_label.text = "[ERR] " + writer.error
		return
	var created_bzn := target.path_join(src_bzn.get_file())
	hide()
	map_created.emit(created_bzn, selected_engine_id(), selected_mod_id(), selected_mission_id())
