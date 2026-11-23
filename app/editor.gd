extends Control

const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const Wintage := preload("res://themes/wintage.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")
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
const WorkspaceState := preload("res://ui/workspace_state.gd")
const AttributesInspector := preload("res://ui/attributes_inspector.gd")
const SceneTreePanel := preload("res://ui/scene_tree.gd")
const LayersPanel := preload("res://ui/layers_panel.gd")
const ToolsPanel := preload("res://ui/tools_panel.gd")
const ObjectAttributesPanel := preload("res://ui/object_attributes_panel.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

const SETTINGS := "user://editor.cfg"

var document: Document
var workspace_state := WorkspaceState.new()
var top := TopView.new()
var scene_view := TerrainView.new()

# Unified DCC workspace containers
var left_split := HSplitContainer.new()
var right_split := HSplitContainer.new()
var views := SplitContainer.new()
var scene_dock_box := VBoxContainer.new()
var top_dock_box := VBoxContainer.new()
var left_dock := PanelContainer.new()
var left_tabs := TabContainer.new()
var attributes_inspector := AttributesInspector.new()
var scene_tree := SceneTreePanel.new()
var layers_panel := LayersPanel.new()
var tools_panel := ToolsPanel.new()
var object_attributes := ObjectAttributesPanel.new()
var center_mode_buttons: Dictionary = {} # int(CenterMode) -> Button
var viewport_bar := HFlowContainer.new()
var preset_select := OptionButton.new()
var diagnostics_button := Button.new()
var diagnostics_drawer := RichTextLabel.new()
var diagnostics_lines: Array[String] = []
var tool_badge := Label.new()
var status := Label.new()
var coordinates := Label.new()
var title := Label.new()
var _applying_layout := false

# Docked tools (zero modal editing Windows)
var brush_panel := BrushPanel.new()
var slope_studio := SlopeStudio.new()
var terrain_tools := TerrainCommands.new()
var water_tools := WaterCommands.new()
var environment_studio := EnvironmentStudio.new()
var sound_editor := SoundEditor.new()
var path_inspector := PathInspector.new()
var mission_studio := MissionStudio.new()
var object_browser := ObjectBrowser.new()
var studio := NodeStudio.new()
var new_map_wizard := NewMapWizard.new()
var target_profile_dialog := TargetProfileDialog.new()
var playtest_dialog := ScrollContainer.new() # Embedded Settings workspace page (no popup Window)

# Path / object / water state
var path_list := OptionButton.new()
var new_path_button: Button
var edit_path_button: Button
var move_path_button: Button
var mission_studio_button: Button
var mod_registry := ModRegistry.new()
var target_profile_button: Button
var default_new_mod_profile := "stock"
var snap_path_drag := false
var selected_extra_paths: Array[int] = []
var path_drag_view: Control
var path_draft := {}
var selected_path_point := -1
var camera_buttons: Array[Button] = []
var objects_button: Button
var object_browser_button: Button
var pending_place_spec: Dictionary = {}
var move_objects_button: Button
var object_tool := MoveObject.new()
var water_button: Button
var water_edit_button: Button
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

# Autosave & allowed OS/transient dialogs
const AUTOSAVE_INTERVAL := 180.0
const AUTOSAVE_KEEP := 3
var autosave_seconds := 0.0
var autosave_custom_root := ""
var last_autosave := ""
var recovered_draft: Dictionary = {}
var recovered_draft_slot := ""
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
var terrain_tools_button: Button
var environment_button: Button
var sound_button: Button
var object_label_button: Button
var theme_slug := Wintage.DEFAULT_THEME
var ui_font_size := 12
var ui_compact := false
var backdrop := ColorRect.new()
var theme_select := ChoiceGroup.new(0)
var font_size_field := SliderField.new()
var compact_check := CheckBox.new()
var tool_search := LineEdit.new()
var empty_state_hint := Label.new()
var toolbar_buttons: Array[Button] = []
var confirmation := ConfirmationDialog.new()
var draft_save_dialog := ConfirmationDialog.new()
var keys_dialog := AcceptDialog.new()
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

# Unsaved-change tracking
var saved_edits := {}
var saved_layers: Array = []
var saved_sculpt_layers: Array = []
var saved_color_layers: Array = []
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

# Continuous paint state
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
	backdrop.color = colors["background"]
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	add_child(margin)

	var root_col := VBoxContainer.new()
	root_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_col.add_theme_constant_override("separation", 4)
	margin.add_child(root_col)

	# 1. TOP BAR: Menu strip + compact frequent actions + workspace preset + command filter
	_build_top_bar(root_col)

	# 2. MAIN 3-COLUMN DOCKED WORKSPACE (Left Dock | Center Workspace | Right Attributes)
	left_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_split.dragged.connect(_on_left_split_dragged)
	root_col.add_child(left_split)

	left_split.add_child(left_dock)
	_build_left_dock()

	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_split.dragged.connect(_on_right_split_dragged)
	left_split.add_child(right_split)

	var center_col := VBoxContainer.new()
	right_split.add_child(center_col)
	_build_center_workspace(center_col, colors)

	right_split.add_child(attributes_inspector)
	_build_right_inspector()

	# 3. BOTTOM STATUS BAR + COLLAPSIBLE DIAGNOSTICS DRAWER
	_build_bottom_bar(root_col, colors)

	# 4. ALLOWED OS / TRANSIENT DIALOGS (FileDialogs, destructive confirm, autosave recover, hotkeys)
	_build_allowed_dialogs()

	# 5. WIRE ALL TOOL SIGNALS & WORKSPACE STATE
	_wire_workspace_signals()

	# 6. LOAD SETTINGS & WORKSPACE LAYOUT
	game_path.text = String(settings.get_value("playtest", "game", ""))
	vrv_path.text = String(settings.get_value("playtest", "vrv", ""))
	autosave_root_field.text = String(settings.get_value("autosave", "root", ""))
	autosave_custom_root = autosave_root_field.text.strip_edges()
	engine_editor_mode.button_pressed = bool(settings.get_value("playtest", "engine_editor", false))
	vrv_configured = settings.has_section_key("playtest", "vrv")
	default_new_mod_profile = String(settings.get_value("new_map", "default_mod", "stock"))
	if default_new_mod_profile.is_empty():
		default_new_mod_profile = "stock"
	mod_registry.discover_installed(game_path.text.strip_edges(), vrv_path.text.strip_edges())
	sync_theme_controls()
	for window in all_dialogs():
		window.theme = theme

	workspace_state.load_from_config(settings, get_viewport_rect().size)
	_bind_all_collapsible_sections()
	_apply_workspace_layout()
	resized.connect(_on_editor_resized)

	sync_actions()
	var args := OS.get_cmdline_user_args()
	if args.size() == 1 and FileAccess.file_exists(args[0]):
		call_deferred("open_command_line", args[0])


func _build_top_bar(parent: Control) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 4)
	parent.add_child(bar)

	# Menus (Cinema 4D / Photoshop style compact horizontal bar)
	_add_menu(bar, "File", [
		["Open Map / Project… (Ctrl+O)", func(): open_dialog.popup_centered_ratio(0.72)],
		["New Map…", open_new_map_wizard],
		["Save Project… (Ctrl+S)", request_save],
		["Recover Autosave…", recover_autosaves],
		["Export Native…", request_export],
		["---", Callable()],
		["Target Profile & Mods", func(): open_target_profile(0)],
		["Settings & Theme", show_playtest_setup],
	])
	_add_menu(bar, "Edit", [
		["Undo (Ctrl+Z)", func(): if document != null: document.undo(); sync_actions()],
		["Redo (Ctrl+Y)", func(): if document != null: document.redo(); sync_actions()],
		["Cancel Active Preview", func(): clear_active_preview("Preview cancelled.")],
	])
	_add_menu(bar, "View", [
		["Split 3D + 2D", func(): set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)],
		["Toggle 2D Stacked Below 3D", toggle_views_vertical],
		["3D Viewport Only", func(): set_center_mode(WorkspaceState.CenterMode.VIEW_3D)],
		["2D Top View Only", func(): set_center_mode(WorkspaceState.CenterMode.VIEW_2D)],
		["Node Graph Workspace", open_studio],
		["---", Callable()],
		["Toggle Left Dock (Scene/Layers)", toggle_left_dock],
		["Toggle Right Inspector (Attributes)", toggle_right_dock],
		["Toggle Diagnostics Drawer", toggle_diagnostics_drawer],
		["Fullscreen Viewport (F11)", toggle_fullscreen_viewport],
		["Reset Workspace Layout", reset_workspace_layout],
	])
	_add_menu(bar, "Terrain", [
		["Terrain Brush (Alt+H)", activate_terrain_brush],
		["Slope Studio (Docked)", open_slope_studio],
		["Shape Terrain (Docked)", open_terrain_tools],
		["Procedural Layers / Nodes", open_studio],
		["Water Editor", toggle_water_edit],
	])
	_add_menu(bar, "Objects", [
		["Object Browser (Assets Dock)", open_object_browser],
		["Move / Edit Object", func(): _toggle_move_objects(true)],
		["Object Attributes / Label", open_object_label_editor],
		["Sound Point Editor", open_sound_editor],
	])
	_add_menu(bar, "Paths", [
		["Mission Studio", open_mission_studio],
		["New AI Path", start_new_path],
		["Edit Selected Path", inspect_path],
		["Move Path Points", func(): _toggle_move_paths(true)],
	])
	_add_menu(bar, "Env", [
		["Sky, Fog & Environment", open_environment_studio],
		["Water Editor", toggle_water_edit],
	])
	_add_menu(bar, "Tools", [
		["Target Profile & Mods", func(): open_target_profile(0)],
		["Settings & Wintage Theme", show_playtest_setup],
		["Hotkeys (F1)", func(): Wintage.popup_fit(keys_dialog, 420)],
	])

	var sep1 := VSeparator.new()
	bar.add_child(sep1)

	# Frequent actions (always single row)
	toolbar_buttons.append(add_button(bar, "Open", open_dialog.popup_centered_ratio.bind(0.72), "Open a BZN map or BZMAG project", KEY_O))
	save_button = add_button(bar, "Save", request_save, "Create a .bzmag project snapshot", KEY_S)
	toolbar_buttons.append(save_button)
	undo_button = add_button(bar, "Undo", func(): document.undo(); sync_actions(), "Undo the last edit", KEY_Z)
	toolbar_buttons.append(undo_button)
	redo_button = add_button(bar, "Redo", func(): document.redo(); sync_actions(), "Redo the last edit", KEY_Y)
	toolbar_buttons.append(redo_button)
	export_button = add_button(bar, "Export", request_export, "Export and re-import a new native map folder")
	toolbar_buttons.append(export_button)
	playtest_button = add_button(bar, "Playtest", playtest, "Launch Battlezone with the current edits (F5)")
	toolbar_buttons.append(playtest_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# Workspace Layout Preset selector
	preset_select.custom_minimum_size.x = 114
	preset_select.tooltip_text = "Switch workspace layout preset"
	for pid in [
		WorkspaceState.LayoutPreset.DEFAULT,
		WorkspaceState.LayoutPreset.SCULPTING,
		WorkspaceState.LayoutPreset.MISSION,
		WorkspaceState.LayoutPreset.OBJECT_PLACEMENT,
		WorkspaceState.LayoutPreset.NODES,
		WorkspaceState.LayoutPreset.FULLSCREEN,
	]:
		preset_select.add_item(String(WorkspaceState.PRESET_NAMES[pid]))
		preset_select.set_item_metadata(preset_select.item_count - 1, pid)
	preset_select.item_selected.connect(_on_preset_dropdown_selected)
	bar.add_child(preset_select)

	tool_search.placeholder_text = "Find tool…"
	tool_search.custom_minimum_size.x = 96
	tool_search.tooltip_text = "Filter commands and tools by name or hint (Enter triggers first match)"
	tool_search.text_changed.connect(filter_toolbar)
	tool_search.text_submitted.connect(_on_tool_search_submitted)
	bar.add_child(tool_search)


func _add_menu(parent: Control, caption: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = caption
	mb.flat = false
	var pop := mb.get_popup()
	var actions: Array[Callable] = []
	for entry in items:
		var lbl: String = entry[0]
		var cb: Callable = entry[1]
		if lbl == "---":
			pop.add_separator()
		else:
			var id := actions.size()
			actions.append(cb)
			pop.add_item(lbl, id)
	pop.id_pressed.connect(func(id: int):
		if id >= 0 and id < actions.size() and actions[id].is_valid():
			actions[id].call())
	parent.add_child(mb)
	return mb


func _build_left_dock() -> void:
	left_dock.custom_minimum_size.x = 204
	left_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL

	left_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_tabs.tab_changed.connect(_on_left_tab_changed)
	left_dock.add_child(left_tabs)

	scene_tree.name = "Scene"
	left_tabs.add_child(scene_tree)
	layers_panel.name = "Layers"
	left_tabs.add_child(layers_panel)
	object_browser.name = "Assets"
	left_tabs.add_child(object_browser)
	tools_panel.name = "Tools"
	left_tabs.add_child(tools_panel)
	tools_panel.ensure_built()

	# Bind legacy button references to the docked ToolsPanel buttons so existing
	# callers & filter_toolbar() work seamlessly without modal clutter.
	slope_studio_button = tools_panel.buttons["slope_studio"]
	terrain_tools_button = tools_panel.buttons["shape_terrain"]
	nodes_button = tools_panel.buttons["nodes"]
	environment_button = tools_panel.buttons["environment"]
	object_browser_button = tools_panel.buttons["object_browser"]
	mission_studio_button = tools_panel.buttons["mission_studio"]
	sound_button = tools_panel.buttons["sound_editor"]
	water_edit_button = tools_panel.buttons["water_editor"]
	target_profile_button = tools_panel.buttons["target_profile"]
	new_path_button = tools_panel.buttons["new_path"]
	edit_path_button = tools_panel.buttons["path_inspector"]
	object_label_button = tools_panel.buttons["move_object"]
	recover_button = Button.new()
	recover_button.visible = false
	for aid: String in tools_panel.buttons:
		toolbar_buttons.append(tools_panel.buttons[aid] as Button)


func _build_center_workspace(center: VBoxContainer, colors: Dictionary) -> void:
	center.custom_minimum_size.x = 320
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)

	# Single compact contextual header bar for the central workspace (wraps cleanly on narrow widths without pushing Right Inspector off-screen)
	var hdr_row := HFlowContainer.new()
	hdr_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_row.custom_minimum_size.x = 0
	hdr_row.add_theme_constant_override("h_separation", 3)
	hdr_row.add_theme_constant_override("v_separation", 3)
	center.add_child(hdr_row)

	for spec in [
		[WorkspaceState.CenterMode.SPLIT_3D_2D, "3D+2D", "Synchronized 3D and 2D editing"],
		[WorkspaceState.CenterMode.VIEW_3D, "3D", "3D Terrain Viewport only"],
		[WorkspaceState.CenterMode.VIEW_2D, "2D", "2D Top Heightmap only"],
		[WorkspaceState.CenterMode.NODES, "Nodes", "Central Procedural Node Graph workspace"],
		[WorkspaceState.CenterMode.NEW_MAP, "New Map", "Embedded Stock/VSR/VRV New Map workspace"],
		[WorkspaceState.CenterMode.SETTINGS, "Settings", "Paths, Wintage themes and layout controls"],
	]:
		var mid: int = spec[0]
		var btn := Button.new()
		btn.text = spec[1]
		btn.tooltip_text = spec[2]
		btn.toggle_mode = true
		btn.pressed.connect(func(): _on_center_mode_button_pressed(mid))
		hdr_row.add_child(btn)
		center_mode_buttons[mid] = btn

	viewport_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_bar.custom_minimum_size.x = 0
	viewport_bar.add_theme_constant_override("h_separation", 3)
	viewport_bar.add_theme_constant_override("v_separation", 3)
	center.add_child(viewport_bar)
	add_camera_toolbar(viewport_bar)

	# Main split 3D + 2D viewports
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.dragged.connect(_on_views_split_dragged)
	center.add_child(views)

	top.palette = colors
	scene_view.palette = colors
	top.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	scene_dock_box.custom_minimum_size.x = 180
	scene_dock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_dock_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_dock_box.size_flags_stretch_ratio = 2.1
	views.add_child(scene_dock_box)
	scene_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_dock_box.add_child(scene_view)

	empty_state_hint.text = "No map loaded — click Open or switch to New Map"
	empty_state_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_state_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_state_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_state_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_state_hint.add_theme_color_override("font_color", colors["textMuted"])
	scene_view.add_child(empty_state_hint)

	top_dock_box.custom_minimum_size.x = 140
	top_dock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_dock_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_dock_box.size_flags_stretch_ratio = 1.0
	views.add_child(top_dock_box)
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_dock_box.add_child(top)

	for panel in [scene_view, top]:
		panel.mouse_exited.connect(func():
			set_cursor(Vector2(-1, -1))
			if paint_view == panel:
				anchor = Vector2(-1, -1))
		panel.gui_input.connect(view_input.bind(panel))

	# Central Node Graph Workspace (hidden unless CenterMode.NODES)
	studio.hide()
	center.add_child(studio)

	# Embedded New Map Workspace page (hidden unless CenterMode.NEW_MAP)
	new_map_wizard.hide()
	center.add_child(new_map_wizard)

	# Embedded Settings Workspace page (hidden unless CenterMode.SETTINGS)
	_build_settings_workspace_page()
	playtest_dialog.hide()
	center.add_child(playtest_dialog)


func _build_settings_workspace_page() -> void:
	playtest_dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playtest_dialog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	playtest_dialog.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["top", "bottom", "left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	playtest_dialog.add_child(pad)

	var paths := VBoxContainer.new()
	paths.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paths.add_theme_constant_override("separation", 5)
	pad.add_child(paths)

	add_label(paths, "Workspace, Paths & Playtest Settings (Docked — No Modal Popup)")
	add_label(paths, "Battlezone installation folder")
	add_folder_field(paths, game_path, game_picker, "Select the Battlezone installation folder")
	add_label(paths, "VRV source folder (optional 1196 converter and VSR assets)")
	add_folder_field(paths, vrv_path, vrv_picker, "Select the VRV source folder")
	add_label(paths, "Autosave folder (empty keeps default user folder; never the map folder)")
	add_folder_field(paths, autosave_root_field, autosave_picker, "Select the autosave store folder")
	add_label(paths, "Asset profile for this project (optional)")
	var profile_row := HBoxContainer.new()
	paths.add_child(profile_row)
	asset_profile_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_profile_path.editable = false
	profile_row.add_child(asset_profile_path)
	asset_profile_browse = add_button(profile_row, "Browse…", asset_profile_picker.popup_centered_ratio.bind(0.72), "Link a JSON asset profile to this project")
	asset_profile_browse.disabled = true

	engine_editor_mode.text = "Start Playtest in engine editor without mission scripts"
	paths.add_child(engine_editor_mode)

	var theme_lbl := Label.new()
	theme_lbl.text = "Wintage Theme (Golden Default preserved)"
	paths.add_child(theme_lbl)
	for slug in Wintage.theme_slugs():
		theme_select.add_item(Wintage.theme_label(slug))
	theme_select.item_selected.connect(func(idx: int): set_wintage_theme(Wintage.theme_slugs()[idx], compact_check.button_pressed))
	paths.add_child(theme_select)

	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 6)
	paths.add_child(font_row)
	var flbl := Label.new()
	flbl.text = "UI Font Size (px)"
	flbl.custom_minimum_size.x = 120
	font_row.add_child(flbl)
	font_size_field.min_value = 10
	font_size_field.max_value = 24
	font_size_field.step = 1
	font_size_field.value = ui_font_size
	font_size_field.set_unit_suffix("px")
	font_size_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_size_field.value_changed.connect(func(v: float):
		ui_font_size = clampi(int(round(v)), 10, 24)
		set_wintage_theme(theme_slug, ui_compact))
	font_row.add_child(font_size_field)

	compact_check.text = "Compact toolbar & control padding"
	compact_check.toggled.connect(func(on: bool): set_wintage_theme(theme_slug, on))
	paths.add_child(compact_check)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 4)
	paths.add_child(actions)
	add_button(actions, "Save Settings", save_playtest_setup, "Save game paths, theme and workspace settings")
	add_button(actions, "Find via Steam", func(): find_steam_game(true), "Find Battlezone in your Steam libraries")
	add_button(actions, "Game & Mods Manager", func(): open_target_profile(1), "Discover Stock, VSR, VRV and Workshop mods in Attributes")
	add_button(actions, "Reset Workspace Layout", reset_workspace_layout, "Reset all dock widths, tabs and split ratios to defaults")
	add_button(actions, "Back to Viewport", func(): set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D), "Return to 3D/2D map editing")
	setup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paths.add_child(setup_status)


