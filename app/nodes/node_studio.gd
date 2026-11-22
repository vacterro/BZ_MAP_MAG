extends VBoxContainer
## Docked Procedural Node Workspace hosted in the Central Workspace "Nodes" tab.
## Central canvas holds full-size GraphEdit; layer parameters live in
## attributes_panel (hosted inside Right Attributes Inspector) and stay synced
## with the Left Dock LayersPanel and MapDocument.layers.

const Graph := preload("res://nodes/height_graph.gd")
const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

signal updated(message: String)
signal preview_display(layer: int)
signal layers_changed(selected_index: int)
signal viewport_requested
signal draft_state_changed(has_draft: bool, has_conflict: bool, detail: String)
signal preview_state_changed(active: bool)
signal conflict_diff_changed(lines: PackedStringArray)

enum DraftState { COMMITTED, DRAFT, PREVIEW, BAKED }

var document: Document
var bound_document_id := -1
var base_layer_revision := -1
var draft_revision := 0
var preview_generation := 0
var draft_state: int = DraftState.COMMITTED
var working: Array = [Graph.layer()]
var working_uids: Array[int] = [1]
var base_snapshot: Array = [Graph.layer()]
var base_uids: Array[int] = [1]
var conflict_pending := false
var conflict_reason := ""
var _next_draft_uid := -1
var selected := 0
var focus: Vector2i
var nodes := GraphEdit.new()
var layer_select := ChoiceGroup.new(0)
var enabled := CheckButton.new()
var parameters := {}
var color_parameters := {}
var range_field := SliderField.new()
var message := Label.new()
var draft_badge := Label.new()
var conflict_bar := HBoxContainer.new()
var conflict_label := Label.new()
var conflict_keep_button: Button
var conflict_committed_button: Button
var conflict_discard_button: Button
var conflict_diff_label: Label
var bake_button: Button
var preview_button: Button
var keep_button: Button
var discard_button: Button
var viewport_button: Button
var preview_channel := ChoiceGroup.new(0)
var attributes_panel := VBoxContainer.new()
var loading := false
var worker := Thread.new()
var job_graph: Graph
var generation := 0
var job_generation := -1
var job_document: Document
var job_document_id := -1
var job_revision := -1
var job_layer_revision := -1
var job_draft_revision := -1


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# Compact single-row top action strip for the central Node Graph canvas
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 4)
	add_child(actions)
	preview_button = button(actions, "Preview", preview)
	bake_button = button(actions, "Bake to Terrain", bake)
	keep_button = button(actions, "Keep Layers", keep_layers)
	discard_button = button(actions, "Discard Draft", discard_draft)
	discard_button.disabled = true
	viewport_button = button(actions, "View 3D/2D", func(): viewport_requested.emit())
	for b in [preview_button, bake_button, keep_button, discard_button, viewport_button]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	draft_badge.text = "[COMMITTED]"
	actions.add_child(draft_badge)

	# Inline non-modal conflict resolution bar (shown only on true stack conflict)
	conflict_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conflict_bar.add_theme_constant_override("separation", 6)
	conflict_bar.visible = false
	add_child(conflict_bar)
	conflict_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conflict_bar.add_child(conflict_label)
	conflict_keep_button = button(conflict_bar, "Keep Draft", func(): resolve_conflict("keep_draft"))
	conflict_committed_button = button(conflict_bar, "Keep Committed", func(): resolve_conflict("keep_committed"))
	conflict_discard_button = button(conflict_bar, "Discard Draft", func(): resolve_conflict("discard_draft"))

	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 6)
	add_child(view_row)
	label(view_row, "Preview channel:")
	for name in ["Auto", "Height", "Color", "Base tile"]:
		preview_channel.add_item(name)
	preview_channel.disabled = true
	preview_channel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_channel.item_selected.connect(func(_index): show_preview_channel())
	view_row.add_child(preview_channel)

	# Full central GraphEdit
	nodes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nodes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nodes.right_disconnects = true
	nodes.minimap_enabled = false
	nodes.snapping_enabled = false
	nodes.show_menu = false
	add_child(nodes)
	make_graph()
	nodes.connection_request.connect(connect_nodes)
	nodes.disconnection_request.connect(disconnect_nodes)

	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message.text = "Connect Height, Color or Base Tile output. Preview around the terrain cursor."
	add_child(message)

	# Build Right-Inspector Node Attributes panel (hosted in AttributesInspector)
	attributes_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attributes_panel.add_theme_constant_override("separation", 4)

	var layer_sec := CollapsibleSection.new("Active Procedural Layer", "node_layer", false)
	attributes_panel.add_child(layer_sec)
	layer_sec.add_content(layer_select)
	layer_select.item_selected.connect(load_layer)
	var lbtns := HFlowContainer.new()
	lbtns.add_theme_constant_override("h_separation", 3)
	layer_sec.add_content(lbtns)
	button(lbtns, "+ Add", add_layer)
	button(lbtns, "− Del", remove_layer)
	button(lbtns, "▲ Up", move_layer.bind(-1))
	button(lbtns, "▼ Dn", move_layer.bind(1))
	enabled.text = "Layer Enabled"
	enabled.toggled.connect(func(on): set_parameter("enabled", on))
	layer_sec.add_content(enabled)

	var noise_sec := CollapsibleSection.new("Noise & Height Range", "node_noise", false)
	attributes_panel.add_child(noise_sec)
	parameter(noise_sec.body, "Opacity", "opacity", 0, 1, 0.05)
	parameter(noise_sec.body, "Seed", "seed", 0, 999999, 1, "", 0, 9999)
	parameter(noise_sec.body, "Scale", "scale", 2, 512, 1, "m")
	parameter(noise_sec.body, "Noise", "amplitude", 0, 100, 0.5, "m")
	parameter(noise_sec.body, "Min H", "low", -3000, 3000, 1, "m", -200, 500)
	parameter(noise_sec.body, "Max H", "high", -3000, 3000, 1, "m", -200, 500)
	var rad_grp := HBoxContainer.new()
	rad_grp.add_theme_constant_override("separation", 4)
	var rad_lbl := Label.new()
	rad_lbl.text = "Radius"
	rad_lbl.custom_minimum_size.x = 76
	rad_grp.add_child(rad_lbl)
	spin(rad_grp, range_field, 32, 256, 16, "m")
	noise_sec.add_content(rad_grp)
	range_field.value = 128
	range_field.value_changed.connect(func(_value): invalidate())

	var mat_sec := CollapsibleSection.new("Vertex Color & Base Tile", "node_materials", false)
	attributes_panel.add_child(mat_sec)
	color_parameter(mat_sec.body, "RGB low", "color_low")
	color_parameter(mat_sec.body, "RGB high", "color_high")
	parameter(mat_sec.body, "Tile below", "tile_low", 0, 15, 1)
	parameter(mat_sec.body, "Tile above", "tile_high", 0, 15, 1)
	parameter(mat_sec.body, "Tile at", "tile_height", -100000, 100000, 1, "m", -200, 500)

	var mask_sec := CollapsibleSection.new("Slope & Mask", "node_masks", true)
	attributes_panel.add_child(mask_sec)
	parameter(mask_sec.body, "Slope min", "slope_low", 0, 90, 1, "°")
	parameter(mask_sec.body, "Slope max", "slope_high", 0, 90, 1, "°")
	parameter(mask_sec.body, "Mask wt", "mask_weight", 0, 1, 0.05)

	conflict_diff_label = Label.new()
	conflict_diff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conflict_diff_label.visible = false
	attributes_panel.add_child(conflict_diff_label)
	conflict_diff_changed.connect(_show_conflict_diff)


