extends AcceptDialog
## Universal Mod-Aware Object Browser & Placement Catalog.
##
## Strictly scoped to the active document's resolved content environment
## (ModRegistry.resolve_content_environment + AssetIndex). Never leaks VSR/VRV
## assets into Stock maps. Clearly distinguishes:
##   - VERIFIED_NEW_CLASS     : proven class-specific native BZN builder (1192/1196)
##   - TEMPLATE_CLONE_ONLY    : class already present in map; safe template clone
##   - PREVIEW_ONLY_UNSUPPORTED: inspectable in active mod, no native insert path yet

const AssetIndex := preload("res://core/asset_index.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const Document := preload("res://core/map_document.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const Wintage := preload("res://themes/wintage.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")

const DIALOG_WIDTH := 760
const DIALOG_MIN_HEIGHT := 450
const MAX_VISIBLE_ROWS := 260

const CAP_NEW_CLASS := "VERIFIED_NEW_CLASS"
const CAP_TEMPLATE_CLONE := "TEMPLATE_CLONE_ONLY"
const CAP_PREVIEW_ONLY := "PREVIEW_ONLY_UNSUPPORTED"

const CATEGORIES := ["All", "Placeable", "Resource", "Building", "Prop", "Mission", "Craft"]

signal place_requested(odf: String, team: int, template_view: int, is_native_new: bool)
signal place_at_cursor_requested(odf: String, team: int, template_view: int, is_native_new: bool)
signal status_message(text: String)

var document: Document
var registry: ModRegistry
var game_dir := ""
var vrv_dir := ""
var active_env: Dictionary = {}
var layered_index: Dictionary = {}
var in_map_templates: Dictionary = {} # odf_stem_lower -> view_index
var catalog_entries: Array[Dictionary] = []
var filtered_entries: Array[Dictionary] = []
var parsed_cache: Dictionary = {} # odf_stem_lower -> parsed info dict

var env_badge := Label.new()
var search_box := LineEdit.new()
var category_group := ChoiceGroup.new(0)
var count_label := Label.new()
var item_list := ItemList.new()
var detail_title := Label.new()
var detail_meta := Label.new()
var detail_deps := Label.new()
var capability_label := Label.new()
var team_field := SliderField.new()
var place_mode_button: Button
var place_cursor_button: Button
var _rebuilding := false


func _ready() -> void:
	title = "Object Browser"
	ok_button_text = "Close"
	var root := VBoxContainer.new()
	root.custom_minimum_size.x = DIALOG_WIDTH - 24
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	env_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	env_badge.custom_minimum_size.x = DIALOG_WIDTH - 32
	root.add_child(env_badge)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	root.add_child(filter_row)
	var search_lbl := Label.new()
	search_lbl.text = "Search:"
	filter_row.add_child(search_lbl)
	search_box.placeholder_text = "Filter by ODF, name, class, faction, source…"
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_box.text_changed.connect(func(_t: String): rebuild_list())
	filter_row.add_child(search_box)
	count_label.text = "0 objects"
	filter_row.add_child(count_label)

	for cat: String in CATEGORIES:
		category_group.add_item(cat)
	category_group.item_selected.connect(func(_i: int): rebuild_list())
	root.add_child(category_group)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(DIALOG_WIDTH - 24, 290)
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 280)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	left.add_theme_constant_override("separation", 3)
	split.add_child(left)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.custom_minimum_size = Vector2(350, 270)
	item_list.item_selected.connect(func(_i: int): update_selection_detail())
	item_list.item_activated.connect(func(_i: int): request_place_mode())
	left.add_child(item_list)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 280)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 4)
	split.add_child(right)

	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_title.custom_minimum_size.x = 328
	right.add_child(detail_title)
	capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	capability_label.custom_minimum_size.x = 328
	right.add_child(capability_label)
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_meta.custom_minimum_size.x = 328
	right.add_child(detail_meta)

	var dep_scroll := ScrollContainer.new()
	dep_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dep_scroll.custom_minimum_size = Vector2(328, 100)
	right.add_child(dep_scroll)
	detail_deps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_deps.custom_minimum_size.x = 310
	detail_deps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dep_scroll.add_child(detail_deps)

	var action_row := HFlowContainer.new()
	action_row.add_theme_constant_override("h_separation", 6)
	action_row.add_theme_constant_override("v_separation", 4)
	right.add_child(action_row)

	var team_grp := HBoxContainer.new()
	team_grp.add_theme_constant_override("separation", 4)
	var team_lbl := Label.new()
	team_lbl.text = "Team"
	team_grp.add_child(team_lbl)
	team_field.min_value = 0
	team_field.max_value = 15
	team_field.step = 1
	team_field.value = 0
	team_field.set_readout_width(32.0)
	team_field.custom_minimum_size.x = 86
	team_grp.add_child(team_field)
	action_row.add_child(team_grp)

	place_mode_button = Button.new()
	place_mode_button.text = "Place on Terrain"
	place_mode_button.tooltip_text = "Click in the 2D or 3D view to place the selected object on the terrain"
	place_mode_button.pressed.connect(request_place_mode)
	action_row.add_child(place_mode_button)

	place_cursor_button = Button.new()
	place_cursor_button.text = "Place at Cursor"
	place_cursor_button.tooltip_text = "Place immediately at the current terrain cursor or map center"
	place_cursor_button.pressed.connect(request_place_at_cursor)
	action_row.add_child(place_cursor_button)