func _build_right_inspector() -> void:
	attributes_inspector.bind_state(workspace_state)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.TERRAIN_BRUSH, brush_panel)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.SLOPE, slope_studio)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.SHAPE, terrain_tools)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.OBJECT, object_attributes)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.OBJECT_BROWSER, object_browser.detail_panel)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.PATH, path_inspector)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.MISSION, mission_studio)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.WATER, water_tools)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.ENVIRONMENT, environment_studio)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.NODE, studio.attributes_panel)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.SOUND, sound_editor)
	attributes_inspector.register_panel(WorkspaceState.InspectorContext.PROJECT, target_profile_dialog)


func _build_bottom_bar(parent: Control, colors: Dictionary) -> void:
	diagnostics_drawer.custom_minimum_size.y = 88
	diagnostics_drawer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics_drawer.hide()
	parent.add_child(diagnostics_drawer)

	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", 8)
	parent.add_child(bar)

	# Compact status bar (never forces horizontal overflow at 1120x690)
	title.text = "No map loaded"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.custom_minimum_size.x = 120
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_stretch_ratio = 0.9
	bar.add_child(title)

	tool_badge.text = "[Terrain Brush]"
	tool_badge.add_theme_color_override("font_color", colors["borderHighlight"])
	bar.add_child(tool_badge)

	coordinates.text = "LMB paint · RMB orbit · MMB pan · Wheel zoom"
	coordinates.add_theme_color_override("font_color", colors["textSecondary"])
	coordinates.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	coordinates.custom_minimum_size.x = 100
	coordinates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coordinates.size_flags_stretch_ratio = 1.1
	bar.add_child(coordinates)

	status.text = "Ready"
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.custom_minimum_size.x = 100
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_stretch_ratio = 1.2
	bar.add_child(status)

	diagnostics_button.text = "Log"
	diagnostics_button.toggle_mode = true
	diagnostics_button.tooltip_text = "Show/hide collapsible Diagnostics & Log drawer"
	diagnostics_button.toggled.connect(func(on: bool):
		workspace_state.set_dock_visibility(workspace_state.left_dock_visible, workspace_state.right_dock_visible, on)
		_save_workspace_layout())
	bar.add_child(diagnostics_button)


