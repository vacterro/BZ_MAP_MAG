extends VBoxContainer
## Embedded Workspace New Map page (no modal ConfirmationDialog).
## Step 1: Engine -> Step 2: Mod Profile (Stock default) -> Step 3: Mission ->
## Step 4: Terrain & Template -> Step 5: Summary -> Create Map.

const ModRegistry := preload("res://core/mod_registry.gd")
const CompatibilityEngine := preload("res://core/compatibility_engine.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")

signal map_created(bzn_path: String, engine_id: String, mod_id: String, mission_id: String)
signal cancel_requested

var registry: ModRegistry
var game_dir := ""
var default_mod_id := "stock"
var default_parent_dir := ""
var fallback_blank_bzn := ""

var engine_select := ChoiceGroup.new(0)
var mod_select := ChoiceGroup.new(0)
var mission_select := ChoiceGroup.new(0)
var size_select := ChoiceGroup.new(3, true)
var height_spin := SliderField.new()
var source_bzn_field := LineEdit.new()
var template_ter_field := LineEdit.new()
var output_parent_field := LineEdit.new()
var incompat_box := VBoxContainer.new()
var incompat_label := Label.new()
var switch_profile_btn := Button.new()
var use_stock_tpl_btn := Button.new()
var sanitize_stock_check := CheckBox.new()
var summary_text := RichTextLabel.new()
var status_label := Label.new()
var create_button := Button.new()
var cancel_button := Button.new()
var source_picker := FileDialog.new()
var ter_picker := FileDialog.new()
var output_picker := FileDialog.new()

