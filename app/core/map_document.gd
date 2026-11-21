extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Graph := preload("res://nodes/height_graph.gd")
const PathCodec := preload("res://formats/bzn_paths.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const HISTORY_LIMIT := 64
const MAX_EDITOR_ABS_HEIGHT := 100000.0
enum Brush { OFFSET, SMOOTH, FLATTEN, SPRAY }
enum BrushShape { SQUARE, CIRCLE, CONE, BELL }
enum MirrorDirection { MIN_X_TO_MAX_X, MAX_X_TO_MIN_X, MIN_Z_TO_MAX_Z, MAX_Z_TO_MIN_Z }

signal terrain_changed(region: Rect2i)
signal materials_changed(region: Rect2i, layer: int)
signal paths_changed
signal object_moved(view_index: int)
signal objects_changed

var package: Package
var base_heights := PackedFloat32Array()
var edits := {}
var path_edits := {}
var native_path_ids := {}
var asset_profile := ""
var object_edits := {}
var object_additions: Array = []
var object_removals := {}
var next_object_id := 1
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var stroke := {}
var stroke_weights := {}
var stroke_active := false
var stroke_layer := Terrain.Layer.HEIGHT
var layers: Array = [Graph.layer()]
var preview_before := {}
var preview_after := {}
var edit_revision := 0
var error := ""


func open(path: String) -> bool:
	var source := path
	var saved: Dictionary = {}
	if path.get_extension().to_lower() == "bzmag":
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null or input.get_length() > 64 * 1024 * 1024:
			return fail("Could not read bounded project file.")
		var data: Variant = JSON.parse_string(input.get_as_text())
		if not data is Dictionary or data.get("schema") != 1 or not data.get("source") is String or not data.get("files") is Dictionary or not data.get("edits") is Dictionary:
			return fail("Invalid BZMAG project schema.")
		saved = data
		source = saved["source"]
		if not source.is_absolute_path() or source.get_extension().to_lower() != "bzn":
			return fail("Project source must be an absolute BZN path.")
	native_path_ids.clear()
	asset_profile = ""
	object_edits = {}
	object_additions = []
	object_removals = {}
	next_object_id = 1
	package = Package.new()
	if not package.open(source):
		return fail(package.error)
	var terrain := package.terrain
	base_heights = terrain.heights.duplicate()
	if not saved.is_empty():
		if saved["files"] != package.files:
			return fail("Project source revisions differ from the saved project.")
		var saved_profile: Variant = saved.get("assetProfile", "")
		if not valid_asset_profile(saved_profile):
			return fail("The project asset profile must be an absolute JSON path.")
		asset_profile = saved_profile
		var graph := Graph.new()
		if not saved.get("layers", layers) is Array or not graph.validate_stack(saved.get("layers", layers)):
			return fail("Invalid node stack. " + graph.error)
		layers = saved.get("layers", layers).map(Graph.normalize_layer)
		for key: String in saved["edits"]:
			var value: Variant = saved["edits"][key]
			var index := key.to_int()
			if not key.is_valid_int() or str(index) != key or index < 0 or index >= base_heights.size() or not (value is float or value is int) or not is_finite(value) or absf(value) > MAX_EDITOR_ABS_HEIGHT:
				return fail("Invalid project height edit.")
			set_height(index, value)
		if not read_material_edits(saved.get("colorEdits", {}), Terrain.Layer.COLOR) or not read_material_edits(saved.get("tileEdits", {}), Terrain.Layer.TILES):
			return false
		if not read_path_edits(saved.get("pathEdits", {})):
			return false
		if not read_object_edits(saved.get("objectEdits", {})):
			return false
		if not read_object_removals(saved.get("objectRemovals", [])):
			return false
		if not read_object_additions(saved.get("objectInserts", [])):
			return false
	if not package.check_sources():
		return fail(package.error)
	edit_revision += 1
	return true


static func valid_asset_profile(value: Variant) -> bool:
	return value is String and (value.is_empty() or (value.is_absolute_path() and value.get_extension().to_lower() == "json"))


func begin_stroke(layer := Terrain.Layer.HEIGHT) -> void:
	if has_preview():
		return
	stroke_active = true
	stroke_layer = layer
	stroke = {}
	stroke_weights = {}


func dab(point: Vector2, radius_m: float, amount: float, mode := Brush.OFFSET, shape := BrushShape.BELL, pressure := 1.0) -> void:
	if not stroke_active or stroke_layer != Terrain.Layer.HEIGHT or not is_finite(amount):
		return
	var terrain := package.terrain
	var radius := radius_m / terrain.SPACING
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return
	var touched := false
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0.0:
				continue
			var index := z * terrain.dimensions.x + x
			if mode == Brush.SPRAY and hash(Vector2i(x, z)) % 5 > 1:
				continue
			var old := terrain.heights[index]
			var start: float = stroke.get(index, old)
			if weight <= stroke_weights.get(index, 0.0):
				continue
			var requested := start + amount
			match mode:
				Brush.SMOOTH:
					requested = lerpf(start, neighborhood_average(Vector2i(x, z), terrain.dimensions), clampf(amount / 100.0, 0, 1))
				Brush.FLATTEN, Brush.SPRAY:
					requested = amount
			requested = lerpf(start, requested, clampf(pressure, 0, 1))
			if requested == start:
				continue
			var target := snappedf(lerpf(start, requested, weight), package.granularity)
			if not is_finite(target) or absf(target) > minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0):
				continue
			if (requested > start and target <= old) or (requested < start and target >= old):
				continue
			stroke[index] = start
			stroke_weights[index] = weight
			set_height(index, target)
			touched = true
	if touched:
		terrain_changed.emit(region)