func _build_allowed_dialogs() -> void:
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

	setup_dialog(game_picker, FileDialog.FILE_MODE_OPEN_DIR, [])
	setup_dialog(vrv_picker, FileDialog.FILE_MODE_OPEN_DIR, [])
	setup_dialog(autosave_picker, FileDialog.FILE_MODE_OPEN_DIR, [])
	setup_dialog(asset_profile_picker, FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Asset profile"])
	asset_profile_picker.title = "Choose a linked asset profile"
	asset_profile_picker.use_native_dialog = true
	asset_profile_picker.file_selected.connect(func(path: String): asset_profile_path.text = path)
	game_picker.use_native_dialog = true
	vrv_picker.use_native_dialog = true

	confirmation.title = "Open another map"
	confirmation.dialog_text = "Open another map and discard unsaved edits?"
	add_child(confirmation)
	confirmation.confirmed.connect(func(): open_map(pending_path, recovered_draft))

	draft_save_dialog.title = "Uncommitted Node Graph Draft"
	draft_save_dialog.dialog_text = "Procedural Node Graph has uncommitted draft edits. Commit them to the layer stack before saving the .bzmag project?"
	draft_save_dialog.ok_button_text = "Commit Layers & Save"
	draft_save_dialog.add_button("Save Committed Only", false, "save_committed")
	add_child(draft_save_dialog)
	draft_save_dialog.confirmed.connect(func():
		if document != null and studio.document == document and studio.has_uncommitted_draft():
			if not studio.keep_layers():
				report("Could not commit Node Graph draft before saving.")
				return
		_open_save_dialog())
	draft_save_dialog.custom_action.connect(func(act: StringName):
		if String(act) == "save_committed":
			draft_save_dialog.hide()
			_open_save_dialog())

	keys_dialog.title = "Editor Hotkeys"
	keys_dialog.dialog_text = "F  Fly camera (3D view)\nW/S/A/D  Fly forward / back / strafe\nQ/E  Fly down / up\nF11  Fullscreen Viewport toggle\n\nShift+1–6  Brush size\nShift+Q/W/E/R  Square / Circle / Cone / Bell\nShift+Z/X/C/V  Pressure 10 / 20 / 50 / 100%\nShift+A/S/D/F/G  Paint / Spray / Raise / Blend / Pick\nAlt+H  Terrain Brush\nF5  Playtest\nCtrl+O/S/Z/Y  Open / Save Project / Undo / Redo\n\nMMB over Slider  Houdini Value Ladder\nMMB over 3D View  Camera Pan\n\nMove Points tool: Drag point · Shift+click append · Delete remove · Esc cancel\nMove Object tool: Drag object · Shift snap · [ / ] rotate · Ctrl+D duplicate · Delete remove"
	add_child(keys_dialog)

	recover_dialog.title = "Recover autosave"
	recover_dialog.min_size = Vector2i(520, 260)
	recover_dialog.ok_button_text = "Open Selected"
	recover_dialog.dialog_autowrap = true
	recover_dialog.add_child(recover_list)
	recover_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recover_list.tooltip_text = "Rolling autosave slots, oldest first."
	recover_dialog.confirmed.connect(open_recovered_autosave)
	add_child(recover_dialog)


func _wire_workspace_signals() -> void:
	workspace_state.layout_changed.connect(_apply_workspace_layout)
	workspace_state.center_mode_changed.connect(_on_center_mode_changed)
	workspace_state.left_tab_changed.connect(_on_state_left_tab_changed)
	workspace_state.preset_changed.connect(_on_state_preset_changed)
	workspace_state.tool_changed.connect(_on_state_tool_changed)
	workspace_state.inspector_context_changed.connect(_on_state_inspector_changed)
	workspace_state.section_toggled.connect(func(_sid: String, _col: bool):
		if not _applying_layout:
			_save_workspace_layout())

	attributes_inspector.close_requested.connect(func():
		workspace_state.set_dock_visibility(workspace_state.left_dock_visible, false, workspace_state.bottom_log_visible)
		_save_workspace_layout())

	tools_panel.tool_action_triggered.connect(_on_tool_panel_action)
	scene_tree.item_selected_kind.connect(_on_scene_tree_selected)
	scene_tree.item_activated_kind.connect(_on_scene_tree_activated)
	scene_tree.objects_selected.connect(func(views: Array[int]): select_object_views(views))
	scene_tree.visibility_toggled.connect(_on_scene_visibility_toggled)

	layers_panel.layer_selected.connect(_on_layers_panel_selected)
	layers_panel.edit_graph_requested.connect(_on_layers_edit_graph)
	layers_panel.preview_requested.connect(func():
		if document != null:
			_prepare_node_studio(layers_panel.selected_index)
			studio.preview())
	layers_panel.bake_requested.connect(func():
		if document != null and document.has_preview():
			studio.bake())
	layers_panel.layers_mutated.connect(func(msg: String):
		sync_actions()
		report(msg))
	layers_panel.sculpt_preview_requested.connect(func():
		if document != null and document.sculpt_preview():
			workspace_state.active_preview_owner = "sculpt"
			layers_panel.refresh()
			report("Sculpt preview composed from %d layer(s). Native TER untouched until Bake." % document.sculpt_layers.size()))
	layers_panel.color_layers_mutated.connect(func(msg: String): report(msg); sync_actions())
	layers_panel.sculpt_bake_requested.connect(func():
		if document != null and document.bake_sculpt_layers():
			workspace_state.active_preview_owner = ""
			layers_panel.refresh()
			report("Baked sculpt layers into native terrain (one undo step)."))

	brush_panel.brush_changed.connect(update_brush_cursor)
	new_map_wizard.map_created.connect(_on_wizard_map_created)
	new_map_wizard.cancel_requested.connect(func(): set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D))
	target_profile_dialog.profile_applied.connect(func(msg: String): sync_actions(); scene_tree.request_rebuild(); report(msg))
	target_profile_dialog.mods_changed.connect(_on_mods_settings_changed)
	path_inspector.path_created.connect(select_created_path)
	path_inspector.path_removed.connect(func(label_str: String): scene_tree.request_rebuild(); report("Removed path %s." % label_str))
	path_inspector.path_updated.connect(func(_idx: int): scene_tree.request_rebuild(); sync_actions())
	mission_studio.paths_selection_changed.connect(set_extra_path_selection)
	mission_studio.path_focused.connect(select_created_path)
	mission_studio.snap_toggled.connect(func(on: bool): snap_path_drag = on)
	mission_studio.status_message.connect(report)
	studio.updated.connect(func(value: String): layers_panel.refresh(studio.selected); scene_tree.request_rebuild(); sync_actions(); report(value))
	studio.preview_display.connect(show_graph_preview)
	studio.preview_state_changed.connect(func(on: bool):
		if on:
			workspace_state.set_preview_owner("node")
		elif workspace_state.active_preview_owner == "node":
			workspace_state.set_preview_owner("")
		sync_actions())
	studio.draft_state_changed.connect(func(has_draft: bool, has_conflict: bool, detail: String):
		layers_panel.set_draft_status(has_draft, has_conflict, detail)
		sync_actions())
	studio.layers_changed.connect(func(sel: int):
		layers_panel.refresh(sel)
		scene_tree.request_rebuild())
	studio.viewport_requested.connect(func(): set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D))
	terrain_tools.updated.connect(func(value: String): sync_actions(); scene_tree.request_rebuild(); report(value))
	terrain_tools.preview_state_changed.connect(func(on: bool):
		if on:
			workspace_state.set_preview_owner("shape")
		elif workspace_state.active_preview_owner == "shape":
			workspace_state.set_preview_owner("")
		sync_actions())
	slope_studio.updated.connect(func(value: String): sync_actions(); scene_tree.request_rebuild(); report(value))
	slope_studio.preview_state_changed.connect(func(on: bool):
		if on:
			workspace_state.set_preview_owner("slope")
		elif workspace_state.active_preview_owner == "slope":
			workspace_state.set_preview_owner("")
		sync_actions())
	slope_studio.canceled.connect(func():
		if workspace_state.active_preview_owner == "slope":
			workspace_state.set_preview_owner("")
		sync_actions()
		report("Slope Studio preview cancelled."))
	environment_studio.updated.connect(func(value: String): sync_actions(); scene_tree.request_rebuild(); report(value))
	environment_studio.preview_toggled.connect(func(on: bool):
		if document != null:
			scene_view.apply_environment_preview(document.effective_environment(), on))
	sound_editor.updated.connect(func(value: String): sync_actions(); scene_tree.request_rebuild(); report(value))
	sound_editor.sound_point_selected.connect(select_object_view)
	object_browser.place_requested.connect(start_place_object)
	object_browser.place_at_cursor_requested.connect(place_object_at_cursor)
	object_browser.status_message.connect(report)
	object_browser.entry_selected.connect(func(_entry: Dictionary):
		if workspace_state.left_tab == WorkspaceState.LeftTab.ASSETS:
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT_BROWSER))
	object_attributes.updated.connect(func(msg: String):
		scene_tree.request_rebuild()
		sync_actions()
		report(msg))
	object_attributes.focus_requested.connect(focus_object_view)
	object_attributes.sound_edit_requested.connect(func(v: int):
		select_object_view(v)
		open_sound_editor())
	object_attributes.select_team_requested.connect(func(team_id: int):
		var matched := scene_tree.select_all_on_team(team_id)
		select_object_views(matched)
		report("Selected %d object(s) on Team %d." % [matched.size(), team_id]))
	object_attributes.select_class_requested.connect(func(odf: String):
		var matched := scene_tree.select_matching_class(odf)
		select_object_views(matched)
		report("Selected %d object(s) of class %s." % [matched.size(), odf]))
	object_attributes.selection_cleared.connect(func():
		object_tool.set_selection()
		workspace_state.select_objects()
		scene_tree.request_rebuild()
		sync_actions())
	water_tools.updated.connect(func(value: String): sync_actions(); scene_tree.request_rebuild(); report(value))
	water_tools.painting_changed.connect(update_water_painting)


func _on_tool_panel_action(action_id: String) -> void:
	match action_id:
		"terrain_brush":
			activate_terrain_brush()
		"slope_studio":
			open_slope_studio()
		"shape_terrain":
			open_terrain_tools()
		"nodes":
			open_studio()
		"move_object":
			_toggle_move_objects(true)
		"object_browser":
			open_object_browser()
		"sound_editor":
			open_sound_editor()
		"move_path":
			_toggle_move_paths(true)
		"path_inspector":
			inspect_path()
		"new_path":
			start_new_path()
		"mission_studio":
			open_mission_studio()
		"water_editor":
			toggle_water_edit()
		"environment":
			open_environment_studio()
		"target_profile":
			open_target_profile(0)
		"new_map":
			open_new_map_wizard()
		"settings":
			show_playtest_setup()


func _on_scene_tree_selected(kind: String, index: int) -> void:
	if document == null:
		return
	match kind:
		"terrain", "terrain_channel":
			if index >= 0 and index <= 2:
				brush_panel.surface.select(index)
				brush_panel.update_buttons()
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.TERRAIN_BRUSH)
		"layers", "layer":
			if index >= 0 and index < document.layers.size():
				workspace_state.select_layer(index)
				layers_panel.refresh(index)
				if studio.document == document:
					studio.load_layer(index)
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.NODE)
		"object":
			if document.valid_view_object(index):
				select_object_view(index)
				object_attributes.refresh(document, index)
				workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT)
		"objects_group":
			workspace_state.set_left_tab(WorkspaceState.LeftTab.ASSETS, true)
			open_object_browser()
		"path":
			select_created_path(index)
			path_inspector.show_path(document, index)
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.PATH)
		"mission":
			mission_studio.begin(document, _world_anchor())
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.MISSION)
		"water":
			water_tools.begin(document)
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.WATER)
		"environment":
			environment_studio.begin(document, scene_view.env_preview_enabled)
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.ENVIRONMENT)
		"project":
			target_profile_dialog.begin(document, mod_registry, game_path.text.strip_edges(), vrv_path.text.strip_edges(), default_new_mod_profile, 0)
			workspace_state.set_inspector_context(WorkspaceState.InspectorContext.PROJECT)


func _on_scene_tree_activated(kind: String, index: int) -> void:
	if document == null:
		return
	match kind:
		"object":
			focus_object_view(index)
		"path":
			focus_path_index(index)
		"layer", "layers":
			_on_layers_edit_graph(maxi(0, index))
		"terrain", "terrain_channel":
			set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
			focus_terrain()
		"environment":
			open_environment_studio()
		"water":
			toggle_water_edit()


func _on_scene_visibility_toggled(channel: String, on: bool) -> void:
	workspace_state.set_editor_visibility(channel, on)
	match channel:
		"objects":
			if objects_button != null:
				objects_button.set_pressed_no_signal(on)
				toggle_objects()
		"paths":
			if document != null:
				if on:
					draw_path(document.path_at(path_index_for_item(path_list.selected)))
				else:
					top.path_overlay = {}
					top.extra_paths.clear()
					top.queue_redraw()
					scene_view.extra_paths.clear()
					scene_view.show_path({})
		"water":
			if water_button != null and document != null and document.package.water != null:
				water_button.set_pressed_no_signal(on)
				toggle_water()