func begin(doc: Document, reg: ModRegistry, game: String, vrv: String) -> void:
	document = doc
	registry = reg
	game_dir = game
	vrv_dir = vrv
	refresh_catalog()
	Wintage.popup_fit(self, DIALOG_WIDTH, DIALOG_MIN_HEIGHT)


func refresh_catalog() -> void:
	if document == null or registry == null:
		return
	_rebuilding = true
	parsed_cache.clear()
	in_map_templates.clear()
	catalog_entries.clear()

	# Collect in-map templates (first view index per ODF stem)
	for view in document.object_count():
		var stem := _stem(document.object_odf(view))
		if not stem.is_empty() and not in_map_templates.has(stem):
			in_map_templates[stem] = view

	active_env = registry.resolve_content_environment(document, game_dir, vrv_dir)
	var layered_roots: Array = active_env.get("layeredRoots", [])
	layered_index = AssetIndex.index_layered_roots(layered_roots)
	var odf_sources: Dictionary = layered_index.get("odfSources", {})
	var first_hits: Dictionary = layered_index.get("firstHit", {})
	var all_odfs := {}
	for odf_k: String in odf_sources:
		var pstr := String(first_hits.get(odf_k, ""))
		all_odfs[odf_k] = {
			"source": String(odf_sources[odf_k]),
			"path": pstr,
			"packed": "::" in pstr,
		}
	var can_insert_count := Layouts.capability_status(document.package.layout_id, Layouts.EDIT_OBJECT_COUNT) in ["NATIVE", "BAKED"]

	var mod_id := String(active_env.get("modProfile", document.mod_profile))
	var root_count := layered_roots.size()
	env_badge.text = "Environment: %s (%s)  |  Mounted Roots: %d  |  Indexed ODFs: %d  |  Layout: %s" % [
		mod_id.to_upper(), document.mission_profile, root_count, all_odfs.size(), document.package.layout_id]

	var seen := {}
	# 1. Verified native new-class builders (only include those actually resolved in active mod env, OR if no game dir configured show Stock spec)
	var has_game_odfs := not all_odfs.is_empty()
	for v_stem: String in BznObjects.VERIFIED_NATIVE_CLASSES:
		var odf_key := v_stem + ".odf"
		if has_game_odfs and not all_odfs.has(odf_key):
			continue
		seen[v_stem] = true
		var spec: Dictionary = BznObjects.VERIFIED_NATIVE_CLASSES[v_stem]
		var rec: Dictionary = all_odfs.get(odf_key, {})
		var cap := CAP_NEW_CLASS if (can_insert_count and BznObjects.supports_native_new_class(v_stem, document.package.bzn_version)) else CAP_PREVIEW_ONLY
		catalog_entries.append({
			"odf": String(spec["odf"]),
			"stem": v_stem,
			"displayName": String(spec["displayName"]),
			"classLabel": String(spec["classLabel"]),
			"category": String(spec["category"]),
			"faction": String(spec["faction"]),
			"defaultTeam": int(spec.get("defaultTeam", 0)),
			"sourceMod": String(rec.get("source", "stock")),
			"assetPath": String(rec.get("path", "")),
			"packed": bool(rec.get("packed", false)),
			"capability": cap,
			"templateView": int(in_map_templates.get(v_stem, -1)),
			"priority": 0,
		})

	# 2. In-map cloneable templates not already listed above
	for stem: String in in_map_templates:
		if seen.has(stem):
			continue
		seen[stem] = true
		var odf_key := stem + ".odf"
		var rec: Dictionary = all_odfs.get(odf_key, {})
		var parsed := _parse_odf_light(stem, rec)
		var cap := CAP_TEMPLATE_CLONE if can_insert_count else CAP_PREVIEW_ONLY
		catalog_entries.append({
			"odf": stem,
			"stem": stem,
			"displayName": String(parsed["displayName"]),
			"classLabel": String(parsed["classLabel"]),
			"category": String(parsed["category"]),
			"faction": String(parsed["faction"]),
			"defaultTeam": document.object_team(int(in_map_templates[stem])),
			"sourceMod": String(rec.get("source", "in-map")),
			"assetPath": String(rec.get("path", "")),
			"packed": bool(rec.get("packed", false)),
			"capability": cap,
			"templateView": int(in_map_templates[stem]),
			"priority": 1,
		})

	# 3. Remaining ODFs in active mod environment (sorted deterministically)
	var extra_keys: Array = all_odfs.keys()
	extra_keys.sort()
	for odf_key_v in extra_keys:
		var odf_key := String(odf_key_v)
		var stem := _stem(odf_key)
		if stem.is_empty() or seen.has(stem):
			continue
		seen[stem] = true
		var rec: Dictionary = all_odfs[odf_key]
		catalog_entries.append({
			"odf": stem,
			"stem": stem,
			"displayName": stem,
			"classLabel": "",
			"category": _guess_category_from_stem(stem),
			"faction": _guess_faction_from_stem(stem),
			"defaultTeam": 0,
			"sourceMod": String(rec.get("source", mod_id)),
			"assetPath": String(rec.get("path", "")),
			"packed": bool(rec.get("packed", false)),
			"capability": CAP_PREVIEW_ONLY,
			"templateView": -1,
			"priority": 2,
		})

	_rebuilding = false
	rebuild_list()


