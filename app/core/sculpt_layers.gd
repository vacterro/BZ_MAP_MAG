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
	return {"uid": uid, "enabled": true, "opacity": 1.0, "deltas": {}}


static func normalize(raw: Dictionary) -> Dictionary:
	var result := layer(int(raw.get("uid", -1)))
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
static func compose(base_heights: PackedFloat32Array, stack: Array, limit: float, committed: Dictionary = {}) -> Dictionary:
	var values := {}
	for layer_v in stack:
		var layer: Dictionary = normalize(layer_v as Dictionary)
		if not bool(layer["enabled"]) or is_equal_approx(float(layer["opacity"]), 0.0):
			continue
		var opacity := float(layer["opacity"])
		for index: int in (layer["deltas"] as Dictionary):
			if index < 0 or index >= base_heights.size():
				continue
			var before: float = values.get(index, float(committed.get(index, base_heights[index])))
			var after := clampf(before + float((layer["deltas"] as Dictionary)[index]) * opacity, -limit, limit)
			values[index] = after
	return values
