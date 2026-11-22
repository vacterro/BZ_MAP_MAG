extends VBoxContainer
## Docked Universal Mod-Aware Object Browser & Placement Catalog.
## Mounted in the Left Dock "Assets" tab for continuous multi-object placement
## without modal popups. Preserves all five separated capability statuses.

const AssetIndex := preload("res://core/asset_index.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const Document := preload("res://core/map_document.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const ChoiceGroup := preload("res://themes/choice_group.gd")
const SliderField := preload("res://themes/slider_field.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")

const PAGE_SIZE := 260

const CAP_NEW_CLASS := "VERIFIED_NEW_CLASS"
const CAP_TEMPLATE_CLONE := "TEMPLATE_CLONE_ONLY"
const CAP_MISSING_ASSET := "MISSING_ASSET"
const CAP_PREVIEW_ONLY := "PREVIEW_ONLY_UNSUPPORTED"

const SER_NATIVE_WRITER := "VERIFIED_NATIVE_WRITER"
const SER_TEMPLATE_CLONE := "TEMPLATE_CLONE"
const SER_UNSUPPORTED := "UNSUPPORTED"

const ASSET_AVAILABLE := "AVAILABLE"
const ASSET_AVAILABLE_PACKED := "AVAILABLE_PACKED"
const ASSET_MISSING := "MISSING"
const ASSET_CORRUPT := "CORRUPT"

const PREVIEW_AVAILABLE := "AVAILABLE"
const PREVIEW_MISSING_MESH := "MISSING_MESH"
const PREVIEW_PACKED_UNVERIFIED := "PACKED_UNVERIFIED"
const PREVIEW_UNKNOWN := "UNKNOWN"

const RUNTIME_READY := "READY"
const RUNTIME_MISSING_ASSETS := "MISSING_ASSETS"
const RUNTIME_UNRESOLVED_DEPS := "UNRESOLVED_MOD_DEPS"
const RUNTIME_UNVERIFIED := "UNVERIFIED"

const PLACE_ENABLED := "ENABLED"
const PLACE_DISABLED := "DISABLED"

const CATEGORIES := ["All", "Placeable", "Resource", "Building", "Prop", "Mission", "Craft"]
const FACTIONS := ["All", "ISDF", "Scion", "Neutral", "Hadean / Mod"]
const AVAILABILITY_FILTERS := ["All", "Available", "Missing"]

signal place_requested(odf: String, team: int, template_view: int, is_native_new: bool)
signal place_at_cursor_requested(odf: String, team: int, template_view: int, is_native_new: bool)
signal status_message(text: String)
signal entry_selected(entry: Dictionary)

var document: Document
var registry: ModRegistry
var game_dir := ""
var vrv_dir := ""
var active_env: Dictionary = {}
var layered_index: Dictionary = {}
var catalog_stamp := ""
var catalog_mod_profile := ""
var catalog_revision := 0
var in_map_templates: Dictionary = {} # odf_stem_lower -> view_index
var catalog_entries: Array[Dictionary] = []
var filtered_entries: Array[Dictionary] = []
var parsed_cache: Dictionary = {}
var dep_cache: Dictionary = {}
var visible_limit := PAGE_SIZE

var env_badge := Label.new()
var search_box := LineEdit.new()
var category_group := ChoiceGroup.new(0)
var faction_group := ChoiceGroup.new(0)
var availability_group := ChoiceGroup.new(0)
var count_label := Label.new()
var item_list := ItemList.new()
var show_more_button := Button.new()
var refresh_button := Button.new()
var detail_panel := VBoxContainer.new()
var detail_title := Label.new()
var detail_meta := Label.new()
var detail_deps := Label.new()
var capability_label := Label.new()
var team_field := SliderField.new()
var place_mode_button := Button.new()
var place_cursor_button := Button.new()
var _rebuilding := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)

	env_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	env_badge.text = "Open a map to browse mod assets."
	add_child(env_badge)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	add_child(filter_row)
	search_box.placeholder_text = "Filter ODF, class, faction…"
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_box.text_changed.connect(func(_t: String): _reset_paging_and_rebuild())
	filter_row.add_child(search_box)
	refresh_button.text = "↻"
	refresh_button.tooltip_text = "Re-scan active mod asset roots and update availability"
	refresh_button.pressed.connect(func(): refresh_catalog())
	filter_row.add_child(refresh_button)

	var filters_sec := CollapsibleSection.new("Filters", "obj_browser_filters", true)
	add_child(filters_sec)
	for cat: String in CATEGORIES:
		category_group.add_item(cat)
	category_group.item_selected.connect(func(_i: int): _reset_paging_and_rebuild())
	filters_sec.add_content(category_group)
	for fac: String in FACTIONS:
		faction_group.add_item(fac)
	faction_group.item_selected.connect(func(_i: int): _reset_paging_and_rebuild())
	filters_sec.add_content(faction_group)
	for av: String in AVAILABILITY_FILTERS:
		availability_group.add_item(av)
	availability_group.item_selected.connect(func(_i: int): _reset_paging_and_rebuild())
	filters_sec.add_content(availability_group)

	count_label.text = "0 objects"
	add_child(count_label)

	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.custom_minimum_size.y = 140
	item_list.item_selected.connect(func(_i: int): update_selection_detail())
	item_list.item_activated.connect(func(_i: int): request_place_mode())
	add_child(item_list)

	show_more_button.text = "Show More (+%d)" % PAGE_SIZE
	show_more_button.hide()
	show_more_button.pressed.connect(_show_more_rows)
	add_child(show_more_button)

	var quick_place := HFlowContainer.new()
	quick_place.add_theme_constant_override("h_separation", 4)
	quick_place.add_theme_constant_override("v_separation", 3)
	add_child(quick_place)
	var team_grp := HBoxContainer.new()
	team_grp.add_theme_constant_override("separation", 3)
	var team_lbl := Label.new()
	team_lbl.text = "Team"
	team_grp.add_child(team_lbl)
	team_field.min_value = 0
	team_field.max_value = 15
	team_field.step = 1
	team_field.value = 0
	team_field.set_readout_width(28.0)
	team_field.custom_minimum_size.x = 76
	team_grp.add_child(team_field)
	quick_place.add_child(team_grp)

	place_mode_button.text = "Place"
	place_mode_button.tooltip_text = "Click in 2D or 3D viewport to place (Shift+click repeats, Esc cancels)"
	place_mode_button.pressed.connect(request_place_mode)
	quick_place.add_child(place_mode_button)

	place_cursor_button.text = "At Cursor"
	place_cursor_button.tooltip_text = "Place immediately at current terrain cursor or map center"
	place_cursor_button.pressed.connect(request_place_at_cursor)
	quick_place.add_child(place_cursor_button)

	# Detail panel (mounted inside Right Attributes Inspector OBJECT_BROWSER context!)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_constant_override("separation", 4)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(detail_title)
	capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(capability_label)
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(detail_meta)
	var dep_sec := CollapsibleSection.new("Dependencies & Native Verification", "obj_browser_deps", false)
	detail_panel.add_child(dep_sec)
	detail_deps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dep_sec.add_content(detail_deps)


