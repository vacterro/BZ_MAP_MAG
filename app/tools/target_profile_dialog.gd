extends AcceptDialog
## Target Profile Switcher + Mod Manager UI.
## Tab 1 ("Target Profile"): Switch editing environment (non-destructive,
## undoable) or run a dry-run conversion compatibility analysis.
## Tab 2 ("Game & Mods"): Discover installed Steam Workshop mods, inspect
## paths/DLLs/dependencies, enable/disable profiles, register custom mods, and
## choose the default profile for new maps.

const Document := preload("res://core/map_document.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const Wintage := preload("res://themes/wintage.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const DIALOG_WIDTH := 640

signal profile_applied(message: String)
signal mods_changed(default_mod_id: String)

var document: Document
var registry: ModRegistry
var game_dir := ""
var vrv_dir := ""
var default_new_mod := "stock"

var tabs := TabContainer.new()
var detected_label := RichTextLabel.new()
var engine_select := ChoiceGroup.new(0)
var mod_select := ChoiceGroup.new(0)
var mission_select := ChoiceGroup.new(0)
var switch_btn: Button
var analyze_btn: Button
var convert_btn: Button
var analysis_output := RichTextLabel.new()

var mod_list := ItemList.new()
var mod_detail := RichTextLabel.new()
var toggle_mod_btn: Button
var set_default_btn: Button
var workshop_btn: Button
var custom_name_field := LineEdit.new()
var custom_dir_field := LineEdit.new()
var custom_dir_picker := FileDialog.new()


func _ready() -> void:
	title = "Target Profile & Mod Manager"
	ok_button_text = "Close"

	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.x = DIALOG_WIDTH - 24
	tabs.tab_changed.connect(func(_t): _fit_dialog())
	add_child(tabs)

	# --- Tab 1: Project Target Profile ---
	var prof_scroll := ScrollContainer.new()
	prof_scroll.name = "Target Profile"
	prof_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prof_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	prof_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(prof_scroll)

	var prof_tab := VBoxContainer.new()
	prof_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof_tab.add_theme_constant_override("separation", 4)
	prof_scroll.add_child(prof_tab)

	var det_hdr := Label.new()
	det_hdr.text = "Detected Map Evidence (read-only inspection — native source bytes are never altered by switching)"
	prof_tab.add_child(det_hdr)
	detected_label.fit_content = true
	detected_label.scroll_active = false
	detected_label.custom_minimum_size = Vector2(DIALOG_WIDTH - 48, 0)
	prof_tab.add_child(detected_label)

	_add_row(prof_tab, "Engine Profile", engine_select)
	for eid: String in ["bzcc-2.0.185", "bzcc-auto-detected", "bzcc-unknown-readonly"]:
		engine_select.add_item(String(ModRegistry.ENGINE_PROFILES[eid]["displayName"]))
		engine_select.set_item_metadata(engine_select.item_count - 1, eid)
	mod_select.set_overflow_limit(6, 54)
	_add_row(prof_tab, "Mod Profile", mod_select)
	_add_row(prof_tab, "Mission Profile", mission_select)
	for mode: String in MissionProfiles.MISSION_MODES:
		mission_select.add_item(String(MissionProfiles.MODE_LABELS.get(mode, mode)))
		mission_select.set_item_metadata(mission_select.item_count - 1, mode)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 4)
	prof_tab.add_child(actions)
	switch_btn = Button.new()
	switch_btn.text = "Change Editing Environment (Non-Destructive)"
	switch_btn.pressed.connect(apply_environment_switch)
	actions.add_child(switch_btn)
	analyze_btn = Button.new()
	analyze_btn.text = "Analyze Conversion (Dry-Run)"
	analyze_btn.pressed.connect(run_conversion_analysis)
	actions.add_child(analyze_btn)
	convert_btn = Button.new()
	convert_btn.text = "Convert Objects (Verified / Undoable)"
	convert_btn.pressed.connect(apply_verified_conversion)
	actions.add_child(convert_btn)

	analysis_output.fit_content = true
	analysis_output.scroll_active = false
	analysis_output.custom_minimum_size = Vector2(DIALOG_WIDTH - 48, 0)
	analysis_output.hide()
	prof_tab.add_child(analysis_output)

	# --- Tab 2: Game & Mods Manager ---
	var mods_tab := VBoxContainer.new()
	mods_tab.name = "Game & Mods"
	mods_tab.add_theme_constant_override("separation", 4)
	tabs.add_child(mods_tab)

	var scan_row := HFlowContainer.new()
	scan_row.add_theme_constant_override("h_separation", 4)
	mods_tab.add_child(scan_row)
	var scan_btn := Button.new()
	scan_btn.text = "Scan Installed Mods"
	scan_btn.pressed.connect(rescan_mods)
	scan_row.add_child(scan_btn)
	toggle_mod_btn = Button.new()
	toggle_mod_btn.text = "Enable / Disable"
	toggle_mod_btn.pressed.connect(toggle_selected_mod)
	scan_row.add_child(toggle_mod_btn)
	set_default_btn = Button.new()
	set_default_btn.text = "Set Default for New Maps"
	set_default_btn.pressed.connect(set_selected_as_default)
	scan_row.add_child(set_default_btn)
	workshop_btn = Button.new()
	workshop_btn.text = "Open Workshop Page"
	workshop_btn.pressed.connect(open_selected_workshop)
	scan_row.add_child(workshop_btn)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size.y = 220
	mods_tab.add_child(split)

	mod_list.custom_minimum_size.x = 260
	mod_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mod_list.item_selected.connect(func(_i): show_selected_mod_detail())
	split.add_child(mod_list)

	mod_detail.custom_minimum_size.x = 280
	mod_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(mod_detail)

	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 4)
	mods_tab.add_child(custom_row)
	custom_name_field.placeholder_text = "Custom mod name"
	custom_name_field.custom_minimum_size.x = 140
	custom_row.add_child(custom_name_field)
	custom_dir_field.placeholder_text = "Custom mod asset folder"
	custom_dir_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_row.add_child(custom_dir_field)
	custom_dir_picker.access = FileDialog.ACCESS_FILESYSTEM
	custom_dir_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	custom_dir_picker.dir_selected.connect(func(d: String): custom_dir_field.text = d)
	add_child(custom_dir_picker)
	var browse_btn := Button.new()
	browse_btn.text = "Browse…"
	browse_btn.pressed.connect(func(): custom_dir_picker.popup_centered_ratio(0.72))
	custom_row.add_child(browse_btn)
	var add_custom_btn := Button.new()
	add_custom_btn.text = "Add Custom Mod"
	add_custom_btn.pressed.connect(add_custom_mod)
	custom_row.add_child(add_custom_btn)


