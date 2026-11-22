extends RefCounted
## Central reactive state for the unified DCC workspace.
## Decouples active tool, inspector context, center mode, dock layout, and
## editor-only visibility from popup Windows so every tool operates docked.

enum Tool {
	TERRAIN_BRUSH,
	SLOPE,
	SHAPE,
	OBJECT_MOVE,
	OBJECT_PLACE,
	PATH_MOVE,
	WATER_PAINT,
}

enum InspectorContext {
	NONE,
	TERRAIN_BRUSH,
	SLOPE,
	SHAPE,
	OBJECT,
	OBJECT_BROWSER,
	PATH,
	MISSION,
	WATER,
	ENVIRONMENT,
	NODE,
	SOUND,
	PROJECT,
	SETTINGS,
}

enum CenterMode {
	SPLIT_3D_2D,
	VIEW_3D,
	VIEW_2D,
	NODES,
	NEW_MAP,
	SETTINGS,
}

enum LeftTab {
	SCENE,
	LAYERS,
	ASSETS,
	TOOLS,
}

enum LayoutPreset {
	DEFAULT,
	SCULPTING,
	MISSION,
	OBJECT_PLACEMENT,
	NODES,
	FULLSCREEN,
}

const PRESET_NAMES := {
	LayoutPreset.DEFAULT: "Default",
	LayoutPreset.SCULPTING: "Sculpting",
	LayoutPreset.MISSION: "Mission",
	LayoutPreset.OBJECT_PLACEMENT: "Object Placement",
	LayoutPreset.NODES: "Nodes",
	LayoutPreset.FULLSCREEN: "Fullscreen Viewport",
}

const CONTEXT_LABELS := {
	InspectorContext.NONE: "Attributes",
	InspectorContext.TERRAIN_BRUSH: "Terrain Brush",
	InspectorContext.SLOPE: "Slope Studio",
	InspectorContext.SHAPE: "Shape Terrain",
	InspectorContext.OBJECT: "Object",
	InspectorContext.OBJECT_BROWSER: "Asset Placement",
	InspectorContext.PATH: "AI Path",
	InspectorContext.MISSION: "Mission & Paths",
	InspectorContext.WATER: "Water Editor",
	InspectorContext.ENVIRONMENT: "Sky & Environment",
	InspectorContext.NODE: "Procedural Layer",
	InspectorContext.SOUND: "Sound Point",
	InspectorContext.PROJECT: "Target Profile & Mods",
	InspectorContext.SETTINGS: "Workspace & Setup",
}

const TOOL_LABELS := {
	Tool.TERRAIN_BRUSH: "Terrain Brush",
	Tool.SLOPE: "Slope Studio",
	Tool.SHAPE: "Shape Terrain",
	Tool.OBJECT_MOVE: "Move Object",
	Tool.OBJECT_PLACE: "Place Object",
	Tool.PATH_MOVE: "Move Path Points",
	Tool.WATER_PAINT: "Water Paint",
}

const DEFAULT_LEFT_WIDTH := 228
const DEFAULT_RIGHT_WIDTH := 296
const DEFAULT_SPLIT_RATIO := 0.68

signal tool_changed(tool_id: int)
signal inspector_context_changed(context_id: int)
signal center_mode_changed(mode_id: int)
signal left_tab_changed(tab_id: int)
signal preset_changed(preset_id: int)
signal pin_changed(pinned: bool)
signal layout_changed
signal selection_changed(kind: String, index: int)
signal editor_visibility_changed(channel: String, visible: bool)
signal section_toggled(section_id: String, collapsed: bool)

var active_tool: int = Tool.TERRAIN_BRUSH
var active_inspector_context: int = InspectorContext.TERRAIN_BRUSH
var pinned_inspector := false
var center_mode: int = CenterMode.SPLIT_3D_2D
var left_tab: int = LeftTab.SCENE
var active_preset: int = LayoutPreset.DEFAULT