func brush_region(point: Vector2, radius_m: float) -> Rect2i:
	if not point.is_finite() or not is_finite(radius_m) or radius_m <= 0.0 or radius_m > 256.0:
		return Rect2i()
	var radius := radius_m / Terrain.SPACING
	var low := Vector2i(floori(point.x - radius), floori(point.y - radius)).max(Vector2i.ZERO)
	var high := Vector2i(ceili(point.x + radius), ceili(point.y + radius)).min(package.terrain.dimensions - Vector2i.ONE)
	return Rect2i(low, high - low + Vector2i.ONE)


func brush_weight(offset: Vector2, radius: float, shape: int) -> float:
	var distance := maxf(absf(offset.x), absf(offset.y)) if shape == BrushShape.SQUARE else offset.length()
	var influence := 1.0 - distance / radius
	if influence <= 0.0:
		return 0.0
	if shape == BrushShape.SQUARE or shape == BrushShape.CIRCLE:
		return 1.0
	return influence if shape == BrushShape.CONE else smoothstep(0.0, 1.0, influence)


func dab_material(point: Vector2, radius_m: float, value: int, shape: int, pressure: float, lane := 0) -> void:
	if not stroke_active or stroke_layer not in [Terrain.Layer.COLOR, Terrain.Layer.TILES] or not is_finite(pressure):
		return
	var tiles := stroke_layer == Terrain.Layer.TILES
	if value < 0 or value > (15 if tiles else 0xffffff) or lane not in [0, 1, 2, 3]:
		return
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return
	var terrain := package.terrain
	var radius := radius_m / Terrain.SPACING
	var changes := {}
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0:
				continue
			var index := terrain.block_at(Vector2i(x, z)) if tiles else z * terrain.dimensions.x + x
			if changes.has(index) or weight <= stroke_weights.get(index, 0.0):
				continue
			var current := terrain.material_value(stroke_layer, index)
			var start: int = stroke.get(index, current)
			var paint: int
			if tiles:
				var shift := lane * 4
				paint = (start & ~(15 << shift)) | (value << shift)
			else:
				paint = Terrain.rgb_word(Terrain.word_color(start).lerp(Terrain.word_color(value), weight * clampf(pressure, 0.0, 1.0)))
			if paint != current:
				stroke[index] = start
				stroke_weights[index] = weight
				changes[index] = paint
	apply_materials(stroke_layer, changes)


func apply_materials(layer: int, values: Dictionary) -> void:
	for index: int in values:
		package.terrain.set_material(layer, index, values[index])
	refresh_materials(layer, values)


func refresh_materials(layer: int, values: Dictionary) -> void:
	if values.is_empty():
		return
	var terrain := package.terrain
	var low := terrain.dimensions
	var high := Vector2i.ZERO
	var extent := Vector2i.ONE * (Terrain.BLOCK if layer == Terrain.Layer.TILES else 1)
	for index: int in values:
		var point := terrain.block_origin(index) if layer == Terrain.Layer.TILES else terrain.sample_at(index)
		low = low.min(point)
		high = high.max(point + extent)
	materials_changed.emit(Rect2i(low, high - low), layer)


func read_material_edits(saved: Variant, layer: int) -> bool:
	var terrain := package.terrain
	var limit := terrain.block_offsets.size() - 1 if layer == Terrain.Layer.TILES else terrain.heights.size()
	var max_value := 0xffff if layer == Terrain.Layer.TILES else 0xffffff
	if not saved is Dictionary or saved.size() > limit:
		return fail("Invalid project material edits.")
	for key: String in saved:
		var index := key.to_int()
		var value: Variant = saved[key]
		if str(index) != key or index < 0 or index >= limit or not valid_native_integer(value) or value > max_value:
			return fail("Invalid project terrain material value.")
		terrain.set_material(layer, index, int(value))
	return true


func neighborhood_average(point: Vector2i, size: Vector2i) -> float:
	var sum := 0.0
	var count := 0
	for z in range(maxi(0, point.y - 1), mini(size.y, point.y + 2)):
		for x in range(maxi(0, point.x - 1), mini(size.x, point.x + 2)):
			var index := z * size.x + x
			sum += stroke.get(index, package.terrain.heights[index])
			count += 1
	return sum / count


