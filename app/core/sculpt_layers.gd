extends RefCounted
## Editor-only, non-destructive sculpt layers.
##
## A layer stores sparse height deltas keyed by native TER sample index. The
## committed terrain is never touched: composition produces a preview, and only
## Bake flattens the result into MapDocument.edits for native export.

const Terrain := preload("res://formats/terrain_v5.gd")

const MAX_LAYERS := 8
const MAX_DELTAS := 2_000_000
const MAX_ABS_DELTA := 100000.0


static func layer(uid: int) -> Dictionary:
	return {"uid": uid, "name": "Sculpt %d" % uid, "enabled": true, "opacity": 1.0, "deltas": {}}


static func normalize(raw: Dictionary) -> Dictionary:
	var result := layer(int(raw.get("uid", -1)))
	result["name"] = String(raw.get("name", result["name"])).strip_edges().substr(0, 64)
	result["enabled"] = bool(raw.get("enabled", true))
	result["opacity"] = clampf(float(raw.get("opacity", 1.0)), 0.0, 1.0)
	var deltas: Dictionary = {}
	var raw_deltas: Variant = raw.get("deltas", {})
	if raw_deltas is Dictionary:
		for key in (raw_deltas as Dictionary):
			var index := int(key)
			var value := float((raw_deltas as Dictionary)[key])
			if index >= 0 and is_finite(value) and value != 0.0:
				deltas[index] = value
	result["deltas"] = deltas
	return result


## Validates an UNMODIFIED saved sculpt record. Raw validation is deliberately
## separate from normalize(): a corrupt payload must be refused, not silently
## coerced into a different valid layer (e.g. "oops" -> sample index 0).
static func validate_raw_record(raw: Variant, sample_count: int) -> bool:
	if not raw is Dictionary:
		return false
	var record := raw as Dictionary
	var uid: Variant = record.get("uid", null)
	if not (uid is int or uid is float):
		return false
	var uid_number := float(uid)
	if not is_finite(uid_number) or uid_number <= 0.0 or uid_number != floorf(uid_number) or uid_number > 9007199254740992.0:
		return false
	var enabled: Variant = record.get("enabled", null)
	if not enabled is bool:
		return false
	var opacity: Variant = record.get("opacity", null)
	if not (opacity is int or opacity is float) or not is_finite(float(opacity)):
		return false
	var opacity_value := float(opacity)
	if opacity_value < 0.0 or opacity_value > 1.0:
		return false
	var raw_deltas: Variant = record.get("deltas", null)
	if not raw_deltas is Dictionary:
		return false
	var deltas := raw_deltas as Dictionary
	if deltas.size() > MAX_DELTAS:
		return false
	var seen := {}
	for key: Variant in deltas:
		var key_text: String
		if key is int or key is float:
			var number := float(key)
			if not is_finite(number) or number < 0.0 or number != floorf(number):
				return false
			key_text = str(int(number))
		elif key is String:
			key_text = key as String
			if key_text.is_empty() or not key_text.is_valid_int():
				return false
			if str(int(key_text)) != key_text:
				return false
		else:
			return false
		var index := int(key_text)
		if index < 0 or index >= sample_count or seen.has(index):
			return false
		seen[index] = true
		var value: Variant = deltas[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		var delta := float(value)
		if delta == 0.0 or absf(delta) > MAX_ABS_DELTA:
			return false
	return true


static func validate_stack_raw(stack: Array, sample_count: int) -> bool:
	if stack.size() > MAX_LAYERS:
		return false
	var seen := {}
	for item in stack:
		if not validate_raw_record(item, sample_count):
			return false
		var uid := int((item as Dictionary).get("uid"))
		if seen.has(uid):
			return false
		seen[uid] = true
	return true


static func validate_stack(stack: Array, sample_count: int) -> bool:
	if stack.size() > MAX_LAYERS:
		return false
	var seen := {}
	for item in stack:
		if not item is Dictionary:
			return false
		var layer: Dictionary = normalize(item as Dictionary)
		if int(layer["uid"]) <= 0 or seen.has(int(layer["uid"])):
			return false
		seen[int(layer["uid"])] = true
		var deltas: Dictionary = layer["deltas"]
		if deltas.size() > MAX_DELTAS:
			return false
		for index: int in deltas:
			if index < 0 or index >= sample_count or not is_finite(float(deltas[index])) or absf(float(deltas[index])) > MAX_ABS_DELTA:
				return false
	return true


## Composes sculpt deltas over the committed terrain revision. `committed`
## holds the document's height edits keyed by TER sample index; a sample absent
## from it falls back to the original TER height in `base_heights`. Composition
## must start from committed heights, never from the raw TER, or applying a
## sculpt layer would silently discard the user's earlier terrain edits.
## Fast path for already-normalized in-memory stacks. normalize() deep-copies
## every sparse delta dictionary, which is too expensive for per-dab previews;
## document-owned layers are canonical at every call site below.
static func compose_canonical(base_heights: PackedFloat32Array, stack: Array, limit: float, committed: Dictionary = {}, only_indices: Array = []) -> Dictionary:
	var values := {}
	var restricted := not only_indices.is_empty()
	if restricted:
		for raw_index in only_indices:
			var index := int(raw_index)
			if index >= 0 and index < base_heights.size():
				values[index] = float(committed.get(index, base_heights[index]))
	for layer_v in stack:
		if not layer_v is Dictionary:
			continue
		var layer := layer_v as Dictionary
		if not bool(layer.get("enabled", true)) or is_equal_approx(float(layer.get("opacity", 1.0)), 0.0):
			continue
		var opacity := float(layer.get("opacity", 1.0))
		var deltas: Variant = layer.get("deltas", {})
		if not deltas is Dictionary:
			continue
		for index: int in (deltas as Dictionary):
			if restricted and not values.has(index):
				continue
			if index < 0 or index >= base_heights.size():
				continue
			var before: float = values.get(index, float(committed.get(index, base_heights[index])))
			var after := clampf(before + float((deltas as Dictionary)[index]) * opacity, -limit, limit)
			values[index] = after
	return values


static func compose(base_heights: PackedFloat32Array, stack: Array, limit: float, committed: Dictionary = {}, only_indices: Array = []) -> Dictionary:
	var values := {}
	var restricted := not only_indices.is_empty()
	if restricted:
		for raw_index in only_indices:
			var index := int(raw_index)
			if index >= 0 and index < base_heights.size():
				values[index] = float(committed.get(index, base_heights[index]))
	for layer_v in stack:
		var layer: Dictionary = normalize(layer_v as Dictionary)
		if not bool(layer["enabled"]) or is_equal_approx(float(layer["opacity"]), 0.0):
			continue
		var opacity := float(layer["opacity"])
		for index: int in (layer["deltas"] as Dictionary):
			if restricted and not values.has(index):
				continue
			if index < 0 or index >= base_heights.size():
				continue
			var before: float = values.get(index, float(committed.get(index, base_heights[index])))
			var after := clampf(before + float((layer["deltas"] as Dictionary)[index]) * opacity, -limit, limit)
			values[index] = after
	return values