func begin(doc: Document, reg: ModRegistry, game: String, vrv: String) -> void:
	var same_env := (document == doc and registry == reg and game_dir == game and vrv_dir == vrv
		and doc != null and catalog_mod_profile == doc.mod_profile and not catalog_entries.is_empty())
	document = doc
	registry = reg
	game_dir = game
	vrv_dir = vrv
	if same_env:
		if not _sync_if_assets_changed():
			update_selection_detail()
		return
	visible_limit = PAGE_SIZE
	refresh_catalog()


func _compute_live_env_stamp() -> String:
	if active_env.is_empty():
		return ""
	var stamps := PackedStringArray()
	for lr_v in active_env.get("layeredRoots", []):
		var lr: Dictionary = lr_v
		var p := String(lr.get("path", "")).strip_edges().simplify_path()
		var rec := bool(lr.get("recurse", true))
		if not p.is_empty() and DirAccess.dir_exists_absolute(p):
			stamps.append("%s|%s=%s" % [p.to_lower(), "1" if rec else "0", AssetIndex.compute_root_stamp(p, rec)])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("\n".join(stamps).to_utf8_buffer())
	return ctx.finish().hex_encode()


func _sync_if_assets_changed() -> bool:
	if document == null or registry == null or active_env.is_empty():
		return false
	var live_stamp := _compute_live_env_stamp()
	if not live_stamp.is_empty() and live_stamp != catalog_stamp:
		refresh_catalog()
		return true
	return false


