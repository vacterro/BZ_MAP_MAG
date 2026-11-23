extends VBoxContainer
## Left-dock Procedural Layers Manager bound directly to MapDocument.layers
## and synchronized with NodeStudio. Never creates a second independent stack.

const Document := preload("res://core/map_document.gd")
const Graph := preload("res://nodes/height_graph.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

signal layer_selected(index: int)
signal edit_graph_requested(index: int)
signal preview_requested
signal bake_requested
signal layers_mutated(message: String)
signal sculpt_preview_requested
signal sculpt_bake_requested
signal color_layers_mutated(message: String)

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
var sculpt_list := ItemList.new()
var sculpt_rename := LineEdit.new()
var sculpt_up_btn := Button.new()
var sculpt_down_btn := Button.new()
var sculpt_opacity := SliderField.new()
var sculpt_visible := CheckBox.new()
var sculpt_mask_btn := Button.new()
var sculpt_mask_enabled := CheckBox.new()
var color_section: CollapsibleSection
var color_list := ItemList.new()
var color_add_btn := Button.new()
var color_del_btn := Button.new()
var color_up_btn := Button.new()
var color_down_btn := Button.new()
var color_visible := CheckBox.new()
var color_opacity := SliderField.new()
var color_mask_btn := Button.new()
var color_mask_enabled := CheckBox.new()
var color_rename := LineEdit.new()
var color_status := Label.new()
var status_label := Label.new()
var _rebuilding := false
var _opacity_gesture_active := false
var _opacity_gesture_index := -1
var _opacity_gesture_initial := 1.0
var _opacity_preview_value := NAN
var _sculpt_opacity_gesture_active := false
var _sculpt_opacity_gesture_uid := -1
var _sculpt_opacity_initial := 1.0
var _color_opacity_gesture_active := false
var _color_opacity_gesture_uid := -1


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

	var sculpt_header := Label.new()
	sculpt_header.text = "Sculpt Layers (non-destructive)"
	add_child(sculpt_header)
	sculpt_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sculpt_list.custom_minimum_size.y = 64
	sculpt_list.item_selected.connect(_on_sculpt_selected)
	sculpt_list.item_activated.connect(_on_sculpt_activated)
	add_child(sculpt_list)
	sculpt_rename.placeholder_text = "Double-click layer to rename"
	sculpt_rename.editable = false
	sculpt_rename.text_submitted.connect(_on_sculpt_rename_submitted)
	sculpt_rename.focus_exited.connect(_on_sculpt_rename_focus_exit)
	add_child(sculpt_rename)
	var sculpt_move_row := HFlowContainer.new()
	sculpt_move_row.add_theme_constant_override("h_separation", 4)
	sculpt_up_btn.text = "▲ Sculpt Up"
	sculpt_up_btn.pressed.connect(func(): _on_sculpt_move(-1))
	sculpt_move_row.add_child(sculpt_up_btn)
	sculpt_down_btn.text = "▼ Sculpt Dn"
	sculpt_down_btn.pressed.connect(func(): _on_sculpt_move(1))
	sculpt_move_row.add_child(sculpt_down_btn)
	add_child(sculpt_move_row)
	var sculpt_op_row := HBoxContainer.new()
	sculpt_op_row.add_theme_constant_override("separation", 4)
	add_child(sculpt_op_row)
	sculpt_visible.text = "Visible"
	sculpt_visible.toggled.connect(_on_sculpt_visible_toggled)
	sculpt_op_row.add_child(sculpt_visible)
	var sculpt_op_lbl := Label.new()
	sculpt_op_lbl.text = "Opacity"
	sculpt_op_lbl.custom_minimum_size.x = 44
	sculpt_op_row.add_child(sculpt_op_lbl)
	sculpt_opacity.min_value = 0.0
	sculpt_opacity.max_value = 1.0
	sculpt_opacity.step = 0.05
	sculpt_opacity.set_readout_width(40.0)
	sculpt_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sculpt_opacity.bind_direct_edit(
		_on_sculpt_opacity_gesture_started,
		_on_sculpt_opacity_preview_changed,
		_on_sculpt_opacity_committed,
		_on_sculpt_opacity_cancelled
	)
	sculpt_opacity.gesture_ended.connect(_on_sculpt_opacity_gesture_ended)
	sculpt_op_row.add_child(sculpt_opacity)
	var sculpt_mask_row := HBoxContainer.new()
	sculpt_mask_row.add_theme_constant_override("separation", 4)
	sculpt_mask_btn.text = "+ Mask"
	sculpt_mask_btn.pressed.connect(_on_sculpt_mask_toggled)
	sculpt_mask_row.add_child(sculpt_mask_btn)
	sculpt_mask_enabled.text = "Mask On"
	sculpt_mask_enabled.toggled.connect(_on_sculpt_mask_enabled_toggled)
	sculpt_mask_row.add_child(sculpt_mask_enabled)
	add_child(sculpt_mask_row)

	color_section = CollapsibleSection.new("Color Layers (non-destructive RGB)", "color-layers", true)
	add_child(color_section)
	color_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_list.custom_minimum_size.y = 56
	color_list.item_selected.connect(_on_color_selected)
	color_section.add_content(color_list)
	color_rename.placeholder_text = "Double-click layer to rename"
	color_rename.editable = false
	color_rename.text_submitted.connect(_on_color_rename_submitted)
	color_section.add_content(color_rename)
	var color_actions := HFlowContainer.new()
	color_actions.add_theme_constant_override("h_separation", 4)
	for spec in [
		[color_add_btn, "+ Color", _on_color_add],
		[color_del_btn, "− Color", _on_color_remove],
		[color_up_btn, "▲ Color", func(): _on_color_move(-1)],
		[color_down_btn, "▼ Color", func(): _on_color_move(1)],
	]:
		var btn: Button = spec[0]
		btn.text = spec[1]
		btn.pressed.connect(spec[2])
		color_actions.add_child(btn)
	color_section.add_content(color_actions)
	var color_op_row := HBoxContainer.new()
	color_op_row.add_theme_constant_override("separation", 4)
	color_visible.text = "Visible"
	color_visible.toggled.connect(_on_color_visible_toggled)
	color_op_row.add_child(color_visible)
	var color_op_lbl := Label.new()
	color_op_lbl.text = "Opacity"
	color_op_lbl.custom_minimum_size.x = 44
	color_op_row.add_child(color_op_lbl)
	color_opacity.min_value = 0.0
	color_opacity.max_value = 1.0
	color_opacity.step = 0.05
	color_opacity.set_readout_width(40.0)
	color_opacity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_opacity.bind_direct_edit(
		_on_color_opacity_gesture_started,
		_on_color_opacity_preview_changed,
		_on_color_opacity_committed,
		_on_color_opacity_cancelled
	)
	color_opacity.gesture_ended.connect(_on_color_opacity_gesture_ended)
	color_op_row.add_child(color_opacity)
	color_section.add_content(color_op_row)
	var color_mask_row := HBoxContainer.new()
	color_mask_row.add_theme_constant_override("separation", 4)
	color_mask_btn.text = "+ Mask"
	color_mask_btn.pressed.connect(_on_color_mask_toggled)
	color_mask_row.add_child(color_mask_btn)
	color_mask_enabled.text = "Mask On"
	color_mask_enabled.toggled.connect(_on_color_mask_enabled_toggled)
	color_mask_row.add_child(color_mask_enabled)
	color_section.add_content(color_mask_row)
	color_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	color_section.add_content(color_status)

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
	if _sculpt_opacity_gesture_active:
		_sculpt_opacity_gesture_active = false
		_sculpt_opacity_gesture_uid = -1
		if document != null:
			document.cancel_sculpt_opacity_preview()
		sculpt_opacity.cancel_gesture()
	if _color_opacity_gesture_active:
		_color_opacity_gesture_active = false
		_color_opacity_gesture_uid = -1
		if document != null:
			document.cancel_color_opacity_preview()
		color_opacity.cancel_gesture()
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
		color_add_btn.disabled = true
		color_del_btn.disabled = true
		color_up_btn.disabled = true
		color_down_btn.disabled = true
		color_visible.disabled = true
		color_opacity.editable = false
		color_status.text = ""
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
	sculpt_bake_btn.disabled = not document.has_preview() or document.preview_owner != "sculpt"
	var active_sculpt := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active_sculpt >= 0:
		var sc: Dictionary = document.sculpt_layers[active_sculpt]
		var mask_data: Variant = sc.get("mask", null)
		var mask_text := "no mask"
		if mask_data is Dictionary:
			var mask: Dictionary = mask_data
			var sample_count := int((mask["samples"] as Dictionary).size())
			mask_text = "mask %s default %d%% · %d overrides" % [
				"on" if bool(mask["enabled"]) else "off",
				int(round(float(mask["default"]) * 100.0)), sample_count]
		var mode_text := " · MASK PAINTING" if document.sculpt_mask_stroke_active else ""
		sculpt_status.text = "Sculpt layer %d/%d: %d deltas · opacity %d%% · %s · %s%s" % [
			active_sculpt + 1, sculpt_count, (sc["deltas"] as Dictionary).size(),
			int(round(float(sc["opacity"]) * 100.0)), "enabled" if bool(sc["enabled"]) else "disabled",
			mask_text, mode_text]
	else:
		sculpt_status.text = "No sculpt layer. Add one, then use Raise/Lower brush; original TER stays untouched until Sculpt Bake."
	_refresh_sculpt_list()
	_refresh_color_list()
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


func _refresh_sculpt_list() -> void:
	sculpt_list.clear()
	if document == null:
		sculpt_visible.disabled = true
		sculpt_opacity.editable = false
		return
	for i in document.sculpt_layers.size():
		var sc: Dictionary = document.sculpt_layers[i]
		var label := "%s · %d samples · %d%%%s" % [
			String(sc.get("name", "Sculpt %d" % (i + 1))),
			(sc["deltas"] as Dictionary).size(),
			int(round(float(sc["opacity"]) * 100.0)),
			"" if bool(sc["enabled"]) else " · hidden"]
		sculpt_list.add_item(label)
		if int(sc["uid"]) == document.active_sculpt_uid:
			sculpt_list.select(i)
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	sculpt_rename.editable = active >= 0
	if active >= 0 and not sculpt_rename.has_focus():
		sculpt_rename.text = String((document.sculpt_layers[active] as Dictionary).get("name", ""))
	sculpt_up_btn.disabled = active <= 0
	sculpt_down_btn.disabled = active < 0 or active >= document.sculpt_layers.size() - 1
	sculpt_visible.disabled = active < 0
	sculpt_opacity.editable = active >= 0
	sculpt_mask_btn.disabled = active < 0
	sculpt_mask_enabled.disabled = active < 0
	if active >= 0:
		var cur: Dictionary = document.sculpt_layers[active]
		sculpt_visible.set_pressed_no_signal(bool(cur["enabled"]))
		if not _sculpt_opacity_gesture_active:
			sculpt_opacity.set_value_no_signal(float(cur["opacity"]))
		var mask_data: Variant = cur.get("mask", null)
		sculpt_mask_btn.text = "− Mask" if mask_data != null else "+ Mask"
		sculpt_mask_enabled.disabled = mask_data == null
		sculpt_mask_enabled.set_pressed_no_signal(mask_data != null and bool((mask_data as Dictionary)["enabled"]))


func _on_sculpt_selected(index: int) -> void:
	if _rebuilding or document == null or index < 0 or index >= document.sculpt_layers.size():
		return
	if document.set_active_sculpt_layer(index):
		refresh()
		layers_mutated.emit("Active sculpt layer selected.")


func _on_sculpt_visible_toggled(on: bool) -> void:
	if _rebuilding or document == null:
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active >= 0 and document.set_sculpt_layer_enabled(active, on):
		refresh()
		layers_mutated.emit("Sculpt layer visibility changed.")


func _on_sculpt_mask_toggled() -> void:
	if document == null:
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active < 0:
		return
	var has_mask: bool = (document.sculpt_layers[active] as Dictionary).get("mask", null) != null
	var ok := document.remove_sculpt_mask(active) if has_mask else document.add_sculpt_mask(active, 0.0)
	if not ok:
		sculpt_status.text = "[ERR] " + document.error
	refresh()
	layers_mutated.emit("Sculpt mask toggled.")


func _on_sculpt_mask_enabled_toggled(on: bool) -> void:
	if _rebuilding or document == null:
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active >= 0 and document.set_sculpt_mask_enabled(active, on):
		refresh()
		layers_mutated.emit("Sculpt mask visibility changed.")


func _on_sculpt_opacity_gesture_started(_initial: float) -> void:
	if _rebuilding or document == null:
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active < 0:
		_cancel_sculpt_opacity_gesture_admission("Select a valid sculpt layer before changing opacity.")
		return
	if not document.begin_sculpt_opacity_preview(active):
		_cancel_sculpt_opacity_gesture_admission(document.error)
		return
	_sculpt_opacity_gesture_active = true
	_sculpt_opacity_gesture_uid = int((document.sculpt_layers[active] as Dictionary)["uid"])
	_sculpt_opacity_initial = float((document.sculpt_layers[active] as Dictionary)["opacity"])


func _cancel_sculpt_opacity_gesture_admission(reason: String) -> void:
	if sculpt_opacity.is_gesture_active():
		sculpt_opacity.cancel_gesture()
	var detail := reason if not reason.is_empty() else "Sculpt opacity gesture refused."
	sculpt_status.text = "[ERR] " + detail


func _on_sculpt_opacity_preview_changed(value: float) -> void:
	if _rebuilding or not _sculpt_opacity_gesture_active or document == null:
		return
	var value_clamped := clampf(value, 0.0, 1.0)
	if not document.preview_sculpt_layer_opacity(_sculpt_opacity_gesture_uid, value_clamped):
		_cancel_sculpt_opacity_gesture_admission("Document refused the sculpt opacity preview.")
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active >= 0 and active < sculpt_list.item_count:
		var sc: Dictionary = document.sculpt_layers[active]
		var label := "%s · %d samples · %d%% *%s" % [
			String(sc.get("name", "Sculpt %d" % (active + 1))),
			(sc["deltas"] as Dictionary).size(),
			int(round(value_clamped * 100.0)),
			"" if bool(sc["enabled"]) else " · hidden"]
		sculpt_list.set_item_text(active, label)
	sculpt_status.text = "Previewing sculpt opacity %d%% (release to commit, Esc to cancel)." % int(round(value_clamped * 100.0))


func _on_sculpt_opacity_committed(_initial: float, final_val: float) -> void:
	if not _sculpt_opacity_gesture_active or document == null:
		return
	var uid := _sculpt_opacity_gesture_uid
	_sculpt_opacity_gesture_active = false
	_sculpt_opacity_gesture_uid = -1
	if not document.commit_sculpt_opacity_preview(uid, clampf(final_val, 0.0, 1.0)):
		refresh()
		return
	refresh()


func _on_sculpt_opacity_cancelled(_restored: float) -> void:
	if not _sculpt_opacity_gesture_active:
		return
	_sculpt_opacity_gesture_active = false
	var uid := _sculpt_opacity_gesture_uid
	_sculpt_opacity_gesture_uid = -1
	if document != null:
		document.cancel_sculpt_opacity_preview(uid)
	refresh()


## SliderField emits gesture_ended for zero-change gestures too; commit and
## cancel callbacks do not. Close the document-level preview here so a click
## with no movement cannot leave opacity gesture state armed.
func _on_sculpt_opacity_gesture_ended(_committed: bool) -> void:
	if not _sculpt_opacity_gesture_active or document == null:
		return
	_sculpt_opacity_gesture_active = false
	var uid := _sculpt_opacity_gesture_uid
	_sculpt_opacity_gesture_uid = -1
	document.cancel_sculpt_opacity_preview(uid)
	refresh()


func _on_sculpt_activated(index: int) -> void:
	if _rebuilding or document == null or index < 0 or index >= document.sculpt_layers.size():
		return
	_on_sculpt_selected(index)
	sculpt_rename.text = String((document.sculpt_layers[index] as Dictionary).get("name", ""))
	sculpt_rename.grab_focus()
	sculpt_rename.select_all()


func _on_sculpt_rename_submitted(text: String) -> void:
	if document == null:
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	if active < 0:
		return
	if String((document.sculpt_layers[active] as Dictionary).get("name", "")) != text.strip_edges():
		if not document.rename_sculpt_layer(active, text):
			sculpt_status.text = "[ERR] " + document.error
	refresh()


func _on_sculpt_rename_focus_exit() -> void:
	_on_sculpt_rename_submitted(sculpt_rename.text)


func _on_sculpt_move(delta: int) -> void:
	if document == null:
		return
	var active := document.sculpt_index_by_uid(document.active_sculpt_uid)
	var target := active + delta
	if active < 0 or target < 0 or target >= document.sculpt_layers.size():
		return
	if not document.move_sculpt_layer(active, target):
		sculpt_status.text = "[ERR] " + document.error
		return
	refresh()


func _refresh_color_list() -> void:
	color_list.clear()
	if document == null:
		color_visible.disabled = true
		color_opacity.editable = false
		return
	for i in document.color_layers.size():
		var layer: Dictionary = document.color_layers[i]
		var opacity := float(layer.get("opacity", 1.0))
		if _color_opacity_gesture_active and int(layer["uid"]) == _color_opacity_gesture_uid:
			opacity = float(color_opacity.value)
		var label := "%s Color %d · %d samples · %d%%%s" % [
			"[ON]" if bool(layer.get("enabled", true)) else "[OFF]",
			i + 1, (layer["samples"] as Dictionary).size(),
			int(round(opacity * 100.0)),
			"" if bool(layer.get("enabled", true)) else " · hidden"]
		color_list.add_item(label)
		if int(layer["uid"]) == document.active_color_uid:
			color_list.select(i)
	var active := document.color_index_by_uid(document.active_color_uid)
	color_rename.editable = active >= 0
	if active >= 0 and not color_rename.has_focus():
		color_rename.text = String((document.color_layers[active] as Dictionary).get("name", ""))
	color_add_btn.disabled = document.color_layers.size() >= 8
	color_del_btn.disabled = active < 0
	color_up_btn.disabled = active <= 0
	color_down_btn.disabled = active < 0 or active >= document.color_layers.size() - 1
	color_visible.disabled = active < 0
	color_opacity.editable = active >= 0
	color_mask_btn.disabled = active < 0
	color_mask_enabled.disabled = active < 0
	if active >= 0:
		var cur: Dictionary = document.color_layers[active]
		var mask_data: Variant = cur.get("mask", null)
		color_mask_btn.text = "− Mask" if mask_data != null else "+ Mask"
		color_mask_enabled.disabled = mask_data == null
		color_mask_enabled.set_pressed_no_signal(mask_data != null and bool((mask_data as Dictionary)["enabled"]))
		color_visible.set_pressed_no_signal(bool(cur["enabled"]))
		if not _color_opacity_gesture_active:
			color_opacity.set_value_no_signal(float(cur["opacity"]))
		color_status.text = "Color layer %d/%d: %d sparse RGB samples · %d%% · paint with Color Brush, export composes RGB." % [
			active + 1, document.color_layers.size(), (cur["samples"] as Dictionary).size(),
			int(round(float(cur["opacity"]) * 100.0))]
	else:
		color_status.text = "No color layer. Add one, then select Color Brush; native RGB stays untouched."


func _on_color_add() -> void:
	if document == null or document.add_color_layer() < 0:
		return
	refresh()
	color_layers_mutated.emit("Color layer added.")


func _on_color_remove() -> void:
	if document == null or document.active_color_uid < 0:
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	if document.remove_color_layer(active):
		refresh()
		color_layers_mutated.emit("Color layer removed.")


func _on_color_selected(index: int) -> void:
	if _rebuilding or document == null or index < 0 or index >= document.color_layers.size():
		return
	if document.set_active_color_layer(index):
		refresh()
		color_layers_mutated.emit("Active color layer selected.")


func _on_color_visible_toggled(on: bool) -> void:
	if _rebuilding or document == null:
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	if active < 0 or not document.set_color_layer_enabled(active, on):
		return
	refresh()
	color_layers_mutated.emit("Color layer visibility changed.")


func _on_color_mask_toggled() -> void:
	if document == null:
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	if active < 0:
		return
	var has_mask: bool = (document.color_layers[active] as Dictionary).get("mask", null) != null
	var ok := document.remove_color_mask(active) if has_mask else document.add_color_mask(active, 0.0)
	if not ok:
		color_status.text = "[ERR] " + document.error
	refresh()
	color_layers_mutated.emit("Color mask toggled.")


func _on_color_mask_enabled_toggled(on: bool) -> void:
	if _rebuilding or document == null:
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	if active < 0:
		return
	if not document.set_color_mask_enabled(active, on):
		color_status.text = "[ERR] " + document.error
	refresh()
	color_layers_mutated.emit("Color mask visibility changed.")


func _on_color_opacity_gesture_started(_initial: float) -> void:
	if document == null:
		color_opacity.cancel_gesture()
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	if active < 0 or not document.begin_color_opacity_preview(active):
		color_opacity.cancel_gesture()
		return
	_color_opacity_gesture_active = true
	_color_opacity_gesture_uid = document.active_color_uid


func _on_color_opacity_preview_changed(value: float) -> void:
	if not _color_opacity_gesture_active or document == null:
		return
	if not document.preview_color_layer_opacity(_color_opacity_gesture_uid, value):
		_color_opacity_gesture_active = false
		_color_opacity_gesture_uid = -1
		document.cancel_color_opacity_preview()
		color_opacity.cancel_gesture()
		return
	_refresh_color_list()


func _on_color_opacity_committed(_initial: float, value: float) -> void:
	if not _color_opacity_gesture_active or document == null:
		return
	var uid := _color_opacity_gesture_uid
	_color_opacity_gesture_active = false
	_color_opacity_gesture_uid = -1
	if document.commit_color_opacity_preview(uid, value):
		color_layers_mutated.emit("Color layer opacity committed.")
	refresh()


func _on_color_opacity_cancelled(_restored: float) -> void:
	if not _color_opacity_gesture_active or document == null:
		return
	var uid := _color_opacity_gesture_uid
	_color_opacity_gesture_active = false
	_color_opacity_gesture_uid = -1
	document.cancel_color_opacity_preview(uid)
	refresh()


## SliderField emits gesture_ended for zero-change gestures too; commit and
## cancel callbacks do not. Close the document-level preview here so a click
## with no movement cannot leave opacity gesture state armed.
func _on_color_opacity_gesture_ended(_committed: bool) -> void:
	if not _color_opacity_gesture_active or document == null:
		return
	_color_opacity_gesture_active = false
	var uid := _color_opacity_gesture_uid
	_color_opacity_gesture_uid = -1
	document.cancel_color_opacity_preview(uid)
	refresh()


func _on_color_rename_submitted(text: String) -> void:
	if document == null:
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	if active >= 0 and document.rename_color_layer(active, text):
		refresh()
		color_layers_mutated.emit("Color layer renamed.")


func _on_color_move(delta: int) -> void:
	if document == null:
		return
	var active := document.color_index_by_uid(document.active_color_uid)
	var target := active + delta
	if active < 0 or target < 0 or target >= document.color_layers.size():
		return
	if not document.move_color_layer(active, target):
		return
	refresh()
	color_layers_mutated.emit("Color layer reordered.")