var left_dock_visible := true
var right_dock_visible := true
var bottom_log_visible := false
var left_dock_width: int = DEFAULT_LEFT_WIDTH
var right_dock_width: int = DEFAULT_RIGHT_WIDTH
var viewport_split_ratio: float = DEFAULT_SPLIT_RATIO

var selected_object_view := -1
var selected_path_index := -1
var selected_path_point := -1
var selected_layer_index := 0
var selected_node_name := ""
var active_preview_owner := ""

var editor_visibility := {
	"objects": false,
	"paths": true,
	"water": false,
}
var collapsed_sections := {}
var _pre_fullscreen := {}


func set_tool(next_tool: int) -> void:
	if active_tool == next_tool:
		return
	active_tool = next_tool
	tool_changed.emit(active_tool)


func set_inspector_context(next_context: int, force := false) -> bool:
	if pinned_inspector and not force:
		return false
	if active_inspector_context == next_context:
		if not right_dock_visible and force:
			right_dock_visible = true
			layout_changed.emit()
		return true
	active_inspector_context = next_context
	if force and not right_dock_visible and active_preset != LayoutPreset.FULLSCREEN:
		right_dock_visible = true
		layout_changed.emit()
	inspector_context_changed.emit(active_inspector_context)
	return true


func set_pinned(on: bool) -> void:
	if pinned_inspector == on:
		return
	pinned_inspector = on
	pin_changed.emit(pinned_inspector)


func set_center_mode(next_mode: int) -> void:
	if center_mode == next_mode:
		return
	center_mode = next_mode
	center_mode_changed.emit(center_mode)


func set_left_tab(next_tab: int, ensure_visible := false) -> void:
	var changed := left_tab != next_tab
	left_tab = next_tab
	if ensure_visible and not left_dock_visible and active_preset != LayoutPreset.FULLSCREEN:
		left_dock_visible = true
		layout_changed.emit()
	if changed:
		left_tab_changed.emit(left_tab)


func set_dock_visibility(left_vis: bool, right_vis: bool, log_vis: bool = bottom_log_visible) -> void:
	if left_dock_visible == left_vis and right_dock_visible == right_vis and bottom_log_visible == log_vis:
		return
	left_dock_visible = left_vis
	right_dock_visible = right_vis
	bottom_log_visible = log_vis
	layout_changed.emit()


func set_editor_visibility(channel: String, on: bool) -> void:
	if bool(editor_visibility.get(channel, false)) == on:
		return
	editor_visibility[channel] = on
	editor_visibility_changed.emit(channel, on)


func is_section_collapsed(section_id: String, default_collapsed := false) -> bool:
	if collapsed_sections.has(section_id):
		return bool(collapsed_sections[section_id])
	return default_collapsed


func set_section_collapsed(section_id: String, collapsed: bool) -> void:
	if section_id.is_empty():
		return
	collapsed_sections[section_id] = collapsed
	section_toggled.emit(section_id, collapsed)


func select_object(view_index: int) -> void:
	selected_object_view = view_index
	selection_changed.emit("object", view_index)


func select_path(path_index: int, point_index: int = -1) -> void:
	selected_path_index = path_index
	selected_path_point = point_index
	selection_changed.emit("path", path_index)


func select_layer(layer_index: int) -> void:
	selected_layer_index = maxi(0, layer_index)
	selection_changed.emit("layer", selected_layer_index)


