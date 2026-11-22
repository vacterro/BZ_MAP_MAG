extends VBoxContainer
## Left-dock Scene Tree bound directly to MapDocument.
## Provides real navigation (Terrain, Procedural Layers, Objects by team,
## Paths, Water, Environment) and editor-only viewport visibility toggles.

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")

signal item_selected_kind(kind: String, index: int)
signal item_activated_kind(kind: String, index: int)
signal objects_selected(views: Array[int])
signal visibility_toggled(channel: String, visible: bool)

var document: Document
var filter_box := LineEdit.new()
var vis_objects_btn := Button.new()
var vis_paths_btn := Button.new()
var vis_water_btn := Button.new()
var tree := Tree.new()
var summary_label := Label.new()
var _rebuilding := false
var _rebuild_pending := false
var _selected_meta: Dictionary = {}
var _selected_keys: Array[String] = []
var _expanded_keys: Dictionary = {} # stable_key -> bool (true = expanded)
var _pre_filter_expanded: Dictionary = {}
var _filter_active := false
var _items_by_key: Dictionary = {}
var _bound_document_id := -1


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)

	var vis_bar := HBoxContainer.new()
	vis_bar.add_theme_constant_override("separation", 3)
	add_child(vis_bar)

	var vis_lbl := Label.new()
	vis_lbl.text = "View:"
	vis_lbl.tooltip_text = "Editor-only viewport visibility (never alters native BZN/WAT files)"
	vis_bar.add_child(vis_lbl)

	for spec in [
		[vis_objects_btn, "Obj", "objects", "Show/hide 3D native object models (editor-only; never removes BZN objects)"],
		[vis_paths_btn, "Path", "paths", "Show/hide AI path overlay in viewports (editor-only)"],
		[vis_water_btn, "Wat", "water", "Show/hide native water preview in viewports (editor-only)"],
	]:
		var btn: Button = spec[0]
		var ch: String = spec[2]
		btn.text = spec[1]
		btn.tooltip_text = spec[3]
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggled.connect(func(on: bool):
			if not _rebuilding:
				visibility_toggled.emit(ch, on))
		vis_bar.add_child(btn)
	vis_paths_btn.set_pressed_no_signal(true)

	filter_box.placeholder_text = "Filter scene…"
	filter_box.text_changed.connect(func(_t: String): rebuild())
	add_child(filter_box)

	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.hide_root = false
	tree.select_mode = Tree.SELECT_MULTI
	tree.item_selected.connect(_on_item_selected)
	tree.multi_selected.connect(_on_multi_selected)
	tree.item_activated.connect(_on_item_activated)
	tree.item_collapsed.connect(_on_item_collapsed)
	add_child(tree)

	summary_label.text = "No map loaded"
	summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(summary_label)


func bind_document(doc: Document) -> void:
	var next_id := doc.document_id if doc != null else -1
	if next_id != _bound_document_id:
		_bound_document_id = next_id
		_expanded_keys.clear()
		_pre_filter_expanded.clear()
		_selected_meta = {}
		_selected_keys.clear()
		_filter_active = false
	document = doc
	rebuild()


func sync_visibility_buttons(obj_vis: bool, path_vis: bool, wat_vis: bool) -> void:
	_rebuilding = true
	vis_objects_btn.set_pressed_no_signal(obj_vis)
	vis_paths_btn.set_pressed_no_signal(path_vis)
	vis_water_btn.set_pressed_no_signal(wat_vis)
	_rebuilding = false


func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_flush_rebuild")


func _flush_rebuild() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	rebuild()


func _capture_scroll() -> Vector2:
	var pos := tree.get_scroll()
	for child in tree.get_children(true):
		if child is HScrollBar:
			pos.x = (child as HScrollBar).value
		elif child is VScrollBar:
			pos.y = (child as VScrollBar).value
	return pos


func _restore_scroll(pos: Vector2) -> void:
	for child in tree.get_children(true):
		if child is HScrollBar:
			var hsb: HScrollBar = child
			hsb.value = clampf(pos.x, hsb.min_value, maxf(hsb.min_value, hsb.max_value))
		elif child is VScrollBar:
			var vsb: VScrollBar = child
			vsb.value = clampf(pos.y, vsb.min_value, maxf(vsb.min_value, vsb.max_value))


