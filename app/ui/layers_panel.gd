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
signal sculpt_preview_requested
signal sculpt_bake_requested

var document: Document
var selected_index := 0
var badge_label := Label.new()
var draft_banner := Label.new()
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
var sculpt_row := HFlowContainer.new()
var sculpt_add_btn := Button.new()
var sculpt_del_btn := Button.new()
var sculpt_preview_btn := Button.new()
var sculpt_bake_btn := Button.new()
var sculpt_status := Label.new()
var status_label := Label.new()
var _rebuilding := false
var _opacity_gesture_active := false
var _opacity_gesture_index := -1
var _opacity_gesture_initial := 1.0
var _opacity_preview_value := NAN


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	badge_label.text = "Non-Destructive Procedural Stack (Bakes to Native TER)"
	badge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(badge_label)

	draft_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	draft_banner.visible = false
	add_child(draft_banner)

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
	opacity_field.bind_direct_edit(
		_on_opacity_gesture_started,
		_on_opacity_preview_changed,
		_on_opacity_committed,
		_on_opacity_cancelled
	)
	opacity_field.gesture_ended.connect(_on_opacity_gesture_ended)
	opacity_field.value_changed.connect(_on_opacity_value_changed)
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

	sculpt_row.add_theme_constant_override("h_separation", 4)
	add_child(sculpt_row)
	sculpt_add_btn.text = "+ Sculpt Layer"
	sculpt_add_btn.pressed.connect(func():
		if document != null:
			document.add_sculpt_layer()
			layers_mutated.emit("Added non-destructive sculpt layer.")
	)
	sculpt_row.add_child(sculpt_add_btn)
	sculpt_del_btn.text = "− Sculpt"
	sculpt_del_btn.pressed.connect(func():
		if document != null:
			document.remove_sculpt_layer(document.sculpt_index_by_uid(document.active_sculpt_uid))
			layers_mutated.emit("Removed sculpt layer.")
	)
	sculpt_row.add_child(sculpt_del_btn)
	sculpt_preview_btn.text = "Sculpt Preview"
	sculpt_preview_btn.pressed.connect(func(): sculpt_preview_requested.emit())
	sculpt_row.add_child(sculpt_preview_btn)
	sculpt_bake_btn.text = "Sculpt Bake"
	sculpt_bake_btn.pressed.connect(func(): sculpt_bake_requested.emit())
	sculpt_row.add_child(sculpt_bake_btn)
	sculpt_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(sculpt_status)

	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Open a map to manage procedural layers."
	add_child(status_label)


func bind_document(doc: Document, active_index: int = 0) -> void:
	if _opacity_gesture_active:
		_opacity_gesture_active = false
		_opacity_gesture_index = -1
		_opacity_preview_value = NAN
		opacity_field.cancel_gesture()
	document = doc
	selected_index = active_index
	set_draft_status(false, false, "")
	refresh()


func set_draft_status(has_draft: bool, has_conflict: bool, detail: String = "") -> void:
	if has_conflict:
		draft_banner.text = detail if not detail.is_empty() else "[CONFLICT] Node Graph has uncommitted draft edits. Resolve in Nodes."
		draft_banner.visible = true
	elif has_draft:
		draft_banner.text = detail if not detail.is_empty() else "[DRAFT] Uncommitted Node Graph edits active. Use Keep Layers in Nodes to commit."
		draft_banner.visible = true
	else:
		draft_banner.text = ""
		draft_banner.visible = false


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

	document.ensure_layer_uids()
	if select_idx >= 0:
		selected_index = select_idx
	selected_index = clampi(selected_index, 0, document.layers.size() - 1)

	for i in document.layers.size():
		var item: Dictionary = document.layers[i]
		var on_str := "[ON]" if bool(item.get("enabled", true)) else "[OFF]"
		var op_val := _opacity_preview_value if (_opacity_gesture_active and i == _opacity_gesture_index and is_finite(_opacity_preview_value)) else float(item.get("opacity", 1.0))
		var pct := int(round(op_val * 100.0))
		var ch := _layer_channels(item)
		var prev_tag := " *" if (_opacity_gesture_active and i == _opacity_gesture_index) else ""
		layer_list.add_item("%s Layer %d · %d%%%s · %s" % [on_str, i + 1, pct, prev_tag, ch])
	layer_list.select(selected_index)

	var cur: Dictionary = document.layers[selected_index]
	enabled_check.disabled = false
	enabled_check.set_pressed_no_signal(bool(cur.get("enabled", true)))
	opacity_field.editable = true
	if not _opacity_gesture_active:
		opacity_field.set_value_no_signal(float(cur.get("opacity", 1.0)))

	add_btn.disabled = document.layers.size() >= Graph.MAX_LAYERS
	remove_btn.disabled = document.layers.size() <= 1
	up_btn.disabled = selected_index <= 0
	down_btn.disabled = selected_index >= document.layers.size() - 1
	edit_graph_btn.disabled = false
	preview_btn.disabled = false
	bake_btn.disabled = not document.has_preview()
	status_label.text = "%d procedural layer(s) (rev %d). Undoable stack; bakes to native TER on Bake." % [document.layers.size(), document.layer_stack_revision]
	var sculpt_count := document.sculpt_layers.size()
	sculpt_add_btn.disabled = sculpt_count >= 8
	sculpt_del_btn.disabled = sculpt_count == 0
	sculpt_preview_btn.disabled = sculpt_count == 0
	sculpt_bake_btn.disabled = not document.has_preview()
	var active_sculpt := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active_sculpt >= 0:
		var sc: Dictionary = document.sculpt_layers[active_sculpt]
		sculpt_status.text = "Sculpt layer %d/%d: %d sparse deltas · opacity %d%% · %s · edit with Raise/Lower brush, Bake to commit." % [
			active_sculpt + 1, sculpt_count, (sc["deltas"] as Dictionary).size(),
			int(round(float(sc["opacity"]) * 100.0)), "enabled" if bool(sc["enabled"]) else "disabled"]
	else:
		sculpt_status.text = "No sculpt layer. Add one, then use Raise/Lower brush; original TER stays untouched until Sculpt Bake."
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
	if _opacity_gesture_active:
		opacity_field.cancel_gesture()
	selected_index = clampi(index, 0, document.layers.size() - 1)
	refresh(selected_index)
	layer_selected.emit(selected_index)