func refresh_catalog() -> void:
	if document == null or registry == null:
		return
	_rebuilding = true
	catalog_revision += 1
	parsed_cache.clear()
	dep_cache.clear()
	in_map_templates.clear()
	catalog_entries.clear()
	visible_limit = PAGE_SIZE

	if not game_dir.strip_edges().is_empty() and registry.last_game_dir != game_dir.strip_edges():
		registry.discover_installed(game_dir, vrv_dir)

	for view in document.object_count():
		var stem := _stem(document.object_odf(view))
		if not stem.is_empty() and not in_map_templates.has(stem):
			in_map_templates[stem] = view

	active_env = registry.resolve_content_environment(document, game_dir, vrv_dir)
	catalog_mod_profile = document.mod_profile
	var layered_roots: Array[Dictionary] = []
	for lr_v in active_env.get("layeredRoots", []):
		layered_roots.append(lr_v as Dictionary)
	layered_index = AssetIndex.index_layered_roots(layered_roots)
	catalog_stamp = String(layered_index.get("compositeStamp", ""))

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

	var mod_id := String(active_env.get("modProfile", document.mod_profile))
	var known_profile := bool(active_env.get("knownProfile", false))
	var mod_installed := bool(active_env.get("modInstalled", false))
	var missing_deps: Array = active_env.get("missingDependencies", [])
	var disabled_deps: Array = active_env.get("disabledDependencies", [])
	var dep_cycles: Array = active_env.get("dependencyCycles", [])
	var deps_complete := bool(active_env.get("dependenciesComplete", false))
	var mod_usable := known_profile and mod_id != "custom:unknown" and mod_installed and disabled_deps.is_empty() and dep_cycles.is_empty()
	var can_insert_count := Layouts.capability_status(document.package.layout_id, Layouts.EDIT_OBJECT_COUNT) in ["NATIVE", "BAKED"]

	var dep_note := ""
	if not known_profile or mod_id == "custom:unknown":
		dep_note = " · [WARN] Unknown Mod"
	elif not mod_installed:
		dep_note = " · [WARN] Not Installed"
	elif not disabled_deps.is_empty():
		dep_note = " · [WARN] Disabled Dep"
	elif not missing_deps.is_empty():
		dep_note = " · [WARN] Missing Dep"
	env_badge.text = "%s (%s) · %d roots · %d ODFs%s" % [
		mod_id.to_upper(), document.mission_profile, layered_roots.size(), all_odfs.size(), dep_note]

	var seen := {}
	for v_stem: String in BznObjects.VERIFIED_NATIVE_CLASSES:
		seen[v_stem] = true
		var odf_key := v_stem + ".odf"
		var spec: Dictionary = BznObjects.VERIFIED_NATIVE_CLASSES[v_stem]
		var has_odf := all_odfs.has(odf_key)
		var rec: Dictionary = all_odfs.get(odf_key, {})
		var is_packed := bool(rec.get("packed", false))
		var writer_ok := can_insert_count and BznObjects.supports_native_new_class(v_stem, document.package.bzn_version)
		var serialization := SER_NATIVE_WRITER if writer_ok else SER_UNSUPPORTED
		var asset_avail := (ASSET_AVAILABLE_PACKED if is_packed else ASSET_AVAILABLE) if has_odf else ASSET_MISSING
		var runtime_st := _compute_runtime_status(asset_avail, serialization, mod_usable, deps_complete)
		var place_st := PLACE_ENABLED if (serialization == SER_NATIVE_WRITER and asset_avail in [ASSET_AVAILABLE, ASSET_AVAILABLE_PACKED] and mod_usable) else PLACE_DISABLED
		var cap := CAP_NEW_CLASS if place_st == PLACE_ENABLED else (CAP_MISSING_ASSET if asset_avail == ASSET_MISSING else CAP_PREVIEW_ONLY)
		catalog_entries.append({
			"odf": String(spec["odf"]),
			"stem": v_stem,
			"displayName": String(spec["displayName"]),
			"classLabel": String(spec["classLabel"]),
			"category": String(spec["category"]),
			"faction": String(spec["faction"]),
			"defaultTeam": int(spec.get("defaultTeam", 0)),
			"sourceMod": String(rec.get("source", "missing")) if has_odf else "missing",
			"assetPath": String(rec.get("path", "")),
			"packed": is_packed,
			"serialization": serialization,
			"assetAvailability": asset_avail,
			"preview": PREVIEW_UNKNOWN,
			"runtime": runtime_st,
			"placement": place_st,
			"capability": cap,
			"binaryMatch": String(spec.get("binaryMatch", "UNVERIFIED")),
			"engineLoad": String(spec.get("engineLoad", "UNVERIFIED")),
			"gameplayBehavior": String(spec.get("gameplayBehavior", "UNVERIFIED")),
			"templateView": int(in_map_templates.get(v_stem, -1)),
			"priority": 0 if place_st == PLACE_ENABLED else 1,
		})

	for stem: String in in_map_templates:
		if seen.has(stem):
			continue
		seen[stem] = true
		var odf_key := stem + ".odf"
		var has_odf := all_odfs.has(odf_key)
		var rec: Dictionary = all_odfs.get(odf_key, {})
		var is_packed := bool(rec.get("packed", false))
		var parsed := _parse_odf_light(stem, rec)
		var serialization := SER_TEMPLATE_CLONE if can_insert_count else SER_UNSUPPORTED
		var asset_avail := (ASSET_AVAILABLE_PACKED if is_packed else ASSET_AVAILABLE) if has_odf else ASSET_MISSING
		var runtime_st := _compute_runtime_status(asset_avail, serialization, mod_usable, deps_complete)
		var place_st := PLACE_ENABLED if (serialization == SER_TEMPLATE_CLONE and asset_avail in [ASSET_AVAILABLE, ASSET_AVAILABLE_PACKED] and mod_usable) else PLACE_DISABLED
		var cap := CAP_TEMPLATE_CLONE if place_st == PLACE_ENABLED else (CAP_MISSING_ASSET if asset_avail == ASSET_MISSING else CAP_PREVIEW_ONLY)
		catalog_entries.append({
			"odf": stem,
			"stem": stem,
			"displayName": String(parsed["displayName"]),
			"classLabel": String(parsed["classLabel"]),
			"category": String(parsed["category"]),
			"faction": String(parsed["faction"]),
			"defaultTeam": document.object_team(int(in_map_templates[stem])),
			"sourceMod": String(rec.get("source", "missing")) if has_odf else "in-map-missing-odf",
			"assetPath": String(rec.get("path", "")),
			"packed": is_packed,
			"serialization": serialization,
			"assetAvailability": asset_avail,
			"preview": PREVIEW_UNKNOWN,
			"runtime": runtime_st,
			"placement": place_st,
			"capability": cap,
			"templateView": int(in_map_templates[stem]),
			"priority": 1 if place_st == PLACE_ENABLED else 2,
		})

	var extra_keys: Array = all_odfs.keys()
	extra_keys.sort()
	for odf_key_v in extra_keys:
		var odf_key := String(odf_key_v)
		var stem := _stem(odf_key)
		if stem.is_empty() or seen.has(stem):
			continue
		seen[stem] = true
		var rec: Dictionary = all_odfs[odf_key]
		var is_packed := bool(rec.get("packed", false))
		var asset_avail := ASSET_AVAILABLE_PACKED if is_packed else ASSET_AVAILABLE
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
			"packed": is_packed,
			"serialization": SER_UNSUPPORTED,
			"assetAvailability": asset_avail,
			"preview": PREVIEW_UNKNOWN,
			"runtime": RUNTIME_UNVERIFIED,
			"placement": PLACE_DISABLED,
			"capability": CAP_PREVIEW_ONLY,
			"templateView": -1,
			"priority": 3,
		})

	_rebuilding = false
	rebuild_list()


