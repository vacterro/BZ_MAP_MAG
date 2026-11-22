extends VBoxContainer
## Left-dock Scene Tree bound directly to MapDocument.
## Provides real navigation (Terrain, Procedural Layers, Objects by team,
## Paths, Water, Environment) and editor-only viewport visibility toggles.

const Document := preload("res://core/map_document.gd")
const Terrain := preload("res://formats/terrain_v5.gd")

signal item_selected_kind(kind: String, index: int)
signal item_activated_kind(kind: String, index: int)
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
	tree.select_mode = Tree.SELECT_SINGLE
	tree.item_selected.connect(_on_item_selected)
	tree.item_activated.connect(_on_item_activated)
	add_child(tree)

	summary_label.text = "No map loaded"
	summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(summary_label)


func bind_document(doc: Document) -> void:
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


func rebuild() -> void:
	_rebuild_pending = false
	_rebuilding = true
	tree.clear()
	if document == null or document.package == null:
		summary_label.text = "Open or create a map"
		var empty_root := tree.create_item()
		empty_root.set_text(0, "No Map Loaded")
		empty_root.set_metadata(0, {"kind": "none", "index": -1})
		_rebuilding = false
		return

	var needle := filter_box.text.strip_edges().to_lower()
	var terrain := document.package.terrain
	var root := tree.create_item()
	root.set_text(0, "%s (%s · BZN %d)" % [document.package.mission_name, document.mod_profile, document.package.bzn_version])
	root.set_metadata(0, {"kind": "project", "index": 0})

	# Terrain node
	var terrain_item := tree.create_item(root)
	terrain_item.set_text(0, "Terrain (%d×%d m)" % [terrain.dimensions.x * 2, terrain.dimensions.y * 2])
	terrain_item.set_metadata(0, {"kind": "terrain", "index": Terrain.Layer.HEIGHT})
	var h_item := tree.create_item(terrain_item)
	h_item.set_text(0, "Height (%d edits)" % document.edits.size())
	h_item.set_metadata(0, {"kind": "terrain_channel", "index": Terrain.Layer.HEIGHT})
	var c_item := tree.create_item(terrain_item)
	c_item.set_text(0, "Vertex Color (%d edits)" % terrain.color_edits.size())
	c_item.set_metadata(0, {"kind": "terrain_channel", "index": Terrain.Layer.COLOR})
	var t_item := tree.create_item(terrain_item)
	t_item.set_text(0, "Tiles / Materials (%d edits)" % terrain.tile_edits.size())
	t_item.set_metadata(0, {"kind": "terrain_channel", "index": Terrain.Layer.TILES})
	terrain_item.collapsed = needle.is_empty()

	# Procedural Layers node
	var layers_item := tree.create_item(root)
	layers_item.set_text(0, "Procedural Layers (%d)" % document.layers.size())
	layers_item.set_metadata(0, {"kind": "layers", "index": 0})
	for li in document.layers.size():
		var layer_d: Dictionary = document.layers[li]
		var on_tag := "ON" if bool(layer_d.get("enabled", true)) else "OFF"
		var ltxt := "Layer %d [%s · %d%%]" % [li + 1, on_tag, int(round(float(layer_d.get("opacity", 1.0)) * 100.0))]
		if needle.is_empty() or ltxt.to_lower().contains(needle):
			var child := tree.create_item(layers_item)
			child.set_text(0, ltxt)
			child.set_metadata(0, {"kind": "layer", "index": li})
	layers_item.collapsed = needle.is_empty()

	# Objects grouped by Team
	var obj_count := document.object_count()
	var objects_item := tree.create_item(root)
	objects_item.set_text(0, "Objects (%d)" % obj_count)
	objects_item.set_metadata(0, {"kind": "objects_group", "index": -1})
	var by_team := {}
	for v in obj_count:
		var team := document.object_team(v)
		if not by_team.has(team):
			by_team[team] = []
		(by_team[team] as Array).append(v)
	var team_ids: Array = by_team.keys()
	team_ids.sort()
	var shown_objs := 0
	for tid_v in team_ids:
		var tid := int(tid_v)
		var views: Array = by_team[tid]
		var matched: Array[int] = []
		for v_v in views:
			var v := int(v_v)
			var odf := document.object_odf(v)
			var lbl := document.object_label(v)
			var entry_txt := "#%d %s%s" % [v, odf, (" · " + lbl) if not lbl.is_empty() else ""]
			if needle.is_empty() or entry_txt.to_lower().contains(needle):
				matched.append(v)
		if matched.is_empty() and not needle.is_empty():
			continue
		var team_item := tree.create_item(objects_item)
		team_item.set_text(0, "Team %d (%d)" % [tid, matched.size()])
		team_item.set_metadata(0, {"kind": "objects_group", "index": tid})
		team_item.collapsed = needle.is_empty() and matched.size() > 16
		var limit := mini(matched.size(), 200)
		for i in limit:
			var v := matched[i]
			var odf := document.object_odf(v)
			var lbl := document.object_label(v)
			var oitem := tree.create_item(team_item)
			oitem.set_text(0, "#%d %s%s" % [v, odf, (" · " + lbl) if not lbl.is_empty() else ""])
			oitem.set_metadata(0, {"kind": "object", "index": v})
			shown_objs += 1
		if matched.size() > limit:
			var more := tree.create_item(team_item)
			more.set_text(0, "… +%d more (filter to narrow)" % (matched.size() - limit))
			more.set_metadata(0, {"kind": "objects_group", "index": tid})
	objects_item.collapsed = needle.is_empty() and obj_count > 32

	# Paths
	var p_indices := document.path_indices()
	var paths_item := tree.create_item(root)
	paths_item.set_text(0, "Paths (%d)" % p_indices.size())
	paths_item.set_metadata(0, {"kind": "mission", "index": -1})
	for pidx in p_indices:
		var p: Dictionary = document.path_at(pidx)
		var pname := String(p.get("name", ""))
		var pts: PackedVector2Array = p.get("points", PackedVector2Array())
		var ptxt := "%s (%d pts)" % [pname, pts.size()]
		if needle.is_empty() or ptxt.to_lower().contains(needle):
			var pitem := tree.create_item(paths_item)
			pitem.set_text(0, ptxt)
			pitem.set_metadata(0, {"kind": "path", "index": pidx})
	paths_item.collapsed = needle.is_empty() and p_indices.size() > 12

	# Water
	var water_item := tree.create_item(root)
	var wat_layers := document.water_layers_effective().size() if document.package.water != null else 0
	water_item.set_text(0, "Water (%d active layers)" % wat_layers if document.package.water != null else "Water (absent)")
	water_item.set_metadata(0, {"kind": "water", "index": 0})

	# Environment
	var env_item := tree.create_item(root)
	var sky_name := document.package.sky_name if not document.package.sky_name.is_empty() else "(no .SKY)"
	var sky_cap := String(document.package.sky_env.get("capability", "READ_ONLY"))
	env_item.set_text(0, "Environment (%s · %s)" % [sky_name, sky_cap])
	env_item.set_metadata(0, {"kind": "environment", "index": 0})

	summary_label.text = "%d obj · %d paths · %d layers" % [obj_count, p_indices.size(), document.layers.size()]
	_rebuilding = false


func select_entry(kind: String, index: int) -> void:
	if tree.get_root() == null:
		return
	var target := _find_item(tree.get_root(), kind, index)
	if target != null:
		_rebuilding = true
		var parent := target.get_parent()
		while parent != null:
			parent.collapsed = false
			parent = parent.get_parent()
		target.select(0)
		tree.ensure_cursor_is_visible()
		_rebuilding = false


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


func _on_item_selected() -> void:
	if _rebuilding:
		return
	var sel := tree.get_selected()
	if sel == null:
		return
	var meta: Variant = sel.get_metadata(0)
	if meta is Dictionary:
		_selected_meta = meta
		item_selected_kind.emit(String(_selected_meta.get("kind", "none")), int(_selected_meta.get("index", -1)))


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