func _on_add() -> void:
	if document == null:
		return
	if _opacity_gesture_active:
		opacity_field.cancel_gesture()
	var added_idx := document.add_procedural_layer()
	if added_idx < 0:
		status_label.text = "[ERR] " + document.error
		return
	selected_index = added_idx
	refresh(selected_index)
	layers_mutated.emit("Added procedural Layer %d." % (selected_index + 1))
	layer_selected.emit(selected_index)


func _on_remove() -> void:
	if document == null:
		return
	if _opacity_gesture_active:
		opacity_field.cancel_gesture()
	var target_sel := mini(selected_index, maxi(0, document.layers.size() - 2))
	if not document.remove_procedural_layer(selected_index):
		status_label.text = "[ERR] " + document.error
		return
	selected_index = clampi(target_sel, 0, document.layers.size() - 1)
	refresh(selected_index)
	layers_mutated.emit("Removed procedural layer (%d remaining)." % document.layers.size())
	layer_selected.emit(selected_index)


func _on_move(delta: int) -> void:
	if document == null:
		return
	if _opacity_gesture_active:
		opacity_field.cancel_gesture()
	var next := selected_index + delta
	if next < 0 or next >= document.layers.size():
		return
	if not document.move_procedural_layer(selected_index, next):
		status_label.text = "[ERR] " + document.error
		return
	selected_index = next
	refresh(selected_index)
	layers_mutated.emit("Moved procedural layer to slot %d." % (selected_index + 1))
	layer_selected.emit(selected_index)


func _on_enabled_toggled(on: bool) -> void:
	if _rebuilding or document == null or selected_index >= document.layers.size():
		return
	if not document.set_procedural_layer_enabled(selected_index, on):
		refresh(selected_index)
		status_label.text = "[ERR] " + document.error
		return
	refresh(selected_index)
	layers_mutated.emit("Layer %d %s." % [selected_index + 1, "enabled" if on else "disabled"])


func _on_opacity_gesture_started(_initial_val: float) -> void:
	if _rebuilding or document == null or selected_index < 0 or selected_index >= document.layers.size():
		return
	_opacity_gesture_active = true
	_opacity_gesture_index = selected_index
	_opacity_gesture_initial = float(document.layers[selected_index].get("opacity", 1.0))
	_opacity_preview_value = _opacity_gesture_initial


func _on_opacity_preview_changed(val: float) -> void:
	if _rebuilding or not _opacity_gesture_active or document == null:
		return
	if _opacity_gesture_index < 0 or _opacity_gesture_index >= document.layers.size():
		return
	_opacity_preview_value = clampf(val, 0.0, 1.0)
	var item: Dictionary = document.layers[_opacity_gesture_index]
	var on_str := "[ON]" if bool(item.get("enabled", true)) else "[OFF]"
	var pct := int(round(_opacity_preview_value * 100.0))
	var ch := _layer_channels(item)
	if _opacity_gesture_index < layer_list.item_count:
		layer_list.set_item_text(_opacity_gesture_index, "%s Layer %d · %d%% * · %s" % [on_str, _opacity_gesture_index + 1, pct, ch])
	status_label.text = "Previewing Layer %d opacity %d%% (release to commit, Esc to cancel)." % [_opacity_gesture_index + 1, pct]


func _on_opacity_committed(_initial_val: float, final_val: float) -> void:
	var idx := _opacity_gesture_index if _opacity_gesture_active else selected_index
	_opacity_gesture_active = false
	_opacity_gesture_index = -1
	_opacity_preview_value = NAN
	_commit_opacity(idx, final_val)


func _on_opacity_cancelled(_restored_val: float) -> void:
	var restored := _opacity_gesture_initial
	_opacity_gesture_active = false
	_opacity_gesture_index = -1
	_opacity_preview_value = NAN
	if document != null and selected_index >= 0 and selected_index < document.layers.size():
		restored = float(document.layers[selected_index].get("opacity", restored))
	_rebuilding = true
	opacity_field.set_value_no_signal(restored)
	_rebuilding = false
	refresh(selected_index)
	status_label.text = "Opacity edit cancelled (restored %.0f%%)." % (restored * 100.0)


func _on_opacity_gesture_ended(_committed: bool) -> void:
	if _opacity_gesture_active:
		_opacity_gesture_active = false
		_opacity_gesture_index = -1
		_opacity_preview_value = NAN
		refresh(selected_index)


func _on_opacity_value_changed(val: float) -> void:
	if _rebuilding or _opacity_gesture_active or opacity_field.is_gesture_active():
		return
	_commit_opacity(selected_index, val)


func _commit_opacity(idx: int, val: float) -> void:
	if document == null or idx < 0 or idx >= document.layers.size():
		return
	var clamped := clampf(val, 0.0, 1.0)
	var before := float(document.layers[idx].get("opacity", 1.0))
	if is_equal_approx(before, clamped):
		refresh(idx)
		return
	if not document.set_procedural_layer_opacity(idx, clamped):
		refresh(idx)
		status_label.text = "[ERR] " + document.error
		return
	refresh(idx)
	layers_mutated.emit("Layer %d opacity %.0f%%." % [idx + 1, clamped * 100.0])