func _snapshot_tree_state() -> void:
	var root := tree.get_root()
	if root == null:
		return
	if not _filter_active:
		_snapshot_branch_recursive(root)
	var live_keys: Array[String] = []
	var sel := tree.get_next_selected(null)
	while sel != null:
		var meta: Variant = sel.get_metadata(0)
		if meta is Dictionary:
			var key := String((meta as Dictionary).get("key", ""))
			if not key.is_empty():
				live_keys.append(key)
		sel = tree.get_next_selected(sel)
	if not live_keys.is_empty():
		_selected_keys = live_keys
	elif _selected_meta.has("key") and not String(_selected_meta["key"]).is_empty():
		var fallback_key := String(_selected_meta["key"])
		if _selected_keys.is_empty():
			_selected_keys = [fallback_key]


func _snapshot_branch_recursive(item: TreeItem) -> void:
	if item.get_first_child() != null:
		var meta: Variant = item.get_metadata(0)
		if meta is Dictionary:
			var key := String((meta as Dictionary).get("key", ""))
			if not key.is_empty():
				_expanded_keys[key] = not item.collapsed
	var child := item.get_first_child()
	while child != null:
		_snapshot_branch_recursive(child)
		child = child.get_next()


func _apply_branch_collapse(item: TreeItem, key: String, default_collapsed: bool, filtering: bool) -> void:
	if filtering:
		item.collapsed = false
	elif _expanded_keys.has(key):
		item.collapsed = not bool(_expanded_keys[key])
	else:
		item.collapsed = default_collapsed


func _register_item(item: TreeItem, kind: String, index: int, key: String) -> void:
	item.set_metadata(0, {"kind": kind, "index": index, "key": key})
	if not key.is_empty():
		_items_by_key[key] = item