func end_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	if stroke.is_empty():
		return
	var after := {}
	for index: int in stroke:
		after[index] = package.terrain.heights[index] if stroke_layer == Terrain.Layer.HEIGHT else package.terrain.material_value(stroke_layer, index)
	if stroke_layer == Terrain.Layer.HEIGHT:
		record_change(stroke, after)
	else:
		push_history({"material": stroke_layer, "before": stroke, "after": after})
	stroke = {}


func undo() -> void:
	if stroke_active or has_preview() or undo_stack.is_empty():
		return
	var change: Dictionary = undo_stack.pop_back()
	apply_history(change, "before")
	redo_stack.append(change)


func redo() -> void:
	if stroke_active or has_preview() or redo_stack.is_empty():
		return
	var change: Dictionary = redo_stack.pop_back()
	apply_history(change, "after")
	undo_stack.append(change)


func record_change(before: Dictionary, after: Dictionary) -> void:
	push_history({"before": before, "after": after})


func push_history(change: Dictionary) -> void:
	edit_revision += 1
	undo_stack.append(change)
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()


func apply_history(change: Dictionary, direction: String) -> void:
	edit_revision += 1
	if change.has("path"):
		set_path_edit(change["path"], change[direction])
	elif change.has("object"):
		apply_object_transform(change["object"], change[direction])
	elif change.has("object_add") or change.has("object_add_removed"):
		var addition: Dictionary = change["object_add"] if change.has("object_add") else change["object_add_removed"]
		var restore := (change.has("object_add") and direction == "after") or (change.has("object_add_removed") and direction == "before")
		if restore:
			while object_additions.size() < change["slot"]:
				object_additions.append({})
			object_additions.insert(mini(int(change["slot"]), object_additions.size()), addition)
		else:
			for slot in range(object_additions.size() - 1, -1, -1):
				if object_additions[slot] and int(object_additions[slot].get("id", -1)) == int(addition["id"]):
					object_additions.remove_at(slot)
		objects_changed.emit()
	elif change.has("object_remove"):
		var base := int(change["object_remove"])
		if direction == "after":
			object_removals[base] = true
		else:
			object_removals.erase(base)
		objects_changed.emit()
	elif change.has("material"):
		apply_materials(change["material"], change[direction])
	else:
		var materials := {}
		for layer: int in change.get("materials", {}):
			materials[layer] = change["materials"][layer][direction]
		apply_channels(change[direction], materials)


func path_at(index: int) -> Dictionary:
	if path_edits.has(index):
		return path_edits[index]
	return source_path_at(index)


func source_path_at(index: int) -> Dictionary:
	return package.paths[index] if index >= 0 and index < package.paths.size() else {}


func path_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in package.paths.size():
		if not path_at(index).is_empty():
			indices.append(index)
	for index: int in path_edits:
		if index >= package.paths.size():
			indices.append(index)
	indices.sort()
	return indices


func edit_path(index: int, label: String, points: PackedVector2Array, kind: int) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	var before := path_at(index)
	if before.is_empty():
		return fail("Select a supported native path.")
	var base := source_path_at(index)
	if not valid_path_fields(label, points, kind, base) or not unique_path_name(index, label):
		return false
	var updated := {"id": before["id"], "name": label, "points": points.duplicate(), "type": kind}
	if same_path_fields(updated, before):
		return true
	push_history({"path": index, "before": before, "after": updated})
	set_path_edit(index, updated)
	return true


func create_path(label: String, points: PackedVector2Array, kind: int) -> int:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return -1
	if not package.path_codec.can_resize or path_indices().size() >= PathCodec.MAX_PATHS:
		fail("This native path table cannot accept another path.")
		return -1
	var index := package.paths.size()
	while path_edits.has(index):
		index += 1
	if not valid_path_fields(label, points, kind, {}) or not unique_path_name(index, label):
		return -1
	var ids := path_pointer_counts().duplicate()
	var id := 1
	for record in package.paths:
		id = maxi(id, int(record["id"]) + 1)
	if id > 4294967295:
		id = 1
	for slot in path_indices():
		ids[path_at(slot)["id"]] = true
	while ids.has(id):
		id = 1 if id == 4294967295 else id + 1
	var path := {"id": id, "name": label, "points": points.duplicate(), "type": kind}
	push_history({"path": index, "before": {}, "after": path})
	set_path_edit(index, path)
	return index


func remove_path(index: int) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	var before := path_at(index)
	if before.is_empty() or not package.path_codec.can_resize:
		return fail("Select a path from a supported native path table.")
	if not can_remove_source_path(index):
		return false
	push_history({"path": index, "before": before, "after": {}})
	set_path_edit(index, {})
	return true


func path_pointer_counts() -> Dictionary:
	if native_path_ids.is_empty():
		native_path_ids = package.path_codec.pointer_counts(path_source_bytes())
	return native_path_ids