static func _compute_runtime_status(asset_avail: String, serialization: String, mod_usable: bool, deps_complete: bool) -> String:
	if asset_avail in [ASSET_MISSING, ASSET_CORRUPT]:
		return RUNTIME_MISSING_ASSETS
	if not mod_usable or not deps_complete:
		return RUNTIME_UNRESOLVED_DEPS
	if serialization in [SER_NATIVE_WRITER, SER_TEMPLATE_CLONE]:
		return RUNTIME_READY
	return RUNTIME_UNVERIFIED


func _reset_paging_and_rebuild() -> void:
	visible_limit = PAGE_SIZE
	rebuild_list()


func _show_more_rows() -> void:
	visible_limit += PAGE_SIZE
	rebuild_list()


func rebuild_list() -> void:
	if _rebuilding:
		return
	var query := search_box.text.strip_edges().to_lower()
	var cat_idx := maxi(category_group.selected, 0)
	var cat_filter: String = CATEGORIES[cat_idx] if cat_idx < CATEGORIES.size() else "All"
	var fac_idx := maxi(faction_group.selected, 0)
	var fac_filter: String = FACTIONS[fac_idx] if fac_idx < FACTIONS.size() else "All"
	var av_idx := maxi(availability_group.selected, 0)
	var av_filter: String = AVAILABILITY_FILTERS[av_idx] if av_idx < AVAILABILITY_FILTERS.size() else "All"

	filtered_entries.clear()
	for entry: Dictionary in catalog_entries:
		if cat_filter == "Placeable":
			if String(entry["placement"]) != PLACE_ENABLED:
				continue
		elif cat_filter != "All":
			if String(entry["category"]) != cat_filter:
				continue
		if fac_filter != "All":
			if String(entry["faction"]) != fac_filter:
				continue
		if av_filter == "Available":
			if not (String(entry["assetAvailability"]) in [ASSET_AVAILABLE, ASSET_AVAILABLE_PACKED]):
				continue
		elif av_filter == "Missing":
			if String(entry["assetAvailability"]) != ASSET_MISSING and String(entry["assetAvailability"]) != ASSET_CORRUPT:
				continue
		if not query.is_empty():
			var hay := ("%s %s %s %s %s %s %s" % [
				entry["odf"], entry["displayName"], entry["classLabel"],
				entry["category"], entry["faction"], entry["sourceMod"], entry["assetAvailability"]
			]).to_lower()
			if not hay.contains(query):
				continue
		filtered_entries.append(entry)

	item_list.clear()
	var shown := mini(filtered_entries.size(), visible_limit)
	for i in shown:
		var e: Dictionary = filtered_entries[i]
		var cap := String(e["capability"])
		var tag := "[NEW]" if cap == CAP_NEW_CLASS else ("[CLONE]" if cap == CAP_TEMPLATE_CLONE else ("[MISS]" if cap == CAP_MISSING_ASSET else "[VIEW]"))
		var title_part := "%s — %s" % [e["odf"], e["displayName"]] if String(e["displayName"]) != String(e["odf"]) else String(e["odf"])
		item_list.add_item("%s %s (%s)" % [tag, title_part, e["category"]])
		item_list.set_item_metadata(i, i)

	var remaining := filtered_entries.size() - shown
	if remaining > 0:
		count_label.text = "%d / %d matches (total %d)" % [shown, filtered_entries.size(), catalog_entries.size()]
		show_more_button.text = "Show More (+%d)" % mini(PAGE_SIZE, remaining)
		show_more_button.show()
	else:
		count_label.text = "%d / %d objects" % [filtered_entries.size(), catalog_entries.size()]
		show_more_button.hide()

	if item_list.item_count > 0:
		item_list.select(0)
	update_selection_detail()