func _on_layers_panel_selected(index: int) -> void:
	workspace_state.select_layer(index)
	if document != null:
		if studio.document != document:
			_prepare_node_studio(index)
		else:
			studio.load_layer(index)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.NODE)


func _on_layers_edit_graph(index: int) -> void:
	if document == null:
		return
	_prepare_node_studio(index)
	set_center_mode(WorkspaceState.CenterMode.NODES)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.NODE, true)


func _prepare_node_studio(layer_idx: int = -1) -> void:
	if document == null:
		return
	clear_incompatible_preview("node")
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	studio.begin(document, Vector2i(target.round()), layer_idx)


func _on_center_mode_button_pressed(mode_id: int) -> void:
	if mode_id == WorkspaceState.CenterMode.NODES:
		open_studio()
	elif mode_id == WorkspaceState.CenterMode.NEW_MAP:
		open_new_map_wizard()
	elif mode_id == WorkspaceState.CenterMode.SETTINGS:
		show_playtest_setup()
	else:
		set_center_mode(mode_id)


func set_center_mode(mode_id: int) -> void:
	cancel_all_slider_gestures()
	workspace_state.set_center_mode(mode_id)


func _on_center_mode_changed(mode_id: int) -> void:
	var is_vp := mode_id in [WorkspaceState.CenterMode.SPLIT_3D_2D, WorkspaceState.CenterMode.VIEW_3D, WorkspaceState.CenterMode.VIEW_2D]
	views.visible = is_vp
	viewport_bar.visible = is_vp
	scene_dock_box.visible = mode_id in [WorkspaceState.CenterMode.SPLIT_3D_2D, WorkspaceState.CenterMode.VIEW_3D]
	top_dock_box.visible = mode_id in [WorkspaceState.CenterMode.SPLIT_3D_2D, WorkspaceState.CenterMode.VIEW_2D]
	studio.visible = (mode_id == WorkspaceState.CenterMode.NODES)
	new_map_wizard.visible = (mode_id == WorkspaceState.CenterMode.NEW_MAP)
	playtest_dialog.visible = (mode_id == WorkspaceState.CenterMode.SETTINGS)
	for mid_v in center_mode_buttons:
		var mid := int(mid_v)
		(center_mode_buttons[mid] as Button).set_pressed_no_signal(mid == mode_id)
	_apply_views_split_offset()
	sync_actions()


func _on_left_tab_changed(tab_idx: int) -> void:
	if _applying_layout:
		return
	workspace_state.set_left_tab(tab_idx, false)
	if tab_idx == WorkspaceState.LeftTab.ASSETS and document != null:
		var game := game_path.text.strip_edges()
		var vrv := vrv_path.text.strip_edges()
		object_browser.begin(document, mod_registry, game, vrv)
		workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT_BROWSER)
	elif tab_idx == WorkspaceState.LeftTab.LAYERS and document != null:
		layers_panel.refresh()
	_save_workspace_layout()


func _on_state_left_tab_changed(tab_idx: int) -> void:
	if left_tabs.current_tab != tab_idx and tab_idx >= 0 and tab_idx < left_tabs.get_tab_count():
		_applying_layout = true
		left_tabs.current_tab = tab_idx
		_applying_layout = false


func _on_preset_dropdown_selected(idx: int) -> void:
	if _applying_layout or idx < 0:
		return
	var pid := int(preset_select.get_item_metadata(idx))
	apply_workspace_preset(pid)


func apply_workspace_preset(preset_id: int) -> void:
	workspace_state.apply_preset(preset_id)
	if preset_id == WorkspaceState.LayoutPreset.NODES and document != null:
		_prepare_node_studio(layers_panel.selected_index)
	elif preset_id == WorkspaceState.LayoutPreset.SCULPTING and document != null:
		slope_studio.begin(document, _world_anchor(), true)
	elif preset_id == WorkspaceState.LayoutPreset.MISSION and document != null:
		mission_studio.begin(document, _world_anchor())
	elif preset_id == WorkspaceState.LayoutPreset.OBJECT_PLACEMENT and document != null:
		object_browser.begin(document, mod_registry, game_path.text.strip_edges(), vrv_path.text.strip_edges())
		object_attributes.refresh(document, object_tool.selected)
	_save_workspace_layout()


func _on_state_preset_changed(preset_id: int) -> void:
	_applying_layout = true
	for i in preset_select.item_count:
		if int(preset_select.get_item_metadata(i)) == preset_id:
			preset_select.select(i)
			break
	_applying_layout = false


func _on_state_tool_changed(tool_id: int) -> void:
	_update_tool_badge()
	var action_map := {
		WorkspaceState.Tool.TERRAIN_BRUSH: "terrain_brush",
		WorkspaceState.Tool.SLOPE: "slope_studio",
		WorkspaceState.Tool.SHAPE: "shape_terrain",
		WorkspaceState.Tool.OBJECT_MOVE: "move_object",
		WorkspaceState.Tool.OBJECT_PLACE: "object_browser",
		WorkspaceState.Tool.PATH_MOVE: "move_path",
		WorkspaceState.Tool.WATER_PAINT: "water_editor",
	}
	tools_panel.set_active_action(String(action_map.get(tool_id, "")))


func _on_state_inspector_changed(ctx: int) -> void:
	if ctx == WorkspaceState.InspectorContext.ENVIRONMENT:
		tools_panel.set_active_action("environment")
	elif ctx == WorkspaceState.InspectorContext.MISSION:
		tools_panel.set_active_action("mission_studio")
	elif ctx == WorkspaceState.InspectorContext.SOUND:
		tools_panel.set_active_action("sound_editor")
	elif ctx == WorkspaceState.InspectorContext.PROJECT:
		tools_panel.set_active_action("target_profile")


func _update_tool_badge() -> void:
	var tname := String(WorkspaceState.TOOL_LABELS.get(workspace_state.active_tool, "Ready"))
	var prev_str := " · PREVIEW ACTIVE" if document != null and document.has_preview() else ""
	tool_badge.text = "[%s%s]" % [tname, prev_str]


func toggle_left_dock() -> void:
	workspace_state.set_dock_visibility(not workspace_state.left_dock_visible, workspace_state.right_dock_visible, workspace_state.bottom_log_visible)
	_save_workspace_layout()


func toggle_right_dock() -> void:
	workspace_state.set_dock_visibility(workspace_state.left_dock_visible, not workspace_state.right_dock_visible, workspace_state.bottom_log_visible)
	_save_workspace_layout()


func toggle_diagnostics_drawer() -> void:
	workspace_state.set_dock_visibility(workspace_state.left_dock_visible, workspace_state.right_dock_visible, not workspace_state.bottom_log_visible)
	_save_workspace_layout()


func toggle_fullscreen_viewport() -> void:
	if workspace_state.active_preset == WorkspaceState.LayoutPreset.FULLSCREEN:
		workspace_state.exit_fullscreen()
	else:
		workspace_state.apply_preset(WorkspaceState.LayoutPreset.FULLSCREEN)
	_save_workspace_layout()


func toggle_views_vertical() -> void:
	workspace_state.stack_2d_below = not workspace_state.stack_2d_below
	_apply_workspace_layout()
	_save_workspace_layout()
	report("2D Top View stacked below 3D viewport." if workspace_state.stack_2d_below else "3D and 2D viewports side-by-side.")


func _bind_all_collapsible_sections(root_node: Node = self) -> void:
	if root_node is CollapsibleSection:
		(root_node as CollapsibleSection).bind_workspace_state(workspace_state)
	for child in root_node.get_children():
		_bind_all_collapsible_sections(child)


func reset_workspace_layout() -> void:
	cancel_all_slider_gestures()
	workspace_state.reset_layout(get_viewport_rect().size)
	_save_workspace_layout()
	report("Workspace layout reset to Default.")


func _on_editor_resized() -> void:
	workspace_state.clamp_to_viewport(get_viewport_rect().size)
	_apply_workspace_layout()


func _apply_workspace_layout() -> void:
	_applying_layout = true
	var vp_sz := get_viewport_rect().size
	if vp_sz.x < 320.0:
		vp_sz = Vector2(1280, 720)
	workspace_state.clamp_to_viewport(vp_sz)
	left_dock.visible = workspace_state.left_dock_visible
	attributes_inspector.visible = workspace_state.right_dock_visible
	diagnostics_drawer.visible = workspace_state.bottom_log_visible
	diagnostics_button.set_pressed_no_signal(workspace_state.bottom_log_visible)
	if left_tabs.current_tab != workspace_state.left_tab and workspace_state.left_tab < left_tabs.get_tab_count():
		left_tabs.current_tab = workspace_state.left_tab
	if left_dock.visible:
		left_dock.custom_minimum_size.x = 180
		left_split.split_offset = maxi(0, workspace_state.left_dock_width - 180)
	if attributes_inspector.visible:
		attributes_inspector.custom_minimum_size.x = 228
		right_split.split_offset = -maxi(0, workspace_state.right_dock_width - 228)
		right_split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	var est_center_w := vp_sz.x - (float(workspace_state.left_dock_width) if left_dock.visible else 0.0) - (float(workspace_state.right_dock_width) if attributes_inspector.visible else 0.0) - 24.0
	views.vertical = workspace_state.stack_2d_below or est_center_w < 360.0
	_on_center_mode_changed(workspace_state.center_mode)
	_on_state_preset_changed(workspace_state.active_preset)
	_applying_layout = false


func _apply_views_split_offset() -> void:
	if workspace_state.center_mode != WorkspaceState.CenterMode.SPLIT_3D_2D:
		return
	var r := clampf(workspace_state.viewport_split_ratio, 0.25, 0.85)
	scene_dock_box.size_flags_stretch_ratio = r / maxf(0.15, 1.0 - r)
	top_dock_box.size_flags_stretch_ratio = 1.0


func _on_left_split_dragged(_offset: int) -> void:
	if _applying_layout or not left_dock.visible:
		return
	workspace_state.left_dock_width = clampi(int(round(left_dock.size.x)), 168, 420)
	_save_workspace_layout()


func _on_right_split_dragged(_offset: int) -> void:
	if _applying_layout or not attributes_inspector.visible:
		return
	workspace_state.right_dock_width = clampi(int(round(attributes_inspector.size.x)), 224, 520)
	_save_workspace_layout()


func _on_views_split_dragged(_offset: int) -> void:
	if _applying_layout or workspace_state.center_mode != WorkspaceState.CenterMode.SPLIT_3D_2D:
		return
	var primary_span := scene_dock_box.size.y if views.vertical else scene_dock_box.size.x
	var secondary_span := top_dock_box.size.y if views.vertical else top_dock_box.size.x
	var total := maxf(1.0, primary_span + secondary_span)
	workspace_state.viewport_split_ratio = clampf(primary_span / total, 0.25, 0.85)
	_save_workspace_layout()


func _save_workspace_layout() -> void:
	var settings := ConfigFile.new()
	settings.load(settings_path)
	workspace_state.save_to_config(settings)
	settings.save(settings_path)


func clear_active_preview(announce_msg: String = "") -> void:
	if document == null:
		return
	cancel_all_slider_gestures()
	if slope_studio.is_preview_active():
		slope_studio.clear_preview()
	if terrain_tools.document == document and workspace_state.active_preview_owner == "shape":
		terrain_tools.clear_preview()
	if studio.document == document and (workspace_state.active_preview_owner == "node" or studio.draft_state == NodeStudio.DraftState.PREVIEW or studio.worker.is_started()):
		studio.clear_preview_only()
	if document.has_preview():
		document.clear_preview()
	show_graph_preview(-1)
	workspace_state.set_preview_owner("")
	if not announce_msg.is_empty():
		report(announce_msg)
	sync_actions()


func clear_incompatible_preview(next_owner: String) -> void:
	if document == null:
		return
	var live_sculpt := document.sculpt_stroke_active and document.has_preview()
	var live_color := document.color_stroke_active and document.has_preview()
	var active_preview := document.has_active_preview_context() or (studio.document == document and studio.worker.is_started())
	if not active_preview:
		return
	if (live_sculpt or live_color) and next_owner == "brush":
		return
	# The document preview itself knows its true owner even when the workspace
	# mirror has drifted: a compatible next owner must never clear it.
	if (workspace_state.active_preview_owner == next_owner or document.preview_owner == next_owner) \
			and not next_owner.is_empty():
		return
	clear_active_preview()