func rebuild_list() -> void:
	if _rebuilding:
		return
	var query := search_box.text.strip_edges().to_lower()
	var cat_idx := maxi(category_group.selected, 0)
	var cat_filter: String = CATEGORIES[cat_idx] if cat_idx < CATEGORIES.size() else "All"

	filtered_entries.clear()
	for entry: Dictionary in catalog_entries:
		if cat_filter == "Placeable":
			if String(entry["capability"]) == CAP_PREVIEW_ONLY:
				continue
		elif cat_filter != "All":
			if String(entry["category"]) != cat_filter:
				continue
		if not query.is_empty():
			var hay := ("%s %s %s %s %s %s" % [
				entry["odf"], entry["displayName"], entry["classLabel"],
				entry["category"], entry["faction"], entry["sourceMod"]
			]).to_lower()
			if not hay.contains(query):
				continue
		filtered_entries.append(entry)

	item_list.clear()
	var shown := mini(filtered_entries.size(), MAX_VISIBLE_ROWS)
	for i in shown:
		var e: Dictionary = filtered_entries[i]
		var tag := "[NEW]" if e["capability"] == CAP_NEW_CLASS else ("[CLONE]" if e["capability"] == CAP_TEMPLATE_CLONE else "[VIEW]")
		var title_part := "%s — %s" % [e["odf"], e["displayName"]] if String(e["displayName"]) != String(e["odf"]) else String(e["odf"])
		item_list.add_item("%s %s  (%s · %s)" % [tag, title_part, e["category"], e["sourceMod"]])
		item_list.set_item_metadata(i, i)

	if filtered_entries.size() > shown:
		count_label.text = "Showing %d / %d matches" % [shown, filtered_entries.size()]
	else:
		count_label.text = "%d / %d objects" % [filtered_entries.size(), catalog_entries.size()]

	if item_list.item_count > 0:
		item_list.select(0)
	update_selection_detail()