func path_source_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(package.source_path.get_base_dir().path_join(package.bzn_name))


func can_remove_source_path(index: int) -> bool:
	var base := source_path_at(index)
	if base.is_empty():
		return true
	var label: String = base["name"].to_lower()
	var spawn := RegEx.new()
	spawn.compile("^(player|enemy)_[0-9]+$")
	if label == "edge_path" or spawn.search(label) != null:
		return fail("The mission may require the path named %s." % base["name"])
	if path_pointer_counts().get(base["id"], 0) != 1:
		return fail("The BZN may reference the native ID of %s." % base["name"])
	if package.path_codec.has_name_reference(path_source_bytes(), label):
		return fail("The BZN may refer to the name %s." % base["name"])
	for member: String in package.files:
		if member.get_extension().to_lower() in ["lua", "aip", "trn", "inf"]:
			var content := FileAccess.get_file_as_string(package.source_path.get_base_dir().path_join(member))
			if content.to_lower().contains(label):
				return fail("%s may refer to %s." % [member, base["name"]])
	return true


func valid_path_fields(label: Variant, points: PackedVector2Array, kind: int, base: Dictionary) -> bool:
	var base_kind: int = base.get("type", -1)
	if not label is String or points.is_empty() or points.size() > PathCodec.MAX_POINTS or (kind != base_kind and kind not in [0, 1, 2]):
		return fail("Choose a valid path type and provide at least one point, or three for a loop.")
	if kind == 2 and points.size() < 3 and (base_kind != 2 or points.size() != base["points"].size()):
		return fail("A loop needs at least three points.")
	if label != base.get("name", "") or base.is_empty():
		var permitted := RegEx.new()
		permitted.compile("^[A-Za-z0-9_][A-Za-z0-9_. -]{0,63}$")
		if permitted.search(label) == null or label != label.strip_edges():
			return fail("Choose a path name using 1–64 ASCII letters, digits, spaces, underscores, dots or hyphens.")
	for point in points:
		if not point.is_finite():
			return fail("All path coordinates must be finite.")
	return true


func unique_path_name(index: int, label: String) -> bool:
	for other in path_indices():
		if other != index and label.nocasecmp_to(path_at(other)["name"]) == 0:
			if label != source_path_at(index).get("name") or path_at(other)["name"] != source_path_at(other).get("name"):
				return fail("Choose a unique path name.")
	return true


func set_path_edit(index: int, data: Dictionary) -> void:
	if same_path_fields(source_path_at(index), data):
		path_edits.erase(index)
	else:
		path_edits[index] = data
	paths_changed.emit()