func selected_entry() -> Dictionary:
	var sel := item_list.get_selected_items()
	if sel.is_empty():
		return {}
	var idx := int(item_list.get_item_metadata(sel[0]))
	return filtered_entries[idx] if idx >= 0 and idx < filtered_entries.size() else {}


func inspect_entry_capabilities(entry: Dictionary) -> Dictionary:
	var stem := String(entry.get("stem", ""))
	var odf_key := stem + ".odf"
	var cache_key := "%s|%s" % [odf_key, catalog_stamp]
	var dep_info: Dictionary
	if dep_cache.has(cache_key):
		dep_info = dep_cache[cache_key]
	else:
		dep_info = AssetIndex.inspect_odf_dependencies(odf_key, layered_index) if not layered_index.is_empty() else {}
		dep_cache[cache_key] = dep_info

	var asset_avail := String(entry.get("assetAvailability", ASSET_MISSING))
	var insp_status := String(dep_info.get("inspectionStatus", AssetIndex.INSPECT_MISSING))
	if insp_status == AssetIndex.INSPECT_ENTRY_CORRUPT:
		asset_avail = ASSET_CORRUPT
	elif insp_status == AssetIndex.INSPECT_MISSING:
		asset_avail = ASSET_MISSING

	var preview_st := PREVIEW_UNKNOWN
	if not dep_info.is_empty() and bool(dep_info.get("found", false)):
		if not String(dep_info.get("meshPath", "")).is_empty():
			preview_st = PREVIEW_AVAILABLE
		elif bool(dep_info.get("meshMissing", false)):
			preview_st = PREVIEW_MISSING_MESH
		elif bool(dep_info.get("packed", false)) and not bool(dep_info.get("contentParsed", false)):
			preview_st = PREVIEW_PACKED_UNVERIFIED

	var serialization := String(entry.get("serialization", SER_UNSUPPORTED))
	var mod_id := String(active_env.get("modProfile", document.mod_profile if document != null else "stock"))
	var known_profile := bool(active_env.get("knownProfile", false))
	var mod_installed := bool(active_env.get("modInstalled", false))
	var disabled_deps: Array = active_env.get("disabledDependencies", [])
	var dep_cycles: Array = active_env.get("dependencyCycles", [])
	var deps_complete := bool(active_env.get("dependenciesComplete", false))
	var mod_usable := known_profile and mod_id != "custom:unknown" and mod_installed and disabled_deps.is_empty() and dep_cycles.is_empty()

	var runtime_st := _compute_runtime_status(asset_avail, serialization, mod_usable, deps_complete)
	var place_st := PLACE_ENABLED if (serialization in [SER_NATIVE_WRITER, SER_TEMPLATE_CLONE] and asset_avail in [ASSET_AVAILABLE, ASSET_AVAILABLE_PACKED] and mod_usable) else PLACE_DISABLED

	entry["assetAvailability"] = asset_avail
	entry["preview"] = preview_st
	entry["runtime"] = runtime_st
	entry["placement"] = place_st
	if place_st == PLACE_DISABLED:
		entry["capability"] = CAP_MISSING_ASSET if asset_avail in [ASSET_MISSING, ASSET_CORRUPT] else CAP_PREVIEW_ONLY

	return {
		"serialization": serialization,
		"assetAvailability": asset_avail,
		"inspectionStatus": insp_status,
		"preview": preview_st,
		"runtime": runtime_st,
		"placement": place_st,
		"depInfo": dep_info,
	}