func rebuild() -> void:
	_rebuild_pending = false
	var saved_scroll := _capture_scroll()
	var had_focus := tree.has_focus()
	_snapshot_tree_state()

	_rebuilding = true
	tree.clear()
	_items_by_key.clear()
	if document == null or document.package == null:
		summary_label.text = "Open or create a map"
		var empty_root := tree.create_item()
		empty_root.set_text(0, "No Map Loaded")
		_register_item(empty_root, "none", -1, "none")
		_selected_meta = {}
		_selected_keys.clear()
		_rebuilding = false
		return

	var needle := filter_box.text.strip_edges().to_lower()
	var filtering := not needle.is_empty()
	if filtering and not _filter_active:
		_pre_filter_expanded = _expanded_keys.duplicate()
		_filter_active = true
	elif not filtering and _filter_active:
		_expanded_keys = _pre_filter_expanded.duplicate()
		_pre_filter_expanded.clear()
		_filter_active = false

	var terrain := document.package.terrain
	var root := tree.create_item()
	root.set_text(0, "%s (%s · BZN %d)" % [document.package.mission_name, document.mod_profile, document.package.bzn_version])
	_register_item(root, "project", 0, "project:%d" % document.document_id)

	# Terrain node
	var terrain_item := tree.create_item(root)
	terrain_item.set_text(0, "Terrain (%d×%d m)" % [terrain.dimensions.x * 2, terrain.dimensions.y * 2])
	_register_item(terrain_item, "terrain", Terrain.Layer.HEIGHT, "terrain")
	var h_item := tree.create_item(terrain_item)
	h_item.set_text(0, "Height (%d edits)" % document.edits.size())
	_register_item(h_item, "terrain_channel", Terrain.Layer.HEIGHT, "terrain_channel:%d" % Terrain.Layer.HEIGHT)
	var c_item := tree.create_item(terrain_item)
	c_item.set_text(0, "Vertex Color (%d edits)" % terrain.color_edits.size())
	_register_item(c_item, "terrain_channel", Terrain.Layer.COLOR, "terrain_channel:%d" % Terrain.Layer.COLOR)
	var t_item := tree.create_item(terrain_item)
	t_item.set_text(0, "Tiles / Materials (%d edits)" % terrain.tile_edits.size())
	_register_item(t_item, "terrain_channel", Terrain.Layer.TILES, "terrain_channel:%d" % Terrain.Layer.TILES)
	_apply_branch_collapse(terrain_item, "terrain", true, filtering)

	# Procedural Layers node (stable UID identity)
	document.ensure_layer_uids()
	var layers_item := tree.create_item(root)
	layers_item.set_text(0, "Procedural Layers (%d)" % document.layers.size())
	_register_item(layers_item, "layers", 0, "layers")
	for li in document.layers.size():
		var layer_d: Dictionary = document.layers[li]
		var on_tag := "ON" if bool(layer_d.get("enabled", true)) else "OFF"
		var ltxt := "Layer %d [%s · %d%%]" % [li + 1, on_tag, int(round(float(layer_d.get("opacity", 1.0)) * 100.0))]
		if needle.is_empty() or ltxt.to_lower().contains(needle):
			var child := tree.create_item(layers_item)
			child.set_text(0, ltxt)
			_register_item(child, "layer", li, "layer:%d" % document.layer_uid(li))
	_apply_branch_collapse(layers_item, "layers", true, filtering)

	# Objects grouped by Team (O(N) via object_entries() + entry helpers)
	var entries := document.object_entries()
	var obj_count := entries.size()
	var objects_item := tree.create_item(root)
	objects_item.set_text(0, "Objects (%d)" % obj_count)
	_register_item(objects_item, "objects_group", -1, "objects_group")
	var by_team := {}
	for v in obj_count:
		var entry: Dictionary = entries[v]
		var team := document.object_team_for_entry(entry)
		if not by_team.has(team):
			by_team[team] = []
		(by_team[team] as Array).append(v)
	var team_ids: Array = by_team.keys()
	team_ids.sort()
	for tid_v in team_ids:
		var tid := int(tid_v)
		var views: Array = by_team[tid]
		var matched: Array[int] = []
		for v_v in views:
			var v := int(v_v)
			var entry: Dictionary = entries[v]
			var odf := document.object_odf_for_entry(entry)
			var lbl := document.object_label_for_entry(entry)
			var entry_txt := "#%d %s%s" % [v, odf, (" · " + lbl) if not lbl.is_empty() else ""]
			if needle.is_empty() or entry_txt.to_lower().contains(needle):
				matched.append(v)
		if matched.is_empty() and not needle.is_empty():
			continue
		var team_key := "objects_team:%d" % tid
		var team_item := tree.create_item(objects_item)
		team_item.set_text(0, "Team %d (%d)" % [tid, matched.size()])
		_register_item(team_item, "objects_group", tid, team_key)
		# A native BZN can hold more objects than one team's display cap. Added
		# objects must stay selectable from the Scene Tree even past the cap, or
		# a freshly duplicated object cannot be selected or deleted by the user.
		var limit := mini(matched.size(), 1024)
		for i in limit:
			var v := matched[i]
			var entry: Dictionary = entries[v]
			var odf := document.object_odf_for_entry(entry)
			var lbl := document.object_label_for_entry(entry)
			var okey := document.object_stable_key_for_entry(entry)
			var oitem := tree.create_item(team_item)
			oitem.set_text(0, "#%d %s%s" % [v, odf, (" · " + lbl) if not lbl.is_empty() else ""])
			_register_item(oitem, "object", v, okey)
		if matched.size() > limit:
			var more := tree.create_item(team_item)
			more.set_text(0, "… +%d more (filter to narrow)" % (matched.size() - limit))
			_register_item(more, "objects_group", tid, "objects_team_more:%d" % tid)
		_apply_branch_collapse(team_item, team_key, matched.size() > 16, filtering)
	_apply_branch_collapse(objects_item, "objects_group", obj_count > 32, filtering)

	# Paths (stable native path ID)
	var p_indices := document.path_indices()
	var paths_item := tree.create_item(root)
	paths_item.set_text(0, "Paths (%d)" % p_indices.size())
	_register_item(paths_item, "mission", -1, "paths")
	for pidx in p_indices:
		var p: Dictionary = document.path_at(pidx)
		var pname := String(p.get("name", ""))
		var pts: PackedVector2Array = p.get("points", PackedVector2Array())
		var ptxt := "%s (%d pts)" % [pname, pts.size()]
		if needle.is_empty() or ptxt.to_lower().contains(needle):
			var pitem := tree.create_item(paths_item)
			pitem.set_text(0, ptxt)
			_register_item(pitem, "path", pidx, "path:%d" % int(p.get("id", pidx)))
	_apply_branch_collapse(paths_item, "paths", p_indices.size() > 12, filtering)

	# Water
	var water_item := tree.create_item(root)
	var wat_layers := document.water_layers_effective().size() if document.package.water != null else 0
	water_item.set_text(0, "Water (%d active layers)" % wat_layers if document.package.water != null else "Water (absent)")
	_register_item(water_item, "water", 0, "water")

	# Environment
	var env_item := tree.create_item(root)
	var sky_name := document.package.sky_name if not document.package.sky_name.is_empty() else "(no .SKY)"
	var sky_cap := String(document.package.sky_env.get("capability", "READ_ONLY"))
	env_item.set_text(0, "Environment (%s · %s)" % [sky_name, sky_cap])
	_register_item(env_item, "environment", 0, "environment")

	# Restore valid selection(s) by stable key without dangling stale selection
	var surviving_keys: Array[String] = []
	var last_restored_meta: Dictionary = {}
	for key in _selected_keys:
		if _items_by_key.has(key):
			var target: TreeItem = _items_by_key[key]
			if target != null:
				target.select(0)
				surviving_keys.append(key)
				var m: Variant = target.get_metadata(0)
				if m is Dictionary:
					last_restored_meta = m
	_selected_keys = surviving_keys
	_selected_meta = last_restored_meta

	summary_label.text = "%d obj · %d paths · %d layers" % [obj_count, p_indices.size(), document.layers.size()]
	_rebuilding = false

	_restore_scroll(saved_scroll)
	call_deferred("_restore_scroll", saved_scroll)
	if had_focus and tree.is_visible_in_tree():
		tree.grab_focus()