static func same_path_fields(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return left.is_empty() and right.is_empty()
	return left["id"] == right["id"] and left["name"] == right["name"] and left["points"] == right["points"] and left["type"] == right["type"]


func read_path_edits(saved: Variant) -> bool:
	if not saved is Dictionary or saved.size() > 2 * PathCodec.MAX_PATHS:
		return fail("Invalid project path edits.")
	var added_ids := {}
	for key: String in saved:
		var index := key.to_int()
		if str(index) != key or index < 0 or index >= package.paths.size() + PathCodec.MAX_PATHS:
			return fail("Invalid project path reference.")
		var entry: Variant = saved[key]
		var base := source_path_at(index)
		if entry == null:
			if base.is_empty() or not package.path_codec.can_resize:
				return fail("Invalid saved path removal.")
			if not can_remove_source_path(index):
				return false
			path_edits[index] = {}
			continue
		if not entry is Dictionary:
			return fail("Invalid project path record.")
		var id: int = base.get("id", 0)
		if base.is_empty():
			var new_id: Variant = entry.get("id")
			if not package.path_codec.can_resize or not valid_native_integer(new_id) or new_id == 0:
				return fail("Invalid saved native path ID.")
			id = int(new_id)
			if added_ids.has(id) or path_pointer_counts().has(id):
				return fail("Saved path IDs conflict with another native record.")
			added_ids[id] = true
		var position_list: Variant = entry.get("points")
		var kind: Variant = entry.get("type")
		if not position_list is Array or position_list.size() > PathCodec.MAX_POINTS or not valid_native_integer(kind):
			return fail("Invalid saved path geometry or type.")
		var points := PackedVector2Array()
		for pair: Variant in position_list:
			if not pair is Array or pair.size() != 2 or not (pair[0] is int or pair[0] is float) or not (pair[1] is int or pair[1] is float):
				return fail("Invalid saved path coordinate.")
			points.append(Vector2(pair[0], pair[1]))
		if not valid_path_fields(entry.get("name"), points, int(kind), base):
			return false
		path_edits[index] = {"id": id, "name": entry["name"], "points": points, "type": int(kind)}
	if path_indices().size() > PathCodec.MAX_PATHS:
		return fail("The project has too many paths.")
	for index: int in path_edits:
		var entry := path_at(index)
		if not entry.is_empty() and not unique_path_name(index, entry["name"]):
			return false
	return true


func valid_native_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= 4294967295 and value == floorf(value)


func read_object_edits(saved: Variant) -> bool:
	if not saved is Dictionary or saved.size() > package.objects.size():
		return fail("Invalid project object edits.")
	for key: String in saved:
		var index := key.to_int()
		var fields: Variant = saved[key]
		if str(index) != key or index < 0 or index >= package.objects.size():
			return fail("Invalid project object reference.")
		if fields is Array and fields.size() == 3:
			for value in fields:
				if not (value is float or value is int) or not is_finite(value):
					return fail("Invalid saved object coordinate.")
			var legacy := Vector3(fields[0], fields[1], fields[2])
			if not valid_object_position(legacy):
				return fail("Saved object position is outside the supported map.")
			set_object_edit(index, Transform3D(package.objects[index]["transform"].basis, legacy))
			continue
		if not fields is Dictionary or not valid_object_edit(index, fields):
			return fail("Invalid saved object edit.")
		set_object_edit(index, Transform3D(read_saved_basis(fields["basis"]), Vector3(fields["position"][0], fields["position"][1], fields["position"][2])))
	return true


func read_object_removals(saved: Variant) -> bool:
	if saved == null:
		saved = []
	if not saved is Array or saved.size() > package.objects.size() or object_removals.size() + saved.size() > package.objects.size():
		return fail("Invalid project object removals.")
	for value: Variant in saved:
		if not valid_native_integer(value):
			return fail("Invalid project object removal reference.")
		var index := int(value)
		if index < 0 or index >= package.objects.size() or object_removals.has(index):
			return fail("Invalid project object removal reference.")
		remove_base_object(index, false)
	return true


func read_object_additions(saved: Variant) -> bool:
	if not saved is Array or saved.size() > 8192 - package.objects.size():
		return fail("Invalid project object insertions.")
	for item: Variant in saved:
		if not item is Dictionary or not valid_object_insertion(item):
			return fail("Invalid project object insertion.")
		var addition: Dictionary = item.duplicate()
		addition["transform"] = Transform3D(read_saved_basis(item["basis"]), Vector3(item["position"][0], item["position"][1], item["position"][2]))
		next_object_id = maxi(next_object_id, int(item["id"]) + 1)
		object_additions.append(addition)
	return true


func valid_object_edit(index: int, fields: Dictionary) -> bool:
	var position: Variant = fields.get("position")
	if not position is Array or position.size() != 3:
		return false
	for value in position:
		if not (value is float or value is int) or not is_finite(value):
			return false
	if not valid_object_position(Vector3(position[0], position[1], position[2])):
		return false
	return valid_basis_array(fields.get("basis", []))


func valid_object_insertion(item: Dictionary) -> bool:
	var template: Variant = item.get("template")
	if not valid_native_integer(template):
		return false
	var index := int(template)
	if index < 0 or index >= package.objects.size() or object_removals.has(index):
		return false
	if not valid_native_integer(item.get("sequence")) or not valid_native_integer(item.get("id")):
		return false
	if sequence_taken(int(item["sequence"])):
		return false
	var label: Variant = item.get("label", "")
	if not label is String or label.length() > 128:
		return false
	return valid_object_edit(index, item)


func valid_basis_array(values: Variant) -> bool:
	if not values is Array or values.size() not in [0, 9]:
		return false
	for value in values:
		if not (value is float or value is int) or not is_finite(value):
			return false
	return true


func read_saved_basis(values: Variant) -> Basis:
	if values is Array and values.size() == 9:
		return Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8]))
	return Basis()


func object_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in package.objects.size():
		if not object_removals.has(index):
			result.append({"base": index})
	for slot in object_additions.size():
		result.append({"added": slot})
	return result


func object_count() -> int:
	return package.objects.size() - object_removals.size() + object_additions.size()


func object_entry(view: int) -> Dictionary:
	if view < 0:
		return {}
	var entries := object_entries()
	return entries[view] if view < entries.size() else {}


func object_is_added(view: int) -> bool:
	return view >= 0 and object_entry(view).has("added")


func object_addition(view: int) -> Dictionary:
	var entry := object_entry(view)
	var slot: int = entry.get("added", -1)
	return object_additions[slot] if slot >= 0 and slot < object_additions.size() else {}


func object_template(view: int) -> Dictionary:
	var entry := object_entry(view)
	if entry.has("added"):
		var template: int = int(object_addition(view)["template"])
		return package.objects[template] if template >= 0 and template < package.objects.size() else {}
	if entry.is_empty():
		return {}
	return package.objects[int(entry["base"])]


func object_actual_index(view: int) -> int:
	var entry := object_entry(view)
	return int(entry["base"]) if not entry.is_empty() else -1