static func _normalized_stack(raw: Array) -> Array:
	var out: Array = []
	for item in raw:
		out.append(Graph.normalize_layer(item as Dictionary))
	return out


## Layer identity is part of the draft, not just layer contents. Two identical
## layers with swapped UIDs are a real edit and must arm save/recovery warnings.
static func _stacks_equal(layers_a: Array, uids_a: Array, layers_b: Array, uids_b: Array) -> bool:
	return _normalized_stack(layers_a) == _normalized_stack(layers_b) and uids_a == uids_b


func has_uncommitted_draft() -> bool:
	if document == null or bound_document_id != document.document_id:
		return false
	if conflict_pending:
		return true
	document.ensure_layer_uids()
	return not _stacks_equal(working, working_uids, document.layers, document.layer_uids)


func _reset_working_from_document(initial_layer: int = -1) -> void:
	if document == null:
		return
	document.ensure_layer_uids()
	working = _normalized_stack(document.layers)
	working_uids = document.layer_uids.duplicate()
	base_snapshot = working.duplicate(true)
	base_uids = working_uids.duplicate()
	base_layer_revision = document.layer_stack_revision
	conflict_pending = false
	conflict_reason = ""
	draft_state = DraftState.COMMITTED
	var target_layer := clampi(initial_layer if initial_layer >= 0 else selected, 0, working.size() - 1)
	_load_layer_ui(target_layer, false)
	_sync_draft_ui()