func _world_anchor() -> Vector2:
	if document == null:
		return Vector2.ZERO
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	var world := scene_view.point_world(target)
	return Vector2(world.x, world.z)


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
	solid_button = add_button(parent, "Solid", show_wire.bind(false), "Solid terrain view")
	wire_button = add_button(parent, "Wire", show_wire.bind(true), "Wireframe terrain mesh")
	for button in [solid_button, wire_button]:
		button.toggle_mode = true
	show_wire(false)
	camera_buttons.append(add_button(parent, "Top", scene_view.set_view.bind(true), "Orthographic top view"))
	camera_buttons.append(add_button(parent, "Orbit", scene_view.set_view.bind(false), "Perspective orbit view"))
	focus_button = add_button(parent, "Focus", focus_terrain, "Focus 3D camera on last cursor")
	fly_button = add_button(parent, "Fly", toggle_fly, "Free-flight camera (F toggles; WASD/QE move)")
	fly_button.toggle_mode = true
	color_button = add_button(parent, "Col", show_vertex_colors, "Preview native TER vertex colors")
	color_button.toggle_mode = true
	texture_button = add_button(parent, "Tex", toggle_textures, "Preview native TRN tile textures")
	texture_button.toggle_mode = true
	objects_button = add_button(parent, "Obj", toggle_objects, "Display native BZCC object models in 3D view (editor-only)")
	objects_button.toggle_mode = true
	water_button = add_button(parent, "Wat", toggle_water, "Preview decoded native water layers in both views (editor-only)")
	water_button.toggle_mode = true
	move_objects_button = add_button(parent, "Move Obj", object_tool_changed, "Select and drag an object in 2D/3D")
	move_objects_button.toggle_mode = true
	move_path_button = add_button(parent, "Move Pt", path_tool_changed, "Drag AI path points in 2D/3D")
	move_path_button.toggle_mode = true
	path_list.custom_minimum_size.x = 84
	path_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_list.tooltip_text = "Display a native BZN path in both views"
	path_list.add_item("Path overlay")
	path_list.disabled = true
	path_list.item_selected.connect(select_path)
	parent.add_child(path_list)


func toggle_water() -> void:
	if document == null or document.package.water == null:
		return
	top.water_visible = water_button.button_pressed
	top.queue_redraw()
	scene_view.show_water(top.water_visible)
	workspace_state.set_editor_visibility("water", top.water_visible)
	scene_tree.sync_visibility_buttons(objects_button.button_pressed, bool(workspace_state.editor_visibility.get("paths", true)), water_button.button_pressed)
	if top.water_visible:
		var water := document.package.water
		var msg := "%d WAT layer(s) visible" % document.water_layers_effective().size()
		if water.invalid_layer_flags != 0:
			msg += " · skipped invalid layer heights"
		report(msg)


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


func activate_terrain_brush() -> void:
	cancel_all_slider_gestures()
	if document != null and document.sculpt_stroke_active:
		document.cancel_sculpt_stroke()
		paint_view = null
	if document != null and document.sculpt_mask_stroke_active:
		document.cancel_sculpt_mask_stroke()
		paint_view = null
	if document != null and document.color_stroke_active:
		document.cancel_color_stroke()
		paint_view = null
	if document != null and document.color_mask_stroke_active:
		document.cancel_color_mask_stroke()
		paint_view = null
	clear_incompatible_preview("brush")
	leave_water_paint()
	leave_object_tool()
	cancel_place_object(false)
	move_path_button.set_pressed_no_signal(false)
	if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.TERRAIN_BRUSH, not workspace_state.pinned_inspector)
	set_cursor(cursor)
	sync_actions()


func update_brush_cursor() -> void:
	var layer := brush_panel.paint_layer()
	var lane := int(brush_panel.texture_lane.value)
	if layer != top.preview_layer or (layer == Terrain.Layer.TILES and lane != top.preview_tile_lane):
		finish_stroke()
	move_path_button.set_pressed_no_signal(false)
	if object_tool.active:
		leave_object_tool()
	leave_water_paint()
	workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
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
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if event.keycode == KEY_F11 and not event.ctrl_pressed and not event.alt_pressed:
		toggle_fullscreen_viewport()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and workspace_state.active_preset == WorkspaceState.LayoutPreset.FULLSCREEN:
		workspace_state.exit_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F1:
		Wintage.popup_fit(keys_dialog, 420)
		get_viewport().set_input_as_handled()
		return
	if document == null or document.stroke_active or document.water_stroke_active:
		return
	if event.keycode == KEY_ESCAPE and document.sculpt_stroke_active:
		document.cancel_sculpt_stroke()
		paint_view = null
		anchor = Vector2(-1, -1)
		paint_hold_elapsed = 0.0
		layers_panel.refresh()
		report("Sculpt stroke cancelled.")
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and document.sculpt_mask_stroke_active:
		document.cancel_sculpt_mask_stroke()
		paint_view = null
		anchor = Vector2(-1, -1)
		paint_hold_elapsed = 0.0
		layers_panel.refresh()
		report("Sculpt stroke cancelled.")
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and document.color_stroke_active:
		document.cancel_color_stroke()
		paint_view = null
		anchor = Vector2(-1, -1)
		paint_hold_elapsed = 0.0
		layers_panel.refresh()
		report("Color stroke cancelled.")
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and document.color_mask_stroke_active:
		document.cancel_color_mask_stroke()
		paint_view = null
		anchor = Vector2(-1, -1)
		paint_hold_elapsed = 0.0
		layers_panel.refresh()
		report("Color mask stroke cancelled.")
		get_viewport().set_input_as_handled()
		return
	# When editing inside Nodes/NewMap/Settings, never leak terrain/object viewport shortcuts
	var in_viewport := workspace_state.center_mode in [WorkspaceState.CenterMode.SPLIT_3D_2D, WorkspaceState.CenterMode.VIEW_3D, WorkspaceState.CenterMode.VIEW_2D]
	if event.keycode == KEY_F5 and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
		playtest()
		get_viewport().set_input_as_handled()
		return
	if not in_viewport:
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
				object_attributes.refresh(document, object_tool.selected)
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
					object_attributes.refresh(document, view)
					scene_tree.rebuild()
					report(object_tool.description() + object_count_notice("Duplicated"))
				else:
					report(document.error)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE and not event.ctrl_pressed:
			if object_tool.selected >= 0 and document.remove_object(object_tool.selected):
				object_tool.selected = -1
				object_tool.refresh_marker()
				object_attributes.refresh(document, -1)
				scene_tree.rebuild()
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
		activate_terrain_brush()
		get_viewport().set_input_as_handled()
	elif event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and brush_panel.shortcut(key):
		move_path_button.set_pressed_no_signal(false)
		path_tool_changed(false)
		get_viewport().set_input_as_handled()


func sync_actions() -> void:
	var locked := document == null or document.has_active_edit_transaction() or path_drag_view != null or object_tool.drag_view != null
	undo_button.disabled = locked or document.undo_stack.is_empty()
	redo_button.disabled = locked or document.redo_stack.is_empty()
	save_button.disabled = locked
	export_button.disabled = locked
	playtest_button.disabled = locked or launcher_pid > 0 or game_pid > 0 or OS.get_name() != "Windows"
	focus_button.disabled = locked
	fly_button.disabled = locked
	for button in camera_buttons:
		button.disabled = locked
	var thread_busy := object_thread != null and object_thread.is_started()
	var has_doc := document != null
	var has_objs := has_doc and document.object_count() > 0
	var has_wat := has_doc and document.package.water != null
	var can_resize_paths := has_doc and document.package.path_codec.can_resize
	tools_panel.set_map_loaded(not locked, has_wat, has_objs, can_resize_paths)
	if slope_studio_button != null:
		slope_studio_button.disabled = locked
	if edit_path_button != null:
		edit_path_button.disabled = locked or path_list.selected <= 0
	move_path_button.disabled = locked or path_list.selected <= 0
	objects_button.disabled = locked or not has_objs or thread_busy
	move_objects_button.disabled = locked or not has_objs or (has_doc and document.has_preview())
	water_button.disabled = locked or not has_wat
	color_button.disabled = locked or texture_button.button_pressed
	texture_button.disabled = locked or thread_busy
	if document != null:
		var terrain := document.package.terrain
		var dirty := "*" if has_unsaved_changes() else ""
		title.text = "%s%s  |  %s · %s  |  BZN %d  |  %d × %d m" % [
			document.package.mission_name, dirty, document.mod_profile, document.mission_profile,
			document.package.bzn_version, terrain.dimensions.x * 2, terrain.dimensions.y * 2]
		title.tooltip_text = title.text
	else:
		title.text = "No map loaded"
	if empty_state_hint != null:
		empty_state_hint.visible = (document == null)
	_update_tool_badge()