func is_branch_expanded(key: String) -> bool:
	if _items_by_key.has(key):
		return not (_items_by_key[key] as TreeItem).collapsed
	return bool(_expanded_keys.get(key, false))


func set_branch_expanded(key: String, expanded: bool) -> void:
	_expanded_keys[key] = expanded
	if _items_by_key.has(key):
		_rebuilding = true
		(_items_by_key[key] as TreeItem).collapsed = not expanded
		_rebuilding = false


func selected_stable_key() -> String:
	return String(_selected_meta.get("key", ""))


func selected_object_views() -> Array[int]:
	var out: Array[int] = []
	var sel := tree.get_next_selected(null)
	while sel != null:
		var meta: Variant = sel.get_metadata(0)
		if meta is Dictionary and String((meta as Dictionary).get("kind", "")) == "object":
			out.append(int((meta as Dictionary).get("index", -1)))
		sel = tree.get_next_selected(sel)
	return out


func select_entry(kind: String, index: int) -> void:
	if tree.get_root() == null:
		return
	var target: TreeItem = null
	if kind == "object" and document != null and document.valid_view_object(index):
		var okey := document.object_stable_key(index)
		target = _items_by_key.get(okey, null)
	elif kind == "layer" and document != null:
		var lkey := "layer:%d" % document.layer_uid(index)
		target = _items_by_key.get(lkey, null)
	if target == null:
		target = _find_item(tree.get_root(), kind, index)
	if target == null and kind == "object":
		# Added objects may live in a collapsed team branch; walk every
		# registered object item by index when the stable key did not resolve.
		for key in _items_by_key:
			var item: TreeItem = _items_by_key[key]
			if item == null or not item.is_valid():
				continue
			var meta: Variant = item.get_metadata(0)
			if meta is Dictionary and String((meta as Dictionary).get("kind", "")) == kind and int((meta as Dictionary).get("index", -1)) == index:
				target = item
				break
	if target != null:
		_rebuilding = true
		tree.deselect_all()
		var parent := target.get_parent()
		while parent != null:
			parent.collapsed = false
			var pm: Variant = parent.get_metadata(0)
			if pm is Dictionary and not String((pm as Dictionary).get("key", "")).is_empty():
				_expanded_keys[String((pm as Dictionary)["key"])] = true
			parent = parent.get_parent()
		target.select(0)
		var tm: Variant = target.get_metadata(0)
		if tm is Dictionary:
			_selected_meta = tm
			var tkey := String(_selected_meta.get("key", ""))
			_selected_keys.clear()
			if not tkey.is_empty():
				_selected_keys.append(tkey)
		tree.ensure_cursor_is_visible()
		_rebuilding = false


func clear_selection() -> void:
	if tree.get_root() != null:
		_rebuilding = true
		tree.deselect_all()
		_rebuilding = false
	_selected_keys.clear()
	_selected_meta = {}