func _sync_draft_ui() -> void:
	var is_draft := has_uncommitted_draft()
	if conflict_pending:
		draft_badge.text = "[CONFLICT · DRAFT]"
		conflict_label.text = "Layer stack conflict: %s" % conflict_reason
		conflict_bar.visible = true
	else:
		conflict_bar.visible = false
		match draft_state:
			DraftState.PREVIEW:
				draft_badge.text = "[PREVIEW · DRAFT]" if is_draft else "[PREVIEW]"
			DraftState.BAKED:
				draft_badge.text = "[BAKED]"
			_:
				draft_badge.text = "[DRAFT]" if is_draft else "[COMMITTED]"
	if discard_button != null:
		discard_button.disabled = not is_draft and not conflict_pending
	if keep_button != null:
		keep_button.text = "Keep Layers *" if is_draft else "Keep Layers"
	draft_state_changed.emit(is_draft, conflict_pending, conflict_reason)


func begin(value: Document, center: Vector2i, initial_layer: int = -1) -> void:
	if value == null:
		close_studio()
		return
	var same_doc := (document == value and bound_document_id == value.document_id)
	focus = center
	if same_doc:
		if has_uncommitted_draft():
			var keep_idx := clampi(initial_layer if initial_layer >= 0 else selected, 0, working.size() - 1)
			_load_layer_ui(keep_idx, false)
			_sync_draft_ui()
			return
		if document.layer_stack_revision != base_layer_revision or _normalized_stack(working) != _normalized_stack(document.layers):
			invalidate()
			_reset_working_from_document(initial_layer)
		else:
			var target_idx := clampi(initial_layer if initial_layer >= 0 else selected, 0, working.size() - 1)
			_load_layer_ui(target_idx, false)
			_sync_draft_ui()
		return
	invalidate()
	document = value
	bound_document_id = value.document_id
	draft_revision = 0
	_reset_working_from_document(initial_layer)
	set_message("Connect Height, Color or Base Tile output. Preview around the terrain cursor.")


static func _relative_order(source: Array, reference: Array) -> Array[int]:
	var out: Array[int] = []
	for uid_v in source:
		var uid := int(uid_v)
		if reference.has(uid):
			out.append(uid)
	return out


func _raise_merge_conflict(reason: String, resolution: String) -> bool:
	if resolution == "keep_draft" or resolution == "keep_committed":
		return false
	invalidate()
	conflict_pending = true
	conflict_reason = reason
	draft_state = DraftState.DRAFT
	_sync_draft_ui()
	conflict_diff_changed.emit(build_conflict_diff())
	set_message("Conflict: %s Inspect the Node Inspector diff, then choose an action." % reason)
	return true


## Docked, non-modal conflict summary. Lists independent changes separately from
## values that need a decision, so the user can see what each resolution keeps.
func _show_conflict_diff(lines: PackedStringArray) -> void:
	if conflict_diff_label == null:
		return
	conflict_diff_label.text = "Conflict diff · %s" % (" | ".join(lines) if not lines.is_empty() else conflict_reason)
	conflict_diff_label.tooltip_text = conflict_diff_label.text
	conflict_diff_label.visible = true