func has_unsaved_changes() -> bool:
	return document != null and (document.edits != saved_edits or document.layers != saved_layers
		or document.sculpt_layers != saved_sculpt_layers
		or document.color_layers != saved_color_layers
		or (studio.document == document and studio.has_uncommitted_draft())
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
	saved_sculpt_layers = document.sculpt_layers.duplicate(true)
	saved_color_layers = document.color_layers.duplicate(true)
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
	if document != null and document.sculpt_stroke_active:
		document.cancel_sculpt_stroke()
		paint_view = null
	if document != null and document.sculpt_mask_stroke_active:
		document.cancel_sculpt_mask_stroke()
		paint_view = null
	if document != null and document.color_stroke_active:
		document.cancel_color_stroke()
		paint_view = null
	if document != null and document.color_mask_stroke_active:
		document.cancel_color_mask_stroke()
		paint_view = null
	finish_stroke()
	if has_unsaved_changes():
		pending_path = path
		if studio.document == document and studio.has_uncommitted_draft():
			confirmation.dialog_text = "Open another map and discard unsaved edits (including uncommitted Node Graph draft)?"
		else:
			confirmation.dialog_text = "Open another map and discard unsaved edits?"
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


func open_map(path: String, draft_payload: Dictionary = {}) -> bool:
	cancel_all_slider_gestures()
	if not path.is_absolute_path():
		path = OS.get_executable_path().get_base_dir().path_join(path) if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://").path_join(path)
	var next := Document.new()
	if not next.open(path.simplify_path()):
		report(next.error)
		return false
	if document != null:
		clear_active_preview()
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
		if document.layers_changed.is_connected(on_document_layers_changed):
			document.layers_changed.disconnect(on_document_layers_changed)
		if document.sculpt_layers_changed.is_connected(_on_document_sculpt_changed):
			document.sculpt_layers_changed.disconnect(_on_document_sculpt_changed)
		if document.color_layers_changed.is_connected(_on_document_color_changed):
			document.color_layers_changed.disconnect(_on_document_color_changed)

	leave_water_paint()
	cancel_place_object(false)
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
	document.layers_changed.connect(on_document_layers_changed)
	document.sculpt_layers_changed.connect(_on_document_sculpt_changed)
	document.color_layers_changed.connect(_on_document_color_changed)
	workspace_state.select_objects()
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

	# Rebind all docked workspace panels safely (no stale references!)
	slope_studio.document = null
	slope_studio._initialized = false
	terrain_tools.document = document
	water_tools.begin(document)
	environment_studio.begin(document, scene_view.env_preview_enabled)
	object_attributes.refresh(document, -1)
	scene_tree.bind_document(document)
	scene_tree.sync_visibility_buttons(false, true, false)
	layers_panel.bind_document(document, 0)
	_offer_recovered_draft(draft_payload)
	if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	if workspace_state.left_tab == WorkspaceState.LeftTab.ASSETS:
		object_browser.begin(document, mod_registry, cur_game, cur_vrv)
	if workspace_state.active_inspector_context == WorkspaceState.InspectorContext.SLOPE:
		slope_studio.begin(document, _world_anchor(), false)
	elif workspace_state.active_inspector_context == WorkspaceState.InspectorContext.MISSION:
		mission_studio.begin(document, _world_anchor())
	elif workspace_state.active_inspector_context == WorkspaceState.InspectorContext.PROJECT:
		target_profile_dialog.begin(document, mod_registry, cur_game, cur_vrv, default_new_mod_profile, 0)

	sync_actions()
	var open_compat := CompatibilityEngine.evaluate(document, mod_registry, document.mod_profile, document.mission_profile, document.engine_profile, cur_game, cur_vrv, {}, engine_editor_mode.button_pressed)
	var open_note := ""
	if String(open_compat["validationStatus"]) != CompatibilityEngine.PLAYTEST_READY:
		var reasons: Array = open_compat.get("refusalReasons", [])
		if not reasons.is_empty():
			open_note = " [%s: %s]" % [String(open_compat["validationStatus"]), String(reasons[0])]
	report("Opened %s [%s / %s]%s" % [document.package.source_path.get_file(), document.mod_profile, document.mission_profile, open_note])
	return true


## Crash recovery never silently commits a graph draft. The committed document
## opens first; a matching draft is offered as a separate, inspectable restore.
func _offer_recovered_draft(payload: Dictionary) -> void:
	recovered_draft = {}
	recovered_draft_slot = ""
	if payload.is_empty() or document == null:
		return
	if int(payload.get("schema", 0)) != AutoSaveStore.DRAFT_SCHEMA:
		report("Recovery draft ignored: unsupported schema.")
		return
	if String(payload.get("source", "")) != document.package.source_path:
		report("Recovery draft ignored: source project differs.")
		return
	if String(payload.get("sourceRevision", "")) != AutoSaveStore.digest(JSON.stringify(document.package.files).to_utf8_buffer()):
		report("Recovery draft ignored: source revision drift.")
		return
	var draft: Variant = payload.get("draft", null)
	if not draft is Dictionary or (draft as Dictionary).is_empty():
		report("Recovery draft ignored: invalid payload.")
		return
	var inner: Dictionary = (draft as Dictionary).duplicate(true)
	var raw_base: Variant = inner.get("baseUids", [])
	var raw_layers: Variant = inner.get("baseLayers", [])
	if not raw_base is Array or not raw_layers is Array:
		report("Recovery draft ignored: invalid base stack.")
		return
	document.ensure_layer_uids()
	var recovered_base_uids: Array[int] = []
	for uid in (raw_base as Array):
		recovered_base_uids.append(int(uid))
	var fingerprint := String(inner.get("baseFingerprint", ""))
	var base_match: bool = recovered_base_uids == document.layer_uids
	if fingerprint.is_empty():
		base_match = base_match and int(inner.get("baseLayerRevision", -1)) == document.layer_stack_revision
	else:
		base_match = base_match and fingerprint == AutoSaveStore.base_stack_fingerprint(document)
	var raw_working: Variant = inner.get("working", [])
	var raw_work_uids: Variant = inner.get("workingUids", [])
	var graph := NodeStudio.Graph.new()
	if not raw_working is Array or not raw_work_uids is Array or (raw_work_uids as Array).size() != (raw_working as Array).size() or not graph.validate_stack(raw_working):
		report("Recovery draft ignored: invalid graph payload.")
		return
	var diff := PackedStringArray()
	if not base_match:
		diff.append("Base layer stack changed since the draft was captured · three-way merge required")
	else:
		diff.append("Base layer stack matches the recovered project")
	diff.append("Draft layers: %d · Committed layers: %d" % [(raw_working as Array).size(), document.layers.size()])
	recovered_draft = inner
	recovered_draft_slot = payload.get("source", "")
	_prepare_node_studio(clampi(int(inner.get("selected", 0)), 0, (raw_working as Array).size() - 1))
	studio.working = (raw_working as Array).duplicate(true)
	studio.working_uids = []
	for uid in (raw_work_uids as Array):
		studio.working_uids.append(int(uid))
	studio.draft_revision = maxi(int(inner.get("revision", 1)), 1)
	studio.conflict_pending = not base_match
	studio.conflict_reason = "Recovered draft base revision differs from the project." if not base_match else ""
	studio.draft_state = NodeStudio.DraftState.DRAFT
	studio.base_snapshot = (raw_layers as Array).duplicate(true)
	studio.base_uids = []
	for uid in (raw_base as Array):
		studio.base_uids.append(int(uid))
	studio.base_layer_revision = int(inner.get("baseLayerRevision", -1))
	studio.draft_state_changed.emit(true, not base_match, studio.conflict_reason)
	studio.conflict_diff_changed.emit(diff)
	studio.set_message("Recovered project + uncommitted Node Graph draft. Keep Layers to commit or Discard Draft to reject.")
	report("Recovered project + uncommitted Node Graph draft from " + recovered_draft_slot)
	if not base_match:
		studio.sync_from_document(studio.selected)


func open_new_map_wizard() -> void:
	cancel_all_slider_gestures()
	clear_incompatible_preview("page")
	leave_water_paint()
	leave_object_tool()
	cancel_place_object(false)
	move_path_button.set_pressed_no_signal(false)
	find_steam_game()
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != game:
		mod_registry.discover_installed(game, vrv)
	var fallback := tool_root().path_join("map_references/blank_map1/duel_map_27_autosave_01.bzn")
	var parent_dir := document.package.source_path.get_base_dir().get_base_dir() if document != null else tool_root().path_join("build")
	new_map_wizard.begin(mod_registry, game, default_new_mod_profile, parent_dir, fallback)
	set_center_mode(WorkspaceState.CenterMode.NEW_MAP)


func _on_wizard_map_created(bzn_path: String, engine_id: String, mod_id: String, mission_id: String) -> void:
	default_new_mod_profile = mod_id
	_save_new_map_default()
	if open_map(bzn_path):
		document.engine_profile = engine_id
		document.mod_profile = mod_id
		document.mission_profile = mission_id
		document.profile_explicit = true
		remember_saved_changes()
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
		scene_tree.rebuild()
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
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.PROJECT, true)


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
	if mission_studio.document == document and mission_studio.is_visible_in_tree():
		mission_studio.refresh_all()
	if target_profile_dialog.document == document and target_profile_dialog.is_visible_in_tree():
		target_profile_dialog.refresh_all()
	if object_browser.document == document and object_browser.is_visible_in_tree():
		object_browser.refresh_catalog()
	scene_tree.request_rebuild()
	cancel_place_object(false)
	sync_actions()


func on_document_layers_changed(select_idx: int = -1) -> void:
	if document == null:
		return
	layers_panel.refresh(select_idx)
	if studio.document == document:
		var res := studio.sync_from_document(select_idx)
		if String(res.get("status", "")) == "conflict":
			report("Node Graph conflict: %s Open Nodes to Keep Draft or Discard Draft." % String(res.get("reason", "")))
	scene_tree.request_rebuild()
	sync_actions()


func _on_document_sculpt_changed(_uid: int) -> void:
	if document != null:
		layers_panel.refresh()
		sync_actions()
		if document.sculpt_stroke_active and document.has_preview():
			workspace_state.set_preview_owner("sculpt")
		if document.color_stroke_active and document.has_preview():
			workspace_state.set_preview_owner("color")


func _on_document_color_changed(_uid: int) -> void:
	if document != null:
		layers_panel.refresh()
		sync_actions()


func on_document_environment_changed() -> void:
	if document == null:
		return
	if scene_view.env_preview_enabled:
		scene_view.apply_environment_preview(document.effective_environment(), true)
	environment_studio.refresh_all()
	scene_tree.request_rebuild()
	sync_actions()


func open_environment_studio() -> void:
	if document == null:
		return
	environment_studio.begin(document, scene_view.env_preview_enabled)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.ENVIRONMENT, true)


func _open_save_dialog() -> void:
	if document == null:
		return
	save_dialog.current_file = document.package.source_path.get_file().get_basename() + ".bzmag"
	save_dialog.popup_centered_ratio(0.72)


func request_save() -> void:
	if document == null:
		return
	if studio.document == document and studio.has_uncommitted_draft():
		draft_save_dialog.popup_centered()
		return
	_open_save_dialog()


func select_path(index: int) -> void:
	selected_path_point = -1
	if index <= 0:
		move_path_button.set_pressed_no_signal(false)
	var pidx := path_index_for_item(index)
	workspace_state.select_path(pidx, -1)
	var path := document.path_at(pidx)
	draw_path(path)
	if index > 0:
		if workspace_state.active_inspector_context == WorkspaceState.InspectorContext.PATH:
			path_inspector.show_path(document, pidx)
		report("%s · %d points · native path type %d" % [path["name"], path["points"].size(), path["type"]])
	sync_actions()


func draw_path(path: Dictionary) -> void:
	if not bool(workspace_state.editor_visibility.get("paths", true)):
		top.path_overlay = {}
		top.extra_paths.clear()
		top.queue_redraw()
		scene_view.extra_paths.clear()
		scene_view.show_path({})
		return
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
	mission_studio.begin(document, _world_anchor())
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.MISSION, true)


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
	if mission_studio.document == document:
		mission_studio.refresh_all()
	scene_tree.rebuild()


func path_index_for_item(item: int) -> int:
	return int(path_list.get_item_metadata(item)) if item > 0 and item < path_list.item_count else -1


func start_new_path() -> void:
	if document == null:
		return
	path_inspector.show_new_path(document, _world_anchor())
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.PATH, true)


func select_created_path(index: int) -> void:
	for item in range(1, path_list.item_count):
		if path_index_for_item(item) == index:
			path_list.select(item)
			select_path(item)
			return


func inspect_path() -> void:
	if document == null:
		return
	if path_list.selected > 0:
		path_inspector.show_path(document, path_index_for_item(path_list.selected))
	else:
		path_inspector.show_path(document, -1)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.PATH, true)


func focus_path_index(index: int) -> void:
	if document == null:
		return
	var p := document.path_at(index)
	if p.is_empty():
		return
	var pts: PackedVector2Array = p["points"]
	if pts.is_empty():
		return
	var c := MissionProfiles.centroid(pts)
	var terrain := document.package.terrain
	var samp := Vector2(c.x / terrain.SPACING - float(terrain.origin.x), c.y / terrain.SPACING - float(terrain.origin.y))
	scene_view.center = scene_view.point_world(samp)
	scene_view.update_camera()
	set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)


func _toggle_move_paths(enable: bool) -> void:
	move_path_button.set_pressed_no_signal(enable)
	path_tool_changed(true)


func path_tool_changed(announce := true) -> void:
	if move_path_button.button_pressed:
		leave_object_tool()
		leave_water_paint()
		cancel_place_object(false)
		if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
			set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
		workspace_state.set_tool(WorkspaceState.Tool.PATH_MOVE)
	else:
		if workspace_state.active_tool == WorkspaceState.Tool.PATH_MOVE:
			workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
	set_cursor(cursor)
	if announce:
		report("Drag a path point. Shift+click appends a point. Delete removes the selected point." if move_path_button.button_pressed else "Terrain brush ready.")


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
	if document == null:
		return
	export_dialog.title = "Choose parent folder for a new native snapshot"
	export_dialog.popup_centered_ratio(0.72)


func save_project(path: String) -> void:
	var writer := Snapshots.new()
	if writer.save_project(document, path):
		remember_saved_changes()
		sync_actions()
		if studio.document == document and studio.has_uncommitted_draft():
			report("Saved " + path + " [NOTE: uncommitted Node Graph draft not included; click Keep Layers in Nodes to commit]")
		else:
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


func object_count_notice(suffix: String) -> String:
	if document == null or (document.object_additions.is_empty() and document.object_removals.is_empty()):
		return " | " + suffix
	var status_label := Layouts.capability_status(document.package.layout_id, Layouts.EDIT_OBJECT_COUNT)
	if status_label in ["NATIVE", "BAKED"]:
		return " | Added %d and removed %d objects (%s on 2.0.185; %s)" % [
			document.object_additions.size(), document.object_removals.size(), status_label, suffix]
	return " | Adding %d and removing %d objects is %s: undo count edits before Playtest. %s" % [
		document.object_additions.size(), document.object_removals.size(), status_label, suffix]


