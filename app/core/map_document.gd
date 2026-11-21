extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Graph := preload("res://nodes/height_graph.gd")
const PathCodec := preload("res://formats/bzn_paths.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const Water := preload("res://formats/water_v5.gd")
const SlopeShapes := preload("res://core/slope_shapes.gd")
const VrvShapes := preload("res://core/vrv_shapes.gd")
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
signal water_changed

const WATER_LAYERS := 8
const WATER_BLOCK := 16

var package: Package
var base_heights := PackedFloat32Array()
var edits := {}
var path_edits := {}
var native_path_ids := {}
var asset_profile := ""
var object_edits := {}
var object_label_edits := {}
var object_additions: Array = []
var object_removals := {}
var next_object_id := 1
var water_edits := {}
var water_heights := {}
var water_base := {}
var water_stroke := {}
var water_stroke_active := false
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
	water_edits = {}
	water_heights = {}
	water_base = {}
	water_stroke = {}
	water_stroke_active = false
	object_label_edits = {}
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
		if not read_object_label_edits(saved.get("objectLabelEdits", {})):
			return false
		if not read_object_removals(saved.get("objectRemovals", [])):
			return false
		if not read_object_additions(saved.get("objectInserts", [])):
			return false
		if not read_water_edits(saved.get("waterEdits", {})):
			return false
	if not package.check_sources():
		return fail(package.error)
	edit_revision += 1
	return true


static func sound_point(label: String) -> Dictionary:
	# VRV sound points are plain BZN objects of vrv_sndpoint whose label carries
	# vrvsnd:<sound>:<volume>:<range>:<interval>:<jitter>:<pitch>:<near>
	# (VRV src/shared/SoundPoints.h). Playback stays VRV-managed.
	if not label.begins_with("vrvsnd:"):
		return {}
	var parts := label.split(":")
	if parts.size() != 8:
		return {}
	var sound := parts[1]
	if sound.is_empty() or sound.length() > 48:
		return {}
	for character in sound:
		if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."):
			return {}
	var extension := sound.get_extension().to_lower()
	if extension != "wav" and extension != "ogg":
		return {}
	var values: Array[int] = []
	for index in range(2, 8):
		if not parts[index].is_valid_int():
			return {}
		values.append(int(parts[index]))
	return {"odf": "vrv_sndpoint", "sound": sound, "volume": values[0], "range": values[1],
		"interval": values[2], "jitter": values[3], "pitch": values[4], "near": values[5]}


static func format_sound_point(settings: Dictionary) -> Dictionary:
	var sound := String(settings.get("sound", "")).strip_edges()
	if sound.is_empty() or sound.length() > 48:
		return {"label": "", "error": "Enter a sound filename between 1 and 48 characters."}
	for character in sound:
		if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."):
			return {"label": "", "error": "Sound filename may only use A-Z, 0-9, '_', '-' and '.'."}
	var extension := sound.get_extension().to_lower()
	if extension != "wav" and extension != "ogg":
		return {"label": "", "error": "Sound filename must end with .wav or .ogg."}
	var volume := clampi(int(settings.get("volume", 70)), 0, 100)
	var rng := clampi(int(settings.get("range", 150)), 10, 2000)
	var interval := clampi(int(settings.get("interval", 0)), 0, 600)
	var jitter := clampi(int(settings.get("jitter", 0)), 0, 100)
	var pitch := clampi(int(settings.get("pitch", 100)), 25, 200)
	var near := clampi(int(settings.get("near", 20)), 0, 90)
	return {
		"label": "vrvsnd:%s:%d:%d:%d:%d:%d:%d" % [sound, volume, rng, interval, jitter, pitch, near],
		"error": "",
	}


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
	elif change.has("path_batch"):
		var batch: Array = change["path_batch"]
		var ordered := batch.duplicate()
		if direction == "before":
			ordered.reverse()
		for item: Dictionary in ordered:
			set_path_edit_silent(int(item["index"]), item[direction])
		paths_changed.emit()
	elif change.has("object"):
		apply_object_transform(change["object"], change[direction])
	elif change.has("object_label"):
		apply_object_label(change["object_label"], String(change[direction]))
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
	elif change.has("water"):
		var layer := int(change["water"])
		for block: int in change[direction]:
			set_water_cover(layer, block, change[direction][block])
		water_changed.emit()
	elif change.has("water_height"):
		set_water_height_internal(int(change["water_height"]), float(change[direction]))
		water_changed.emit()
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


func set_path_edit_silent(index: int, data: Dictionary) -> void:
	if same_path_fields(source_path_at(index), data):
		path_edits.erase(index)
	else:
		path_edits[index] = data


func set_path_edit(index: int, data: Dictionary) -> void:
	set_path_edit_silent(index, data)
	paths_changed.emit()


func allocate_path_id() -> int:
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
	return id


func create_paths_batch(specs: Array[Dictionary]) -> Array[int]:
	var created: Array[int] = []
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return created
	if not package.path_codec.can_resize or path_indices().size() + specs.size() > PathCodec.MAX_PATHS:
		fail("This native path table cannot accept that many paths.")
		return created
	var batch: Array[Dictionary] = []
	var next_index := package.paths.size()
	var taken_names := {}
	for slot in path_indices():
		taken_names[String(path_at(slot)["name"]).to_lower()] = true
	var used_ids := path_pointer_counts().duplicate()
	for slot in path_indices():
		used_ids[path_at(slot)["id"]] = true
	var next_id := allocate_path_id()
	for spec: Dictionary in specs:
		var label := String(spec.get("name", ""))
		var points: PackedVector2Array = spec.get("points", PackedVector2Array())
		var kind := int(spec.get("type", 0))
		if not valid_path_fields(label, points, kind, {}) or taken_names.has(label.to_lower()):
			return []
		taken_names[label.to_lower()] = true
		while path_edits.has(next_index):
			next_index += 1
		while used_ids.has(next_id):
			next_id = 1 if next_id == 4294967295 else next_id + 1
		used_ids[next_id] = true
		var data := {"id": next_id, "name": label, "points": points.duplicate(), "type": kind}
		batch.append({"index": next_index, "before": {}, "after": data})
		created.append(next_index)
		next_index += 1
	if batch.is_empty():
		return created
	push_history({"path_batch": batch})
	for item: Dictionary in batch:
		set_path_edit_silent(int(item["index"]), item["after"])
	paths_changed.emit()
	return created


func edit_paths_batch(changes: Array[Dictionary]) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	var batch: Array[Dictionary] = []
	for item: Dictionary in changes:
		var index := int(item["index"])
		var before := path_at(index)
		if before.is_empty():
			return fail("Select a supported native path.")
		var label := String(item["name"])
		var points: PackedVector2Array = item["points"]
		var kind := int(item["type"])
		var base := source_path_at(index)
		if not valid_path_fields(label, points, kind, base) or not unique_path_name(index, label):
			return false
		var after := {"id": before["id"], "name": label, "points": points.duplicate(), "type": kind}
		if not same_path_fields(after, before):
			batch.append({"index": index, "before": before, "after": after})
	if batch.is_empty():
		return true
	push_history({"path_batch": batch})
	for item: Dictionary in batch:
		set_path_edit_silent(int(item["index"]), item["after"])
	paths_changed.emit()
	return true


func clone_path(index: int, offset := Vector2(32.0, 32.0)) -> int:
	var source := path_at(index)
	if source.is_empty():
		fail("Select a path to clone.")
		return -1
	var base_name := String(source["name"])
	var candidate := ""
	for suffix in range(2, 999):
		var try_name := "%s_%d" % [base_name, suffix]
		if try_name.length() > 64:
			try_name = base_name.substr(0, maxi(1, 64 - str(suffix).length() - 1)) + "_" + str(suffix)
		var taken := false
		for other in path_indices():
			if try_name.nocasecmp_to(String(path_at(other)["name"])) == 0:
				taken = true
				break
		if not taken:
			candidate = try_name
			break
	if candidate.is_empty():
		fail("No unique clone path name available.")
		return -1
	var terrain := package.terrain
	var rect := Rect2(Vector2(terrain.origin) * Terrain.SPACING, Vector2((terrain.dimensions - Vector2i.ONE).maxi(1)) * Terrain.SPACING)
	var pts := PackedVector2Array()
	for pt: Vector2 in source["points"]:
		var shifted := pt + offset
		pts.append(Vector2(clampf(shifted.x, rect.position.x, rect.end.x), clampf(shifted.y, rect.position.y, rect.end.y)))
	return create_path(candidate, pts, int(source["type"]))


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


func read_object_label_edits(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary or saved.size() > package.objects.size():
		return fail("Invalid project object label edits.")
	for key: String in saved:
		var index := key.to_int()
		var value: Variant = saved[key]
		if str(index) != key or index < 0 or index >= package.objects.size() or not (value is String) or String(value).length() > 128:
			return fail("Invalid saved object label edit.")
		set_base_object_label(index, String(value))
	return true


func read_water_edits(saved: Variant) -> bool:
	if package.water == null:
		return true if saved == null or (saved is Dictionary and saved.is_empty()) else fail("This map has no native water.")
	if not saved is Dictionary or saved.size() > WATER_LAYERS:
		return fail("Invalid project water edits.")
	for key: String in saved:
		var layer := key.to_int()
		if str(layer) != key or not valid_water_layer(layer):
			return fail("Invalid project water layer.")
		var entry: Variant = saved[key]
		if not entry is Dictionary:
			return fail("Invalid project water record.")
		var height: Variant = entry.get("height", null)
		if height != null:
			if not (height is float or height is int) or not is_finite(float(height)) or absf(float(height)) > Water.MAX_HEIGHT:
				return fail("Invalid saved water elevation.")
			set_water_height(layer, float(height), false)
		var cover: Variant = entry.get("cover", null)
		if cover != null:
			if not cover is Dictionary or cover.size() > package.water.width * package.water.depth:
				return fail("Invalid saved water coverage.")
			for block_key: String in cover:
				var block := block_key.to_int()
				if str(block) != block_key or block < 0 or block >= package.water.width * package.water.depth:
					return fail("Invalid saved water coverage reference.")
				var value: Variant = cover[block_key]
				if not (value is bool):
					return fail("Invalid saved water coverage value.")
				set_water_cover(layer, block, value)
	return true


func valid_water_layer(layer: int) -> bool:
	return package.water != null and layer >= 0 and layer < WATER_LAYERS


func water_block_count() -> int:
	var water := package.water
	return water.width * water.depth if water != null else 0


func water_base_cover(layer: int) -> Dictionary:
	if not water_base.has(layer):
		var result := {}
		for record: Dictionary in package.water.layers:
			if int(record["index"]) == layer:
				for tile: Vector2 in record["tiles"]:
					result[int(tile.y) * package.water.width + int(tile.x)] = true
				break
		water_base[layer] = result
	return water_base[layer]


func water_effective_cover(layer: int) -> Dictionary:
	var result := water_base_cover(layer).duplicate()
	if water_edits.has(layer):
		for block: int in water_edits[layer]:
			if water_edits[layer][block]:
				result[block] = true
			else:
				result.erase(block)
	return result


func water_cover_count(layer: int) -> int:
	return water_effective_cover(layer).size()


func water_layer_height(layer: int) -> float:
	if water_heights.has(layer):
		return float(water_heights[layer])
	return Water.layer_height(package.water_bytes, layer)


func water_layers_effective() -> Array:
	var result: Array = []
	if package.water == null:
		return result
	for layer in WATER_LAYERS:
		var cover := water_effective_cover(layer)
		if cover.is_empty():
			continue
		var blocks := cover.keys()
		blocks.sort()
		var tiles := PackedVector2Array()
		for block: int in blocks:
			tiles.append(Vector2(block % package.water.width, block / package.water.width))
		result.append({"index": layer, "height": water_layer_height(layer), "tiles": tiles})
	return result


func set_water_height(layer: int, height: float, announce := true) -> bool:
	if not valid_water_layer(layer) or not is_finite(height) or absf(height) > Water.MAX_HEIGHT:
		return fail("Choose a water layer and a finite elevation within ±100000 m.")
	var before := water_layer_height(layer)
	if before == height:
		return true
	set_water_height_internal(layer, height)
	if announce:
		push_history({"water_height": layer, "before": before, "after": height})
	water_changed.emit()
	return true


func set_water_height_internal(layer: int, height: float) -> void:
	if height == Water.layer_height(package.water_bytes, layer):
		water_heights.erase(layer)
	else:
		water_heights[layer] = height


func set_water_cover(layer: int, block: int, value: bool) -> void:
	if water_base_cover(layer).get(block, false) == value:
		var record: Dictionary = water_edits.get(layer, {})
		record.erase(block)
		if record.is_empty():
			water_edits.erase(layer)
		else:
			water_edits[layer] = record
		return
	if not water_edits.has(layer):
		water_edits[layer] = {}
	water_edits[layer][block] = value


func begin_water_stroke() -> void:
	if has_preview():
		fail("Clear the terrain preview before painting water.")
		return
	water_stroke = {}
	water_stroke_active = true


func water_dab(point: Vector2, radius_m: float, layer: int, add: bool) -> void:
	if not water_stroke_active or not valid_water_layer(layer) or not is_finite(radius_m) or radius_m <= 0.0 or radius_m > 1024.0:
		return
	var water := package.water
	var block_m := Terrain.SPACING * Terrain.BLOCK
	var radius := radius_m / block_m
	var center := Vector2(point.x, point.y) / WATER_BLOCK
	var cover := water_effective_cover(layer)
	for block in water_block_count():
		var column := block % water.width
		var row := block / water.width
		var nearest := center.clamp(Vector2(column, row), Vector2(column + 1.0, row + 1.0))
		if center.distance_to(nearest) > radius:
			continue
		if not water_stroke.has(block):
			water_stroke[block] = cover.get(block, false)
		set_water_cover(layer, block, add)
	water_changed.emit()


func end_water_stroke(layer: int) -> void:
	if not water_stroke_active:
		return
	water_stroke_active = false
	if water_stroke.is_empty():
		return
	var after := {}
	for block: int in water_stroke:
		after[block] = water_effective_cover(layer).get(block, false)
	push_history({"water": layer, "before": water_stroke.duplicate(), "after": after})
	water_stroke = {}


func has_water_file_edits() -> bool:
	return not water_edits.is_empty() or not water_heights.is_empty()


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
	var base := object_actual_index(view)
	if object_label_edits.has(base):
		return String(object_label_edits[base])
	return String(object_template(view).get("label", ""))


func object_team(view: int) -> int:
	return int(object_template(view).get("team", 0))


func object_sequence(view: int) -> int:
	var seq := int(object_addition(view).get("sequence", 0)) if object_is_added(view) else int(object_template(view).get("sequence", 0))
	var lbl := object_label(view)
	if not lbl.is_empty():
		return seq & ~0x800000
	if not object_is_added(view) and object_label_edits.has(object_actual_index(view)):
		return seq | 0x800000
	return seq


func object_pool_reference(view: int) -> int:
	# The base object that supplies the mesh, team and pool for this view.
	var entry := object_entry(view)
	if entry.is_empty():
		return -1
	if entry.has("added"):
		return int(object_addition(view).get("template", -1))
	return int(entry["base"])


func has_object_file_edits() -> bool:
	return not object_edits.is_empty() or not object_label_edits.is_empty() or not object_removals.is_empty() or not object_additions.is_empty()


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
		return "add:%d" % int(object_addition(view)["id"])
	return object_actual_index(view)


static func addition_history_id(key: Variant) -> int:
	if key is String and String(key).begins_with("add:"):
		return String(key).substr(4).to_int()
	return int(key)


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


func set_object_label(view: int, new_label: String) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if not valid_view_object(view) or new_label.length() > 128:
		return fail("Select a valid object with a label of at most 128 characters.")
	var before := object_label(view)
	if before == new_label:
		return true
	var key: Variant = object_history_key(view)
	push_history({"object_label": key, "before": before, "after": new_label})
	apply_object_label(key, new_label)
	return true


func set_base_object_label(base: int, new_label: String) -> void:
	if String(package.objects[base].get("label", "")) == new_label:
		object_label_edits.erase(base)
	else:
		object_label_edits[base] = new_label


func apply_object_label(key: Variant, new_label: String) -> void:
	if key is int and key >= 0 and key < package.objects.size():
		set_base_object_label(int(key), new_label)
		object_moved.emit(view_for_base(int(key)))
		return
	var target_id := addition_history_id(key)
	for addition in object_additions:
		if int(addition["id"]) == target_id:
			addition["label"] = new_label
			object_moved.emit(find_object_view(addition))
			return


func apply_object_transform(key: Variant, transform: Transform3D) -> void:
	if key is int and key >= 0 and key < package.objects.size():
		if package.objects[key]["transform"] == transform:
			object_edits.erase(key)
		else:
			object_edits[key] = {"basis": transform.basis, "position": transform.origin}
		object_moved.emit(view_for_base(int(key)))
		return
	var target_id := addition_history_id(key)
	for addition in object_additions:
		if int(addition["id"]) == target_id:
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


func preview_slope_shape(params: Dictionary, batch := {}) -> bool:
	## Advanced sculptor preview: every batch instance evaluates deterministically
	## against the heights before the batch, then the merged result goes through
	## the shared preview/bake pipeline (one undo step per apply).
	if stroke_active:
		return fail("Finish the stroke before shaping terrain.")
	clear_preview()
	var terrain := package.terrain
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var checked_params := params.duplicate()
	checked_params["max_abs_height"] = limit
	var built := SlopeShapes.instances_checked(checked_params, batch)
	if not String(built["error"]).is_empty():
		return fail(String(built["error"]))
	var values := {}
	for instance: Dictionary in built["instances"]:
		var shaped: Dictionary = SlopeShapes.evaluate(instance, terrain.dimensions, terrain.origin, terrain.heights)
		if not String(shaped["error"]).is_empty():
			return fail(shaped["error"])
		for index in shaped["values"]:
			values[index] = shaped["values"][index]
	if values.is_empty():
		return fail("The shape covers no terrain samples. Check start, end, width and masks.")
	var native_sample := PackedFloat32Array([0.0])
	for index in values:
		var value := float(values[index])
		if not is_finite(value) or absf(value) > limit:
			return fail("The shape exceeds the terrain height range.")
		native_sample[0] = value
		values[index] = native_sample[0]
	return show_preview(values)


func preview_vrv_shape(op: String, params: Dictionary, region: Rect2i = Rect2i()) -> bool:
	if stroke_active:
		return fail("Finish the stroke before shaping terrain.")
	clear_preview()
	var terrain := package.terrain
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var strength := clampi(int(params.get("strength", 35)), 0, 100)
	var grain_m := clampi(int(params.get("grain_m", 16)), 2, 64)
	var values: Dictionary = {}
	match op:
		"smooth":
			values = VrvShapes.smooth(terrain.heights, terrain.dimensions, region, strength, grain_m, package.granularity, limit)
		"rough_plus", "rough_minus":
			values = VrvShapes.rough(
				terrain.heights, terrain.dimensions, terrain.origin, region,
				strength, grain_m,
				clampi(int(params.get("softness", 50)), 0, 100),
				clampi(int(params.get("contrast", 35)), 0, 100),
				int(params.get("seed", 1)),
				1 if op == "rough_plus" else -1,
				String(params.get("symmetry", "none")),
				package.granularity, limit
			)
		"relief_plus", "relief_minus":
			values = VrvShapes.relief(terrain.heights, terrain.dimensions, region, strength, 1 if op == "relief_plus" else -1, package.granularity, limit)
		_:
			return fail("Unsupported VRV terrain shape operation.")
	if values.is_empty():
		return fail("The selected VRV shape produced no height changes.")
	return show_preview(values)


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