func build_conflict_diff() -> PackedStringArray:
	var lines := PackedStringArray()
	if document == null:
		return lines
	document.ensure_layer_uids()
	var base_by_uid := {}
	for i in mini(base_snapshot.size(), base_uids.size()):
		base_by_uid[base_uids[i]] = base_snapshot[i]
	var doc_by_uid := {}
	for i in mini(document.layers.size(), document.layer_uids.size()):
		doc_by_uid[document.layer_uids[i]] = document.layers[i]
	var work_by_uid := {}
	for i in mini(working.size(), working_uids.size()):
		work_by_uid[working_uids[i]] = working[i]
	var uids: Array[int] = []
	for uid in base_by_uid:
		if not uids.has(int(uid)):
			uids.append(int(uid))
	for uid in doc_by_uid:
		if not uids.has(int(uid)):
			uids.append(int(uid))
	for uid in work_by_uid:
		if not uids.has(int(uid)):
			uids.append(int(uid))
	for uid in uids:
		var base: Variant = base_by_uid.get(uid, null)
		var doc: Variant = doc_by_uid.get(uid, null)
		var work: Variant = work_by_uid.get(uid, null)
		var label := "Layer %d" % (document.layer_index_by_uid(uid) + 1)
		if base == null and work != null:
			lines.append("%s · draft addition (kept by Keep Draft)" % label)
		elif doc == null and work != null:
			lines.append("%s · removed externally, edited in draft (conflict)" % label)
		elif work == null and doc != null:
			lines.append("%s · draft deletion%s" % [label, " (conflict)" if base != null and doc != base else " (independent)"])
		elif doc == null and base != null:
			lines.append("%s · removed externally (kept removed)" % label)
		elif base != null and doc is Dictionary and work is Dictionary:
			var keys := {}
			for k in (base as Dictionary).keys():
				keys[k] = true
			for k in (doc as Dictionary).keys():
				keys[k] = true
			for k in (work as Dictionary).keys():
				keys[k] = true
			for k in keys:
				var bv: Variant = (base as Dictionary).get(k, null)
				var dv: Variant = (doc as Dictionary).get(k, null)
				var wv: Variant = (work as Dictionary).get(k, null)
				if wv != bv and dv != bv and wv != dv:
					lines.append("%s · %s: draft=%s, committed=%s (conflict)" % [label, str(k), str(wv), str(dv)])
				elif wv != bv:
					lines.append("%s · %s: draft change (independent)" % [label, str(k)])
				elif dv != bv:
					lines.append("%s · %s: committed change (independent)" % [label, str(k)])
	return lines