func report(msg: String) -> void:
	status.text = msg
	status.tooltip_text = msg
	if not msg.is_empty():
		diagnostics_lines.append(msg)
		if diagnostics_lines.size() > 120:
			diagnostics_lines.remove_at(0)
		diagnostics_drawer.text = "\n".join(diagnostics_lines)


func tool_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()


func asset_adapter() -> String:
	var built := tool_root().path_join("build/object-preview/mesh-preview.exe")
	var bundled := tool_root().path_join("tools/mesh-preview.exe")
	if OS.has_feature("editor"):
		return built
	return bundled if FileAccess.file_exists(bundled) else built


func toggle_objects() -> void:
	workspace_state.set_editor_visibility("objects", objects_button.button_pressed)
	scene_tree.sync_visibility_buttons(objects_button.button_pressed, bool(workspace_state.editor_visibility.get("paths", true)), water_button.button_pressed)
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
		report("Choose the game folder in Settings to preview native assets.")
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
	cancel_all_slider_gestures()
	clear_incompatible_preview("page")
	leave_water_paint()
	leave_object_tool()
	cancel_place_object(false)
	move_path_button.set_pressed_no_signal(false)
	find_steam_game()
	suggest_vrv()
	set_center_mode(WorkspaceState.CenterMode.SETTINGS)


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
	setup_status.text = "[OK] Settings saved."
	set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)


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
	workspace_state.save_to_config(settings)
	settings.save(settings_path)
	mod_registry.discover_installed(game_path.text.strip_edges(), vrv_path.text.strip_edges())
	vrv_configured = true


func all_dialogs() -> Array[Window]:
	return [
		open_dialog, blank_dialog, flat_template_dialog, flat_output_dialog, save_dialog, export_dialog,
		confirmation, draft_save_dialog, keys_dialog, recover_dialog, game_picker, vrv_picker, autosave_picker,
		asset_profile_picker, new_map_wizard.source_picker, new_map_wizard.ter_picker,
		new_map_wizard.output_picker, target_profile_dialog.custom_dir_picker,
	]


func sync_theme_controls() -> void:
	var idx := Wintage.theme_slugs().find(theme_slug)
	if idx >= 0 and theme_select.item_count > idx:
		theme_select.select(idx)
	compact_check.set_pressed_no_signal(ui_compact)
	font_size_field.set_value_no_signal(ui_font_size)


func set_wintage_theme(slug: String, compact: bool, persist: bool = true) -> void:
	theme_slug = slug if slug in Wintage.theme_slugs() else Wintage.DEFAULT_THEME
	ui_compact = compact
	var colors := Wintage.palette(theme_slug)
	theme = Wintage.make(colors, ui_font_size, ui_compact)
	backdrop.color = colors["background"]
	coordinates.add_theme_color_override("font_color", colors["textSecondary"])
	tool_badge.add_theme_color_override("font_color", colors["borderHighlight"])
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


func _on_tool_search_submitted(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	if needle.is_empty():
		return
	for button in toolbar_buttons:
		if button.visible and not button.disabled and (button.text.to_lower().contains(needle) or button.tooltip_text.to_lower().contains(needle)):
			button.pressed.emit()
			tool_search.clear()
			filter_toolbar("")
			return


func select_object_view(view: int) -> void:
	if document == null or not document.valid_view_object(view):
		return
	select_object_views([view], view)


func select_object_views(views: Array[int], primary: int = -1) -> void:
	if document == null:
		return
	var valid_views: Array[int] = []
	for v in views:
		if document.valid_view_object(v) and not valid_views.has(v):
			valid_views.append(v)
	var chosen := primary if (primary >= 0 and valid_views.has(primary)) else (valid_views[valid_views.size() - 1] if not valid_views.is_empty() else -1)
	object_tool.set_selection(valid_views, chosen)
	workspace_state.select_objects(valid_views, chosen)
	object_attributes.refresh_selection(document, valid_views)
	if valid_views.size() > 1:
		scene_tree.select_objects(valid_views)
		workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT)
	elif chosen >= 0:
		scene_tree.select_entry("object", chosen)
	if object_tool.active:
		object_tool.refresh_marker()
		report(object_tool.description())


func focus_object_view(view: int) -> void:
	if document == null or not document.valid_view_object(view):
		return
	select_object_view(view)
	scene_view.center = document.object_position(view)
	scene_view.update_camera()
	set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)


func open_object_label_editor() -> void:
	if document == null or document.object_count() == 0:
		return
	object_attributes.refresh(document, object_tool.selected)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT, true)
	if document.valid_view_object(object_tool.selected):
		object_attributes.label_field.grab_focus()


func open_sound_editor() -> void:
	if document == null or document.object_count() == 0:
		return
	var env := mod_registry.resolve_content_environment(document, game_path.text.strip_edges(), vrv_path.text.strip_edges())
	sound_editor.begin(document, object_tool.selected, game_path.text.strip_edges(), vrv_path.text.strip_edges(), env["linkedFolders"] + env["modAssetRoots"])
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.SOUND, true)


func open_object_browser() -> void:
	if document == null:
		return
	var game := game_path.text.strip_edges()
	var vrv := vrv_path.text.strip_edges()
	if mod_registry.last_game_dir != game:
		mod_registry.discover_installed(game, vrv)
	object_browser.begin(document, mod_registry, game, vrv)
	workspace_state.set_left_tab(WorkspaceState.LeftTab.ASSETS, true)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT_BROWSER, true)


func start_place_object(odf: String, team: int, template_view: int, is_native_new: bool) -> void:
	if document == null:
		return
	clear_incompatible_preview("place")
	leave_object_tool()
	leave_water_paint()
	if path_drag_view != null:
		finish_point_drag(false)
	move_path_button.set_pressed_no_signal(false)
	pending_place_spec = {
		"odf": odf,
		"team": team,
		"template_view": template_view,
		"is_native_new": is_native_new,
	}
	if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	workspace_state.set_tool(WorkspaceState.Tool.OBJECT_PLACE)
	report("Place %s (Team %d): click in 2D or 3D view. Shift+click keeps placing. Esc cancels." % [odf, team])
	sync_actions()


func cancel_place_object(announce: bool = false) -> void:
	if pending_place_spec.is_empty():
		return
	pending_place_spec.clear()
	if workspace_state.active_tool == WorkspaceState.Tool.OBJECT_PLACE:
		workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
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
	object_attributes.refresh(document, view)
	scene_tree.rebuild()
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
	if document.has_active_edit_transaction():
		report("Finish the active brush or drag transaction before Playtest.")
		return
	if not find_steam_game():
		show_playtest_setup()
		return
	var plan := playtest_route_plan()
	var compat: Dictionary = plan["compatibility"]
	if not bool(plan["ok"]):
		var status_code := String(compat.get("validationStatus", "UNKNOWN"))
		report("[ERR] [%s] %s" % [status_code, String(plan["error"])])
		if bool(plan["needsConverter"]) and not valid_vrv(vrv_path.text.strip_edges()):
			setup_status.text = "BZN %d requires a valid conversion adapter folder containing tools/bzn_compat.py." % document.package.bzn_version
			show_playtest_setup()
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
	if fly_button != null and fly_button.button_pressed and document != null and views.visible:
		var focused := get_viewport().gui_get_focus_owner()
		if not (focused is LineEdit or focused is TextEdit):
			var forward: float = (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
			var side: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
			var rise: float = (1.0 if Input.is_key_pressed(KEY_E) else 0.0) - (1.0 if Input.is_key_pressed(KEY_Q) else 0.0)
			if forward != 0.0 or side != 0.0 or rise != 0.0:
				scene_view.fly_step(forward, side, rise, time)
				fly_moved = true
	if paint_view != null and document != null and document.sculpt_mask_stroke_active and brush_panel.sculpt_mask_active() == false:
		report("Sculpt Mask target changed during a stroke; the stroke was cancelled.")
		document.cancel_sculpt_mask_stroke()
		paint_view = null
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
	# Sculpt strokes use their own transaction state; hold painting must work
	# for either terrain or sculpt brushing, never both at once.
	var brushing := document.stroke_active or document.sculpt_stroke_active or document.sculpt_mask_stroke_active or document.color_stroke_active or document.color_mask_stroke_active
	if not brushing or anchor.x < 0.0:
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
	if document == null:
		return
	var terrain := document.package.terrain
	var target := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	scene_view.center = scene_view.point_world(target)
	scene_view.update_camera()


func toggle_fly() -> void:
	scene_view.set_fly(fly_button.button_pressed)
	report("Fly camera on. W/S forward/back, A/D strafe, Q/E down/up, right drag look, F toggles." if fly_button.button_pressed else "Fly camera off.")
	sync_actions()


func autosave_root(custom := "") -> String:
	var root := custom if custom != "" else autosave_custom_root
	return root if root != "" else AutoSaveStore.DEFAULT_ROOT


func autosave_now(custom_root := "") -> bool:
	if document == null:
		return false
	if document.has_active_edit_transaction():
		# Defer without resetting the timer so the next tick retries after commit.
		return false
	autosave_seconds = 0.0
	if not has_unsaved_changes():
		return false
	var store := AutoSaveStore.new()
	var draft: Dictionary = {}
	if studio.document == document and studio.has_uncommitted_draft():
		draft = {
			"revision": studio.draft_revision,
			"working": studio.working.duplicate(true),
			"workingUids": studio.working_uids.duplicate(),
			"baseLayers": studio.base_snapshot.duplicate(true),
			"baseUids": studio.base_uids.duplicate(),
			"baseLayerRevision": studio.base_layer_revision,
			"selected": studio.selected,
		}
	var published: String = store.publish(document, autosave_root(custom_root), AUTOSAVE_KEEP, draft)
	if published.is_empty():
		report("Autosave failed. " + store.error)
		return false
	last_autosave = published
	var suffix := " | Uncommitted Node Graph draft preserved" if not draft.is_empty() else ""
	report("Autosaved " + published + suffix + " | Source map folder untouched.")
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
	recover_dialog.dialog_text = "Open an autosave project file. A matching Node Graph draft is recovered separately. Unsaved changes are confirmed first."
	recover_list.select(found - 1)
	Wintage.popup_fit(recover_dialog, 520, 260)


func open_recovered_autosave() -> void:
	var selected := recover_list.get_selected_items()
	if selected.is_empty():
		return
	var slot: String = recover_list.get_item_metadata(selected[0])
	recovered_draft = AutoSaveStore.read_draft(slot)
	recovered_draft_slot = slot if not recovered_draft.is_empty() else ""
	request_open(slot)


func open_autosave_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(autosave_root()))


func open_studio() -> void:
	if document == null:
		return
	_prepare_node_studio(layers_panel.selected_index)
	set_center_mode(WorkspaceState.CenterMode.NODES)
	workspace_state.set_left_tab(WorkspaceState.LeftTab.LAYERS, true)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.NODE, true)


func open_terrain_tools() -> void:
	if document == null:
		return
	cancel_all_slider_gestures()
	clear_incompatible_preview("shape")
	leave_water_paint()
	leave_object_tool()
	cancel_place_object(false)
	move_path_button.set_pressed_no_signal(false)
	var terrain := document.package.terrain
	var sample := last_cursor if last_cursor.x >= 0 else Vector2(terrain.dimensions) * 0.5
	var anchor_point := Vector2i(sample.round()).clamp(Vector2i.ZERO, terrain.dimensions - Vector2i.ONE)
	terrain_tools.begin(document, anchor_point, brush_panel.radius_m)
	if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	workspace_state.set_tool(WorkspaceState.Tool.SHAPE)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.SHAPE, not workspace_state.pinned_inspector)
	sync_actions()


func open_slope_studio() -> void:
	if document == null:
		return
	cancel_all_slider_gestures()
	clear_incompatible_preview("slope")
	leave_water_paint()
	leave_object_tool()
	cancel_place_object(false)
	move_path_button.set_pressed_no_signal(false)
	slope_studio.begin(document, _world_anchor(), slope_studio.document == document and slope_studio._initialized)
	if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	workspace_state.set_tool(WorkspaceState.Tool.SLOPE)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.SLOPE, not workspace_state.pinned_inspector)
	sync_actions()


