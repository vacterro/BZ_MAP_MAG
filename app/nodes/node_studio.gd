extends Window

const Graph := preload("res://nodes/height_graph.gd")
const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")

signal updated(message: String)
signal preview_display(layer: int)

var document: Document
var working: Array
var selected := 0
var focus: Vector2i
var nodes := GraphEdit.new()
var layer_select := ChoiceGroup.new(0)
var enabled := CheckButton.new()
var parameters := {}
var color_parameters := {}
var range_field := SliderField.new()
var message := Label.new()
var bake_button: Button
var preview_button: Button
var keep_button: Button
var preview_channel := ChoiceGroup.new(0)
var loading := false
var worker := Thread.new()
var job_graph: Graph
var generation := 0
var job_generation := -1
var job_document: Document
var job_revision := -1


func _ready() -> void:
	title = "Terrain Layers and Nodes"
	transient = true
	exclusive = true
	unresizable = false
	min_size = Vector2i(600, 390)
	size = Vector2i(720, 480)
	close_requested.connect(close_studio)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	layout.add_theme_constant_override("separation", 3)
	add_child(layout)
	var layers_bar := HBoxContainer.new()
	layers_bar.add_theme_constant_override("separation", 4)
	layout.add_child(layers_bar)
	layers_bar.add_child(layer_select)
	layer_select.item_selected.connect(load_layer)
	button(layers_bar, "Add", add_layer)
	button(layers_bar, "Remove", remove_layer)
	button(layers_bar, "Move up", move_layer.bind(-1))
	button(layers_bar, "Move down", move_layer.bind(1))
	enabled.text = "Visible"
	layers_bar.add_child(enabled)
	enabled.toggled.connect(func(on): set_parameter("enabled", on))
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 4)
	bar.add_theme_constant_override("v_separation", 2)
	layout.add_child(bar)
	parameter(bar, "Opacity", "opacity", 0, 1, 0.05)
	parameter(bar, "Seed", "seed", 0, 999999, 1, "", 0, 9999)
	parameter(bar, "Scale", "scale", 2, 512, 1, "m")
	parameter(bar, "Noise", "amplitude", 0, 100, 0.5, "m")
	var limits := HFlowContainer.new()
	limits.add_theme_constant_override("h_separation", 4)
	limits.add_theme_constant_override("v_separation", 2)
	layout.add_child(limits)
	parameter(limits, "Min", "low", -3000, 3000, 1, "m", -200, 500)
	parameter(limits, "Max", "high", -3000, 3000, 1, "m", -200, 500)
	var rad_grp := HBoxContainer.new()
	rad_grp.add_theme_constant_override("separation", 3)
	label(rad_grp, "Radius")
	spin(rad_grp, range_field, 32, 256, 16, "m")
	limits.add_child(rad_grp)
	range_field.value = 128
	range_field.value_changed.connect(func(_value): invalidate())
	var materials := HFlowContainer.new()
	materials.add_theme_constant_override("h_separation", 4)
	materials.add_theme_constant_override("v_separation", 2)
	layout.add_child(materials)
	color_parameter(materials, "RGB low", "color_low")
	color_parameter(materials, "RGB high", "color_high")
	parameter(materials, "Tile below", "tile_low", 0, 15, 1)
	parameter(materials, "Tile above", "tile_high", 0, 15, 1)
	parameter(materials, "At", "tile_height", -100000, 100000, 1, "m", -200, 500)
	var masks := HFlowContainer.new()
	masks.add_theme_constant_override("h_separation", 4)
	masks.add_theme_constant_override("v_separation", 2)
	layout.add_child(masks)
	parameter(masks, "Slope min", "slope_low", 0, 90, 1, "°")
	parameter(masks, "Slope max", "slope_high", 0, 90, 1, "°")
	parameter(masks, "Mask weight", "mask_weight", 0, 1, 0.05)
	nodes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nodes.right_disconnects = true
	nodes.minimap_enabled = false
	nodes.snapping_enabled = false
	nodes.show_menu = false
	layout.add_child(nodes)
	make_graph()
	nodes.connection_request.connect(connect_nodes)
	nodes.disconnection_request.connect(disconnect_nodes)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	layout.add_child(actions)
	preview_button = button(actions, "Preview", preview)
	bake_button = button(actions, "Bake to Terrain", bake)
	keep_button = button(actions, "Keep Layers", keep_layers)
	button(actions, "Close", close_studio)
	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 6)
	layout.add_child(view_row)
	label(view_row, "Preview view:")
	for name in ["Automatic view", "Height view", "Color view", "Base tile view"]:
		preview_channel.add_item(name)
	preview_channel.disabled = true
	preview_channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_channel.item_selected.connect(func(_index): show_preview_channel())
	view_row.add_child(preview_channel)
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	layout.add_child(message)