## Controlled three-way merge by stable layer UID. `resolution` is empty for an
## automatic merge, or "keep_draft"/"keep_committed" when the user resolves an
## already-raised conflict; independent changes survive either resolution.
func sync_from_document(select_idx: int = -1, resolution: String = "") -> Dictionary:
	if document == null:
		return {"status": "noop", "reason": ""}
	document.ensure_layer_uids()
	if bound_document_id != document.document_id:
		invalidate()
		bound_document_id = document.document_id
		_reset_working_from_document(select_idx)
		return {"status": "synced", "reason": ""}

	var doc_norm := _normalized_stack(document.layers)
	var doc_uids: Array[int] = document.layer_uids.duplicate()
	if not has_uncommitted_draft() and not conflict_pending:
		if base_layer_revision == document.layer_stack_revision and _stacks_equal(working, working_uids, document.layers, document.layer_uids):
			if select_idx >= 0 and select_idx != selected:
				_load_layer_ui(clampi(select_idx, 0, working.size() - 1), false)
			return {"status": "noop", "reason": ""}
		invalidate()
		_reset_working_from_document(select_idx)
		return {"status": "synced", "reason": ""}

	var work_norm := _normalized_stack(working)
	var work_uids: Array[int] = working_uids.duplicate()
	var base_by_uid := {}
	for i in mini(base_snapshot.size(), base_uids.size()):
		base_by_uid[base_uids[i]] = base_snapshot[i]
	var work_by_uid := {}
	for i in work_uids.size():
		if work_uids[i] >= 0:
			work_by_uid[work_uids[i]] = work_norm[i]
	var doc_by_uid := {}
	for i in doc_uids.size():
		doc_by_uid[doc_uids[i]] = doc_norm[i]
	var retained_uids: Array[int] = doc_uids.duplicate()
	var active_uid := work_uids[selected] if selected >= 0 and selected < work_uids.size() else -1

	# A layer deleted in the draft stays deleted unless committed also edited it.
	for uid_v in base_by_uid:
		var uid := int(uid_v)
		if work_by_uid.has(uid) or not doc_by_uid.has(uid):
			continue
		if doc_by_uid[uid] == base_by_uid[uid]:
			retained_uids.erase(uid)
			continue
		if _raise_merge_conflict("A layer deleted in the Node Graph draft was edited externally.", resolution):
			return {"status": "conflict", "reason": conflict_reason}
		if resolution != "keep_committed":
			retained_uids.erase(uid)
		else:
			work_norm.append((doc_by_uid[uid] as Dictionary).duplicate(true))
			work_uids.append(uid)
			work_by_uid[uid] = doc_by_uid[uid]
		# keep_draft: honor the draft deletion and keep the external edit out.

	# A layer removed externally is honored unless the draft actually edited it.
	for uid_v in work_by_uid.duplicate():
		var uid := int(uid_v)
		if uid < 0 or doc_by_uid.has(uid):
			continue
		var base_item: Variant = base_by_uid.get(uid, null)
		if base_item == null or work_by_uid[uid] == base_item or resolution == "keep_committed":
			var at := work_uids.find(uid)
			if at >= 0:
				work_uids.remove_at(at)
				work_norm.remove_at(at)
			work_by_uid.erase(uid)
			retained_uids.erase(uid)
			continue
		if _raise_merge_conflict("A layer with uncommitted Node Graph edits was removed externally.", resolution):
			return {"status": "conflict", "reason": conflict_reason}
		# keep_draft: retain the edited layer and recommit it with the draft.

	# Ordering: honor a draft-only reorder; confront two incompatible reorders.
	var base_order := _relative_order(base_uids, base_uids)
	for uid_v in base_order.duplicate():
		if not retained_uids.has(int(uid_v)) or not work_by_uid.has(int(uid_v)):
			base_order.erase(uid_v)
	var draft_order := _relative_order(work_uids, base_order)
	var doc_order := _relative_order(doc_uids, base_order)
	var order_conflict := false
	if draft_order != doc_order and draft_order != base_order and doc_order != base_order:
		for i in draft_order.size():
			for j in range(i + 1, draft_order.size()):
				var a := int(draft_order[i])
				var b := int(draft_order[j])
				if doc_order.has(a) and doc_order.has(b) and doc_order.find(a) > doc_order.find(b):
					if _raise_merge_conflict("Layer order was changed in both Layers and Node Graph.", resolution):
						return {"status": "conflict", "reason": conflict_reason}
					order_conflict = true
					break
			if order_conflict:
				break
	var draft_reordered := draft_order != base_order and (doc_order == base_order or (order_conflict and resolution == "keep_draft"))

	# Field-level merge for every layer present in both committed and draft state.
	var merged_by_uid := {}
	for i in doc_uids.size():
		var uid := doc_uids[i]
		var doc_item: Dictionary = doc_norm[i]
		if not retained_uids.has(uid):
			continue
		if not work_by_uid.has(uid):
			merged_by_uid[uid] = doc_item.duplicate(true)
			continue
		var work_item: Dictionary = work_by_uid[uid]
		var base_v: Variant = base_by_uid.get(uid, null)
		if base_v == null:
			if work_item != doc_item and resolution != "keep_committed":
				if _raise_merge_conflict("Layer stack diverged without a common base snapshot.", resolution):
					return {"status": "conflict", "reason": conflict_reason}
			merged_by_uid[uid] = (work_item if resolution != "keep_committed" else doc_item).duplicate(true)
			continue
		var base_item: Dictionary = base_v
		var merged_item := base_item.duplicate(true)
		var all_keys := {}
		for k in base_item.keys():
			all_keys[k] = true
		for k in work_item.keys():
			all_keys[k] = true
		for k in doc_item.keys():
			all_keys[k] = true
		for k in all_keys:
			var bv: Variant = base_item.get(k, null)
			var wv: Variant = work_item.get(k, null)
			var dv: Variant = doc_item.get(k, null)
			var w_changed: bool = (wv != bv)
			var d_changed: bool = (dv != bv)
			if w_changed and d_changed and wv != dv:
				if _raise_merge_conflict("Both Layers and Node Graph edited '%s' on Layer %d." % [str(k), i + 1], resolution):
					return {"status": "conflict", "reason": conflict_reason}
				var chosen: Variant = dv if resolution == "keep_committed" else wv
				merged_item[k] = chosen.duplicate(true) if (chosen is Dictionary or chosen is Array) else chosen
			elif w_changed:
				merged_item[k] = wv.duplicate(true) if (wv is Dictionary or wv is Array) else wv
			elif d_changed:
				merged_item[k] = dv.duplicate(true) if (dv is Dictionary or dv is Array) else dv
			else:
				merged_item[k] = bv.duplicate(true) if (bv is Dictionary or bv is Array) else bv
		merged_by_uid[uid] = Graph.normalize_layer(merged_item)
	# Layers added only in the draft survive; draft deletions are not in work_by_uid.
	for i in work_uids.size():
		if work_uids[i] < 0:
			merged_by_uid[work_uids[i]] = work_norm[i].duplicate(true)

	var final_uids: Array[int] = []
	if draft_reordered:
		for uid_v in work_uids:
			var uid := int(uid_v)
			if merged_by_uid.has(uid) and not final_uids.has(uid):
				final_uids.append(uid)
		for uid_v in doc_uids:
			var uid := int(uid_v)
			if not merged_by_uid.has(uid) or final_uids.has(uid):
				continue
			var insert_at := 0
			for back in range(doc_uids.find(uid) - 1, -1, -1):
				var anchor := int(doc_uids[back])
				if final_uids.has(anchor):
					insert_at = final_uids.find(anchor) + 1
					break
			final_uids.insert(insert_at, uid)
	else:
		for uid_v in doc_uids:
			if merged_by_uid.has(int(uid_v)):
				final_uids.append(int(uid_v))
		for uid_v in work_uids:
			if int(uid_v) < 0 and merged_by_uid.has(int(uid_v)):
				final_uids.append(int(uid_v))
	if final_uids.size() > Graph.MAX_LAYERS:
		if _raise_merge_conflict("Merging external layers with uncommitted draft layers exceeds %d layers." % Graph.MAX_LAYERS, resolution):
			return {"status": "conflict", "reason": conflict_reason}
		while final_uids.size() > Graph.MAX_LAYERS:
			var dropped: int = final_uids.pop_back()
			merged_by_uid.erase(dropped)

	var merged_layers: Array = []
	for uid in final_uids:
		merged_layers.append(merged_by_uid[uid])
	invalidate()
	working = merged_layers
	working_uids = final_uids
	base_snapshot = doc_norm.duplicate(true)
	base_uids = doc_uids.duplicate()
	base_layer_revision = document.layer_stack_revision
	draft_revision += 1
	conflict_pending = false
	conflict_reason = ""
	draft_state = DraftState.DRAFT if has_uncommitted_draft() else DraftState.COMMITTED
	var next_sel := select_idx
	if next_sel < 0:
		var followed := working_uids.find(active_uid)
		next_sel = followed if followed >= 0 else selected
	_load_layer_ui(clampi(next_sel, 0, working.size() - 1), false)
	_sync_draft_ui()
	set_message("Preserved uncommitted Node Graph draft across layer update. Keep Layers to commit.")
	return {"status": "merged", "reason": ""}