func object_position(view: int) -> Vector3:
	if object_is_added(view):
		return object_addition(view)["transform"].origin
	var base := object_actual_index(view)
	if base < 0:
		return Vector3.INF
	var edit: Dictionary = object_edits.get(base, {})
	if edit.is_empty():
		return package.objects[base]["transform"].origin
	return Transform3D(edit["basis"], edit["position"]).origin


func object_transform(view: int) -> Transform3D:
	if object_is_added(view):
		return object_addition(view)["transform"]
	var base := object_actual_index(view)
	if base < 0:
		return Transform3D()
	var edit: Dictionary = object_edits.get(base, {})
	if edit.is_empty():
		return package.objects[base]["transform"]
	return Transform3D(edit["basis"], edit["position"])


func object_odf(view: int) -> String:
	return String(object_template(view).get("odf", ""))


func object_label(view: int) -> String:
	if object_is_added(view):
		return String(object_addition(view).get("label", ""))
	return String(object_template(view).get("label", ""))


func object_team(view: int) -> int:
	return int(object_template(view).get("team", 0))


func object_sequence(view: int) -> int:
	if object_is_added(view):
		return int(object_addition(view).get("sequence", 0))
	return int(object_template(view).get("sequence", 0))


func object_pool_reference(view: int) -> int:
	# The base object that supplies the mesh, team and pool for this view.
	var entry := object_entry(view)
	if entry.is_empty():
		return -1
	if entry.has("added"):
		return int(object_addition(view).get("template", -1))
	return int(entry["base"])


func has_object_file_edits() -> bool:
	return not object_edits.is_empty() or not object_removals.is_empty() or not object_additions.is_empty()


func move_object(view: int, position: Vector3) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if not valid_view_object(view) or not valid_object_position(position):
		return fail("Choose a finite object position on the terrain.")
	var before := object_transform(view)
	var after := Transform3D(before.basis, position)
	if before == after:
		return true
	push_history({"object": object_history_key(view), "before": before, "after": after})
	set_object_transform(view, after)
	return true


func rotate_object(view: int, radians: float) -> bool:
	if stroke_active or has_preview() or not valid_view_object(view) or not is_finite(radians):
		return fail("Select an object and finish other terrain edits first.")
	var before := object_transform(view)
	if not before.basis.is_finite():
		return fail("The object basis is not finite.")
	var rotated := before.basis.rotated(Vector3.UP, radians)
	var after := Transform3D(rotated, before.origin)
	if before == after:
		return true
	push_history({"object": object_history_key(view), "before": before, "after": after})
	set_object_transform(view, after)
	return true


func sequence_taken(sequence: int) -> bool:
	for entry in package.objects:
		if int(entry["sequence"]) == sequence:
			return true
	for addition in object_additions:
		if int(addition["sequence"]) == sequence:
			return true
	return false


func fresh_sequence(template: Dictionary) -> int:
	var mask := int(template["sequence"]) & 0x800000
	var low := int(template["sequence"]) & 0x7fffff
	for entry in package.objects:
		low = maxi(low, int(entry["sequence"]) & 0x7fffff)
	for addition in object_additions:
		low = maxi(low, int(addition["sequence"]) & 0x7fffff)
	for attempt in 65535:
		var candidate := (low + 1 + attempt) & 0x7fffff
		if not sequence_taken(candidate | mask):
			return candidate | mask
	return -1


func copy_label(template: Dictionary) -> String:
	var label: String = template.get("label", "")
	if label == "":
		return ""
	for suffix in range(2, 999):
		var candidate := label + "_" + str(suffix)
		if candidate.length() > 128:
			candidate = label.substr(0, maxf(1, 128 - str(suffix).length() - 1)) + "_" + str(suffix)
		if not label_taken(candidate):
			return candidate
	return label


func label_taken(label: String) -> bool:
	for entry in package.objects:
		if String(entry["label"]) == label:
			return true
	for addition in object_additions:
		if String(addition["label"]) == label:
			return true
	return false


func duplicate_object(view: int, position: Vector3) -> int:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return -1
	if not valid_view_object(view) or not valid_object_position(position):
		fail("Choose a finite object position on the terrain.")
		return -1
	var template := object_template(view)
	var sequence := fresh_sequence(template)
	if sequence < 0:
		fail("No unused native object sequence is available.")
		return -1
	var entry := object_entry(view)
	var template_base := int(entry["template"] if entry.has("added") else entry["base"])
	var addition := {"id": next_object_id, "template": template_base,
		"label": copy_label(template), "sequence": sequence, "position": [0.0, 0.0, 0.0], "basis": []}
	var transform := object_transform(view)
	addition["transform"] = Transform3D(transform.basis, position)
	push_history({"object_add": addition, "slot": object_additions.size()})
	object_additions.append(addition)
	next_object_id += 1
	objects_changed.emit()
	return object_count() - 1