func update_selection_detail() -> void:
	var entry := selected_entry()
	if entry.is_empty():
		detail_title.text = "No catalog asset selected."
		capability_label.text = ""
		detail_meta.text = ""
		detail_deps.text = ""
		place_mode_button.disabled = true
		place_cursor_button.disabled = true
		return

	var caps := inspect_entry_capabilities(entry)
	var dep_info: Dictionary = caps["depInfo"]
	var stem := String(entry["stem"])
	var odf_key := stem + ".odf"
	var hit_path := String((layered_index.get("firstHit", {}) as Dictionary).get(odf_key, ""))
	var parsed: Dictionary = _parse_odf_light(stem, {"path": hit_path, "packed": "::" in hit_path})

	var disp_name := String(entry["displayName"])
	if disp_name == stem and String(parsed.get("displayName", stem)) != stem:
		disp_name = String(parsed["displayName"])
	var class_lbl := String(entry["classLabel"])
	if class_lbl.is_empty():
		class_lbl = String(dep_info.get("classLabel", parsed.get("classLabel", "(unknown)")))
		if class_lbl.is_empty():
			class_lbl = "(unknown)"

	var mod_id := String(active_env.get("modProfile", document.mod_profile)).to_upper()
	detail_title.text = "%s (%s)" % [disp_name, odf_key]
	capability_label.text = "Writer: %s | ODF: %s (%s)\nPreview: %s | Mod: %s | Runtime: %s | Place: %s" % [
		String(caps["serialization"]),
		String(caps["assetAvailability"]),
		String(caps["inspectionStatus"]),
		String(caps["preview"]),
		mod_id,
		String(caps["runtime"]),
		String(caps["placement"]),
	]

	var asset_path := String(entry["assetPath"])
	if asset_path.is_empty():
		asset_path = "(ODF MISSING in active content environment)"
	detail_meta.text = "Class: %s | Category: %s | Faction: %s\nSource: %s\nAsset: %s" % [
		class_lbl, entry["category"], entry["faction"], entry["sourceMod"], asset_path]

	var dep_lines: Array[String] = []
	var geom := String(dep_info.get("geometryName", parsed.get("geometryName", "")))
	if not geom.is_empty():
		dep_lines.append("Geometry: " + geom)
	if not dep_info.is_empty():
		var chain: Array = dep_info.get("parentChain", [])
		if not chain.is_empty():
			dep_lines.append("ODF chain: " + " -> ".join(chain))
		var mesh_path := String(dep_info.get("meshPath", ""))
		if not mesh_path.is_empty():
			dep_lines.append("Mesh: %s (resolved)" % mesh_path.get_file())
		elif bool(dep_info.get("meshMissing", false)):
			dep_lines.append("Mesh: %s (MISSING)" % geom)
		var tex_missing: Array = dep_info.get("missingTextures", [])
		var snd_missing: Array = dep_info.get("missingSounds", [])
		var unv_reasons: Array = dep_info.get("unverifiedReasons", [])
		if not tex_missing.is_empty():
			dep_lines.append("Missing textures: " + ", ".join(tex_missing.slice(0, 6)))
		if not snd_missing.is_empty():
			dep_lines.append("Missing sounds: " + ", ".join(snd_missing.slice(0, 6)))
		if not unv_reasons.is_empty():
			for r_v in unv_reasons.slice(0, 4):
				dep_lines.append("[NOTICE] " + String(r_v))
		elif String(dep_info.get("inspectionStatus", "")) == AssetIndex.INSPECT_DEPENDENCIES_RESOLVED:
			dep_lines.append("Dependencies: DEPENDENCIES_RESOLVED (all inspected references present).")
	if String(caps["serialization"]) == SER_NATIVE_WRITER:
		var spec := BznObjects.native_class_spec(stem)
		dep_lines.append("Verification: binary=%s | engineLoad=%s | gameplay=%s" % [
			String(spec.get("binaryMatch", "UNVERIFIED")),
			String(spec.get("engineLoad", "UNVERIFIED")),
			String(spec.get("gameplayBehavior", "UNVERIFIED")),
		])
		dep_lines.append("Builder: %s (%s)" % [String(spec.get("builder", "")), String(spec.get("evidence", ""))])
	if String(caps["placement"]) == PLACE_DISABLED:
		if String(caps["assetAvailability"]) == ASSET_MISSING:
			dep_lines.append("[BLOCKED] Required ODF '%s' is missing in active %s environment." % [odf_key, mod_id])
		elif String(caps["assetAvailability"]) == ASSET_CORRUPT:
			dep_lines.append("[BLOCKED] Packed ODF entry '%s' is corrupt." % odf_key)
		elif String(caps["runtime"]) == RUNTIME_UNRESOLVED_DEPS:
			dep_lines.append("[BLOCKED] Active mod profile has missing/disabled dependencies or is not installed.")
	detail_deps.text = "\n".join(dep_lines)

	team_field.value = float(entry.get("defaultTeam", 0))
	var can_place := String(caps["placement"]) == PLACE_ENABLED
	place_mode_button.disabled = not can_place
	place_cursor_button.disabled = not can_place
	entry_selected.emit(entry)