## Conflict resolution merges independent changes before choosing sides. Keep
## Draft commits the merged working stack; Keep Committed restores the document
## stack. Neither choice throws away edits that never conflicted.
func resolve_conflict(action: String) -> bool:
	match action:
		"keep_draft", "keep_committed":
			var result := sync_from_document(selected, action)
			if result.get("status") == "conflict":
				return false
			return keep_layers()
		"discard_draft":
			discard_draft()
			return true
		"cancel":
			return false
	return false


func discard_draft() -> void:
	if document == null:
		return
	invalidate()
	draft_revision += 1
	_reset_working_from_document(selected)
	layers_changed.emit(selected)
	updated.emit("Discarded uncommitted Node Graph draft and restored committed layers.")
	set_message("Discarded draft edits. Restored committed procedural layers.")


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
	field.set_readout_width(44.0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)


func parameter(bar: Control, caption: String, key: String, minimum: float, maximum: float, step: float, unit: String = "", slider_lo: float = NAN, slider_hi: float = NAN) -> void:
	var grp := HBoxContainer.new()
	grp.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 76
	grp.add_child(lbl)
	var field := SliderField.new()
	spin(grp, field, minimum, maximum, step, unit, slider_lo, slider_hi)
	field.value_changed.connect(func(value): set_parameter(key, value))
	bar.add_child(grp)
	parameters[key] = field