func remove_object(view: int) -> bool:
	if stroke_active or has_preview() or not valid_view_object(view):
		return fail("Select an object and finish the current terrain edit first.")
	var entry := object_entry(view)
	if entry.has("added"):
		var slot: int = int(entry["added"])
		var addition: Dictionary = object_additions[slot]
		push_history({"object_add_removed": addition, "slot": slot})
		object_additions.remove_at(slot)
		objects_changed.emit()
		return true
	var base := int(entry["base"])
	push_history({"object_remove": base})
	remove_base_object(base, true)
	return true


func remove_base_object(base: int, announce: bool) -> void:
	object_removals[base] = true
	if announce:
		objects_changed.emit()


func valid_view_object(view: int) -> bool:
	return view >= 0 and view < object_count()


func object_history_key(view: int) -> Variant:
	if object_is_added(view):
		return int(object_addition(view)["id"])
	return object_actual_index(view)


func set_object_transform(view: int, transform: Transform3D) -> void:
	if object_is_added(view):
		var addition := object_addition(view)
		addition["transform"] = transform
		object_moved.emit(view)
		return
	var base := object_actual_index(view)
	if package.objects[base]["transform"] == transform:
		object_edits.erase(base)
	else:
		object_edits[base] = {"basis": transform.basis, "position": transform.origin}
	object_moved.emit(view)


func set_object_edit(base: int, transform: Transform3D) -> void:
	if package.objects[base]["transform"] == transform:
		object_edits.erase(base)
	else:
		object_edits[base] = {"basis": transform.basis, "position": transform.origin}
	object_moved.emit(base)


func object_export_edits() -> Dictionary:
	var result := {}
	for base: int in object_edits:
		result[base] = Transform3D(object_edits[base]["basis"], object_edits[base]["position"])
	return result


func apply_object_transform(key: Variant, transform: Transform3D) -> void:
	if key is int and key >= 0 and key < package.objects.size():
		if package.objects[key]["transform"] == transform:
			object_edits.erase(key)
		else:
			object_edits[key] = {"basis": transform.basis, "position": transform.origin}
		object_moved.emit(view_for_base(int(key)))
		return
	for addition in object_additions:
		if int(addition["id"]) == int(key):
			addition["transform"] = transform
			object_moved.emit(find_object_view(addition))
			return


func view_for_base(base: int) -> int:
	var entries := object_entries()
	for view in entries.size():
		if int(entries[view].get("base", -1)) == base:
			return view
	return -1


func find_object_view(addition: Dictionary) -> int:
	var entries := object_entries()
	for view in entries.size():
		if entries[view].has("added") and object_additions[int(entries[view]["added"])] == addition:
			return view
	return -1


func valid_object_position(position: Vector3) -> bool:
	var terrain := package.terrain
	var minimum := Vector2(terrain.origin) * terrain.SPACING
	var maximum := minimum + Vector2(terrain.dimensions - Vector2i.ONE) * terrain.SPACING
	return position.is_finite() and absf(position.y) <= MAX_EDITOR_ABS_HEIGHT and position.x >= minimum.x and position.x <= maximum.x and position.z >= minimum.y and position.z <= maximum.y


func preview_slope_plane(center: Vector2i, radius_m: float, height: float, grade: Vector2) -> bool:
	var terrain := package.terrain
	var bounds := Rect2i(Vector2i.ZERO, terrain.dimensions)
	if stroke_active or not bounds.has_point(center) or not grade.is_finite() or not is_finite(height):
		return fail("Finish the stroke and choose a finite slope anchored inside the map.")
	var region := brush_region(Vector2(center), radius_m)
	if not region.has_area():
		return fail("Choose a valid slope radius.")
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var values := {}
	var native_sample := PackedFloat32Array([0.0])
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var offset := Vector2(Vector2i(x, z) - center) * Terrain.SPACING
			if offset.length_squared() > radius_m * radius_m:
				continue
			var value := snappedf(height + offset.dot(grade), package.granularity)
			if not is_finite(value) or absf(value) > limit:
				return fail("The slope plane exceeds the terrain height range.")
			var index := z * terrain.dimensions.x + x
			native_sample[0] = value
			if native_sample[0] != preview_before.get(index, terrain.heights[index]):
				values[index] = native_sample[0]
	show_preview(values)
	return true


func mirror_heights(direction: int) -> int:
	if stroke_active or has_preview() or direction not in MirrorDirection.values():
		fail("Finish the current preview or stroke and choose a mirror direction.")
		return -1
	var terrain := package.terrain
	var size := terrain.dimensions
	var half := size / 2
	var region: Rect2i
	match direction:
		MirrorDirection.MIN_X_TO_MAX_X:
			region = Rect2i(half.x, 0, size.x - half.x, size.y)
		MirrorDirection.MAX_X_TO_MIN_X:
			region = Rect2i(0, 0, half.x, size.y)
		MirrorDirection.MIN_Z_TO_MAX_Z:
			region = Rect2i(0, half.y, size.x, size.y - half.y)
		MirrorDirection.MAX_Z_TO_MIN_Z:
			region = Rect2i(0, 0, size.x, half.y)
	var across_x := direction == MirrorDirection.MIN_X_TO_MAX_X or direction == MirrorDirection.MAX_X_TO_MIN_X
	var before := {}
	var after := {}
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var index := z * size.x + x
			var opposite := z * size.x + size.x - 1 - x if across_x else (size.y - 1 - z) * size.x + x
			if terrain.heights[index] != terrain.heights[opposite]:
				if absf(terrain.heights[opposite]) > MAX_EDITOR_ABS_HEIGHT:
					fail("The source half contains a sample outside the editable height range.")
					return -1
				before[index] = terrain.heights[index]
				after[index] = terrain.heights[opposite]
	if not after.is_empty():
		apply(after)
		record_change(before, after)
	return after.size()