func request_place_mode() -> void:
	_sync_if_assets_changed()
	var entry := selected_entry()
	if entry.is_empty():
		return
	var caps := inspect_entry_capabilities(entry)
	if String(caps["placement"]) != PLACE_ENABLED:
		update_selection_detail()
		status_message.emit("Cannot place '%s': writer=%s, odf=%s, runtime=%s." % [
			entry["odf"], caps["serialization"], caps["assetAvailability"], caps["runtime"]])
		return
	var is_new := String(caps["serialization"]) == SER_NATIVE_WRITER
	var tpl := -1 if is_new else int(entry["templateView"])
	place_requested.emit(String(entry["odf"]), int(team_field.value), tpl, is_new)


func request_place_at_cursor() -> void:
	_sync_if_assets_changed()
	var entry := selected_entry()
	if entry.is_empty():
		return
	var caps := inspect_entry_capabilities(entry)
	if String(caps["placement"]) != PLACE_ENABLED:
		update_selection_detail()
		status_message.emit("Cannot place '%s': writer=%s, odf=%s, runtime=%s." % [
			entry["odf"], caps["serialization"], caps["assetAvailability"], caps["runtime"]])
		return
	var is_new := String(caps["serialization"]) == SER_NATIVE_WRITER
	var tpl := -1 if is_new else int(entry["templateView"])
	place_at_cursor_requested.emit(String(entry["odf"]), int(team_field.value), tpl, is_new)


func _parse_odf_light(stem: String, rec: Dictionary) -> Dictionary:
	var cache_key := "%s|%s" % [stem, catalog_stamp]
	if parsed_cache.has(cache_key):
		return parsed_cache[cache_key]
	var info := {
		"displayName": stem,
		"classLabel": "",
		"geometryName": "",
		"category": _guess_category_from_stem(stem),
		"faction": _guess_faction_from_stem(stem),
	}
	var path := String(rec.get("path", ""))
	if not path.is_empty():
		var p := AssetIndex.parse_odf_file(path)
		if bool(p.get("ok", false)):
			var un := String(p.get("unitName", "")).strip_edges()
			if not un.is_empty():
				info["displayName"] = un
			var cl := String(p.get("classLabel", "")).strip_edges()
			info["classLabel"] = cl
			info["geometryName"] = String(p.get("geometryName", "")).strip_edges()
			info["category"] = _category_for_class(cl, stem)
	parsed_cache[cache_key] = info
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