func color_parameter(bar: Control, caption: String, key: String) -> void:
	var grp := HBoxContainer.new()
	grp.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = caption
	lbl.custom_minimum_size.x = 76
	grp.add_child(lbl)
	var field := ColorPickerButton.new()
	field.custom_minimum_size = Vector2(64, 22)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_load_layer_ui(index, false)


func _load_layer_ui(index: int, clear_preview_flag: bool = false) -> void:
	if clear_preview_flag:
		invalidate()
	loading = true
	if working.is_empty():
		working = [Graph.layer()]
		working_uids.clear()
		working_uids.append(_next_draft_uid)
		_next_draft_uid -= 1
	selected = clampi(index, 0, working.size() - 1)
	layer_select.clear()
	for i in working.size():
		layer_select.add_item("Layer %d" % (i + 1))
	layer_select.select(selected)
	var item: Dictionary = working[selected]
	enabled.button_pressed = item["enabled"]
	for key: String in parameters:
		parameters[key].set_value_no_signal(item[key])
	for key: String in color_parameters:
		color_parameters[key].color = Terrain.word_color(int(item[key]))
	render_connections()
	loading = false


func _mark_draft_mutated() -> void:
	draft_revision += 1
	draft_state = DraftState.DRAFT if has_uncommitted_draft() else DraftState.COMMITTED
	invalidate()
	_sync_draft_ui()


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
		_mark_draft_mutated()
	else:
		set_message(graph.error)


func disconnect_nodes(_from: StringName, _from_port: int, to: StringName, port: int) -> void:
	working[selected]["links"][String(to)][port] = ""
	render_connections()
	_mark_draft_mutated()


func add_layer() -> void:
	if working.size() < Graph.MAX_LAYERS:
		working.append(Graph.layer())
		working_uids.append(_next_draft_uid)
		_next_draft_uid -= 1
		_load_layer_ui(working.size() - 1, false)
		_mark_draft_mutated()


func remove_layer() -> void:
	if working.size() > 1:
		working.remove_at(selected)
		if selected < working_uids.size():
			working_uids.remove_at(selected)
		_load_layer_ui(mini(selected, working.size() - 1), false)
		_mark_draft_mutated()


func move_layer(direction: int) -> void:
	var next := selected + direction
	if next >= 0 and next < working.size():
		var item: Dictionary = working.pop_at(selected)
		working.insert(next, item)
		if selected < working_uids.size():
			var uid: int = working_uids.pop_at(selected)
			working_uids.insert(next, uid)
		_load_layer_ui(next, false)
		_mark_draft_mutated()


func set_parameter(key: String, value: Variant) -> void:
	if not loading and selected >= 0 and selected < working.size():
		if working[selected].get(key) == value:
			return
		working[selected][key] = value
		_mark_draft_mutated()