func apply_preset(preset_id: int) -> void:
	if preset_id == LayoutPreset.FULLSCREEN:
		if active_preset != LayoutPreset.FULLSCREEN:
			_pre_fullscreen = {
				"preset": active_preset,
				"left_visible": left_dock_visible,
				"right_visible": right_dock_visible,
				"bottom_log": bottom_log_visible,
				"center_mode": center_mode,
				"left_tab": left_tab,
			}
		active_preset = LayoutPreset.FULLSCREEN
		left_dock_visible = false
		right_dock_visible = false
		bottom_log_visible = false
		if center_mode in [CenterMode.NODES, CenterMode.NEW_MAP, CenterMode.SETTINGS]:
			center_mode = CenterMode.SPLIT_3D_2D
		preset_changed.emit(active_preset)
		center_mode_changed.emit(center_mode)
		layout_changed.emit()
		return

	if active_preset == LayoutPreset.FULLSCREEN and not _pre_fullscreen.is_empty() and preset_id == int(_pre_fullscreen.get("preset", LayoutPreset.DEFAULT)):
		left_dock_visible = bool(_pre_fullscreen.get("left_visible", true))
		right_dock_visible = bool(_pre_fullscreen.get("right_visible", true))
		bottom_log_visible = bool(_pre_fullscreen.get("bottom_log", false))
		center_mode = int(_pre_fullscreen.get("center_mode", CenterMode.SPLIT_3D_2D))
		left_tab = int(_pre_fullscreen.get("left_tab", LeftTab.SCENE))
		active_preset = preset_id
		_pre_fullscreen.clear()
		preset_changed.emit(active_preset)
		center_mode_changed.emit(center_mode)
		left_tab_changed.emit(left_tab)
		layout_changed.emit()
		return

	_pre_fullscreen.clear()
	active_preset = preset_id
	left_dock_visible = true
	right_dock_visible = true
	match preset_id:
		LayoutPreset.DEFAULT:
			left_tab = LeftTab.SCENE
			center_mode = CenterMode.SPLIT_3D_2D
			viewport_split_ratio = 0.68
		LayoutPreset.SCULPTING:
			left_tab = LeftTab.TOOLS
			center_mode = CenterMode.SPLIT_3D_2D
			viewport_split_ratio = 0.76
			set_inspector_context(InspectorContext.SLOPE, true)
		LayoutPreset.MISSION:
			left_tab = LeftTab.SCENE
			center_mode = CenterMode.SPLIT_3D_2D
			viewport_split_ratio = 0.50
			set_inspector_context(InspectorContext.MISSION, true)
		LayoutPreset.OBJECT_PLACEMENT:
			left_tab = LeftTab.ASSETS
			center_mode = CenterMode.SPLIT_3D_2D
			viewport_split_ratio = 0.74
			set_inspector_context(InspectorContext.OBJECT, true)
		LayoutPreset.NODES:
			left_tab = LeftTab.LAYERS
			center_mode = CenterMode.NODES
			set_inspector_context(InspectorContext.NODE, true)
	preset_changed.emit(active_preset)
	center_mode_changed.emit(center_mode)
	left_tab_changed.emit(left_tab)
	layout_changed.emit()


func exit_fullscreen() -> void:
	if active_preset != LayoutPreset.FULLSCREEN:
		return
	var restore_preset := int(_pre_fullscreen.get("preset", LayoutPreset.DEFAULT))
	apply_preset(restore_preset)


func clamp_to_viewport(viewport_size: Vector2) -> void:
	var total_w := maxf(640.0, viewport_size.x)
	var min_center := 320.0
	var max_side_budget := maxf(300.0, total_w - min_center)
	left_dock_width = clampi(left_dock_width, 168, int(minf(380.0, max_side_budget * 0.48)))
	right_dock_width = clampi(right_dock_width, 224, int(minf(460.0, max_side_budget * 0.56)))
	if left_dock_visible and right_dock_visible and float(left_dock_width + right_dock_width) > max_side_budget:
		var scale := max_side_budget / float(left_dock_width + right_dock_width)
		left_dock_width = maxi(168, int(floor(float(left_dock_width) * scale)))
		right_dock_width = maxi(224, int(floor(float(right_dock_width) * scale)))
	viewport_split_ratio = clampf(viewport_split_ratio, 0.25, 0.85)