func set_cursor(point: Vector2) -> void:
	if document == null:
		return
	cursor = point
	var brush_point := Vector2(-1, -1) if move_path_button.button_pressed or object_tool.active or painting_water_active() or workspace_state.active_tool in [WorkspaceState.Tool.SLOPE, WorkspaceState.Tool.OBJECT_PLACE] else point
	top.cursor = brush_point
	top.queue_redraw()
	scene_view.show_cursor(brush_point)
	if point.x >= 0:
		last_cursor = point
		var world := scene_view.point_world(point)
		var info: Dictionary = scene_view.exact_sample_info(point)
		if not info.is_empty():
			var samp: Vector2i = info["sample"]
			coordinates.text = "X %.1f  Z %.1f  Y %.2f m  (%d,%d)  LOD %dm" % [
				world.x, world.z, world.y, samp.x, samp.y, int(info["resolution_m"])]
		else:
			coordinates.text = "X %.1f m  Z %.1f m  Y %.2f m" % [world.x, world.z, world.y]
	else:
		coordinates.text = "LMB paint · RMB orbit · MMB pan · Wheel zoom"


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
						clear_incompatible_preview("water")
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
							workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
							sync_actions()
				return
			if object_tool.active:
				if event.pressed and object_tool.drag_view == null:
					object_tool.start(panel, event.position, event.ctrl_pressed or event.shift_pressed)
					if not object_tool.selected_views.is_empty():
						workspace_state.select_objects(object_tool.selected_views, object_tool.selected)
						object_attributes.refresh_selection(document, object_tool.selected_views)
						workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT)
						scene_tree.select_objects(object_tool.selected_views)
					elif object_tool.selected >= 0:
						workspace_state.select_object(object_tool.selected)
						object_attributes.refresh(document, object_tool.selected)
						workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT)
						scene_tree.select_entry("object", object_tool.selected)
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
				if workspace_state.active_tool == WorkspaceState.Tool.SLOPE and slope_studio.is_preview_active():
					# Keep Slope Studio preview active while inspecting viewport unless explicitly painting
					return
				var point: Vector2 = panel.sample_at(event.position)
				if point.x >= 0:
					var layer := brush_panel.paint_layer()
					if layer == Terrain.Layer.COLOR and not brush_panel.valid_rgb():
						report("Enter a native RGB color as #RRGGBB.")
						return
					if layer == Terrain.Layer.HEIGHT and brush_panel.mode == BrushPanel.Mode.PICK:
						var h := scene_view.point_world(point).y
						brush_panel.use_picked_height(h)
						report("Picked paint height %.2f m" % h)
						return
					var painting_mask := layer == Terrain.Layer.COLOR and brush_panel.mask_target.button_pressed
					var painting_color_layer := layer == Terrain.Layer.COLOR and brush_panel.color_layer_target.button_pressed
					var painting_sculpt_mask := brush_panel.sculpt_mask_active()
					if painting_sculpt_mask:
						# A Sculpt Mask is an operation on the shared Sculpt
						# composition, so keep the sculpt-owned preview alive.
						clear_incompatible_preview("sculpt")
					elif not painting_color_layer and not painting_mask:
						clear_incompatible_preview("brush")
					if (painting_color_layer or painting_mask) and document.active_color_uid < 0:
						report("Create or activate a Color Layer first.")
						return
					if painting_sculpt_mask and document.active_sculpt_uid < 0:
						report("Create or activate a Sculpt Layer first. Add a Sculpt Mask to paint it.")
						return
					if painting_sculpt_mask:
						var mask_index := document.sculpt_index_by_uid(document.active_sculpt_uid)
						if mask_index < 0 or (document.sculpt_layers[mask_index] as Dictionary).get("mask", null) == null:
							report("Add a Sculpt Mask first. Sculpt Mask brush needs an attached mask.")
							return
					paint_view = panel
					anchor = Vector2(-1, -1)
					paint_hold_elapsed = 0.0
					if painting_mask:
						if not document.begin_color_mask_stroke():
							report(document.error)
							paint_view = null
							return
					elif painting_color_layer:
						if not document.begin_color_stroke():
							report(document.error)
							paint_view = null
							return
					elif painting_sculpt_mask:
						if not document.begin_sculpt_mask_stroke():
							report(document.error)
							paint_view = null
							return
					elif document.active_sculpt_uid < 0 or layer != Terrain.Layer.HEIGHT or not brush_panel.mode in [BrushPanel.Mode.RAISE, BrushPanel.Mode.LOWER]:
						if not document.begin_stroke(layer):
							report(document.error)
							paint_view = null
							return
					elif not document.begin_sculpt_stroke():
						report(document.error)
						paint_view = null
						return
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


func _toggle_move_objects(enable: bool) -> void:
	move_objects_button.set_pressed_no_signal(enable)
	object_tool_changed()


func object_tool_changed() -> void:
	cancel_all_slider_gestures()
	if document != null and document.sculpt_stroke_active:
		document.cancel_sculpt_stroke()
		paint_view = null
	if document != null and document.sculpt_mask_stroke_active:
		document.cancel_sculpt_mask_stroke()
		paint_view = null
	if document != null and document.color_stroke_active:
		document.cancel_color_stroke()
		paint_view = null
	if document != null and document.color_mask_stroke_active:
		document.cancel_color_mask_stroke()
		paint_view = null
	if move_objects_button.button_pressed:
		clear_incompatible_preview("object")
		leave_water_paint()
		cancel_place_object(false)
		if path_drag_view != null:
			finish_point_drag(false)
		move_path_button.set_pressed_no_signal(false)
		if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
			set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
		object_tool.set_active(true)
		workspace_state.set_tool(WorkspaceState.Tool.OBJECT_MOVE)
		var attr_views: Array[int] = []
		if not object_tool.selected_views.is_empty():
			attr_views.assign(object_tool.selected_views)
		elif object_tool.selected >= 0:
			attr_views.append(object_tool.selected)
		object_attributes.refresh_selection(document, attr_views)
		workspace_state.set_inspector_context(WorkspaceState.InspectorContext.OBJECT, not workspace_state.pinned_inspector)
		report("Drag an object in either view. Ctrl+click multi-selects. Shift snaps to terrain grid. Esc cancels.")
	else:
		leave_object_tool()
		workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
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
	if not object_tool.selected_views.is_empty():
		object_attributes.refresh_selection(document, object_tool.selected_views)
	elif object_tool.selected >= 0:
		object_attributes.refresh(document, object_tool.selected)
	report(object_tool.description() if applied else document.error)
	sync_actions()


func object_position_changed(index: int) -> void:
	object_tool.position_changed(index)
	if object_tool.selected_views.size() > 1 and object_tool.selected_views.has(index):
		object_attributes.refresh_selection(document, object_tool.selected_views)
	elif object_tool.selected == index:
		object_attributes.refresh(document, index)
	if object_tool.active and object_tool.selected == index:
		report(object_tool.description())
	sync_actions()


func objects_topology_changed() -> void:
	if loaded_objects == document:
		scene_view.object_models.rebuild(document)
		top.queue_redraw()
	var valid_sel: Array[int] = []
	for v in object_tool.selected_views:
		if document != null and document.valid_view_object(v):
			valid_sel.append(v)
	object_tool.selected_views = valid_sel
	if object_tool.selected >= document.object_count():
		object_tool.selected = valid_sel[valid_sel.size() - 1] if not valid_sel.is_empty() else -1
		if object_tool.active:
			object_tool.set_active(true)
	if object_attributes.is_visible_in_tree():
		var refresh_views: Array[int] = []
		if not valid_sel.is_empty():
			refresh_views.assign(valid_sel)
		elif object_tool.selected >= 0:
			refresh_views.append(object_tool.selected)
		object_attributes.refresh_selection(document, refresh_views)
	var selected_key := scene_tree.selected_stable_key()
	if selected_key.begins_with("obj:") and document != null and document.view_for_object_stable_key(selected_key) < 0:
		scene_tree.clear_selection()
	scene_tree.request_rebuild()
	sync_actions()


func finish_stroke() -> void:
	if paint_view == null:
		return
	paint_view = null
	paint_hold_elapsed = 0.0
	if document.color_mask_stroke_active:
		document.end_color_mask_stroke()
		layers_panel.refresh()
		report("Color mask stroke recorded in the active layer.")
		sync_actions()
		return
	if document.color_stroke_active:
		document.end_color_stroke()
		if document.has_preview() and document.preview_owner == "color":
			workspace_state.active_preview_owner = "color"
		layers_panel.refresh()
		report("Color stroke recorded as sparse RGB samples in the active layer.")
		sync_actions()
		return
	if document.sculpt_mask_stroke_active:
		document.end_sculpt_mask_stroke()
		if document.has_preview() and document.preview_owner == "sculpt":
			workspace_state.active_preview_owner = "sculpt"
		layers_panel.refresh()
		report("Sculpt mask stroke recorded in the active layer.")
		sync_actions()
		return
	if document.sculpt_stroke_active:
		document.end_sculpt_stroke()
		if not document.has_preview():
			document.sculpt_preview()
		if document.has_preview() and document.preview_owner == "sculpt":
			workspace_state.active_preview_owner = "sculpt"
		layers_panel.refresh()
		report("Sculpt stroke recorded as sparse deltas in the active layer.")
		sync_actions()
		return
	if document.active_sculpt_uid >= 0 and document.stroke_layer == Terrain.Layer.HEIGHT and brush_panel.mode in [BrushPanel.Mode.RAISE, BrushPanel.Mode.LOWER] and not document.stroke_active:
		layers_panel.refresh()
		report("Sculpt stroke recorded as sparse deltas in the active layer.")
		sync_actions()
		return
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
	water_tools.refresh_layers()
	report("Water stroke done. Layer %d has %d block edits." % [layer + 1, document.water_edits.get(layer, {}).size()])
	sync_actions()


func painting_water_active() -> bool:
	return painting_water and workspace_state.active_tool == WorkspaceState.Tool.WATER_PAINT and document != null and water_tools.document == document


func leave_water_paint() -> void:
	if paint_view != null and document != null and document.water_stroke_active:
		finish_water_stroke()
	painting_water = false
	if water_tools != null and water_tools.paint_toggle.button_pressed:
		water_tools.paint_toggle.set_pressed_no_signal(false)
	if workspace_state.active_tool == WorkspaceState.Tool.WATER_PAINT:
		workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)


func toggle_water_edit() -> void:
	if document == null or document.package == null or document.package.water == null:
		return
	clear_incompatible_preview("water")
	water_tools.begin(document)
	if workspace_state.center_mode in [WorkspaceState.CenterMode.NODES, WorkspaceState.CenterMode.NEW_MAP, WorkspaceState.CenterMode.SETTINGS]:
		set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	workspace_state.set_inspector_context(WorkspaceState.InspectorContext.WATER, true)
	workspace_state.set_tool(WorkspaceState.Tool.WATER_PAINT)
	water_button.set_pressed_no_signal(true)
	toggle_water()
	sync_actions()


func update_water_painting() -> void:
	var want_paint := water_tools.painting() and document != null and water_tools.document == document
	if want_paint and not painting_water:
		if path_drag_view != null:
			finish_point_drag(false)
		move_path_button.set_pressed_no_signal(false)
		leave_object_tool()
		cancel_place_object(false)
		if paint_view != null:
			finish_stroke()
		workspace_state.set_tool(WorkspaceState.Tool.WATER_PAINT)
	elif not want_paint and workspace_state.active_tool == WorkspaceState.Tool.WATER_PAINT:
		workspace_state.set_tool(WorkspaceState.Tool.TERRAIN_BRUSH)
	painting_water = want_paint
	set_cursor(cursor)
	sync_actions()


func refresh_water() -> void:
	top.queue_redraw()
	scene_view.rebuild_water()
	scene_tree.rebuild()
	sync_actions()


func _exit_tree() -> void:
	if object_thread != null and object_thread.is_started():
		object_thread.wait_to_finish()