func begin(value: Document, center: Vector2i) -> void:
	invalidate()
	document = value
	focus = center
	working = document.layers.duplicate(true)
	load_layer(0)
	set_message("Connect Height, Color or Base Tile output. Preview around the terrain cursor.")
	popup_centered()


func button(parent: Control, caption: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(action)
	parent.add_child(control)
	return control


func label(parent: Control, caption: String) -> void:
	var control := Label.new()
	control.text = caption
	parent.add_child(control)


func spin(parent: Control, field: SliderField, minimum: float, maximum: float, step: float, unit: String = "", slider_lo: float = NAN, slider_hi: float = NAN) -> void:
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	if is_finite(slider_lo) and is_finite(slider_hi):
		field.set_slider_range(slider_lo, slider_hi)
	if not unit.is_empty():
		field.set_unit_suffix(unit)
	field.set_readout_width(42.0)
	field.custom_minimum_size.x = 100
	parent.add_child(field)


func parameter(bar: Control, caption: String, key: String, minimum: float, maximum: float, step: float, unit: String = "", slider_lo: float = NAN, slider_hi: float = NAN) -> void:
	var grp := HBoxContainer.new()
	grp.add_theme_constant_override("separation", 3)
	label(grp, caption)
	var field := SliderField.new()
	spin(grp, field, minimum, maximum, step, unit, slider_lo, slider_hi)
	field.value_changed.connect(func(value): set_parameter(key, value))
	bar.add_child(grp)
	parameters[key] = field


func color_parameter(bar: Control, caption: String, key: String) -> void:
	var grp := HBoxContainer.new()
	grp.add_theme_constant_override("separation", 3)
	label(grp, caption)
	var field := ColorPickerButton.new()
	field.custom_minimum_size = Vector2(34, 20)
	field.edit_alpha = false
	field.color_changed.connect(func(color: Color): set_parameter(key, Terrain.rgb_word(color)))
	grp.add_child(field)
	bar.add_child(grp)
	color_parameters[key] = field


func make_graph() -> void:
	var positions := {
		Graph.INPUT: Vector2(30, 32), Graph.NOISE: Vector2(30, 134),
		Graph.BLEND: Vector2(170, 54), Graph.CLAMP: Vector2(313, 55), Graph.OUTPUT: Vector2(475, 55),
		Graph.COLOR_RAMP: Vector2(170, 173), Graph.COLOR_BLEND: Vector2(325, 193), Graph.COLOR_OUTPUT: Vector2(475, 193),
		Graph.EXISTING_COLOR: Vector2(30, 230), Graph.SLOPE: Vector2(30, 326), Graph.SLOPE_MASK: Vector2(170, 326),
		Graph.MASK: Vector2(30, 418), Graph.HEIGHT_MASK: Vector2(170, 418),
		Graph.EXISTING_TILE: Vector2(30, 510), Graph.THRESHOLD: Vector2(170, 510),
		Graph.TILE_SELECT: Vector2(325, 510), Graph.TILE_OUTPUT: Vector2(475, 510)
	}
	var inks := [Color("#F0D060"), Color("#008080"), Color("#D4C89A"), Color("#9C9371"), Color("#AAD9CB"), Color("#E6A871")]
	var types := ["Height", "Noise Δ", "RGB", "Tile ID", "Slope °", "Mask"]
	for name: String in Graph.NODE_NAMES:
		var node := GraphNode.new()
		node.name = name
		node.title = {Graph.INPUT: "Height", Graph.OUTPUT: "Height Output", Graph.TILE_OUTPUT: "Base Tile Output"}.get(name, name)
		node.custom_minimum_size.x = 100
		node.position_offset = positions[name]
		var inputs: Array = Graph.PORTS[name]
		var output := Graph.output_type(name)
		for row in maxi(1, inputs.size()):
			var input_type: int = inputs[row] if not inputs.is_empty() else output
			var description: String = types[input_type]
			if name == Graph.COLOR_BLEND and row < 2:
				description = ["Base RGB", "Paint RGB"][row]
			var has_output := row == 0 and name not in Graph.OUTPUT_NODES
			if has_output and input_type != output:
				description += " → " + types[output]
			label(node, description)
			node.set_slot(row, not inputs.is_empty(), input_type, inks[input_type], has_output, output, inks[output])
		nodes.add_child(node)


func load_layer(index: int) -> void:
	invalidate()
	loading = true
	selected = index
	layer_select.clear()
	for i in working.size():
		layer_select.add_item("Layer %d" % (i + 1))
	layer_select.select(selected)
	var item: Dictionary = working[selected]
	enabled.button_pressed = item["enabled"]
	for key: String in parameters:
		parameters[key].value = item[key]
	for key: String in color_parameters:
		color_parameters[key].color = Terrain.word_color(int(item[key]))
	render_connections()
	loading = false


func render_connections() -> void:
	nodes.clear_connections()
	var links: Dictionary = working[selected]["links"]
	for to: String in links:
		for port in links[to].size():
			var source: String = links[to][port]
			if source != "":
				nodes.connect_node(source, 0, to, port)


func connect_nodes(from: StringName, _from_port: int, to: StringName, port: int) -> void:
	var links: Dictionary = working[selected]["links"].duplicate(true)
	links[String(to)][port] = String(from)
	var graph := Graph.new()
	if graph.validate_links(links, true):
		working[selected]["links"] = links
		render_connections()
		invalidate()
	else:
		set_message(graph.error)


func disconnect_nodes(_from: StringName, _from_port: int, to: StringName, port: int) -> void:
	working[selected]["links"][String(to)][port] = ""
	render_connections()
	invalidate()


func add_layer() -> void:
	if working.size() < Graph.MAX_LAYERS:
		working.append(Graph.layer())
		load_layer(working.size() - 1)


func remove_layer() -> void:
	if working.size() > 1:
		working.remove_at(selected)
		load_layer(mini(selected, working.size() - 1))


func move_layer(direction: int) -> void:
	var next := selected + direction
	if next >= 0 and next < working.size():
		var item: Dictionary = working.pop_at(selected)
		working.insert(next, item)
		load_layer(next)


func set_parameter(key: String, value: Variant) -> void:
	if not loading:
		working[selected][key] = value
		invalidate()


func invalidate() -> void:
	generation += 1
	bake_button.disabled = true
	preview_channel.disabled = true
	if document:
		document.clear_preview()
		preview_display.emit(-1)
	if worker.is_started():
		set_message("Preview discarded. Finish the current evaluation before retrying.")


func preview() -> void:
	if worker.is_started() or document == null or document.stroke_active:
		return
	invalidate()
	var preview_graph := Graph.new()
	if not preview_graph.validate_stack(working):
		set_message(preview_graph.error)
		return
	var terrain := document.package.terrain
	var surface := preview_graph.material_snapshot(working, terrain, focus, range_field.value)
	var job := preview_graph.compute_channels.bind(working.duplicate(true), terrain.heights.duplicate(),
		terrain.dimensions, terrain.origin, focus, range_field.value, document.package.granularity, surface)
	if worker.start(job) != OK:
		set_message("Unable to start the preview worker.")
		return
	job_generation = generation
	job_graph = preview_graph
	job_document = document
	job_revision = document.edit_revision
	preview_button.disabled = true
	set_message("Evaluating preview…")


func _process(_delta: float) -> void:
	if worker.is_started() and not worker.is_alive():
		var result: Variant = worker.wait_to_finish()
		job_graph = null
		preview_button.disabled = false
		if result is Dictionary:
			accept_preview(result)
		job_document = null


func accept_preview(result: Dictionary) -> void:
	if not visible or generation != job_generation or document != job_document or document.edit_revision != job_revision:
		return
	var materials: Dictionary = result["materials"]
	if not document.show_preview(result["heights"], materials):
		set_message(document.error)
		return
	bake_button.disabled = not document.has_preview()
	preview_channel.disabled = bake_button.disabled
	show_preview_channel()
	set_message("Preview: %d heights · %d colors · %d tile blocks. Bake to commit." % [
		result["heights"].size(), materials[Terrain.Layer.COLOR].size(), materials[Terrain.Layer.TILES].size()])


func show_preview_channel() -> void:
	if not document.has_preview():
		return
	var layer := Terrain.Layer.HEIGHT
	if preview_channel.selected > 0:
		layer = [Terrain.Layer.HEIGHT, Terrain.Layer.COLOR, Terrain.Layer.TILES][preview_channel.selected - 1]
	else:
		var materials := document.package.terrain.material_previews
		if materials.has(Terrain.Layer.COLOR):
			layer = Terrain.Layer.COLOR
		elif materials.has(Terrain.Layer.TILES):
			layer = Terrain.Layer.TILES
	preview_display.emit(layer)


func keep_layers() -> void:
	var graph := Graph.new()
	if not graph.validate_stack(working):
		set_message(graph.error)
		return
	document.layers = working.map(Graph.normalize_layer)
	updated.emit("Saved node settings in the document. Save Project to persist them.")
	set_message("Keeping layer settings. Terrain changes only on Bake.")


func bake() -> void:
	var heights := document.preview_after.size()
	var materials := document.package.terrain.material_previews
	var colors: int = materials.get(Terrain.Layer.COLOR, {}).size()
	var tiles: int = materials.get(Terrain.Layer.TILES, {}).size()
	if not document.bake_preview():
		set_message(document.error)
		return
	keep_layers()
	bake_button.disabled = true
	preview_channel.disabled = true
	preview_display.emit(-1)
	updated.emit("Baked %d heights · %d colors · %d tile blocks." % [heights, colors, tiles])
	hide()


func close_studio() -> void:
	invalidate()
	document = null
	hide()


func set_message(value: String) -> void:
	message.text = value
	message.tooltip_text = value


func _exit_tree() -> void:
	if worker.is_started():
		worker.wait_to_finish()