func reset_layout(viewport_size: Vector2 = Vector2(1280, 720)) -> void:
	pinned_inspector = false
	left_dock_visible = true
	right_dock_visible = true
	bottom_log_visible = false
	left_dock_width = DEFAULT_LEFT_WIDTH
	right_dock_width = DEFAULT_RIGHT_WIDTH
	viewport_split_ratio = DEFAULT_SPLIT_RATIO
	active_preset = LayoutPreset.DEFAULT
	center_mode = CenterMode.SPLIT_3D_2D
	left_tab = LeftTab.SCENE
	collapsed_sections.clear()
	_pre_fullscreen.clear()
	clamp_to_viewport(viewport_size)
	pin_changed.emit(false)
	preset_changed.emit(active_preset)
	center_mode_changed.emit(center_mode)
	left_tab_changed.emit(left_tab)
	layout_changed.emit()


func save_to_config(cfg: ConfigFile) -> void:
	cfg.set_value("workspace", "left_width", left_dock_width)
	cfg.set_value("workspace", "right_width", right_dock_width)
	cfg.set_value("workspace", "split_ratio", viewport_split_ratio)
	cfg.set_value("workspace", "left_tab", left_tab)
	cfg.set_value("workspace", "center_mode", center_mode if center_mode in [CenterMode.SPLIT_3D_2D, CenterMode.VIEW_3D, CenterMode.VIEW_2D, CenterMode.NODES] else CenterMode.SPLIT_3D_2D)
	cfg.set_value("workspace", "preset", active_preset)
	cfg.set_value("workspace", "left_visible", left_dock_visible)
	cfg.set_value("workspace", "right_visible", right_dock_visible)
	cfg.set_value("workspace", "bottom_log_visible", bottom_log_visible)
	cfg.set_value("workspace", "pinned_inspector", pinned_inspector)
	cfg.set_value("workspace", "collapsed_sections", collapsed_sections.duplicate())


func load_from_config(cfg: ConfigFile, viewport_size: Vector2 = Vector2(1280, 720)) -> void:
	if not cfg.has_section("workspace"):
		clamp_to_viewport(viewport_size)
		return
	left_dock_width = int(cfg.get_value("workspace", "left_width", DEFAULT_LEFT_WIDTH))
	right_dock_width = int(cfg.get_value("workspace", "right_width", DEFAULT_RIGHT_WIDTH))
	viewport_split_ratio = float(cfg.get_value("workspace", "split_ratio", DEFAULT_SPLIT_RATIO))
	left_tab = clampi(int(cfg.get_value("workspace", "left_tab", LeftTab.SCENE)), LeftTab.SCENE, LeftTab.TOOLS)
	var saved_mode := int(cfg.get_value("workspace", "center_mode", CenterMode.SPLIT_3D_2D))
	center_mode = saved_mode if saved_mode in [CenterMode.SPLIT_3D_2D, CenterMode.VIEW_3D, CenterMode.VIEW_2D, CenterMode.NODES] else CenterMode.SPLIT_3D_2D
	var saved_preset := int(cfg.get_value("workspace", "preset", LayoutPreset.DEFAULT))
	active_preset = saved_preset if saved_preset in PRESET_NAMES.keys() else LayoutPreset.DEFAULT
	left_dock_visible = bool(cfg.get_value("workspace", "left_visible", true))
	right_dock_visible = bool(cfg.get_value("workspace", "right_visible", true))
	bottom_log_visible = bool(cfg.get_value("workspace", "bottom_log_visible", false))
	pinned_inspector = bool(cfg.get_value("workspace", "pinned_inspector", false))
	var saved_col: Variant = cfg.get_value("workspace", "collapsed_sections", {})
	if saved_col is Dictionary:
		collapsed_sections = (saved_col as Dictionary).duplicate()
	# Never strand user on a broken fullscreen-only launch with hidden docks unless explicitly Fullscreen
	if active_preset != LayoutPreset.FULLSCREEN and not left_dock_visible and not right_dock_visible:
		right_dock_visible = true
	clamp_to_viewport(viewport_size)