func has_preview() -> bool:
	return not preview_after.is_empty() or not package.terrain.material_previews.is_empty()


func valid_preview(values: Dictionary, materials: Dictionary) -> bool:
	var terrain := package.terrain
	for index: Variant in values:
		var value: Variant = values[index]
		if not index is int or index < 0 or index >= terrain.heights.size() or not (value is float or value is int) or not is_finite(value) or absf(value) > MAX_EDITOR_ABS_HEIGHT:
			return false
	for layer: Variant in materials:
		if layer not in [Terrain.Layer.COLOR, Terrain.Layer.TILES] or not materials[layer] is Dictionary:
			return false
		var tiles: bool = layer == Terrain.Layer.TILES
		var limit := terrain.block_offsets.size() - 1 if tiles else terrain.heights.size()
		for index: Variant in materials[layer]:
			var value: Variant = materials[layer][index]
			if not index is int or index < 0 or index >= limit or not value is int or value < 0 or value > (0xffff if tiles else 0xffffff):
				return false
			if tiles and (value & 0xfff0) != (terrain.committed_material_value(layer, index) & 0xfff0):
				return false
	return true


func show_preview(values: Dictionary, materials := {}) -> bool:
	if stroke_active or not valid_preview(values, materials):
		return fail("Invalid terrain preview.")
	clear_preview()
	error = ""
	var terrain := package.terrain
	var native_sample := PackedFloat32Array([0.0])
	for index: int in values:
		native_sample[0] = values[index]
		if native_sample[0] != terrain.heights[index]:
			preview_before[index] = terrain.heights[index]
			preview_after[index] = native_sample[0]
	for layer: int in materials:
		var changes := {}
		for index: int in materials[layer]:
			if materials[layer][index] != terrain.committed_material_value(layer, index):
				changes[index] = materials[layer][index]
		if not changes.is_empty():
			terrain.material_previews[layer] = changes
	apply(preview_after, false)
	for layer: int in terrain.material_previews:
		refresh_materials(layer, terrain.material_previews[layer])
	return true


func clear_preview() -> void:
	var heights := preview_before
	preview_before = {}
	preview_after = {}
	var materials := package.terrain.material_previews
	package.terrain.material_previews = {}
	apply(heights, false)
	for layer: int in materials:
		refresh_materials(layer, materials[layer])


func bake_preview() -> bool:
	if not has_preview():
		return fail("Create a terrain preview before baking.")
	var terrain := package.terrain
	var materials := terrain.material_previews
	if not valid_preview(preview_after, materials):
		return fail("Invalid terrain preview.")
	var after := preview_after
	var history := {"before": preview_before, "after": after, "materials": {}}
	terrain.material_previews = {}
	for layer: int in materials:
		var previous := {}
		for index: int in materials[layer]:
			previous[index] = terrain.committed_material_value(layer, index)
		history["materials"][layer] = {"before": previous, "after": materials[layer]}
	preview_before = {}
	preview_after = {}
	push_history(history)
	apply_channels(after, materials)
	return true


func apply_channels(heights: Dictionary, materials: Dictionary) -> void:
	var terrain := package.terrain
	for layer: int in materials:
		for index: int in materials[layer]:
			terrain.set_material(layer, index, materials[layer][index])
	apply(heights)
	for layer: int in materials:
		refresh_materials(layer, materials[layer])


func apply(values: Dictionary, commit := true) -> void:
	if values.is_empty():
		return
	var dimensions := package.terrain.dimensions
	var low := dimensions
	var high := Vector2i.ZERO
	for index: int in values:
		var point := Vector2i(index % dimensions.x, index / dimensions.x)
		low = low.min(point)
		high = high.max(point)
		if commit:
			set_height(index, values[index])
		else:
			package.terrain.heights[index] = values[index]
	terrain_changed.emit(Rect2i(low, high - low + Vector2i.ONE))


func set_height(index: int, value: float) -> void:
	package.terrain.heights[index] = value
	var stored := package.terrain.heights[index]
	if stored == base_heights[index]:
		edits.erase(index)
	else:
		edits[index] = stored


func fail(message: String) -> bool:
	error = message
	return false
