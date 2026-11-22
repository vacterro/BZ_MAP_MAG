extends Control

const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const Wintage := preload("res://themes/wintage.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const TopView := preload("res://render/top_view.gd")
const TerrainView := preload("res://render/terrain_view.gd")
const NodeStudio := preload("res://nodes/node_studio.gd")
const PathInspector := preload("res://core/path_inspector.gd")
const BrushPanel := preload("res://tools/brush_panel.gd")
const NativeAssets := preload("res://formats/native_assets.gd")
const TerrainTextures := preload("res://render/terrain_textures.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const TerrainCommands := preload("res://tools/terrain_commands.gd")
const SlopeStudio := preload("res://tools/slope_studio.gd")
const MissionStudio := preload("res://tools/mission_studio.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const CompatibilityEngine := preload("res://core/compatibility_engine.gd")
const NewMapWizard := preload("res://tools/new_map_wizard.gd")
const TargetProfileDialog := preload("res://tools/target_profile_dialog.gd")
const WaterCommands := preload("res://tools/water_commands.gd")
const MoveObject := preload("res://tools/move_object.gd")
const ObjectBrowser := preload("res://tools/object_browser.gd")
const EnvironmentStudio := preload("res://tools/environment_studio.gd")
const SoundEditor := preload("res://tools/sound_editor.gd")
const AutoSaveStore := preload("res://core/autosave_store.gd")
const SETTINGS := "user://editor.cfg"
var document: Document
var top := TopView.new()
var scene_view := TerrainView.new()
var status := Label.new()
var coordinates := Label.new()
var title := Label.new()
var path_list := OptionButton.new()
var new_path_button: Button
var edit_path_button: Button
var move_path_button: Button
var mission_studio_button: Button
var path_inspector := PathInspector.new()
var mission_studio := MissionStudio.new()
var mod_registry := ModRegistry.new()
var new_map_wizard := NewMapWizard.new()
var target_profile_dialog := TargetProfileDialog.new()
var target_profile_button: Button
var default_new_mod_profile := "stock"
var snap_path_drag := false
var selected_extra_paths: Array[int] = []
var path_drag_view: Control
var path_draft := {}
var selected_path_point := -1
var brush_panel := BrushPanel.new()
var camera_buttons: Array[Button] = []
var objects_button: Button
var object_browser_button: Button
var object_browser := ObjectBrowser.new()
var pending_place_spec: Dictionary = {}
var move_objects_button: Button
var object_tool := MoveObject.new()
var water_button: Button
var water_edit_button: Button
var water_tools := WaterCommands.new()
var painting_water := false
var water_add := true
var color_button: Button
var texture_button: Button
var object_thread := Thread.new()
var asset_worker: NativeAssets
var tile_worker: TerrainTextures
var asset_kind := ""
var active_object_scan: Document
var loaded_objects: Document
var solid_button: Button
var wire_button: Button
var fly_button: Button
const AUTOSAVE_INTERVAL := 180.0
const AUTOSAVE_KEEP := 3
var autosave_seconds := 0.0
var autosave_custom_root := ""
var last_autosave := ""
var autosave_picker := FileDialog.new()
var autosave_root_field := LineEdit.new()
var recover_dialog := ConfirmationDialog.new()
var recover_list := ItemList.new()
var open_dialog := FileDialog.new()
var blank_dialog := FileDialog.new()
var flat_template_dialog := FileDialog.new()
var flat_output_dialog := FileDialog.new()
var blank_mission := ""
var flat_template := ""
var save_dialog := FileDialog.new()
var export_dialog := FileDialog.new()
var undo_button: Button
var redo_button: Button
var save_button: Button
var recover_button: Button
var export_button: Button
var focus_button: Button
var playtest_button: Button
var nodes_button: Button
var slope_studio_button: Button
var studio := NodeStudio.new()
var terrain_tools_button: Button
var terrain_tools := TerrainCommands.new()
var slope_studio := SlopeStudio.new()
var environment_studio := EnvironmentStudio.new()
var environment_button: Button
var sound_editor := SoundEditor.new()
var sound_button: Button
var object_label_button: Button
var object_label_dialog := ConfirmationDialog.new()
var object_label_target := Label.new()
var object_label_field := LineEdit.new()
var object_label_status := Label.new()
var object_label_view := -1
var theme_slug := Wintage.DEFAULT_THEME
var ui_font_size := 12
var ui_compact := false
var backdrop := ColorRect.new()
var theme_select := ChoiceGroup.new(0)
var compact_check := CheckBox.new()
var tool_search := LineEdit.new()
var empty_state_hint := Label.new()
var toolbar_buttons: Array[Button] = []
var confirmation := ConfirmationDialog.new()
var keys_dialog := AcceptDialog.new()
var playtest_dialog := ConfirmationDialog.new()
var game_path := LineEdit.new()
var vrv_path := LineEdit.new()
var asset_profile_path := LineEdit.new()
var asset_profile_picker := FileDialog.new()
var asset_profile_browse: Button
var game_picker := FileDialog.new()
var vrv_picker := FileDialog.new()
var setup_status := Label.new()
var engine_editor_mode := CheckBox.new()
var vrv_configured := false
var launcher_pid := -1
var game_pid := -1
var playtest_result := ""
var settings_path := SETTINGS
var playtest_root := ""
var pending_path := ""
var saved_edits := {}
var saved_layers: Array = []
var saved_path_edits := {}
var saved_object_edits := {}
var saved_object_label_edits := {}
var saved_object_odf_edits := {}
var saved_object_additions: Array = []
var saved_object_removals := {}
var saved_asset_profile := ""
var saved_engine_profile := "bzcc-2.0.185"
var saved_mod_profile := "stock"
var saved_mission_profile := "blank"
var saved_colors := {}
var saved_tiles := {}
var saved_water_edits := {}
var saved_water_heights := {}
var saved_mission_dll := ""
var saved_environment_edits := {}
const HOLD_STEP_SECONDS := 0.05
const HOLD_DAB_SCALE := 0.15
var cursor := Vector2(-1, -1)
var last_cursor := Vector2(-1, -1)
var anchor := Vector2(-1, -1)
var paint_view: Control
var paint_hold_elapsed := 0.0
var pending_refresh := Rect2i()
var pending_materials := {}


func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(640, 540))
	RenderingServer.set_debug_generate_wireframes(true)
	var settings := ConfigFile.new()
	settings.load(settings_path)
	theme_slug = String(settings.get_value("ui", "theme", Wintage.DEFAULT_THEME))
	if not (theme_slug in Wintage.theme_slugs()):
		theme_slug = Wintage.DEFAULT_THEME
	ui_compact = bool(settings.get_value("ui", "compact", false))
	ui_font_size = clampi(int(settings.get_value("ui", "font_size", 12)), 10, 24)
	var colors := Wintage.palette(theme_slug)
	theme = Wintage.make(colors, ui_font_size, ui_compact)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for window in all_dialogs():
		window.theme = theme
	backdrop.color = colors["background"]
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)
	var tools := HFlowContainer.new()
	layout.add_child(tools)
	toolbar_buttons.append(add_button(tools, "Open", open_dialog.popup_centered_ratio.bind(0.72), "Open a BZN map or BZMAG project", KEY_O))
	var new_map := add_button(tools, "New Map", open_new_map_wizard, "Create a new Stock, VSR, VRV or custom-mod map")
	toolbar_buttons.append(new_map)
	target_profile_button = add_button(tools, "Target Profile", func(): open_target_profile(0), "Inspect detected mod/mission profiles, switch editing environment or analyze conversion")
	toolbar_buttons.append(target_profile_button)
	save_button = add_button(tools, "Save Project", request_save, "Create a .bzmag project snapshot", KEY_S)
	toolbar_buttons.append(save_button)
	recover_button = add_button(tools, "Recover…", recover_autosaves, "Open a rolling autosave from the verified recovery store")
	toolbar_buttons.append(recover_button)
	export_button = add_button(tools, "Export Native", request_export, "Export and re-import a new native map folder")
	toolbar_buttons.append(export_button)
	playtest_button = add_button(tools, "Playtest", playtest, "Launch Battlezone with the current edits")
	toolbar_buttons.append(playtest_button)
	toolbar_buttons.append(add_button(tools, "Setup", show_playtest_setup, "Choose the Battlezone and VRV folders"))
	undo_button = add_button(tools, "Undo", func(): document.undo(); sync_actions(), "Undo the last stroke", KEY_Z)
	toolbar_buttons.append(undo_button)
	redo_button = add_button(tools, "Redo", func(): document.redo(); sync_actions(), "Redo the last stroke", KEY_Y)
	toolbar_buttons.append(redo_button)
	nodes_button = add_button(tools, "Layers / Nodes", open_studio, "Preview and bake procedural height, color or base tile layers")
	toolbar_buttons.append(nodes_button)
	terrain_tools_button = add_button(tools, "Shape Terrain", open_terrain_tools, "Preview a slope plane, mirror heights, or apply VRV Smooth/Rough/Relief")
	toolbar_buttons.append(terrain_tools_button)
	slope_studio_button = add_button(tools, "Slope Studio", open_slope_studio, "Build exact-angle ramps, terraces, ridges, valleys, trenches and excavations with batch stamps and masks")
	toolbar_buttons.append(slope_studio_button)
	environment_button = add_button(tools, "Environment", open_environment_studio, "Inspect .SKY/.TRN and edit verified native .SKY fog and sun lighting")
	toolbar_buttons.append(environment_button)
	toolbar_buttons.append(add_button(tools, "Hotkeys", func(): Wintage.popup_fit(keys_dialog, 420), "Show editor shortcuts"))
	tool_search.placeholder_text = "Filter tools…"
	tool_search.custom_minimum_size.x = 110
	tool_search.tooltip_text = "Filter main toolbar commands by name or hint"
	tool_search.text_changed.connect(filter_toolbar)
	tools.add_child(tool_search)
	title.text = "Open a map to edit terrain"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var map_info := HBoxContainer.new()
	layout.add_child(map_info)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_info.add_child(title)
	path_list.custom_minimum_size.x = 146
	path_list.tooltip_text = "Display a native BZN path in both views"
	path_list.add_item("Path overlay")
	path_list.disabled = true
	path_list.item_selected.connect(select_path)
	map_info.add_child(path_list)
	new_path_button = add_button(map_info, "New Path", start_new_path, "Create a native path at the last terrain cursor")
	edit_path_button = add_button(map_info, "Edit Path", inspect_path, "Edit the selected path's name, type and points")
	move_path_button = add_button(map_info, "Move Points", path_tool_changed, "Drag points in either view. Shift+click appends a point. Delete removes the selected point.")
	move_path_button.toggle_mode = true
	mission_studio_button = add_button(map_info, "Mission Studio", open_mission_studio, "Browse mission profiles, generate AI paths, transform/mirror/clone/resample and validate readiness")
	add_child(path_inspector)
	add_child(mission_studio)
	add_child(new_map_wizard)
	add_child(target_profile_dialog)
	new_map_wizard.map_created.connect(_on_wizard_map_created)
	target_profile_dialog.profile_applied.connect(func(msg: String): sync_actions(); report(msg))
	target_profile_dialog.mods_changed.connect(_on_mods_settings_changed)
	path_inspector.path_created.connect(select_created_path)
	path_inspector.path_removed.connect(func(label: String): report("Removed path %s." % label))
	mission_studio.paths_selection_changed.connect(set_extra_path_selection)
	mission_studio.path_focused.connect(select_created_path)
	mission_studio.snap_toggled.connect(func(on: bool): snap_path_drag = on)
	mission_studio.status_message.connect(report)
	var work_area := HBoxContainer.new()
	work_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(work_area)
	work_area.add_child(brush_panel)
	brush_panel.brush_changed.connect(update_brush_cursor)
	var views := HSplitContainer.new()
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_area.add_child(views)
	top.palette = colors
	scene_view.palette = colors
	top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for panel in [scene_view, top]:
		var dock := VBoxContainer.new()
		dock.custom_minimum_size.x = 158 if panel == top else 225
		dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dock.size_flags_stretch_ratio = 2.05 if panel == scene_view else 1.0
		views.add_child(dock)
		var heading := HFlowContainer.new()
		heading.add_theme_constant_override("h_separation", 3)
		heading.add_theme_constant_override("v_separation", 3)
		dock.add_child(heading)
		if panel == scene_view:
			add_camera_toolbar(heading)
		else:
			add_label(heading, "2D Map")
			objects_button = add_button(heading, "Objects", toggle_objects, "Display supported native BZCC models in the 3D view")
			objects_button.toggle_mode = true
			object_browser_button = add_button(heading, "Object Browser", open_object_browser, "Browse active mod ODFs, inspect dependencies and place verified native objects onto terrain")
			move_objects_button = add_button(heading, "Move Object", object_tool_changed, "Select and drag an object in either view. Shift snaps to the terrain grid. [ / ] rotate ±15° (Shift 1°), Ctrl+D duplicates, Delete removes. Esc cancels.")
			move_objects_button.toggle_mode = true
			object_label_button = add_button(heading, "Object Label", open_object_label_editor, "Edit the native BZN label of the selected object")
			sound_button = add_button(heading, "Sound Point", open_sound_editor, "Edit structured VRV sound point settings (vrvsnd:...) on a selected vrv_sndpoint object")
			water_button = add_button(heading, "Water", toggle_water, "Preview decoded native water layers in both views")
			water_button.toggle_mode = true
			water_edit_button = add_button(heading, "Edit Water", toggle_water_edit, "Edit water layer coverage and elevations. Left drag paints, Shift erases.")
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dock.add_child(panel)
		if panel == scene_view:
			empty_state_hint.text = "No map loaded — click Open or New Map"
			empty_state_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_state_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty_state_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			empty_state_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty_state_hint.add_theme_color_override("font_color", colors["textMuted"])
			panel.add_child(empty_state_hint)
		panel.mouse_exited.connect(func():
			set_cursor(Vector2(-1, -1))
			if paint_view == panel:
				anchor = Vector2(-1, -1))
		panel.gui_input.connect(view_input.bind(panel))
	coordinates.text = "Hold or drag left to paint. Orbit with right drag. Pan with middle drag. Zoom with wheel."
	coordinates.add_theme_color_override("font_color", colors["textSecondary"])
	coordinates.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(coordinates)
	status.text = "Ready"
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(status)
	setup_dialog(open_dialog, FileDialog.FILE_MODE_OPEN_FILE, ["*.bzn ; Battlezone mission", "*.bzmag ; BZMAG project"])
	open_dialog.file_selected.connect(request_open)
	setup_dialog(blank_dialog, FileDialog.FILE_MODE_OPEN_FILE, ["*.bzn ; Blank Battlezone mission"])
	blank_dialog.title = "Choose a blank BZN without terrain"
	blank_dialog.file_selected.connect(choose_blank_mission)
	setup_dialog(flat_template_dialog, FileDialog.FILE_MODE_OPEN_FILE, ["*.ter ; Flat terrain template"])
	flat_template_dialog.title = "Choose a flat TER matching the blank map"
	flat_template_dialog.file_selected.connect(choose_flat_template)
	setup_dialog(flat_output_dialog, FileDialog.FILE_MODE_OPEN_DIR, [])
	flat_output_dialog.title = "Choose a parent folder for the new map"
	flat_output_dialog.dir_selected.connect(create_flat_map)
	setup_dialog(save_dialog, FileDialog.FILE_MODE_SAVE_FILE, ["*.bzmag ; BZMAG project"])
	save_dialog.file_selected.connect(save_project)
	setup_dialog(export_dialog, FileDialog.FILE_MODE_OPEN_DIR, [])
	export_dialog.dir_selected.connect(export_package)
	confirmation.title = "Open another map"
	confirmation.dialog_text = "Open another map and discard unsaved edits?"
	add_child(confirmation)
	confirmation.confirmed.connect(func(): open_map(pending_path))
	keys_dialog.title = "Editor Hotkeys"
	keys_dialog.dialog_text = "F  Fly camera (3D view)\nW/S/A/D  Fly forward / back / strafe\nQ/E  Fly down / up\n\nShift+1–6  Brush size\nShift+Q/W/E/R  Square / Circle / Cone / Bell\nShift+Z/X/C/V  Pressure 10 / 20 / 50 / 100%\nShift+A/S/D/F/G  Paint / Spray / Raise / Blend / Pick\nAlt+H  Height brush\nF5  Playtest\nCtrl+O/S/Z/Y  Open / Save Project / Undo / Redo\n\nMove Points tool\nDrag  Move a point\nShift+click  Append a point\nDelete  Remove selected point\nEsc  Cancel drag\n\nMove Object tool\nDrag  Move an object\nShift+drag  Snap to terrain grid\n[ / ]  Rotate −15° / +15°  (Shift for 1°)\nCtrl+D  Duplicate the selection\nDelete  Remove the selection\nEsc  Cancel drag\n\nEdit Water dialog\nLeft drag  Paint coverage on the chosen layer\nShift+drag  Erase coverage\nApply Elevation  Set the layer water height\nDialog closes  Painting stops"
	add_child(keys_dialog)
	studio.hide()
	add_child(studio)
	studio.updated.connect(func(value): sync_actions(); report(value))
	studio.preview_display.connect(show_graph_preview)
	add_child(terrain_tools)
	terrain_tools.updated.connect(func(value: String): sync_actions(); report(value))
	add_child(slope_studio)
	slope_studio.updated.connect(func(value: String): sync_actions(); report(value))
	add_child(environment_studio)
	environment_studio.updated.connect(func(value: String): sync_actions(); report(value))
	environment_studio.preview_toggled.connect(func(on: bool):
		if document != null:
			scene_view.apply_environment_preview(document.effective_environment(), on))
	add_child(sound_editor)
	sound_editor.updated.connect(func(value: String): sync_actions(); report(value))
	sound_editor.sound_point_selected.connect(select_object_view)
	add_child(object_browser)
	object_browser.place_requested.connect(start_place_object)
	object_browser.place_at_cursor_requested.connect(place_object_at_cursor)
	object_browser.status_message.connect(report)
	object_label_dialog.title = "Object Label Editor"
	object_label_dialog.ok_button_text = "Apply Label"
	object_label_dialog.dialog_hide_on_ok = false
	var label_box := VBoxContainer.new()
	label_box.custom_minimum_size.x = 396
	label_box.add_theme_constant_override("separation", 6)
	object_label_target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	object_label_target.custom_minimum_size.x = 396
	label_box.add_child(object_label_target)
	object_label_field.placeholder_text = "ASCII label (empty clears custom label)"
	label_box.add_child(object_label_field)
	object_label_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	object_label_status.custom_minimum_size.x = 396
	label_box.add_child(object_label_status)
	object_label_dialog.add_child(label_box)
	object_label_dialog.confirmed.connect(apply_object_label_dialog)
	add_child(object_label_dialog)
	add_child(water_tools)
	water_tools.updated.connect(func(value: String): sync_actions(); report(value))
	water_tools.painting_changed.connect(update_water_painting)
	setup_dialog(game_picker, FileDialog.FILE_MODE_OPEN_DIR, [])
	setup_dialog(vrv_picker, FileDialog.FILE_MODE_OPEN_DIR, [])
	setup_dialog(autosave_picker, FileDialog.FILE_MODE_OPEN_DIR, [])
	setup_dialog(asset_profile_picker, FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Asset profile"])
	asset_profile_picker.title = "Choose a linked asset profile"
	asset_profile_picker.use_native_dialog = true
	asset_profile_picker.file_selected.connect(func(path: String): asset_profile_path.text = path)
	game_picker.use_native_dialog = true
	vrv_picker.use_native_dialog = true
	playtest_dialog.title = "Playtest Setup"
	playtest_dialog.ok_button_text = "Save Settings"
	playtest_dialog.dialog_hide_on_ok = false
	playtest_dialog.dialog_autowrap = true
	var paths := VBoxContainer.new()
	paths.custom_minimum_size.x = 540
	paths.add_theme_constant_override("separation", 4)
	add_label(paths, "Battlezone installation folder")
	add_folder_field(paths, game_path, game_picker, "Select the Battlezone installation folder")
	add_label(paths, "VRV source folder (optional engine layout converter and VSR assets)")
	add_folder_field(paths, vrv_path, vrv_picker, "Select the VRV source folder")
	add_label(paths, "Autosave folder (empty keeps the default user folder; never the map folder)")
	add_folder_field(paths, autosave_root_field, autosave_picker, "Select the autosave store folder")
	add_label(paths, "Asset profile for this project (optional)")
	var profile_row := HBoxContainer.new()
	paths.add_child(profile_row)
	asset_profile_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_profile_path.editable = false
	profile_row.add_child(asset_profile_path)
	asset_profile_browse = add_button(profile_row, "Browse…", asset_profile_picker.popup_centered_ratio.bind(0.72), "Link a JSON asset profile to this project")
	asset_profile_browse.disabled = true
	engine_editor_mode.text = "Start in the engine editor without mission scripts"
	paths.add_child(engine_editor_mode)
	var theme_row := VBoxContainer.new()
	paths.add_child(theme_row)
	var theme_lbl := Label.new()
	theme_lbl.text = "Wintage theme"
	theme_row.add_child(theme_lbl)
	for slug in Wintage.theme_slugs():
		theme_select.add_item(Wintage.theme_label(slug))
	theme_select.item_selected.connect(func(idx: int): set_wintage_theme(Wintage.theme_slugs()[idx], compact_check.button_pressed))
	theme_row.add_child(theme_select)
	compact_check.text = "Compact toolbar spacing"
	compact_check.toggled.connect(func(on: bool): set_wintage_theme(theme_slug, on))
	paths.add_child(compact_check)
	add_button(paths, "Find via Steam", func(): find_steam_game(true), "Find Battlezone in your Steam libraries")
	add_button(paths, "Game & Mods Manager…", func(): open_target_profile(1), "Discover Stock, VSR, VRV and Steam Workshop mods")
	paths.add_child(setup_status)
	playtest_dialog.add_child(paths)
	add_child(playtest_dialog)
	playtest_dialog.confirmed.connect(save_playtest_setup)
	game_path.text = settings.get_value("playtest", "game", "")
	vrv_path.text = settings.get_value("playtest", "vrv", "")
	autosave_root_field.text = settings.get_value("autosave", "root", "")
	autosave_custom_root = autosave_root_field.text.strip_edges()
	engine_editor_mode.button_pressed = settings.get_value("playtest", "engine_editor", false)
	vrv_configured = settings.has_section_key("playtest", "vrv")
	default_new_mod_profile = String(settings.get_value("new_map", "default_mod", "stock"))
	if default_new_mod_profile.is_empty():
		default_new_mod_profile = "stock"
	mod_registry.discover_installed(game_path.text.strip_edges(), vrv_path.text.strip_edges())
	sync_theme_controls()
	recover_dialog.title = "Recover autosave"
	recover_dialog.min_size = Vector2i(520, 260)
	recover_dialog.ok_button_text = "Open Selected"
	recover_dialog.dialog_autowrap = true
	recover_dialog.add_child(recover_list)
	recover_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recover_list.tooltip_text = "Rolling autosave slots, oldest first. Items outside the verified slot naming rule never appear here."
	recover_dialog.confirmed.connect(open_recovered_autosave)
	add_child(recover_dialog)
	sync_actions()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		call_deferred("open_command_line", args[0])


func add_label(parent: Node, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)


func add_button(parent: Node, caption: String, action: Callable, tip: String, key := KEY_NONE) -> Button:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = tip
	button.pressed.connect(action)
	if key != KEY_NONE:
		var event := InputEventKey.new()
		event.keycode = key
		event.ctrl_pressed = true
		button.shortcut = Shortcut.new()
		button.shortcut.events = [event]
	parent.add_child(button)
	return button


func add_camera_toolbar(parent: Control) -> void:
	solid_button = add_button(parent, "Solid", show_wire.bind(false), "Preview solid terrain")
	wire_button = add_button(parent, "Wire", show_wire.bind(true), "Preview the terrain mesh")
	for button in [solid_button, wire_button]:
		button.toggle_mode = true
	show_wire(false)
	camera_buttons.append(add_button(parent, "Top", scene_view.set_view.bind(true), "Orthographic top view"))
	camera_buttons.append(add_button(parent, "Orbit", scene_view.set_view.bind(false), "Perspective orbit view"))
	focus_button = add_button(parent, "Focus", focus_terrain, "Focus the 3D camera on the last terrain cursor")
	fly_button = add_button(parent, "Fly", toggle_fly, "Free-flight camera. W/S forward and back, A/D strafe, Q/E down and up, right drag to look, F toggles.")
	fly_button.toggle_mode = true
	color_button = add_button(parent, "Color", show_vertex_colors, "Preview native TER vertex colors")
	color_button.toggle_mode = true
	texture_button = add_button(parent, "Texture", toggle_textures, "Preview native TRN tile textures with terrain tint and blending")
	texture_button.toggle_mode = true


func toggle_water() -> void:
	top.water_visible = water_button.button_pressed
	top.queue_redraw()
	scene_view.show_water(top.water_visible)
	if top.water_visible:
		var water := document.package.water
		var message := "%d WAT layer(s) visible" % document.water_layers_effective().size()
		if water.invalid_layer_flags != 0:
			message += " · skipped invalid layer heights"
		report(message)


func show_wire(enabled: bool) -> void:
	scene_view.set_wireframe(enabled)
	solid_button.set_pressed_no_signal(not enabled)
	wire_button.set_pressed_no_signal(enabled)


func add_folder_field(parent: Node, field: LineEdit, picker: FileDialog, caption: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	picker.title = caption
	picker.dir_selected.connect(func(folder): field.text = folder)
	add_button(row, "Browse…", func():
		if DirAccess.dir_exists_absolute(field.text):
			picker.current_dir = field.text
		picker.popup_centered_ratio(0.72), caption)


func setup_dialog(dialog: FileDialog, mode: FileDialog.FileMode, filters: PackedStringArray) -> void:
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = filters
	add_child(dialog)


func update_brush_cursor() -> void:
	var layer := brush_panel.paint_layer()
	var lane := int(brush_panel.texture_lane.value)
	if layer != top.preview_layer or (layer == Terrain.Layer.TILES and lane != top.preview_tile_lane):
		finish_stroke()
	move_path_button.set_pressed_no_signal(false)
	if object_tool.active:
		leave_object_tool()
	top.radius_m = brush_panel.radius_m
	scene_view.radius_m = brush_panel.radius_m
	top.square_brush = brush_panel.shape == Document.BrushShape.SQUARE
	scene_view.square_brush = top.square_brush
	top.show_material(layer, lane)
	show_vertex_colors()
	set_cursor(cursor)


func show_vertex_colors() -> void:
	if color_button == null:
		return
	var enabled := color_button.button_pressed or top.preview_layer == Terrain.Layer.COLOR
	if scene_view.use_vertex_colors != enabled:
		scene_view.show_vertex_colors(enabled)


func show_graph_preview(layer: int) -> void:
	if layer < 0:
		top.show_material(brush_panel.paint_layer(), int(brush_panel.texture_lane.value))
	else:
		top.show_material(layer, 0)
	scene_view.show_graph_channel(layer)
	if layer < 0:
		show_vertex_colors()


func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or document == null or document.stroke_active or document.water_stroke_active:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if event.keycode == KEY_ESCAPE and not pending_place_spec.is_empty():
		cancel_place_object(true)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and (path_drag_view != null or object_tool.drag_view != null):
		if object_tool.drag_view != null:
			finish_object_drag(false)
		else:
			finish_point_drag(false)
		get_viewport().set_input_as_handled()
		return
	if path_drag_view != null or object_tool.drag_view != null:
		return
	if event.keycode == KEY_DELETE and move_path_button.button_pressed and selected_path_point >= 0:
		delete_path_point()
		get_viewport().set_input_as_handled()
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if object_tool.active and not event.echo:
		if event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT] and not event.ctrl_pressed and not event.alt_pressed:
			var step := deg_to_rad(1.0) if event.shift_pressed else deg_to_rad(15.0)
			var direction := -1.0 if event.keycode == KEY_BRACKETLEFT else 1.0
			if object_tool.selected >= 0 and document.rotate_object(object_tool.selected, direction * step):
				report(object_tool.description())
			else:
				report(document.error)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_D and event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
			if object_tool.selected >= 0 and not document.has_preview():
				var origin := document.object_position(object_tool.selected)
				var offset := Vector3(4.0, 0.0, 4.0)
				var view := document.duplicate_object(object_tool.selected, origin + offset)
				if view >= 0:
					object_tool.set_active(true)
					object_tool.selected = view
					object_tool.refresh_marker()
					report(object_tool.description() + object_count_notice("Duplicated"))
				else:
					report(document.error)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE and not event.ctrl_pressed:
			if object_tool.selected >= 0 and document.remove_object(object_tool.selected):
				object_tool.selected = -1
				object_tool.refresh_marker()
				report("Object removed. Undo restores it." + object_count_notice("Removed"))
			else:
				report(document.error)
			get_viewport().set_input_as_handled()
			return
	if event.keycode == KEY_F and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not object_tool.active:
		fly_button.set_pressed_no_signal(not fly_button.button_pressed)
		toggle_fly()
		get_viewport().set_input_as_handled()
	elif event.alt_pressed and key == KEY_H:
		leave_object_tool()
		move_path_button.set_pressed_no_signal(false)
		path_tool_changed()
		get_viewport().set_input_as_handled()
	elif event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and brush_panel.shortcut(key):
		move_path_button.set_pressed_no_signal(false)
		path_tool_changed(false)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F5 and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
		playtest()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F1:
		Wintage.popup_fit(keys_dialog, 420)
		get_viewport().set_input_as_handled()


func sync_actions() -> void:
	var locked := document == null or document.stroke_active or document.water_stroke_active or path_drag_view != null or object_tool.drag_view != null
	undo_button.disabled = locked or document.undo_stack.is_empty()
	redo_button.disabled = locked or document.redo_stack.is_empty()
	save_button.disabled = locked
	export_button.disabled = locked
	playtest_button.disabled = locked or launcher_pid > 0 or game_pid > 0 or OS.get_name() != "Windows"
	focus_button.disabled = locked
	fly_button.disabled = locked
	for button in camera_buttons:
		button.disabled = locked
	nodes_button.disabled = locked
	terrain_tools_button.disabled = locked
	slope_studio_button.disabled = locked or document.has_preview()
	if environment_button != null:
		environment_button.disabled = locked
	new_path_button.disabled = locked or not document.package.path_codec.can_resize
	edit_path_button.disabled = locked or path_list.selected <= 0
	move_path_button.disabled = locked or path_list.selected <= 0
	mission_studio_button.disabled = locked
	var thread_busy := object_thread != null and object_thread.is_started()
	objects_button.disabled = locked or document.object_count() == 0 or thread_busy
	if object_browser_button != null:
		object_browser_button.disabled = locked
	move_objects_button.disabled = locked or document.object_count() == 0 or document.has_preview()
	if object_label_button != null:
		object_label_button.disabled = locked or document.object_count() == 0
	if sound_button != null:
		sound_button.disabled = locked or document.object_count() == 0
	water_button.disabled = locked or document.package.water == null
	water_edit_button.disabled = water_button.disabled
	color_button.disabled = locked or texture_button.button_pressed
	texture_button.disabled = locked or thread_busy
	if document != null:
		var terrain := document.package.terrain
		var dirty := "*" if has_unsaved_changes() else ""
		title.text = "%s%s  |  %s · %s  |  BZN %d  |  %d × %d m" % [
			document.package.mission_name, dirty, document.mod_profile, document.mission_profile,
			document.package.bzn_version, terrain.dimensions.x * 2, terrain.dimensions.y * 2]
	if empty_state_hint != null:
		empty_state_hint.visible = (document == null)


func has_unsaved_changes() -> bool:
	return document != null and (document.edits != saved_edits or document.layers != saved_layers
		or document.path_edits != saved_path_edits or document.asset_profile != saved_asset_profile
		or document.engine_profile != saved_engine_profile or document.mod_profile != saved_mod_profile
		or document.mission_profile != saved_mission_profile
		or document.object_edits != saved_object_edits or document.object_label_edits != saved_object_label_edits
		or document.object_odf_edits != saved_object_odf_edits
		or document.object_additions != saved_object_additions
		or document.object_removals != saved_object_removals
		or document.package.terrain.color_edits != saved_colors or document.package.terrain.tile_edits != saved_tiles
		or document.water_edits != saved_water_edits or document.water_heights != saved_water_heights
		or document.effective_mission_dll() != saved_mission_dll
		or document.environment_edits != saved_environment_edits)


func remember_saved_changes() -> void:
	saved_edits = document.edits.duplicate()
	saved_layers = document.layers.duplicate(true)
	saved_path_edits = document.path_edits.duplicate(true)
	saved_object_edits = document.object_edits.duplicate(true)
	saved_object_label_edits = document.object_label_edits.duplicate()
	saved_object_odf_edits = document.object_odf_edits.duplicate()
	saved_object_additions = document.object_additions.duplicate(true)
	saved_object_removals = document.object_removals.duplicate()
	saved_asset_profile = document.asset_profile
	saved_engine_profile = document.engine_profile
	saved_mod_profile = document.mod_profile
	saved_mission_profile = document.mission_profile
	saved_colors = document.package.terrain.color_edits.duplicate()
	saved_tiles = document.package.terrain.tile_edits.duplicate()
	saved_water_edits = document.water_edits.duplicate(true)
	autosave_seconds = 0.0
	saved_water_heights = document.water_heights.duplicate()
	saved_mission_dll = document.effective_mission_dll()
	saved_environment_edits = document.environment_edits.duplicate(true)


func request_open(path: String) -> void:
	finish_stroke()
	if has_unsaved_changes():
		pending_path = path
		confirmation.popup_centered()
	else:
		open_map(path)


func choose_blank_mission(mission: String) -> void:
	blank_dialog.hide()
	blank_mission = mission
	var templates := vrv_path.text.strip_edges().path_join("mod/Data/Templates")
	if DirAccess.dir_exists_absolute(templates):
		flat_template_dialog.current_dir = templates
	flat_template_dialog.popup_centered_ratio(0.72)


func choose_flat_template(template: String) -> void:
	flat_template_dialog.hide()
	flat_template = template
	flat_output_dialog.current_dir = blank_mission.get_base_dir()
	flat_output_dialog.popup_centered_ratio(0.72)


func create_flat_map(parent: String) -> void:
	flat_output_dialog.hide()
	var writer := Snapshots.new()
	var stem := blank_mission.get_file().get_basename()
	var target := parent.path_join(stem + "-flat-" + writer.nonce().left(8))
	var helper := tool_root().path_join("tools/New-FlatTerrainSnapshot.ps1")
	if not writer.create_flat_map(blank_mission, flat_template, target, helper):
		report(writer.error)
		return
	request_open(target.path_join(blank_mission.get_file()))
	report("Created and verified flat map at " + target)


func open_command_line(path: String) -> void:
	if document != null:
		return
	if open_map(path):
		print(title.text)
	else:
		printerr(status.text)


func cancel_all_slider_gestures(root_node: Node = self) -> void:
	if root_node.has_method("is_gesture_active") and root_node.has_method("cancel_gesture"):
		if bool(root_node.call("is_gesture_active")):
			root_node.call("cancel_gesture")
	for child in root_node.get_children():
		cancel_all_slider_gestures(child)


func open_map(path: String) -> bool:
	cancel_all_slider_gestures()
	if not path.is_absolute_path():
		path = OS.get_executable_path().get_base_dir().path_join(path) if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://").path_join(path)
	var next := Document.new()
	if not next.open(path.simplify_path()):
		report(next.error)
		return false
	if document != null:
		if studio.document != null:
			studio.close_studio()
		if document.terrain_changed.is_connected(mark_refresh):
			document.terrain_changed.disconnect(mark_refresh)
		if document.materials_changed.is_connected(mark_material_refresh):
			document.materials_changed.disconnect(mark_material_refresh)
		if document.paths_changed.is_connected(refresh_path_list):
			document.paths_changed.disconnect(refresh_path_list)
		if document.object_moved.is_connected(object_position_changed):
			document.object_moved.disconnect(object_position_changed)
		if document.objects_changed.is_connected(objects_topology_changed):
			document.objects_changed.disconnect(objects_topology_changed)
		if document.water_changed.is_connected(refresh_water):
			document.water_changed.disconnect(refresh_water)
		if document.profile_changed.is_connected(on_document_profile_changed):
			document.profile_changed.disconnect(on_document_profile_changed)
		if document.environment_changed.is_connected(on_document_environment_changed):
			document.environment_changed.disconnect(on_document_environment_changed)
	water_tools.hide()
	painting_water = false
	document = next
	loaded_objects = null
	objects_button.set_pressed_no_signal(false)
	top.objects_visible = false
	top.object_marks.clear()
	texture_button.set_pressed_no_signal(false)
	water_button.set_pressed_no_signal(false)
	top.water_visible = false
	last_cursor = Vector2(-1, -1)
	selected_extra_paths.clear()
	top.extra_paths.clear()
	scene_view.extra_paths.clear()
	move_path_button.set_pressed_no_signal(false)
	move_objects_button.set_pressed_no_signal(false)
	remember_saved_changes()
	asset_profile_path.text = document.asset_profile
	asset_profile_path.editable = true
	asset_profile_browse.disabled = false
	pending_refresh = Rect2i()
	pending_materials.clear()
	document.terrain_changed.connect(mark_refresh)
	document.materials_changed.connect(mark_material_refresh)
	document.paths_changed.connect(refresh_path_list)
	document.object_moved.connect(object_position_changed)
	document.objects_changed.connect(objects_topology_changed)
	document.water_changed.connect(refresh_water)
	document.profile_changed.connect(on_document_profile_changed)
	document.environment_changed.connect(on_document_environment_changed)
	top.bind(document)
	scene_view.bind(document)
	brush_panel.sync_height_range(document.package.terrain.min_height, document.package.terrain.max_height)
	object_tool.bind(document, top, scene_view)
	refresh_path_list(true)
	set_cursor(Vector2(-1, -1))
	var cur_game := game_path.text.strip_edges()
	var cur_vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != cur_game:
		mod_registry.discover_installed(cur_game, cur_vrv)
	document.detected_profile_info = ModRegistry.detect_map_profiles(document.package, mod_registry)
	if not document.profile_explicit:
		document.mod_profile = String(document.detected_profile_info.get("recommendedMod", "stock"))
		document.mission_profile = String(document.detected_profile_info.get("recommendedMission", "blank"))
		remember_saved_changes()
	sync_actions()
	var open_compat := CompatibilityEngine.evaluate(document, mod_registry, document.mod_profile, document.mission_profile, document.engine_profile, cur_game, cur_vrv, {}, engine_editor_mode.button_pressed)
	var open_note := ""
	if String(open_compat["validationStatus"]) != CompatibilityEngine.PLAYTEST_READY:
		var reasons: Array = open_compat.get("refusalReasons", [])
		if not reasons.is_empty():
			open_note = " [%s: %s]" % [String(open_compat["validationStatus"]), String(reasons[0])]
	report("Opened %s [%s / %s]%s" % [document.package.source_path.get_file(), document.mod_profile, document.mission_profile, open_note])
	return true


func open_new_map_wizard() -> void:
	find_steam_game()
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != game:
		mod_registry.discover_installed(game, vrv)
	var fallback := tool_root().path_join("map_references/blank_map1/duel_map_27_autosave_01.bzn")
	var parent_dir := document.package.source_path.get_base_dir().get_base_dir() if document != null else tool_root().path_join("build")
	new_map_wizard.begin(mod_registry, game, default_new_mod_profile, parent_dir, fallback)


func _on_wizard_map_created(bzn_path: String, engine_id: String, mod_id: String, mission_id: String) -> void:
	default_new_mod_profile = mod_id
	_save_new_map_default()
	if open_map(bzn_path):
		# Strictly preserve the user's explicit ModProfile selection (never silently override Stock with VSR/VRV).
		document.engine_profile = engine_id
		document.mod_profile = mod_id
		document.mission_profile = mission_id
		document.profile_explicit = true
		remember_saved_changes()
		sync_actions()
		var compat := validate_playtest_profile()
		if not bool(compat["profileCompatible"]):
			report("Created %s map (%s / %s) at %s [WARN: contains %s object(s): %s — use Target Profile to switch or replace]" % [
				mod_id, mission_id, engine_id, bzn_path.get_base_dir(),
				String(compat["suggestedMod"]).to_upper(), ", ".join(compat["incompatibleOdfs"])])
		else:
			report("Created %s map (%s / %s) at %s" % [mod_id, mission_id, engine_id, bzn_path.get_base_dir()])


func open_target_profile(tab_index: int = 0) -> void:
	target_profile_dialog.begin(document, mod_registry, game_path.text.strip_edges(), vrv_path.text.strip_edges(), default_new_mod_profile, tab_index)


func _on_mods_settings_changed(new_default: String) -> void:
	if not new_default.is_empty():
		default_new_mod_profile = new_default
		_save_new_map_default()


func _save_new_map_default() -> void:
	var settings := ConfigFile.new()
	settings.load(settings_path)
	settings.set_value("new_map", "default_mod", default_new_mod_profile)
	settings.save(settings_path)


func on_document_profile_changed() -> void:
	loaded_objects = null
	scene_view.object_models.clear_models()
	scene_view.object_models.hide()
	top.objects_visible = false
	top.object_marks.clear()
	objects_button.set_pressed_no_signal(false)
	scene_view.tile_material = null
	scene_view.tile_maps.clear()
	scene_view.show_textures(false)
	texture_button.set_pressed_no_signal(false)
	top.queue_redraw()
	if mission_studio.visible:
		mission_studio.refresh_all()
	if target_profile_dialog.visible:
		target_profile_dialog.refresh_all()
	if object_browser.visible:
		object_browser.refresh_catalog()
	cancel_place_object(false)
	sync_actions()


func on_document_environment_changed() -> void:
	if document == null:
		return
	if scene_view.env_preview_enabled:
		scene_view.apply_environment_preview(document.effective_environment(), true)
	if environment_studio.visible:
		environment_studio.refresh_all()
	sync_actions()


func open_environment_studio() -> void:
	if document == null:
		return
	environment_studio.begin(document, scene_view.env_preview_enabled)


func request_save() -> void:
	save_dialog.current_file = document.package.source_path.get_file().get_basename() + ".bzmag"
	save_dialog.popup_centered_ratio(0.72)


func select_path(index: int) -> void:
	selected_path_point = -1
	if index <= 0:
		move_path_button.set_pressed_no_signal(false)
	var path := document.path_at(path_index_for_item(index))
	draw_path(path)
	if index > 0:
		report("%s · %d points · native path type %d" % [path["name"], path["points"].size(), path["type"]])
	sync_actions()


func draw_path(path: Dictionary) -> void:
	var primary_index := path_index_for_item(path_list.selected)
	var extras: Array[Dictionary] = []
	for idx in selected_extra_paths:
		if idx != primary_index:
			var extra := document.path_at(idx)
			if not extra.is_empty():
				extras.append(extra)
	top.selected_path_point = selected_path_point
	scene_view.selected_path_point = selected_path_point
	top.extra_paths = extras
	scene_view.extra_paths = extras
	top.path_overlay = path
	top.queue_redraw()
	scene_view.show_path(path)


func set_extra_path_selection(indices: Array[int]) -> void:
	selected_extra_paths = indices.duplicate()
	if document != null:
		draw_path(document.path_at(path_index_for_item(path_list.selected)))


func open_mission_studio() -> void:
	if document == null:
		return
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	var world := scene_view.point_world(target)
	mission_studio.begin(document, Vector2(world.x, world.z))


func refresh_path_list(reset := false) -> void:
	var slot := -1 if reset else path_index_for_item(path_list.selected)
	var selected := 0
	var point := -1 if reset else selected_path_point
	path_list.clear()
	path_list.add_item("Path overlay")
	for index in document.path_indices():
		path_list.add_item(document.path_at(index)["name"])
		var item := path_list.item_count - 1
		path_list.set_item_metadata(item, index)
		if index == slot:
			selected = item
	path_list.select(selected)
	path_list.disabled = path_list.item_count <= 1
	select_path(selected)
	if selected > 0 and point >= 0:
		var path := document.path_at(slot)
		selected_path_point = mini(point, path["points"].size() - 1)
		draw_path(path)
	if mission_studio.visible:
		mission_studio.refresh_all()


func path_index_for_item(item: int) -> int:
	return int(path_list.get_item_metadata(item)) if item > 0 and item < path_list.item_count else -1


func start_new_path() -> void:
	var sample := last_cursor if last_cursor.x >= 0 else Vector2(document.package.terrain.dimensions) * 0.5
	var point := scene_view.point_world(sample)
	path_inspector.show_new_path(document, Vector2(point.x, point.z))


func select_created_path(index: int) -> void:
	for item in range(1, path_list.item_count):
		if path_index_for_item(item) == index:
			path_list.select(item)
			select_path(item)
			return


func inspect_path() -> void:
	if path_list.selected > 0:
		path_inspector.show_path(document, path_index_for_item(path_list.selected))


func path_tool_changed(announce := true) -> void:
	if move_path_button.button_pressed:
		leave_object_tool()
	set_cursor(cursor)
	if announce:
		report("Drag a path point. Shift+click appends a point. Delete removes the selected point." if move_path_button.button_pressed else "Height brush ready.")


func start_point_drag(panel: Control, pixel: Vector2, append: bool) -> void:
	var path := document.path_at(path_index_for_item(path_list.selected))
	if append:
		var sample: Vector2 = panel.sample_at(pixel)
		if sample.x >= 0:
			var point := scene_view.point_world(sample)
			var points: PackedVector2Array = path["points"].duplicate()
			points.append(Vector2(point.x, point.z))
			submit_path_points(path, points)
		return
	var best := 16.0
	var nearest := -1
	var points: PackedVector2Array = path["points"]
	for index in points.size():
		var distance: float = pixel.distance_to(panel.path_point_pixel(points[index]))
		if distance < best:
			best = distance
			nearest = index
	if nearest < 0:
		return
	selected_path_point = nearest
	path_drag_view = panel
	path_draft = path.duplicate(true)
	draw_path(path_draft)
	sync_actions()


func preview_path_point(sample: Vector2) -> void:
	if sample.x < 0:
		return
	var point := scene_view.point_world(sample)
	var xz := Vector2(point.x, point.z)
	if snap_path_drag:
		xz = MissionProfiles.snap_point(xz, document.package.terrain)
	path_draft["points"][selected_path_point] = xz
	draw_path(path_draft)


func finish_point_drag(commit: bool) -> void:
	path_drag_view = null
	if commit:
		submit_path_points(path_draft, path_draft["points"])
	draw_path(document.path_at(path_index_for_item(path_list.selected)))
	path_draft = {}
	sync_actions()


func delete_path_point() -> void:
	var path := document.path_at(path_index_for_item(path_list.selected))
	var points: PackedVector2Array = path["points"].duplicate()
	points.remove_at(selected_path_point)
	submit_path_points(path, points)


func submit_path_points(path: Dictionary, points: PackedVector2Array) -> void:
	if not document.edit_path(path_index_for_item(path_list.selected), path["name"], points, path["type"]):
		report(document.error)


func request_export() -> void:
	export_dialog.title = "Choose parent folder for a new native snapshot"
	export_dialog.popup_centered_ratio(0.72)


func save_project(path: String) -> void:
	var writer := Snapshots.new()
	if writer.save_project(document, path):
		remember_saved_changes()
		sync_actions()
		report("Saved " + path)
	else:
		report(writer.error)


func export_package(folder: String) -> void:
	var writer := Snapshots.new()
	var name := document.package.source_path.get_file().get_basename()
	var target := folder.path_join(name + "-bzmag-" + writer.nonce().left(8))
	if writer.export_native(document, target):
		var compat := validate_playtest_profile()
		var status_tag := String(compat.get("validationStatus", "UNKNOWN"))
		report("Exported and re-imported %s | Compatibility: %s%s" % [
			target, status_tag, object_count_notice("Format verified")])
	else:
		report(writer.error)


## Engine-compatibility notice for object count edits. Verified 1192/1196 layouts
## insert before the 640-byte groupTargets boundary with fresh pointer IDs; any
## layout without verified count edits stays gated before Playtest.
func object_count_notice(suffix: String) -> String:
	if document == null or (document.object_additions.is_empty() and document.object_removals.is_empty()):
		return " | " + suffix
	var status_label := Layouts.capability_status(document.package.layout_id, Layouts.EDIT_OBJECT_COUNT)
	if status_label in ["NATIVE", "BAKED"]:
		return " | Added %d and removed %d objects (%s on 2.0.185; %s)" % [
			document.object_additions.size(), document.object_removals.size(), status_label, suffix]
	return " | Adding %d and removing %d objects is %s: undo count edits before Playtest. %s" % [
		document.object_additions.size(), document.object_removals.size(), status_label, suffix]


func report(message: String) -> void:
	status.text = message
	status.tooltip_text = message


func tool_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()


func asset_adapter() -> String:
	var built := tool_root().path_join("build/object-preview/mesh-preview.exe")
	var bundled := tool_root().path_join("tools/mesh-preview.exe")
	if OS.has_feature("editor"):
		return built
	return bundled if FileAccess.file_exists(bundled) else built


func toggle_objects() -> void:
	if not objects_button.button_pressed:
		scene_view.object_models.hide()
		top.objects_visible = false
		object_tool.update_anchors()
		top.queue_redraw()
		return
	if loaded_objects == document:
		scene_view.object_models.show()
		top.objects_visible = true
		object_tool.update_anchors()
		top.queue_redraw()
		return
	start_asset_scan("objects", objects_button)


func toggle_textures() -> void:
	if not texture_button.button_pressed or scene_view.tile_material:
		scene_view.show_textures(texture_button.button_pressed)
		sync_actions()
		return
	start_asset_scan("textures", texture_button)


func start_asset_scan(kind: String, button: Button) -> void:
	var adapter := asset_adapter()
	if not FileAccess.file_exists(adapter):
		report("Native asset preview needs the local VRV adapter. Run Build-ObjectPreview.ps1.")
		button.set_pressed_no_signal(false)
		return
	if not find_steam_game():
		report("Choose the game folder in Setup to preview native assets.")
		button.set_pressed_no_signal(false)
		return
	active_object_scan = document
	asset_kind = kind
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != game:
		mod_registry.discover_installed(game, vrv)
	var env := mod_registry.resolve_content_environment(document, game, vrv)
	var folder := String(env["mapFolder"])
	var extra_roots: Array = env["linkedFolders"] + env["modAssetRoots"]
	var active_mod := String(env["modProfile"])
	var task: Callable
	if kind == "objects":
		asset_worker = NativeAssets.new()
		var scan_objects: Array = []
		for v in document.object_count():
			scan_objects.append({
				"odf": document.object_odf(v),
				"transform": document.object_transform(v),
			})
		task = asset_worker.load_objects.bind(game, folder, adapter, scan_objects, extra_roots, active_mod)
	else:
		tile_worker = TerrainTextures.new()
		task = tile_worker.load_native.bind(game, folder, adapter, document.package.terrain, document.package.metadata["trn"].get("texture", {}), extra_roots, active_mod)
	if object_thread.start(task) == OK:
		report("Loading native meshes and materials…" if kind == "objects" else "Loading native terrain textures…")
	else:
		report("Unable to start native asset preview.")
		button.set_pressed_no_signal(false)
	sync_actions()


func poll_objects() -> void:
	if object_thread == null or not object_thread.is_started() or object_thread.is_alive():
		return
	var result: Variant = object_thread.wait_to_finish()
	asset_worker = null
	if document == active_object_scan and result is Dictionary and asset_kind == "objects":
		var count := scene_view.object_models.display(result)
		for index in document.object_count():
			scene_view.object_models.set_instance_transform(index, document.object_transform(index))
		loaded_objects = document
		scene_view.object_models.show()
		top.object_marks = result["instances"]
		top.objects_visible = true
		object_tool.update_anchors()
		top.queue_redraw()
		report("Native models %d / %d · %d verified pool definitions · %d unresolved ODFs" % [
			count, document.object_count(), result["pools"], result["missing"].size()])
	elif document == active_object_scan and result is Dictionary and asset_kind == "textures":
		if not result.is_empty():
			scene_view.tile_material = tile_worker.material(result, document.package.terrain)
		if scene_view.tile_material:
			scene_view.tile_maps = {"slots": result["slots"], "colors": result["colors"]}
			scene_view.show_textures(true)
			report("Loaded %d native texture slots. Terrain repeat is approximate." % result["loaded"])
		else:
			texture_button.set_pressed_no_signal(false)
			report("No supported native terrain textures were found.")
	tile_worker = null
	active_object_scan = null
	sync_actions()


func valid_game(folder: String) -> bool:
	return folder.is_absolute_path() and FileAccess.file_exists(folder.path_join("battlezone2.exe")) and DirAccess.dir_exists_absolute(folder.path_join("bz2r_res"))


func valid_vrv(folder: String) -> bool:
	return folder.is_absolute_path() and FileAccess.file_exists(folder.path_join("tools/bzn_compat.py"))


func find_steam_game(force := false) -> bool:
	if not force and valid_game(game_path.text.strip_edges()):
		return true
	var script := tool_root().path_join("tools/Find-Bzcc.ps1")
	if OS.get_name() != "Windows" or not FileAccess.file_exists(script):
		return false
	var answer := ProjectSettings.globalize_path("user://").path_join("steam-" + Snapshots.new().nonce() + ".txt")
	var arguments := PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-ResultFile", answer])
	OS.execute("powershell.exe", arguments)
	var folder := FileAccess.get_file_as_string(answer).trim_prefix("\uFEFF").strip_edges() if FileAccess.file_exists(answer) else ""
	DirAccess.remove_absolute(answer)
	if valid_game(folder):
		game_path.text = folder
		setup_status.text = "Found Battlezone in Steam."
		return true
	setup_status.text = "Steam did not report a Battlezone install. Use Browse to select one."
	return false


func suggest_vrv() -> void:
	if vrv_configured or vrv_path.text.strip_edges() != "":
		return
	var configured := OS.get_environment("BZMAG_VRV_SOURCE")
	if valid_vrv(configured):
		vrv_path.text = configured
		return
	var ancestor := tool_root()
	for depth in 5:
		for relative in ["_BZDECOMP/vrv", "vrv"]:
			var candidate := ancestor.path_join(relative)
			if valid_vrv(candidate):
				vrv_path.text = candidate
				return
		var parent := ancestor.get_base_dir()
		if parent == ancestor or parent.is_empty():
			break
		ancestor = parent


func show_playtest_setup() -> void:
	find_steam_game()
	suggest_vrv()
	Wintage.popup_fit(playtest_dialog, 560)


func save_playtest_setup() -> void:
	if not valid_game(game_path.text.strip_edges()):
		setup_status.text = "Choose the folder containing battlezone2.exe."
		return
	if vrv_path.text.strip_edges() != "" and not valid_vrv(vrv_path.text.strip_edges()):
		setup_status.text = "The VRV folder must contain tools/bzn_compat.py."
		return
	if document != null:
		var profile := asset_profile_path.text.strip_edges()
		if not Document.valid_asset_profile(profile) or (not profile.is_empty() and not FileAccess.file_exists(profile)):
			setup_status.text = "Choose an existing JSON asset profile or clear the field."
			return
		document.asset_profile = profile
		sync_actions()
	store_playtest_settings()
	playtest_dialog.hide()


func store_playtest_settings() -> void:
	var settings := ConfigFile.new()
	settings.load(settings_path)
	settings.set_value("playtest", "game", game_path.text.strip_edges())
	settings.set_value("playtest", "vrv", vrv_path.text.strip_edges())
	settings.set_value("playtest", "engine_editor", engine_editor_mode.button_pressed)
	var root := autosave_root_field.text.strip_edges()
	settings.set_value("autosave", "root", root)
	autosave_custom_root = root
	settings.set_value("ui", "theme", theme_slug)
	settings.set_value("ui", "compact", ui_compact)
	settings.set_value("ui", "font_size", ui_font_size)
	settings.set_value("new_map", "default_mod", default_new_mod_profile)
	settings.save(settings_path)
	mod_registry.discover_installed(game_path.text.strip_edges(), vrv_path.text.strip_edges())
	vrv_configured = true


func all_dialogs() -> Array[Window]:
	return [
		open_dialog, blank_dialog, flat_template_dialog, flat_output_dialog, save_dialog, export_dialog,
		confirmation, keys_dialog, playtest_dialog, recover_dialog, game_picker, vrv_picker, autosave_picker,
		asset_profile_picker, studio, path_inspector, mission_studio, terrain_tools, slope_studio, water_tools,
		sound_editor, object_label_dialog, new_map_wizard, target_profile_dialog, object_browser, environment_studio,
	]


func sync_theme_controls() -> void:
	var idx := Wintage.theme_slugs().find(theme_slug)
	if idx >= 0 and theme_select.item_count > idx:
		theme_select.select(idx)
	compact_check.set_pressed_no_signal(ui_compact)


func set_wintage_theme(slug: String, compact: bool, persist: bool = true) -> void:
	theme_slug = slug if slug in Wintage.theme_slugs() else Wintage.DEFAULT_THEME
	ui_compact = compact
	var colors := Wintage.palette(theme_slug)
	theme = Wintage.make(colors, ui_font_size, ui_compact)
	backdrop.color = colors["background"]
	coordinates.add_theme_color_override("font_color", colors["textSecondary"])
	top.palette = colors
	scene_view.palette = colors
	top.queue_redraw()
	for window in all_dialogs():
		window.theme = theme
	sync_theme_controls()
	if persist:
		var settings := ConfigFile.new()
		settings.load(settings_path)
		settings.set_value("ui", "theme", theme_slug)
		settings.set_value("ui", "compact", ui_compact)
		settings.set_value("ui", "font_size", ui_font_size)
		settings.save(settings_path)


func filter_toolbar(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	for button in toolbar_buttons:
		button.visible = needle.is_empty() or button.text.to_lower().contains(needle) or button.tooltip_text.to_lower().contains(needle)


func select_object_view(view: int) -> void:
	if document == null or not document.valid_view_object(view):
		return
	object_tool.selected = view
	if object_tool.active:
		object_tool.refresh_marker()
		report(object_tool.description())


func open_object_label_editor() -> void:
	if document == null or document.object_count() == 0:
		return
	object_label_view = object_tool.selected
	if not document.valid_view_object(object_label_view):
		object_label_target.text = "Select an object in Move Object mode first."
		object_label_field.text = ""
		object_label_field.editable = false
		object_label_dialog.get_ok_button().disabled = true
		object_label_status.text = ""
		Wintage.popup_fit(object_label_dialog, 420)
		return
	object_label_target.text = "Object #%d (%s)" % [object_label_view, document.object_odf(object_label_view)]
	object_label_field.text = document.object_label(object_label_view)
	object_label_field.editable = true
	object_label_dialog.get_ok_button().disabled = false
	object_label_status.text = ""
	Wintage.popup_fit(object_label_dialog, 420)


func apply_object_label_dialog() -> void:
	if document == null or not document.valid_view_object(object_label_view):
		object_label_status.text = "[ERR] Select an object first."
		return
	var next_label := object_label_field.text.strip_edges()
	if not document.set_object_label(object_label_view, next_label):
		object_label_status.text = "[ERR] " + document.error
		return
	sync_actions()
	report("Updated object #%d label: %s" % [object_label_view, next_label if not next_label.is_empty() else "(cleared)"])
	object_label_dialog.hide()


func open_sound_editor() -> void:
	if document == null or document.object_count() == 0:
		return
	var env := mod_registry.resolve_content_environment(document, game_path.text.strip_edges(), vrv_path.text.strip_edges())
	sound_editor.begin(document, object_tool.selected, game_path.text.strip_edges(), vrv_path.text.strip_edges(), env["linkedFolders"] + env["modAssetRoots"])


func open_object_browser() -> void:
	if document == null:
		return
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != game:
		mod_registry.discover_installed(game, vrv)
	object_browser.begin(document, mod_registry, game, vrv)


func start_place_object(odf: String, team: int, template_view: int, is_native_new: bool) -> void:
	if document == null:
		return
	leave_object_tool()
	if path_drag_view != null:
		finish_point_drag(false)
	move_path_button.set_pressed_no_signal(false)
	pending_place_spec = {
		"odf": odf,
		"team": team,
		"template_view": template_view,
		"is_native_new": is_native_new,
	}
	report("Place %s (Team %d): click in 2D or 3D view. Shift+click keeps placing. Esc cancels." % [odf, team])
	sync_actions()


func cancel_place_object(announce: bool = false) -> void:
	if pending_place_spec.is_empty():
		return
	pending_place_spec.clear()
	if announce:
		report("Object placement cancelled.")
	sync_actions()


func place_object_at_cursor(odf: String, team: int, template_view: int, is_native_new: bool) -> void:
	if document == null:
		return
	var terrain := document.package.terrain
	var sample := last_cursor if last_cursor.x >= 0.0 else Vector2(terrain.dimensions) * 0.5
	pending_place_spec = {
		"odf": odf,
		"team": team,
		"template_view": template_view,
		"is_native_new": is_native_new,
	}
	var placed := place_object_at_sample(sample)
	pending_place_spec.clear()
	if placed >= 0:
		object_browser.refresh_catalog()


func place_object_at_sample(sample: Vector2) -> int:
	if document == null or pending_place_spec.is_empty() or sample.x < 0.0:
		return -1
	var world := scene_view.point_world(sample)
	var odf := String(pending_place_spec["odf"])
	var team := int(pending_place_spec["team"])
	var is_new := bool(pending_place_spec["is_native_new"])
	var view := -1
	if is_new:
		view = document.place_native_object(odf, world, team)
	else:
		view = document.duplicate_object(int(pending_place_spec["template_view"]), world)
	if view < 0:
		report(document.error)
		return -1
	top.objects_visible = true
	top.queue_redraw()
	object_tool.selected = view
	object_tool.refresh_marker()
	object_tool.update_anchors()
	if objects_button.button_pressed and not (object_thread != null and object_thread.is_started()):
		loaded_objects = null
		start_asset_scan("objects", objects_button)
	report("Placed %s (#%d, Team %d) at X %.1f, Y %.1f, Z %.1f%s" % [
		odf, view, document.object_team(view), world.x, world.y, world.z, object_count_notice("Placed")])
	sync_actions()
	return view


func validate_playtest_profile() -> Dictionary:
	if document == null:
		return {
			"schema": CompatibilityEngine.SCHEMA,
			"ok": false,
			"profileCompatible": true,
			"validationStatus": CompatibilityEngine.PLAYTEST_UNKNOWN,
			"playtestStatus": CompatibilityEngine.PLAYTEST_UNKNOWN,
			"selectedMod": "stock",
			"detectedMod": "stock",
			"suggestedMod": "stock",
			"verifiedPlaytestMod": "",
			"incompatibleOdfs": [],
			"refusalReasons": ["No map loaded."],
			"error": "No map loaded.",
		}
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != game:
		mod_registry.discover_installed(game, vrv)
	return CompatibilityEngine.evaluate(
		document, mod_registry,
		document.mod_profile, document.mission_profile, document.engine_profile,
		game, vrv, {}, engine_editor_mode.button_pressed)


func _effective_playtest_mod() -> String:
	return document.mod_profile if document != null else "stock"


func playtest_route_plan() -> Dictionary:
	if document == null:
		return {"ok": false, "route": "refuse", "error": "No map loaded."}
	var effective_mod := _effective_playtest_mod()
	var route := Layouts.playtest_route(document.package.bzn_version, "binary")
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	var needs_converter := (route == "convert")
	if needs_converter and vrv.is_empty():
		suggest_vrv()
		vrv = vrv_path.text.strip_edges()
	var unused_vrv_warning := ""
	if not needs_converter and not vrv.is_empty() and not valid_vrv(vrv):
		unused_vrv_warning = "Ignoring stale VRV converter path '%s' (not needed for %s native %d route)." % [vrv, effective_mod, document.package.bzn_version]
	var compat := validate_playtest_profile()
	var pass_converter := needs_converter and valid_vrv(vrv)
	var pass_vrv_source := (effective_mod == "vrv" or (effective_mod == "vsr" and bool(compat.get("modProfile", {}).get("localFallbackUsed", false)))) and valid_vrv(vrv)
	return {
		"ok": bool(compat["ok"]),
		"route": route,
		"effectiveMod": effective_mod,
		"needsConverter": needs_converter,
		"converterArg": vrv if pass_converter else "",
		"vrvSourceArg": vrv if pass_vrv_source else "",
		"unusedVrvWarning": unused_vrv_warning,
		"compatibility": compat,
		"error": String(compat.get("error", "")),
	}


func playtest() -> void:
	if launcher_pid > 0 or game_pid > 0 or document == null:
		return
	if not find_steam_game():
		Wintage.popup_fit(playtest_dialog, 560)
		return
	var plan := playtest_route_plan()
	var compat: Dictionary = plan["compatibility"]
	if not bool(plan["ok"]):
		var status_code := String(compat.get("validationStatus", "UNKNOWN"))
		report("[ERR] [%s] %s" % [status_code, String(plan["error"])])
		if bool(plan["needsConverter"]) and not valid_vrv(vrv_path.text.strip_edges()):
			setup_status.text = "BZN %d requires a valid conversion adapter folder containing tools/bzn_compat.py." % document.package.bzn_version
			Wintage.popup_fit(playtest_dialog, 560)
		elif not bool(compat.get("profileCompatible", true)) or status_code in [CompatibilityEngine.PLAYTEST_MISSING_ASSETS, CompatibilityEngine.PLAYTEST_UNKNOWN]:
			open_target_profile(0)
		return
	var game := game_path.text.strip_edges()
	var effective_mod := String(plan["effectiveMod"])
	var script := tool_root().path_join("tools/Start-Playtest.ps1")
	if not FileAccess.file_exists(script):
		report("Playtest helper missing at " + script)
		return
	var writer := Snapshots.new()
	var scratch := playtest_root if playtest_root != "" else OS.get_environment("TEMP").path_join("bzm")
	var run := scratch.path_join("BZMAG-" + writer.nonce())
	var game_folder := run.path_join("game")
	if DirAccess.make_dir_recursive_absolute(game_folder) != OK:
		report("Could not reserve a temporary Playtest session.")
		return
	var target := game_folder.path_join("snapshot")
	if not writer.export_native(document, target):
		DirAccess.remove_absolute(game_folder)
		DirAccess.remove_absolute(run)
		report(writer.error)
		return
	var mission := target.path_join(document.package.source_path.get_file())
	playtest_result = run.path_join("playtest.json")
	var args := PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Game", game, "-Mission", mission, "-ResultFile", playtest_result, "-PreparedRun", run, "-WaitForGame", "-ModProfile", effective_mod, "-MissionProfile", document.mission_profile])
	if OS.has_feature("editor"):
		args.append_array(PackedStringArray(["-Godot", OS.get_executable_path()]))
	var conv_arg := String(plan["converterArg"])
	if not conv_arg.is_empty():
		args.append_array(PackedStringArray(["-Converter", conv_arg]))
	var vrv_src_arg := String(plan["vrvSourceArg"])
	if not vrv_src_arg.is_empty():
		args.append_array(PackedStringArray(["-VrvSource", vrv_src_arg]))
	if engine_editor_mode.button_pressed:
		args.append_array(PackedStringArray(["-StartInEditor", "-WithoutMissionScript"]))
	if not document.asset_profile.is_empty():
		args.append_array(PackedStringArray(["-AssetProfile", document.asset_profile]))
	var env := mod_registry.resolve_content_environment(document, game, conv_arg)
	var mod_roots: Array = env.get("modAssetRoots", [])
	if effective_mod != "stock" and not mod_roots.is_empty():
		var joined := PackedStringArray()
		for r_v in mod_roots:
			if DirAccess.dir_exists_absolute(String(r_v)):
				joined.append(String(r_v))
		if not joined.is_empty():
			args.append("-AssetRoots")
			args.append(";".join(joined))
	launcher_pid = OS.create_process("powershell.exe", args, false)
	if launcher_pid <= 0:
		report("Could not start the Playtest helper. Export retained at " + target)
		return
	store_playtest_settings()
	sync_actions()
	var warn_note := (" [" + String(plan["unusedVrvWarning"]) + "]") if not String(plan["unusedVrvWarning"]).is_empty() else ""
	report("Starting Battlezone with the current edits…" + warn_note)


func poll_playtest() -> void:
	if launcher_pid <= 0:
		return
	var active := OS.is_process_running(launcher_pid)
	if game_pid <= 0 and playtest_result != "" and FileAccess.file_exists(playtest_result):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(playtest_result).trim_prefix("\uFEFF"))
		if data is Dictionary and data.has("ProcessId"):
			game_pid = int(data["ProcessId"])
			report("Battlezone launched. Session files in " + str(data["Run"]))
		elif data is Dictionary and data.has("error"):
			report("Playtest: " + str(data["error"]))
			playtest_result = ""
	if not active:
		launcher_pid = -1
		if game_pid > 0:
			var outcome: Variant = JSON.parse_string(FileAccess.get_file_as_string(playtest_result).trim_prefix("\uFEFF"))
			if outcome is Dictionary and outcome.has("ExitCode") and int(outcome["ExitCode"]) != 0:
				report("Battlezone stopped with exit code %s. See the game log." % outcome["ExitCode"])
			else:
				report("Battlezone closed. Terrain editing is ready.")
		elif playtest_result != "":
			report("Playtest helper returned without a launch result.")
		game_pid = -1
		playtest_result = ""
		sync_actions()


func mark_refresh(region: Rect2i) -> void:
	pending_refresh = pending_refresh.merge(region) if pending_refresh.has_area() else region


func mark_material_refresh(region: Rect2i, layer: int) -> void:
	var prior: Rect2i = pending_materials.get(layer, Rect2i())
	pending_materials[layer] = prior.merge(region) if prior.has_area() else region


func _process(time: float) -> void:
	poll_playtest()
	poll_objects()
	var fly_moved := false
	if fly_button != null and fly_button.button_pressed and document != null:
		var forward: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
		var side: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
		var rise: float = (1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
		if forward != 0.0 or side != 0.0 or rise != 0.0:
			scene_view.fly_step(forward, side, rise, time)
			fly_moved = true
	if paint_view != null:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if document.water_stroke_active:
				finish_water_stroke()
			else:
				finish_stroke()
		else:
			step_hold_paint(time, fly_moved)
	if document != null:
		autosave_seconds += time
		if autosave_seconds >= AUTOSAVE_INTERVAL and has_unsaved_changes() and not document.stroke_active and not document.water_stroke_active and path_drag_view == null and object_tool.drag_view == null and paint_view == null:
			autosave_now()
	if pending_refresh.has_area():
		top.refresh(pending_refresh)
		scene_view.refresh(pending_refresh)
		pending_refresh = Rect2i()
	if scene_view.lod_pending_count > 0:
		scene_view.step_lod_queue()
	for layer: int in pending_materials:
		var region: Rect2i = pending_materials[layer]
		if top.preview_layer == layer:
			top.refresh(region)
		scene_view.refresh_material(region, layer)
	pending_materials.clear()
	if path_drag_view != null and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		finish_point_drag(true)


func step_hold_paint(delta: float, fly_moved: bool = false) -> bool:
	if document == null or paint_view == null or delta <= 0.0:
		return false
	if fly_moved and paint_view == scene_view:
		var moved_point: Vector2 = scene_view.sample_at(scene_view.get_local_mouse_position())
		if moved_point.x >= 0.0:
			anchor = moved_point
	if document.water_stroke_active:
		if anchor.x >= 0.0:
			water_paint(anchor)
			return true
		return false
	if not document.stroke_active or anchor.x < 0.0:
		return false
	paint_hold_elapsed += minf(delta, 0.25)
	var ticks := 0
	while paint_hold_elapsed >= HOLD_STEP_SECONDS and ticks < 5:
		paint_hold_elapsed -= HOLD_STEP_SECONDS
		brush_panel.apply_dab(document, anchor, HOLD_DAB_SCALE, true)
		ticks += 1
	if ticks > 0:
		set_cursor(anchor)
		return true
	return false


func focus_terrain() -> void:
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	scene_view.center = scene_view.point_world(target)
	scene_view.update_camera()


func toggle_fly() -> void:
	scene_view.set_fly(fly_button.button_pressed)
	report("Fly camera on. W/S forward and back, A/D strafe, Q/E down and up, right drag to look." if fly_button.button_pressed else "Fly camera off.")
	sync_actions()


func autosave_root(custom := "") -> String:
	var root := custom if custom != "" else autosave_custom_root
	return root if root != "" else AutoSaveStore.DEFAULT_ROOT


## publishes the current document through the transactional autosave store.
## The autosave never writes into the map's own folder; every slot is fully
## written, verified by re-opening and only then do old slots get pruned.
func autosave_now(custom_root := "") -> bool:
	if document == null:
		return false
	autosave_seconds = 0.0
	if not has_unsaved_changes():
		return false
	var store := AutoSaveStore.new()
	var published: String = store.publish(document, autosave_root(custom_root), AUTOSAVE_KEEP)
	if published.is_empty():
		report("Autosave failed. " + store.error)
		return false
	last_autosave = published
	report("Autosaved " + published + " | The source map folder is never touched.")
	return true


func recover_autosaves() -> void:
	recover_list.clear()
	var root := autosave_root()
	var projects: PackedStringArray = []
	if document != null:
		projects.push_back(AutoSaveStore.project_dir(root, document.package.source_path))
	else:
		var handle := DirAccess.open(root)
		if handle != null:
			for name in handle.get_directories():
				projects.push_back(root.path_join(name))
	var found := 0
	for project in projects:
		for slot in AutoSaveStore.slots(project):
			var item := recover_list.add_item("%s · %s" % [project.get_file(), slot.get_file()])
			recover_list.set_item_metadata(item, slot)
			found += 1
	if found == 0:
		report("No autosaves found under " + root + ".")
		return
	recover_dialog.dialog_text = "Open an autosave project file. Unsaved changes are always confirmed first."
	recover_list.select(found - 1)
	Wintage.popup_fit(recover_dialog, 520, 260)


func open_recovered_autosave() -> void:
	var selected := recover_list.get_selected_items()
	if selected.is_empty():
		return
	var slot: String = recover_list.get_item_metadata(selected[0])
	request_open(slot)


func open_autosave_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(autosave_root()))


func open_studio() -> void:
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	studio.begin(document, Vector2i(target.round()))


func open_terrain_tools() -> void:
	var terrain := document.package.terrain
	var sample := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	var anchor_point := Vector2i(sample.round()).clamp(Vector2i.ZERO, terrain.dimensions - Vector2i.ONE)
	terrain_tools.begin(document, anchor_point, brush_panel.radius_m)


func open_slope_studio() -> void:
	if document == null:
		return
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	var world := scene_view.point_world(Vector2(target.x, target.y))
	slope_studio.begin(document, Vector2(world.x, world.z))


func set_cursor(point: Vector2) -> void:
	if document == null:
		return
	cursor = point
	var brush_point := Vector2(-1, -1) if move_path_button.button_pressed or object_tool.active or painting_water_active() else point
	top.cursor = brush_point
	top.queue_redraw()
	scene_view.show_cursor(brush_point)
	if point.x >= 0:
		last_cursor = point
		var world := scene_view.point_world(point)
		var info: Dictionary = scene_view.exact_sample_info(point)
		if not info.is_empty():
			var samp: Vector2i = info["sample"]
			coordinates.text = "X %.1f m   Z %.1f m   Elevation %.2f m   Sample (%d, %d) %.2f m   LOD %d m" % [
				world.x, world.z, world.y, samp.x, samp.y, float(info["height"]), int(info["resolution_m"])]
		else:
			coordinates.text = "X %.1f m   Z %.1f m   Elevation %.2f m" % [world.x, world.z, world.y]
	else:
		coordinates.text = "Hold or drag left to paint. Orbit with right drag. Pan with middle drag. Zoom with wheel."


func view_input(event: InputEvent, panel: Control) -> void:
	if document == null:
		return
	if event is InputEventMouseMotion:
		if panel == scene_view and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			scene_view.orbit(event.relative)
		elif panel == scene_view and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			scene_view.pan(event.relative)
		var point: Vector2 = panel.sample_at(event.position)
		set_cursor(point)
		if object_tool.drag_view == panel:
			object_tool.preview(event.position, point, event.shift_pressed)
			report(object_tool.description())
		elif path_drag_view == panel:
			preview_path_point(point)
		if paint_view == panel:
			if document.water_stroke_active:
				water_paint(point)
			else:
				paint(point)
	elif event is InputEventMouseButton:
		if panel == scene_view and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			scene_view.zoom(0.87 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15)
			set_cursor(scene_view.sample_at(event.position))
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed and paint_view != null and document.water_stroke_active:
				finish_water_stroke()
				return
			if painting_water_active():
				if event.pressed and paint_view == null:
					var water_point: Vector2 = panel.sample_at(event.position)
					if water_point.x >= 0:
						water_add = not event.shift_pressed
						document.begin_water_stroke()
						if document.water_stroke_active:
							paint_view = panel
							anchor = Vector2(-1, -1)
							water_paint(water_point)
							set_cursor(water_point)
							sync_actions()
						else:
							report(document.error)
				elif not event.pressed and paint_view != null:
					finish_water_stroke()
				return
			if not pending_place_spec.is_empty():
				if event.pressed:
					var place_pt: Vector2 = panel.sample_at(event.position)
					if place_pt.x >= 0.0:
						place_object_at_sample(place_pt)
						if not event.shift_pressed:
							pending_place_spec.clear()
							sync_actions()
				return
			if object_tool.active:
				if event.pressed and object_tool.drag_view == null:
					object_tool.start(panel, event.position)
					report(object_tool.description() if object_tool.selected >= 0 else "Select an object in either view.")
					sync_actions()
				elif not event.pressed and object_tool.drag_view != null:
					finish_object_drag(true)
				return
			if move_path_button.button_pressed and path_list.selected > 0:
				if event.pressed and path_drag_view == null:
					start_point_drag(panel, event.position, event.shift_pressed)
				elif not event.pressed and path_drag_view != null:
					finish_point_drag(true)
				return
			if event.pressed and paint_view == null:
				var point: Vector2 = panel.sample_at(event.position)
				if point.x >= 0:
					var layer := brush_panel.paint_layer()
					if layer == Terrain.Layer.COLOR and not brush_panel.valid_rgb():
						report("Enter a native RGB color as #RRGGBB.")
						return
					if layer == Terrain.Layer.HEIGHT and brush_panel.mode == BrushPanel.Mode.PICK:
						var height := scene_view.point_world(point).y
						brush_panel.use_picked_height(height)
						report("Picked paint height %.2f m" % height)
						return
					paint_view = panel
					anchor = Vector2(-1, -1)
					paint_hold_elapsed = 0.0
					document.begin_stroke(layer)
					paint(point)
					set_cursor(point)
					sync_actions()
			elif not event.pressed:
				finish_stroke()


func paint(point: Vector2) -> void:
	if point.x < 0:
		anchor = point
		return
	var spacing := document.package.terrain.SPACING
	if anchor.x < 0:
		brush_panel.apply_dab(document, point)
	else:
		var segments := maxi(1, ceili(anchor.distance_to(point) / maxf(1, brush_panel.radius_m / spacing * 0.3)))
		for i in range(1, segments + 1):
			brush_panel.apply_dab(document, anchor.lerp(point, float(i) / segments))
	anchor = point


func object_tool_changed() -> void:
	if move_objects_button.button_pressed:
		if path_drag_view != null:
			finish_point_drag(false)
		move_path_button.set_pressed_no_signal(false)
		object_tool.set_active(true)
		report("Drag an object in either view. Shift snaps to the terrain grid. Esc cancels.")
	else:
		leave_object_tool()
		report("Terrain brush ready.")
	set_cursor(cursor)
	sync_actions()


func leave_object_tool() -> void:
	if object_tool.drag_view != null:
		finish_object_drag(false)
	move_objects_button.set_pressed_no_signal(false)
	if object_tool.active:
		object_tool.set_active(false)


func finish_object_drag(commit: bool) -> void:
	var applied := object_tool.finish(commit)
	report(object_tool.description() if applied else document.error)
	sync_actions()


func object_position_changed(index: int) -> void:
	object_tool.position_changed(index)
	if object_tool.active and object_tool.selected == index:
		report(object_tool.description())
	sync_actions()


func objects_topology_changed() -> void:
	if loaded_objects == document:
		scene_view.object_models.rebuild(document)
		top.queue_redraw()
	if object_tool.active and object_tool.selected >= document.object_count():
		object_tool.selected = -1
		object_tool.set_active(true)
	sync_actions()


func finish_stroke() -> void:
	if paint_view == null:
		return
	paint_view = null
	paint_hold_elapsed = 0.0
	document.end_stroke()
	sync_actions()
	match document.stroke_layer:
		Terrain.Layer.COLOR:
			report("%d native color samples changed" % document.package.terrain.color_edits.size())
		Terrain.Layer.TILES:
			report("%d native texture blocks changed" % document.package.terrain.tile_edits.size())
		_:
			report("%d terrain samples changed" % document.edits.size())


func water_paint(point: Vector2) -> void:
	if point.x < 0:
		anchor = point
		return
	var spacing := document.package.terrain.SPACING
	var radius_m := water_tools.radius_m()
	var layer := water_tools.current_layer()
	if anchor.x < 0:
		document.water_dab(point, radius_m, layer, water_add)
	else:
		var segments := maxi(1, ceili(anchor.distance_to(point) / maxf(1, radius_m / spacing * 0.25)))
		for i in range(1, segments + 1):
			document.water_dab(anchor.lerp(point, float(i) / segments), radius_m, layer, water_add)
	anchor = point


func finish_water_stroke() -> void:
	if paint_view == null or not document.water_stroke_active:
		return
	var layer := water_tools.current_layer()
	paint_view = null
	document.end_water_stroke(layer)
	report("Water stroke done. Layer %d has %d block edits." % [layer + 1, document.water_edits.get(layer, {}).size()])
	sync_actions()


func painting_water_active() -> bool:
	return painting_water and document != null and water_tools.document == document


func toggle_water_edit() -> void:
	if document == null or document.package.water == null:
		return
	water_tools.begin(document)


func update_water_painting() -> void:
	var paint := water_tools.painting() and document != null and water_tools.document == document
	if paint and not painting_water:
		if path_drag_view != null:
			finish_point_drag(false)
		move_path_button.set_pressed_no_signal(false)
		leave_object_tool()
		if paint_view != null:
			finish_stroke()
	painting_water = paint
	set_cursor(cursor)
	sync_actions()


func refresh_water() -> void:
	top.queue_redraw()
	scene_view.rebuild_water()
	sync_actions()


func _exit_tree() -> void:
	if object_thread != null and object_thread.is_started():
		object_thread.wait_to_finish()
