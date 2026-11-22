extends VBoxContainer
## Left-dock categorized Tools palette (Cinema 4D / Photoshop style).
## Clicking any tool activates it in the docked Attributes Inspector or Center mode.

signal tool_action_triggered(action_id: String)

var buttons: Dictionary = {} # action_id -> Button
var _built := false


func _ready() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)

	_add_group(body, "Terrain Sculpting", [
		["terrain_brush", "Terrain Brush", "Paint height, vertex color or base tile IDs (Alt+H)"],
		["slope_studio", "Slope Studio", "Exact-angle ramps, terraces, ridges, trenches in Attributes"],
		["shape_terrain", "Shape Terrain", "Slope plane, height mirror and VRV Smooth/Rough/Relief"],
		["nodes", "Procedural Nodes", "Open full-canvas Node Graph workspace"],
	])
	_add_group(body, "Objects & Assets", [
		["move_object", "Move / Edit Object", "Select, move, rotate, duplicate or label native BZN objects"],
		["object_browser", "Object Browser", "Browse mod ODF catalog and place verified native objects"],
		["sound_editor", "Sound Point", "Edit structured VRV sound points (vrv_sndpoint)"],
	])
	_add_group(body, "Mission & AI Paths", [
		["move_path", "Move Path Points", "Drag AI path points in 2D/3D (Shift+click appends)"],
		["path_inspector", "Path Inspector", "Edit selected AI path name, type and point coordinates"],
		["new_path", "New AI Path", "Create a new native BZN AI path at terrain cursor"],
		["mission_studio", "Mission Studio", "Mission profiles, required paths, batch transforms & validation"],
	])
	_add_group(body, "World & Atmosphere", [
		["water_editor", "Water Editor", "Paint native water coverage and edit layer elevations"],
		["environment", "Sky & Environment", "Inspect .SKY/.TRN and edit verified 1YKS fog & lighting"],
	])
	_add_group(body, "Project & Workspace", [
		["target_profile", "Target Profile & Mods", "Switch Stock/VSR/VRV/Custom profile or analyze conversion"],
		["new_map", "New Map", "Create a new Stock/VSR/VRV/Custom map inside workspace"],
		["settings", "Settings & Theme", "Game/VRV folders, Wintage theme and layout reset"],
	])


func _add_group(parent: Control, heading: String, items: Array) -> void:
	var lbl := Label.new()
	lbl.text = heading
	parent.add_child(lbl)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	for entry in items:
		var aid: String = entry[0]
		var btn := Button.new()
		btn.text = entry[1]
		btn.tooltip_text = entry[2]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): tool_action_triggered.emit(aid))
		grid.add_child(btn)
		buttons[aid] = btn


func set_active_action(action_id: String) -> void:
	for aid: String in buttons:
		(buttons[aid] as Button).set_pressed_no_signal(aid == action_id)


func set_map_loaded(loaded: bool, has_water: bool = false, has_objects: bool = false, can_resize_paths: bool = false) -> void:
	var always_on := ["new_map", "settings", "target_profile"]
	for aid: String in buttons:
		var btn: Button = buttons[aid]
		if aid in always_on:
			btn.disabled = false
		elif aid == "water_editor":
			btn.disabled = not loaded or not has_water
		elif aid in ["move_object", "sound_editor"]:
			btn.disabled = not loaded or not has_objects
		elif aid == "new_path":
			btn.disabled = not loaded or not can_resize_paths
		else:
			btn.disabled = not loaded