var _detected_source_info: Dictionary = {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["top", "bottom", "left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	scroll.add_child(pad)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 5)
	pad.add_child(layout)

	var hdr := Label.new()
	hdr.text = "New Map Workspace (Stock-First · Universal BZCC Mod Support)"
	layout.add_child(hdr)

	_add_row(layout, "1. Engine", engine_select)
	for eid: String in ["bzcc-2.0.185", "bzcc-auto-detected", "bzcc-unknown-readonly"]:
		engine_select.add_item(String(ModRegistry.ENGINE_PROFILES[eid]["displayName"]))
		engine_select.set_item_metadata(engine_select.item_count - 1, eid)
	engine_select.item_selected.connect(func(_i): refresh_summary())

	mod_select.set_overflow_limit(6, 48)
	_add_row(layout, "2. Mod Profile", mod_select)
	mod_select.item_selected.connect(func(_i): _on_mod_changed())

	_add_row(layout, "3. Mission Mode", mission_select)
	mission_select.item_selected.connect(func(_i): refresh_summary())

	for sz in [1024, 2048, 4096]:
		size_select.add_item("%d × %d m" % [sz, sz])
		size_select.set_item_metadata(size_select.item_count - 1, sz)
	size_select.select(1)
	size_select.item_selected.connect(func(_i): refresh_summary())
	_add_row(layout, "4a. Terrain Size", size_select)

	height_spin.min_value = -1000.0
	height_spin.max_value = 5000.0
	height_spin.step = 1.0
	height_spin.set_slider_range(-200.0, 500.0)
	height_spin.set_unit_suffix("m")
	height_spin.value = 100.0
	height_spin.value_changed.connect(func(_v): refresh_summary())
	_add_row(layout, "4b. Initial Height", height_spin)

	source_bzn_field.placeholder_text = "Blank BZN source (auto-selected for Stock if BZCC installed)"
	source_bzn_field.text_changed.connect(func(_t): refresh_summary())
	_add_browse_row(layout, "4c. Blank BZN", source_bzn_field, source_picker, FileDialog.FILE_MODE_OPEN_FILE, ["*.bzn ; Battlezone mission"])

	template_ter_field.placeholder_text = "(Optional) External .ter template — blank generates native flat TER"
	template_ter_field.text_changed.connect(func(_t): refresh_summary())
	_add_browse_row(layout, "4d. TER Template", template_ter_field, ter_picker, FileDialog.FILE_MODE_OPEN_FILE, ["*.ter ; Terrain v5"])

	output_parent_field.placeholder_text = "Parent folder for the new map package"
	output_parent_field.text_changed.connect(func(_t): refresh_summary())
	_add_browse_row(layout, "4e. Output Folder", output_parent_field, output_picker, FileDialog.FILE_MODE_OPEN_DIR, [])

	incompat_box.add_theme_constant_override("separation", 3)
	incompat_box.hide()
	layout.add_child(incompat_box)
	incompat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	incompat_box.add_child(incompat_label)
	var incompat_actions := HFlowContainer.new()
	incompat_actions.add_theme_constant_override("h_separation", 4)
	incompat_box.add_child(incompat_actions)
	sanitize_stock_check.text = "Replace non-Stock template ODFs with verified Stock equivalents"
	sanitize_stock_check.button_pressed = false
	sanitize_stock_check.toggled.connect(func(_on): refresh_summary())
	incompat_actions.add_child(sanitize_stock_check)
	use_stock_tpl_btn.text = "Use Stock Template"
	use_stock_tpl_btn.pressed.connect(_use_discovered_stock_template)
	incompat_actions.add_child(use_stock_tpl_btn)
	switch_profile_btn.text = "Switch Profile to Match Template"
	switch_profile_btn.pressed.connect(_apply_suggested_profile_from_source)
	incompat_actions.add_child(switch_profile_btn)

	summary_text.fit_content = true
	summary_text.scroll_active = false
	summary_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_row(layout, "5. Summary", summary_text)

	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 6)
	layout.add_child(footer)
	create_button.text = "Create Map & Open in Editor"
	create_button.pressed.connect(create_selected_map)
	footer.add_child(create_button)
	cancel_button.text = "Back to Viewport"
	cancel_button.pressed.connect(func(): cancel_requested.emit())
	footer.add_child(cancel_button)

	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.hide()
	layout.add_child(status_label)


func _add_row(parent: Control, caption: String, widget: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 124
	row.add_child(lbl)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(widget)


func _add_browse_row(parent: Control, caption: String, field: LineEdit, picker: FileDialog, mode: FileDialog.FileMode, filters: PackedStringArray) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 124
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


func _set_status(msg: String) -> void:
	status_label.text = msg
	status_label.visible = not msg.is_empty()


func begin(mod_reg: ModRegistry, game_path: String, preferred_mod: String = "stock", parent_dir: String = "", fallback_bzn: String = "") -> void:
	registry = mod_reg
	game_dir = game_path
	default_mod_id = preferred_mod if mod_reg.has_profile(preferred_mod) else "stock"
	default_parent_dir = parent_dir
	fallback_blank_bzn = fallback_bzn
	sanitize_stock_check.set_pressed_no_signal(false)
	_set_status("")

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


func selected_engine_id() -> String:
	return String(engine_select.get_item_metadata(maxi(engine_select.selected, 0)))


func selected_mod_id() -> String:
	return String(mod_select.get_item_metadata(maxi(mod_select.selected, 0))) if mod_select.item_count > 0 else "stock"


func selected_mission_id() -> String:
	return String(mission_select.get_item_metadata(maxi(mission_select.selected, 0))) if mission_select.item_count > 0 else "blank"


func selected_size_m() -> int:
	return int(size_select.get_item_metadata(maxi(size_select.selected, 0)))


func inspect_source_bzn(bzn_path: String, target_mod: String = "stock") -> Dictionary:
	return CompatibilityEngine.evaluate_bzn_path(
		bzn_path, registry, target_mod, selected_mission_id(), selected_engine_id(),
		game_dir, registry.last_vrv_dir if registry != null else "")


func _use_discovered_stock_template() -> void:
	var stock_tpls := ModRegistry.discover_stock_templates(game_dir)
	if not stock_tpls.is_empty():
		source_bzn_field.text = stock_tpls[0]
		sanitize_stock_check.set_pressed_no_signal(false)
		refresh_summary()


func _apply_suggested_profile_from_source() -> void:
	var suggested := String(_detected_source_info.get("recommendedMod", "stock"))
	for i in mod_select.item_count:
		if String(mod_select.get_item_metadata(i)) == suggested:
			mod_select.select(i)
			_on_mod_changed()
			return


func _on_mod_changed() -> void:
	var mid := selected_mod_id()
	var prof := registry.get_profile(mid) if registry != null else {}
	var modes: Array = prof.get("missionModes", MissionProfiles.MISSION_MODES)
	var prev_mis := selected_mission_id()
	mission_select.clear()
	var restore_idx := 0
	for mode_v in modes:
		var mode := String(mode_v)
		mission_select.add_item(String(MissionProfiles.MODE_LABELS.get(mode, mode)))
		var idx := mission_select.item_count - 1
		mission_select.set_item_metadata(idx, mode)
		if mode == prev_mis:
			restore_idx = idx
	if mission_select.item_count > 0:
		mission_select.select(restore_idx)
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
	_detected_source_info = inspect_source_bzn(source_bzn_field.text, mid)
	var bad_odfs: Array[String] = []
	if mid == "stock":
		for o: String in _detected_source_info.get("vrvOdfs", []):
			bad_odfs.append(o)
		for o: String in _detected_source_info.get("vsrOdfs", []):
			bad_odfs.append(o)
		for o: String in _detected_source_info.get("unknownOdfs", []):
			bad_odfs.append(o)
	elif mid == "vsr":
		for o: String in _detected_source_info.get("vrvOdfs", []):
			bad_odfs.append(o)
		for o: String in _detected_source_info.get("unknownOdfs", []):
			bad_odfs.append(o)

	var conv_plan: Dictionary = _detected_source_info.get("conversionPlan", {})
	var conv_ok := bool(conv_plan.get("ok", false))
	var stock_tpls := ModRegistry.discover_stock_templates(game_dir)

	if not bad_odfs.is_empty():
		var suggested := String(_detected_source_info.get("recommendedMod", "vsr"))
		var summary_pairs: Array = conv_plan.get("summaryLines", [])
		var unsupported_list: Array = conv_plan.get("unsupported", [])
		var short_pairs: Array[String] = []
		var seen_short := {}
		for rep_v in conv_plan.get("replacements", []):
			var rep: Dictionary = rep_v
			var pk := "%s->%s" % [String(rep.get("sourceOdf", "")), String(rep.get("targetOdf", ""))]
			if not seen_short.has(pk):
				seen_short[pk] = true
				short_pairs.append("%s -> %s" % [String(rep.get("sourceOdf", "")), String(rep.get("targetOdf", ""))])
		if conv_ok and not short_pairs.is_empty():
			incompat_label.text = "[WARN] Source '%s' has non-%s ODF(s): %s (verified map: %s)." % [
				suggested, mid, ", ".join(bad_odfs), ", ".join(short_pairs)]
			incompat_label.tooltip_text = "\n".join(summary_pairs)
		else:
			incompat_label.text = "[ERR] Source '%s' has unverified %s ODF(s): %s." % [
				suggested, mid, ", ".join(bad_odfs)]
			incompat_label.tooltip_text = "\n".join(unsupported_list)
		switch_profile_btn.text = "Switch to '%s'" % suggested.to_upper()
		sanitize_stock_check.visible = (mid == "stock" and conv_ok)
		use_stock_tpl_btn.visible = (mid == "stock" and not stock_tpls.is_empty() and source_bzn_field.text.simplify_path() != stock_tpls[0].simplify_path())
		incompat_box.show()
	else:
		incompat_box.hide()

	var lines: Array[String] = [
		"Target: %s | Mod: %s | Mission: %s" % [eng, String(prof.get("displayName", mid)), String(contract.get("label", mis))],
		"Terrain: %d × %d m @ %.1f m (%s)" % [
			selected_size_m(), selected_size_m(), height_spin.value,
			"Native flat TER v5" if template_ter_field.text.strip_edges().is_empty() else template_ter_field.text.get_file()],
		"DLL: %s (src: %s) | Rules: %s | Paths: %s" % [
			String(contract.get("dll", "(none)")) if not String(contract.get("dll", "")).is_empty() else "(none)",
			String(_detected_source_info.get("dll", "(none)")) if not String(_detected_source_info.get("dll", "")).is_empty() else "(none)",
			String(contract.get("semantics", "UNKNOWN")),
			", ".join(req_paths) if not req_paths.is_empty() else "(none)"],
	]
	if mid == "stock":
		if not bad_odfs.is_empty():
			if not conv_ok:
				lines.append("[ERR] Blocked: unverified ODF(s) %s. Pick a Stock template or switch profile." % ", ".join(conv_plan.get("unverifiedOdfs", bad_odfs)))
			elif not sanitize_stock_check.button_pressed:
				lines.append("[WARN] Blocked: enable verified ODF conversion above, pick a Stock template, or switch profile.")
			else:
				lines.append("[OK] Verified semantic conversion active: %s" % "; ".join(conv_plan.get("summaryLines", [])))
		else:
			lines.append("[OK] Native Stock BZCC template verified (zero VRV/VSR dependency).")
	elif mid == "vsr" and not bad_odfs.is_empty():
		lines.append("[ERR] Incompatible source template for VSR: contains non-VSR ODF(s) %s." % ", ".join(bad_odfs))
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
		_set_status("[ERR] Choose an existing blank BZN source file.")
		return
	if parent.is_empty() or not DirAccess.dir_exists_absolute(parent):
		_set_status("[ERR] Choose an existing output parent folder.")
		return
	var mid := selected_mod_id()
	var mis := selected_mission_id()
	_detected_source_info = inspect_source_bzn(src_bzn, mid)
	if not bool(_detected_source_info.get("valid", false)):
		_set_status("[ERR] Selected source BZN is not a valid supported BZN template.")
		return
	var bad_odfs: Array[String] = []
	if mid == "stock":
		for o: String in _detected_source_info.get("vrvOdfs", []):
			bad_odfs.append(o)
		for o: String in _detected_source_info.get("vsrOdfs", []):
			bad_odfs.append(o)
		for o: String in _detected_source_info.get("unknownOdfs", []):
			bad_odfs.append(o)
	elif mid == "vsr":
		for o: String in _detected_source_info.get("vrvOdfs", []):
			bad_odfs.append(o)
		for o: String in _detected_source_info.get("unknownOdfs", []):
			bad_odfs.append(o)
	var conv_plan: Dictionary = _detected_source_info.get("conversionPlan", {})
	var conv_ok := bool(conv_plan.get("ok", false))
	if not bad_odfs.is_empty():
		var suggested := String(_detected_source_info.get("recommendedMod", "mod")).to_upper()
		if mid == "stock":
			if not conv_ok:
				_set_status("[ERR] Cannot create Stock map: source template contains unverified ODF(s) (%s) with no verified Stock equivalent." % ", ".join(conv_plan.get("unverifiedOdfs", bad_odfs)))
				return
			if not sanitize_stock_check.button_pressed:
				_set_status("[ERR] Cannot create Stock map from %s source template containing %s without conversion. Enable verified ODF conversion, choose a Stock source BZN, or switch profile." % [suggested, ", ".join(bad_odfs)])
				return
		elif mid == "vsr":
			_set_status("[ERR] Cannot create VSR map from source template containing incompatible ODF(s): %s." % ", ".join(bad_odfs))
			return
	var writer := Snapshots.new()
	var stem := src_bzn.get_file().get_basename()
	var mod_tag := mid.replace(":", "_")
	var target := parent.path_join("%s-%s-%s" % [stem, mod_tag, writer.nonce().left(8)])
	var options := {
		"mod_profile": mid,
		"mission_profile": mis,
		"configure_mission": mis != "blank",
		"sync_mission_dll": true,
		"sanitize_stock_objects": (mid == "stock" and sanitize_stock_check.button_pressed),
		"trim_showcase_objects": (mid == "stock"),
	}
	if not writer.create_native_flat_map(src_bzn, target, selected_size_m(), height_spin.value, tpl_ter, options):
		_set_status("[ERR] " + writer.error)
		return
	var created_bzn := target.path_join(src_bzn.get_file())
	map_created.emit(created_bzn, selected_engine_id(), mid, mis)