func selected_entry() -> Dictionary:
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return {}
	var idx := int(item_list.get_item_metadata(sel[0]))
	return filtered_entries[idx] if idx >= 0 and idx < filtered_entries.size() else {}


func update_selection_detail() -> void:
	var entry := selected_entry()
	if entry.is_empty():
		detail_title.text = "No object selected."
		capability_label.text = ""
		detail_meta.text = ""
		detail_deps.text = ""
		place_mode_button.disabled = true
		place_cursor_button.disabled = true
		return

	var stem := String(entry["stem"])
	var odf_key := stem + ".odf"
	var dep_info: Dictionary = AssetIndex.inspect_odf_dependencies(odf_key, layered_index) if not layered_index.is_empty() else {}
	var hit_path := String((layered_index.get("firstHit", {}) as Dictionary).get(odf_key, ""))
	var parsed: Dictionary = _parse_odf_light(stem, {"path": hit_path, "packed": "::" in hit_path})

	var disp_name := String(entry["displayName"])
	if disp_name == stem and String(parsed.get("displayName", stem)) != stem:
		disp_name = String(parsed["displayName"])
	var class_lbl := String(entry["classLabel"])
	if class_lbl.is_empty():
		class_lbl = String(parsed.get("classLabel", "(unknown)"))

	detail_title.text = "%s  (%s)" % [disp_name, odf_key]
	var cap := String(entry["capability"])
	if cap == CAP_NEW_CLASS:
		capability_label.text = "Placement: VERIFIED_NEW_CLASS — Native class-specific BZN builder verified for %s." % document.package.layout_id
	elif cap == CAP_TEMPLATE_CLONE:
		capability_label.text = "Placement: TEMPLATE_CLONE_ONLY — Clones verified in-map template #%d." % int(entry["templateView"])
	else:
		capability_label.text = "Placement: PREVIEW_ONLY_UNSUPPORTED — No in-map template or verified native class builder yet."

	var asset_path := String(entry["assetPath"])
	if asset_path.is_empty():
		asset_path = "(in-map binary record only)"
	detail_meta.text = "Class: %s  |  Category: %s  |  Faction: %s\nSource: %s\nAsset: %s" % [
		class_lbl, entry["category"], entry["faction"], entry["sourceMod"], asset_path]

	var dep_lines: Array[String] = []
	var geom := String(parsed.get("geometryName", ""))
	if not geom.is_empty():
		dep_lines.append("Geometry: " + geom)
	if not dep_info.is_empty():
		var chain: Array = dep_info.get("chain", [])
		if not chain.is_empty():
			dep_lines.append("ODF chain: " + " -> ".join(chain))
		var mesh_file := String(dep_info.get("mesh", ""))
		if not mesh_file.is_empty():
			dep_lines.append("Mesh: %s (%s)" % [mesh_file, "resolved" if bool(dep_info.get("meshResolved", false)) else "MISSING"])
		var tex_missing: Array = dep_info.get("missingTextures", [])
		var snd_missing: Array = dep_info.get("missingSounds", [])
		var odf_missing: Array = dep_info.get("missingOdfs", [])
		if not odf_missing.is_empty():
			dep_lines.append("Missing ODFs: " + ", ".join(odf_missing))
		if not tex_missing.is_empty():
			dep_lines.append("Missing textures: " + ", ".join(tex_missing.slice(0, 6)))
		if not snd_missing.is_empty():
			dep_lines.append("Missing sounds: " + ", ".join(snd_missing.slice(0, 6)))
		if odf_missing.is_empty() and tex_missing.is_empty() and snd_missing.is_empty() and bool(dep_info.get("found", false)):
			dep_lines.append("Dependencies: all inspected references resolved in active environment.")
	if cap == CAP_NEW_CLASS:
		var spec := BznObjects.native_class_spec(stem)
		dep_lines.append("Builder: %s (%s)" % [String(spec.get("builder", "")), String(spec.get("evidence", ""))])
	detail_deps.text = "\n".join(dep_lines)

	team_field.value = float(entry.get("defaultTeam", 0))
	var can_place := cap in [CAP_NEW_CLASS, CAP_TEMPLATE_CLONE]
	place_mode_button.disabled = not can_place
	place_cursor_button.disabled = not can_place


