extends VBoxContainer
## Left-dock Procedural Layers Manager bound directly to MapDocument.layers
## and synchronized with NodeStudio. Never creates a second independent stack.

const Document := preload("res://core/map_document.gd")
const Graph := preload("res://nodes/height_graph.gd")
const SliderField := preload("res://themes/slider_field.gd")

signal layer_selected(index: int)
signal edit_graph_requested(index: int)
signal preview_requested
signal bake_requested
signal layers_mutated(message: String)

var document: Document
var selected_index := 0
var badge_label := Label.new()
var layer_list := ItemList.new()
var add_btn := Button.new()
var remove_btn := Button.new()
var up_btn := Button.new()
var down_btn := Button.new()
var enabled_check := CheckBox.new()
var opacity_field := SliderField.new()
var edit_graph_btn := Button.new()
var preview_btn := Button.new()
var bake_btn := Button.new()
var status_label := Label.new()
var _rebuilding := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	badge_label.text = "Non-Destructive Procedural Stack (Bakes to Native TER)"
	badge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(badge_label)

	var op_row := HFlowContainer.new()
	op_row.add_theme_constant_override("h_separation", 3)
	op_row.add_theme_constant_override("v_separation", 3)
	add_child(op_row)
	for spec in [
		[add_btn, "+ Add", _on_add],
		[remove_btn, "− Del", _on_remove],
		[up_btn, "▲ Up", func(): _on_move(-1)],
		[down_btn, "▼ Dn", func(): _on_move(1)],
	]:
		var btn: Button = spec[0]
		btn.text = spec[1]
		btn.pressed.connect(spec[2])
		op_row.add_child(btn)

	layer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layer_list.custom_minimum_size.y = 120
	layer_list.item_selected.connect(_on_select)
	layer_list.item_activated.connect(func(idx: int): edit_graph_requested.emit(idx))
	add_child(layer_list)

	enabled_check.text = "Layer Enabled (Included in Stack Evaluation)"
	enabled_check.toggled.connect(_on_enabled_toggled)
	add_child(enabled_check)

	var op_val_row := HBoxContainer.new()
	op_val_row.add_theme_constant_override("separation", 4)
	add_child(op_val_row)
	var op_lbl := Label.new()
	op_lbl.text = "Opacity"
	op_lbl.custom_minimum_size.x = 54
	op_val_row.add_child(op_lbl)
	opacity_field.min_value = 0.0
	opacity_field.max_value = 1.0
	opacity_field.step = 0.05
	opacity_field.set_readout_width(40.0)
	opacity_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opacity_field.value_changed.connect(_on_opacity_changed)
	op_val_row.add_child(opacity_field)

	var act_row := HFlowContainer.new()
	act_row.add_theme_constant_override("h_separation", 4)
	act_row.add_theme_constant_override("v_separation", 3)
	add_child(act_row)
	edit_graph_btn.text = "Edit Graph"
	edit_graph_btn.pressed.connect(func(): edit_graph_requested.emit(selected_index))
	act_row.add_child(edit_graph_btn)
	preview_btn.text = "Preview"
	preview_btn.pressed.connect(func(): preview_requested.emit())
	act_row.add_child(preview_btn)
	bake_btn.text = "Bake"
	bake_btn.pressed.connect(func(): bake_requested.emit())
	act_row.add_child(bake_btn)

	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Open a map to manage procedural layers."
	add_child(status_label)


func bind_document(doc: Document, active_index: int = 0) -> void:
	document = doc
	selected_index = active_index
	refresh()