func _add_row(parent: Control, caption: String, widget: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 120
	row.add_child(lbl)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(widget)


func _set_analysis_text(text: String) -> void:
	analysis_output.text = text
	analysis_output.visible = not text.strip_edges().is_empty()
	_fit_dialog()


func _fit_dialog(initial_popup: bool = false) -> void:
	var min_h := 360 if tabs.current_tab == 1 else 0
	if initial_popup:
		Wintage.popup_fit(self, DIALOG_WIDTH, min_h)
	elif visible:
		Wintage.shrink_dialog(self, DIALOG_WIDTH, min_h)


func begin(doc: Document, mod_reg: ModRegistry, game_path: String, vrv_path: String, current_default_mod: String = "stock", initial_tab: int = 0) -> void:
	document = doc
	registry = mod_reg
	game_dir = game_path
	vrv_dir = vrv_path
	default_new_mod = current_default_mod
	tabs.current_tab = clampi(initial_tab, 0, 1)
	refresh_all()
	_fit_dialog(true)


func refresh_all() -> void:
	_refresh_mod_lists()
	_refresh_project_tab()


func _refresh_mod_lists() -> void:
	mod_select.clear()
	mod_list.clear()
	if registry == null:
		return
	for mid: String in registry.all_profile_ids():
		var prof := registry.get_profile(mid)
		var enabled: bool = (mid == "stock") or not registry.disabled_mods.get(mid, false)
		var installed := bool(prof.get("installed", mid == "stock"))
		var def_tag := " [DEFAULT]" if mid == default_new_mod else ""
		var state_tag := "[ON]" if enabled else "[OFF]"
		var inst_tag := "installed" if installed else "not installed"
		mod_list.add_item("%s %s (%s)%s" % [state_tag, String(prof.get("displayName", mid)), inst_tag, def_tag])
		mod_list.set_item_metadata(mod_list.item_count - 1, mid)
		if enabled:
			mod_select.add_item(String(prof.get("displayName", mid)))
			mod_select.set_item_metadata(mod_select.item_count - 1, mid)
	if mod_list.item_count > 0:
		mod_list.select(0)
		show_selected_mod_detail()


func _refresh_project_tab() -> void:
	var has_doc := document != null
	switch_btn.disabled = not has_doc
	analyze_btn.disabled = not has_doc
	if convert_btn != null:
		convert_btn.disabled = not has_doc
	if not has_doc:
		detected_label.text = "Open a map or BZMAG project to inspect or switch its Target Profile."
		_set_analysis_text("")
		return
	var info := document.detected_profile_info
	var lines: Array[String] = [
		"Active: Engine=%s | Mod=%s | Mission=%s | Format=%s (%s)" % [
			document.engine_profile, document.mod_profile, document.mission_profile,
			document.package.layout_id, "explicit" if document.profile_explicit else "auto-detected"],
	]
	for cand_v in info.get("candidates", []):
		var cand: Dictionary = cand_v
		lines.append("Candidate: %s / %s (%s) — %s" % [
			String(cand["modProfile"]), String(cand["missionProfile"]), String(cand["confidence"]),
			"; ".join(cand.get("evidence", []))])
	detected_label.text = "\n".join(lines)
	for i in engine_select.item_count:
		if String(engine_select.get_item_metadata(i)) == document.engine_profile:
			engine_select.select(i)
			break
	for i in mod_select.item_count:
		if String(mod_select.get_item_metadata(i)) == document.mod_profile:
			mod_select.select(i)
			break
	for i in mission_select.item_count:
		if String(mission_select.get_item_metadata(i)) == document.mission_profile:
			mission_select.select(i)
			break
	_set_analysis_text("")


func selected_target_engine() -> String:
	return String(engine_select.get_item_metadata(maxi(engine_select.selected, 0)))


func selected_target_mod() -> String:
	return String(mod_select.get_item_metadata(maxi(mod_select.selected, 0))) if mod_select.item_count > 0 else "stock"


func selected_target_mission() -> String:
	return String(mission_select.get_item_metadata(maxi(mission_select.selected, 0))) if mission_select.item_count > 0 else "blank"


func apply_environment_switch() -> void:
	if document == null:
		return
	var eng := selected_target_engine()
	var mid := selected_target_mod()
	var mis := selected_target_mission()
	if not document.set_target_profile(mid, mis, eng):
		_set_analysis_text("[ERR] " + document.error)
		return
	_refresh_project_tab()
	_set_analysis_text("[OK] Switched editing environment to %s / %s (%s). Source map bytes untouched; Undo reverses this change." % [mid, mis, eng])
	profile_applied.emit("Target profile switched to %s / %s." % [mid, mis])


func run_conversion_analysis() -> void:
	if document == null or registry == null:
		return
	var report := registry.analyze_conversion(document, selected_target_mod(), selected_target_mission(), MissionProfiles)
	var lines: Array[String] = [
		"=== Dry-Run Conversion Report (%s/%s -> %s/%s) ===" % [
			report["sourceMod"], report["sourceMission"], report["targetMod"], report["targetMission"]],
		"Format profile: %s | Target mod installed: %s | Feasible: %s" % [
			report["formatProfile"], "yes" if report["modInstalled"] else "NO",
			"YES (verified)" if bool(report.get("conversionFeasible", true)) else "NO (blocked by unverified ODFs)"],
	]
	if not String(report["dllChange"]).is_empty():
		lines.append("Mission DLL change: " + String(report["dllChange"]))
	var bad_odfs: Array = report["incompatibleOdfs"]
	if bad_odfs.is_empty():
		lines.append("ODF compatibility: all placed ODF classes appear compatible with target mod.")
	else:
		lines.append("[WARN] Mod-specific ODFs (%d): %s" % [bad_odfs.size(), ", ".join(bad_odfs)])
	var missing_paths: Array = report["missingRequiredPaths"]
	if not missing_paths.is_empty():
		lines.append("[WARN] Missing required paths for target mission: " + ", ".join(missing_paths))
	for w in report["lossyWarnings"]:
		lines.append("[LOSSY] " + String(w))
	lines.append("Note: Original native map files stay untouched. Use Export Native to publish a new target copy.")
	_set_analysis_text("\n".join(lines))


func apply_verified_conversion() -> void:
	if document == null:
		return
	var mid := selected_target_mod()
	var mis := selected_target_mission()
	var res := document.convert_objects_to_profile(mid, mis)
	if not bool(res.get("ok", false)):
		_set_analysis_text("[ERR] Semantic conversion refused: " + String(res.get("error", document.error)))
		return
	_refresh_project_tab()
	var rep_cnt := int(res.get("replacedCount", 0))
	var rem_cnt := int(res.get("removedCount", 0))
	_set_analysis_text("[OK] Converted %d object ODF(s) (removed %d) to %s / %s in 1 undo step. Source files remain untouched until Export Native." % [
		rep_cnt, rem_cnt, mid, mis])
	profile_applied.emit("Converted %d object(s) to %s / %s (1 undo step)." % [rep_cnt, mid, mis])


func rescan_mods() -> void:
	if registry == null:
		return
	var res := registry.discover_installed(game_dir, vrv_dir)
	refresh_all()
	mod_detail.text = "Scanned %d profiles from %s.\nCycles detected: %d" % [
		int(res["count"]),
		String(res["workshopRoot"]) if not String(res["workshopRoot"]).is_empty() else "(no Workshop folder)",
		(res["cycles"] as Array).size()]
	mods_changed.emit(default_new_mod)


func _selected_mod_id() -> String:
	var items := mod_list.get_selected_items()
	if items.is_empty():
		return ""
	return String(mod_list.get_item_metadata(items[0]))


func show_selected_mod_detail() -> void:
	var mid := _selected_mod_id()
	if mid.is_empty() or registry == null:
		mod_detail.text = ""
		return
	var p := registry.get_profile(mid)
	var url := String(p.get("homepage", ""))
	workshop_btn.disabled = not url.begins_with("https://steamcommunity.com/")
	toggle_mod_btn.disabled = (mid == "stock")
	var lines: Array[String] = [
		"ID: %s" % mid,
		"Name: %s" % String(p.get("displayName", mid)),
		"Type: %s | Installed: %s" % [String(p.get("modType", "")), "yes" if bool(p.get("installed", false)) else "no"],
		"Workshop ID: %s" % (String(p.get("workshopId", "")) if not String(p.get("workshopId", "")).is_empty() else "(none)"),
		"Root: %s" % (String(p.get("gameRoot", "")) if not String(p.get("gameRoot", "")).is_empty() else "(game install)"),
		"Asset roots (%d): %s" % [(p.get("assetRoots", []) as Array).size(), ", ".join(p.get("assetRoots", []))],
		"Mission DLLs (%d): %s" % [(p.get("missionDlls", []) as Array).size(), ", ".join(p.get("missionDlls", []))],
		"Dependencies: %s" % (", ".join(p.get("dependencies", [])) if not (p.get("dependencies", []) as Array).is_empty() else "(none)"),
		"Missing deps: %s" % (", ".join(p.get("missingDependencies", [])) if not (p.get("missingDependencies", []) as Array).is_empty() else "(none)"),
	]
	mod_detail.text = "\n".join(lines)


func toggle_selected_mod() -> void:
	var mid := _selected_mod_id()
	if mid.is_empty() or mid == "stock" or registry == null:
		return
	var currently_enabled: bool = not bool(registry.disabled_mods.get(mid, false))
	registry.set_mod_enabled(mid, not currently_enabled)
	refresh_all()
	mods_changed.emit(default_new_mod)


func set_selected_as_default() -> void:
	var mid := _selected_mod_id()
	if mid.is_empty() or registry == null:
		return
	default_new_mod = mid
	refresh_all()
	mods_changed.emit(default_new_mod)


func open_selected_workshop() -> void:
	var mid := _selected_mod_id()
	if mid.is_empty() or registry == null:
		return
	var url := String(registry.get_profile(mid).get("homepage", ""))
	if url.begins_with("https://steamcommunity.com/"):
		OS.shell_open(url)


func add_custom_mod() -> void:
	if registry == null:
		return
	var cname := custom_name_field.text.strip_edges()
	var cdir := custom_dir_field.text.strip_edges()
	if cname.is_empty() or cdir.is_empty() or not DirAccess.dir_exists_absolute(cdir):
		mod_detail.text = "[ERR] Enter a mod name and an existing local folder."
		return
	var slug := cname.to_lower().replace(" ", "_")
	var res := registry.register_custom_mod(slug, cname, cdir, ["stock"])
	if res.has("error"):
		mod_detail.text = "[ERR] " + String(res["error"])
		return
	custom_name_field.text = ""
	custom_dir_field.text = ""
	refresh_all()
	mods_changed.emit(default_new_mod)