func select_objects(views: Array[int]) -> void:
	if tree.get_root() == null or document == null:
		return
	_rebuilding = true
	tree.deselect_all()
	_selected_keys.clear()
	_selected_meta = {}
	var last_item: TreeItem = null
	for v in views:
		if not document.valid_view_object(v):
			continue
		var okey := document.object_stable_key(v)
		var target: TreeItem = _items_by_key.get(okey, null)
		if target == null:
			continue
		var parent := target.get_parent()
		while parent != null:
			parent.collapsed = false
			var pm: Variant = parent.get_metadata(0)
			if pm is Dictionary and not String((pm as Dictionary).get("key", "")).is_empty():
				_expanded_keys[String((pm as Dictionary)["key"])] = true
			parent = parent.get_parent()
		target.select(0)
		_selected_keys.append(okey)
		var tm: Variant = target.get_metadata(0)
		if tm is Dictionary:
			_selected_meta = tm
		last_item = target
	if last_item != null:
		tree.ensure_cursor_is_visible()
	_rebuilding = false


func select_all_on_team(team_id: int) -> Array[int]:
	var result: Array[int] = []
	if document == null:
		return result
	var entries := document.object_entries()
	for v in entries.size():
		if document.object_team_for_entry(entries[v]) == team_id:
			result.append(v)
	select_objects(result)
	return result


func select_matching_class(odf: String) -> Array[int]:
	var result: Array[int] = []
	if document == null or odf.is_empty():
		return result
	var target_lower := odf.to_lower()
	var entries := document.object_entries()
	for v in entries.size():
		if document.object_odf_for_entry(entries[v]).to_lower() == target_lower:
			result.append(v)
	select_objects(result)
	return result


func _find_item(node: TreeItem, kind: String, index: int) -> TreeItem:
	var meta: Variant = node.get_metadata(0)
	if meta is Dictionary:
		var d: Dictionary = meta
		if String(d.get("kind", "")) == kind and int(d.get("index", -999)) == index:
			return node
	var child := node.get_first_child()
	while child != null:
		var hit := _find_item(child, kind, index)
		if hit != null:
			return hit
		child = child.get_next()
	return null


func _on_item_collapsed(item: TreeItem) -> void:
	if _rebuilding or _filter_active or item == null:
		return
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		var key := String((meta as Dictionary).get("key", ""))
		if not key.is_empty():
			_expanded_keys[key] = not item.collapsed


func _sync_selected_keys_from_tree() -> void:
	_selected_keys.clear()
	var sel := tree.get_next_selected(null)
	while sel != null:
		var meta: Variant = sel.get_metadata(0)
		if meta is Dictionary:
			var key := String((meta as Dictionary).get("key", ""))
			if not key.is_empty():
				_selected_keys.append(key)
		sel = tree.get_next_selected(sel)


func _on_multi_selected(item: TreeItem, _column: int, selected_flag: bool) -> void:
	if _rebuilding:
		return
	_sync_selected_keys_from_tree()
	var obj_views := selected_object_views()
	if selected_flag and item != null:
		var meta: Variant = item.get_metadata(0)
		if meta is Dictionary:
			_selected_meta = meta
	if obj_views.size() > 1:
		objects_selected.emit(obj_views)
	elif obj_views.size() == 1:
		objects_selected.emit(obj_views)
		item_selected_kind.emit("object", obj_views[0])
	elif selected_flag and item != null:
		var meta: Variant = item.get_metadata(0)
		if meta is Dictionary:
			item_selected_kind.emit(String((meta as Dictionary).get("kind", "none")), int((meta as Dictionary).get("index", -1)))


func _on_item_selected() -> void:
	if _rebuilding:
		return
	_sync_selected_keys_from_tree()
	var sel := tree.get_selected()
	if sel == null:
		return
	var meta: Variant = sel.get_metadata(0)
	if meta is Dictionary:
		_selected_meta = meta
		var kind := String(_selected_meta.get("kind", "none"))
		var idx := int(_selected_meta.get("index", -1))
		if kind == "object":
			var obj_views := selected_object_views()
			if obj_views.size() > 1:
				objects_selected.emit(obj_views)
				return
		item_selected_kind.emit(kind, idx)


func _on_item_activated() -> void:
	if _rebuilding:
		return
	var sel := tree.get_selected()
	if sel == null:
		return
	var meta: Variant = sel.get_metadata(0)
	if meta is Dictionary:
		_selected_meta = meta
		item_activated_kind.emit(String(_selected_meta.get("kind", "none")), int(_selected_meta.get("index", -1)))