func request_place_mode() -> void:
	var entry := selected_entry()
	if entry.is_empty():
		return
	var cap := String(entry["capability"])
	if cap == CAP_PREVIEW_ONLY:
		status_message.emit("Cannot place '%s': no verified native class builder or in-map template." % entry["odf"])
		return
	var is_new := cap == CAP_NEW_CLASS
	var tpl := -1 if is_new else int(entry["templateView"])
	hide()
	place_requested.emit(String(entry["odf"]), int(team_field.value), tpl, is_new)


func request_place_at_cursor() -> void:
	var entry := selected_entry()
	if entry.is_empty():
		return
	var cap := String(entry["capability"])
	if cap == CAP_PREVIEW_ONLY:
		status_message.emit("Cannot place '%s': no verified native class builder or in-map template." % entry["odf"])
		return
	var is_new := cap == CAP_NEW_CLASS
	var tpl := -1 if is_new else int(entry["templateView"])
	place_at_cursor_requested.emit(String(entry["odf"]), int(team_field.value), tpl, is_new)


func _parse_odf_light(stem: String, rec: Dictionary) -> Dictionary:
	if parsed_cache.has(stem):
		return parsed_cache[stem]
	var info := {
		"displayName": stem,
		"classLabel": "",
		"geometryName": "",
		"category": _guess_category_from_stem(stem),
		"faction": _guess_faction_from_stem(stem),
	}
	var path := String(rec.get("path", ""))
	if not path.is_empty() and not bool(rec.get("packed", false)) and FileAccess.file_exists(path):
		var p := AssetIndex.parse_odf_file(path)
		if bool(p.get("ok", false)):
			var un := String(p.get("unitName", "")).strip_edges()
			if not un.is_empty():
				info["displayName"] = un
			var cl := String(p.get("classLabel", "")).strip_edges()
			info["classLabel"] = cl
			info["geometryName"] = String(p.get("geometryName", "")).strip_edges()
			info["category"] = _category_for_class(cl, stem)
	parsed_cache[stem] = info
	return info


static func _stem(odf: String) -> String:
	var s := odf.strip_edges().get_file().to_lower()
	return s.substr(0, s.length() - 4) if s.ends_with(".odf") else s


static func _guess_faction_from_stem(stem: String) -> String:
	if stem.begins_with("iv") or stem.begins_with("ib") or stem.begins_with("is"):
		return "ISDF"
	if stem.begins_with("fv") or stem.begins_with("fb") or stem.begins_with("fs"):
		return "Scion"
	if stem.begins_with("ev") or stem.begins_with("eb"):
		return "Hadean / Mod"
	return "Neutral"


static func _guess_category_from_stem(stem: String) -> String:
	if "pool" in stem or "scrap" in stem or stem.begins_with("npscr"):
		return "Resource"
	if "pspwn" in stem or "spwn" in stem or "nav" in stem or "sndpoint" in stem:
		return "Mission"
	if stem.begins_with("ib") or stem.begins_with("fb") or stem.begins_with("eb"):
		return "Building"
	if stem.begins_with("iv") or stem.begins_with("fv") or stem.begins_with("ev"):
		return "Craft"
	return "Prop"


static func _category_for_class(class_label: String, stem: String) -> String:
	var low := class_label.to_lower()
	if low in ["deposit", "scrap", "geyser"] or "pool" in low:
		return "Resource"
	if low in ["spawnpnt", "navbeacon", "camera"]:
		return "Mission"
	if low in ["powerplant", "factory", "armory", "recycler", "turret", "commtower", "supplydepot", "silo", "barracks", "techcenter", "extractor", "sign", "powered"]:
		return "Building"
	if low in ["wingman", "scout", "assault", "hover", "walker", "scavenger", "constructionrig", "tug", "minelayer", "apc", "turrettank", "artillery", "morphtank", "sav", "craft", "person"]:
		return "Craft"
	if low in ["i76building", "i76sign", "artifact", "plant", "tree"]:
		return "Prop"
	return _guess_category_from_stem(stem)