func refresh(select_idx: int = -1) -> void:
	_rebuilding = true
	layer_list.clear()
	if document == null:
		add_btn.disabled = true
		remove_btn.disabled = true
		up_btn.disabled = true
		down_btn.disabled = true
		enabled_check.disabled = true
		opacity_field.editable = false
		edit_graph_btn.disabled = true
		preview_btn.disabled = true
		bake_btn.disabled = true
		status_label.text = "Open a map to manage procedural layers."
		_rebuilding = false
		return

	if document.layers.is_empty():
		document.layers.append(Graph.layer())
	if select_idx >= 0:
		selected_index = select_idx
	selected_index = clampi(selected_index, 0, document.layers.size() - 1)

	for i in document.layers.size():
		var item: Dictionary = document.layers[i]
		var on_str := "[ON]" if bool(item.get("enabled", true)) else "[OFF]"
		var pct := int(round(float(item.get("opacity", 1.0)) * 100.0))
		var ch := _layer_channels(item)
		layer_list.add_item("%s Layer %d · %d%% · %s" % [on_str, i + 1, pct, ch])
	layer_list.select(selected_index)

	var cur: Dictionary = document.layers[selected_index]
	enabled_check.disabled = false
	enabled_check.set_pressed_no_signal(bool(cur.get("enabled", true)))
	opacity_field.editable = true
	opacity_field.set_value_no_signal(float(cur.get("opacity", 1.0)))

	add_btn.disabled = document.layers.size() >= Graph.MAX_LAYERS
	remove_btn.disabled = document.layers.size() <= 1
	up_btn.disabled = selected_index <= 0
	down_btn.disabled = selected_index >= document.layers.size() - 1
	edit_graph_btn.disabled = false
	preview_btn.disabled = false
	bake_btn.disabled = not document.has_preview()
	status_label.text = "%d procedural layer(s). Changes evaluate on Preview and commit on Bake." % document.layers.size()
	_rebuilding = false


static func _layer_channels(item: Dictionary) -> String:
	var links: Dictionary = item.get("links", {})
	var tags: Array[String] = []
	var h_links: Array = links.get(Graph.OUTPUT, [])
	if not h_links.is_empty() and not String(h_links[0]).is_empty():
		tags.append("H")
	var c_links: Array = links.get(Graph.COLOR_OUTPUT, [])
	if not c_links.is_empty() and not String(c_links[0]).is_empty():
		tags.append("C")
	var t_links: Array = links.get(Graph.TILE_OUTPUT, [])
	if not t_links.is_empty() and not String(t_links[0]).is_empty():
		tags.append("T")
	return "/".join(tags) if not tags.is_empty() else "unlinked"


func _on_select(index: int) -> void:
	if _rebuilding or document == null:
		return
	selected_index = clampi(index, 0, document.layers.size() - 1)
	refresh(selected_index)
	layer_selected.emit(selected_index)


func _on_add() -> void:
	if document == null or document.layers.size() >= Graph.MAX_LAYERS:
		return
	document.layers.append(Graph.layer())
	selected_index = document.layers.size() - 1
	refresh(selected_index)
	layers_mutated.emit("Added procedural Layer %d." % (selected_index + 1))
	layer_selected.emit(selected_index)


func _on_remove() -> void:
	if document == null or document.layers.size() <= 1:
		return
	document.layers.remove_at(selected_index)
	selected_index = mini(selected_index, document.layers.size() - 1)
	refresh(selected_index)
	layers_mutated.emit("Removed procedural layer (%d remaining)." % document.layers.size())
	layer_selected.emit(selected_index)


func _on_move(delta: int) -> void:
	if document == null:
		return
	var next := selected_index + delta
	if next < 0 or next >= document.layers.size():
		return
	var item: Dictionary = document.layers.pop_at(selected_index)
	document.layers.insert(next, item)
	selected_index = next
	refresh(selected_index)
	layers_mutated.emit("Moved procedural layer to slot %d." % (selected_index + 1))
	layer_selected.emit(selected_index)


func _on_enabled_toggled(on: bool) -> void:
	if _rebuilding or document == null or selected_index >= document.layers.size():
		return
	document.layers[selected_index]["enabled"] = on
	refresh(selected_index)
	layers_mutated.emit("Layer %d %s." % [selected_index + 1, "enabled" if on else "disabled"])


func _on_opacity_changed(val: float) -> void:
	if _rebuilding or document == null or selected_index >= document.layers.size():
		return
	document.layers[selected_index]["opacity"] = clampf(val, 0.0, 1.0)
	refresh(selected_index)
	layers_mutated.emit("Layer %d opacity %.0f%%." % [selected_index + 1, val * 100.0])