func invalidate() -> void:
	generation += 1
	var had_prev := (draft_state == DraftState.PREVIEW) or (document != null and document.has_preview())
	if bake_button != null:
		bake_button.disabled = true
	if preview_channel != null:
		preview_channel.disabled = true
	if document:
		document.clear_preview()
		preview_display.emit(-1)
	if draft_state == DraftState.PREVIEW:
		draft_state = DraftState.DRAFT if has_uncommitted_draft() else DraftState.COMMITTED
	if had_prev:
		preview_state_changed.emit(false)
	if worker.is_started():
		set_message("Preview discarded. Finish the current evaluation before retrying.")


func clear_preview_only() -> void:
	invalidate()
	_sync_draft_ui()


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
	job_document_id = document.document_id
	job_revision = document.edit_revision
	job_layer_revision = document.layer_stack_revision
	job_draft_revision = draft_revision
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
	if (document == null or generation != job_generation or document != job_document
		or document.document_id != job_document_id or document.edit_revision != job_revision
		or document.layer_stack_revision != job_layer_revision or draft_revision != job_draft_revision):
		return
	var materials: Dictionary = result["materials"]
	if not document.show_preview(result["heights"], materials):
		set_message(document.error)
		return
	preview_generation += 1
	draft_state = DraftState.PREVIEW
	bake_button.disabled = not document.has_preview()
	preview_channel.disabled = bake_button.disabled
	show_preview_channel()
	preview_state_changed.emit(document.has_preview())
	_sync_draft_ui()
	layers_changed.emit(selected)
	set_message("Preview: %d heights · %d colors · %d tile blocks. Switch to 3D/2D to inspect or Bake to commit." % [
		result["heights"].size(), materials[Terrain.Layer.COLOR].size(), materials[Terrain.Layer.TILES].size()])


func show_preview_channel() -> void:
	if document == null or not document.has_preview():
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


func keep_layers() -> bool:
	if document == null:
		return false
	var graph := Graph.new()
	if not graph.validate_stack(working):
		set_message(graph.error)
		return false
	if not document.replace_procedural_layers(working, selected, working_uids):
		set_message(document.error)
		return false
	document.ensure_layer_uids()
	working = _normalized_stack(document.layers)
	working_uids = document.layer_uids.duplicate()
	base_snapshot = working.duplicate(true)
	base_uids = working_uids.duplicate()
	base_layer_revision = document.layer_stack_revision
	conflict_pending = false
	conflict_reason = ""
	draft_state = DraftState.COMMITTED
	_load_layer_ui(clampi(selected, 0, working.size() - 1), false)
	_sync_draft_ui()
	layers_changed.emit(selected)
	updated.emit("Committed node stack to document history (1 undo step). Save Project to persist.")
	set_message("Layers committed to history. Terrain changes only on Bake.")
	return true


func bake() -> void:
	if document == null:
		return
	var heights := document.preview_after.size()
	var materials := document.package.terrain.material_previews
	var colors: int = materials.get(Terrain.Layer.COLOR, {}).size()
	var tiles: int = materials.get(Terrain.Layer.TILES, {}).size()
	if not document.bake_preview(working, working_uids):
		set_message(document.error)
		return
	document.ensure_layer_uids()
	working = _normalized_stack(document.layers)
	working_uids = document.layer_uids.duplicate()
	base_snapshot = working.duplicate(true)
	base_uids = working_uids.duplicate()
	base_layer_revision = document.layer_stack_revision
	conflict_pending = false
	conflict_reason = ""
	draft_state = DraftState.BAKED
	bake_button.disabled = true
	preview_channel.disabled = true
	preview_display.emit(-1)
	preview_state_changed.emit(false)
	_load_layer_ui(clampi(selected, 0, working.size() - 1), false)
	_sync_draft_ui()
	layers_changed.emit(selected)
	updated.emit("Baked %d heights · %d colors · %d tile blocks (1 atomic undo step)." % [heights, colors, tiles])


func close_studio() -> void:
	invalidate()
	document = null
	bound_document_id = -1
	base_layer_revision = -1
	conflict_pending = false
	conflict_reason = ""
	draft_state = DraftState.COMMITTED
	_sync_draft_ui()


func set_message(value: String) -> void:
	message.text = value
	message.tooltip_text = value


func _exit_tree() -> void:
	if worker.is_started():
		worker.wait_to_finish()
