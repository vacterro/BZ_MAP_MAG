extends RefCounted
## Editor-only, non-destructive color layers.
##
## A layer stores sparse RGB words and brush coverage keyed by native TER sample
## index. Committed native color edits stay untouched: composition produces a
## read-only display/export dictionary. Within one layer, repeated dabs at the
## same sample keep the newest RGB word and the strongest coverage seen in that
## stroke; a new stroke replaces both (last dab wins RGB, strongest coverage).

const Terrain := preload("res://formats/terrain_v5.gd")

const MAX_LAYERS := 8
const MAX_SAMPLES := 2_000_000
const MAX_NAME_LENGTH := 64
const MAX_UID := 9007199254740992.0
const MASK_DEFAULT := 1.0


static func layer(uid: int) -> Dictionary:
	return {"uid": uid, "name": "Color %d" % uid, "enabled": true, "opacity": 1.0,
		"samples": {}, "mask": null}


static func mask(default_strength: float = 0.0) -> Dictionary:
	return {"enabled": true, "default": clampf(default_strength, 0.0, 1.0), "samples": {}}


static func normalize_mask(raw: Variant, sample_count: int) -> Variant:
	if raw == null:
		return null
	if not raw is Dictionary:
		return null
	var data := raw as Dictionary
	var result := mask(float(data.get("default", 0.0)))
	result["enabled"] = bool(data.get("enabled", true))
	var samples := {}
	var raw_samples: Variant = data.get("samples", {})
	if raw_samples is Dictionary:
		for key in (raw_samples as Dictionary):
			var index := int(key)
			if index < 0 or index >= sample_count:
				continue
			var value := float((raw_samples as Dictionary)[key])
			if is_finite(value):
				samples[index] = clampf(value, 0.0, 1.0)
	result["samples"] = samples
	return result


static func normalize(raw: Dictionary) -> Dictionary:
	var result := layer(int(raw.get("uid", -1)))
	result["name"] = String(raw.get("name", result["name"])).strip_edges().substr(0, MAX_NAME_LENGTH)
	result["enabled"] = bool(raw.get("enabled", true))
	var opacity := float(raw.get("opacity", 1.0))
	result["opacity"] = clampf(opacity, 0.0, 1.0) if is_finite(opacity) else 1.0
	var samples: Dictionary = {}
	var raw_samples: Variant = raw.get("samples", {})
	if raw_samples is Dictionary:
		for key in (raw_samples as Dictionary):
			var index := int(key)
			var sample: Variant = (raw_samples as Dictionary)[key]
			if sample is Dictionary:
				var rgb := int(sample.get("rgb", -1))
				var coverage := float(sample.get("coverage", 0.0))
				if rgb >= 0 and rgb <= 0xffffff and is_finite(coverage) and coverage > 0.0 and coverage <= 1.0:
					samples[index] = {"rgb": rgb, "coverage": clampf(coverage, 0.0, 1.0)}
	result["samples"] = samples
	result["mask"] = normalize_mask(raw.get("mask", null), 1 << 30)
	return result


## Validates an UNMODIFIED saved color record. Raw validation is separate from
## normalize(): a corrupt payload must be refused, not silently coerced.
static func validate_raw_record(raw: Variant, sample_count: int) -> bool:
	if not raw is Dictionary:
		return false
	var record := raw as Dictionary
	var uid: Variant = record.get("uid", null)
	if not (uid is int or uid is float):
		return false
	var uid_number := float(uid)
	if not is_finite(uid_number) or uid_number <= 0.0 or uid_number != floorf(uid_number) or uid_number > MAX_UID:
		return false
	var name: Variant = record.get("name", null)
	if not name is String or (name as String).length() > MAX_NAME_LENGTH:
		return false
	if not record.get("enabled", null) is bool:
		return false
	var opacity: Variant = record.get("opacity", null)
	if not (opacity is int or opacity is float) or not is_finite(float(opacity)):
		return false
	var opacity_value := float(opacity)
	if opacity_value < 0.0 or opacity_value > 1.0:
		return false
	var raw_samples: Variant = record.get("samples", null)
	if not raw_samples is Dictionary or (raw_samples as Dictionary).size() > MAX_SAMPLES:
		return false
	var samples := raw_samples as Dictionary
	var seen := {}
	for key: Variant in samples:
		var key_text: String
		if key is int or key is float:
			var number := float(key)
			if not is_finite(number) or number < 0.0 or number != floorf(number) or number > MAX_UID:
				return false
			key_text = str(int(number))
		elif key is String:
			key_text = key as String
			if key_text.is_empty() or not key_text.is_valid_int() or str(int(key_text)) != key_text:
				return false
		else:
			return false
		var index := int(key_text)
		if index < 0 or index >= sample_count or seen.has(index):
			return false
		seen[index] = true
		var entry: Variant = samples[key]
		if not entry is Dictionary:
			return false
		var sample := entry as Dictionary
		var rgb: Variant = sample.get("rgb", null)
		var coverage: Variant = sample.get("coverage", null)
		if not (rgb is int or rgb is float) or not is_finite(float(rgb)) or float(rgb) != floorf(float(rgb)):
			return false
		var rgb_value := int(rgb)
		if rgb_value < 0 or rgb_value > 0xffffff:
			return false
		if not (coverage is int or coverage is float) or not is_finite(float(coverage)):
			return false
		var coverage_value := float(coverage)
		if coverage_value <= 0.0 or coverage_value > 1.0:
			return false
	if not validate_mask_raw(record.get("mask", null), sample_count):
		return false
	return true


static func validate_mask_raw(raw: Variant, sample_count: int) -> bool:
	if raw == null:
		return true
	if not raw is Dictionary:
		return false
	var data := raw as Dictionary
	if not data.get("enabled", null) is bool:
		return false
	var default_value: Variant = data.get("default", null)
	if not (default_value is int or default_value is float) or not is_finite(float(default_value)):
		return false
	if float(default_value) < 0.0 or float(default_value) > 1.0:
		return false
	var raw_samples: Variant = data.get("samples", null)
	if not raw_samples is Dictionary or (raw_samples as Dictionary).size() > MAX_SAMPLES:
		return false
	var seen := {}
	for key: Variant in (raw_samples as Dictionary):
		var index := -1
		if key is int or key is float:
			var number := float(key)
			if not is_finite(number) or number < 0.0 or number != floorf(number) or number > MAX_UID:
				return false
			index = int(number)
		elif key is String:
			var text := key as String
			if text.is_empty() or not text.is_valid_int() or str(int(text)) != text:
				return false
			index = int(text)
		else:
			return false
		if index < 0 or index >= sample_count or seen.has(index):
			return false
		seen[index] = true
		var value: Variant = (raw_samples as Dictionary)[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		if float(value) < 0.0 or float(value) > 1.0:
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
		var layer_data := normalize(item as Dictionary)
		if int(layer_data["uid"]) <= 0 or seen.has(int(layer_data["uid"])):
			return false
		seen[int(layer_data["uid"])] = true
		var samples: Dictionary = layer_data["samples"]
		if samples.size() > MAX_SAMPLES:
			return false
		for index: int in samples:
			if index < 0 or index >= sample_count:
				return false
	return true


## Composed RGB word for one sample. Native source word is the floor; committed
## native color edits are applied first. Enabled layers then blend in stack
## order with normal alpha: result = lerp(previous, layerRGB, opacity * coverage).
## Every channel is quantized to an 8-bit integer after its own blend, matching
## Terrain.rgb_word / word_color. Deterministic on CPU and GPU-facing previews.
static func compose_word(source_word: int, edits: Dictionary, stack: Array, index: int) -> int:
	var word: int = int(edits.get(index, source_word))
	for layer_v in stack:
		if not layer_v is Dictionary:
			continue
		var layer_data := layer_v as Dictionary
		if not bool(layer_data.get("enabled", true)):
			continue
		var samples: Variant = layer_data.get("samples", {})
		if not samples is Dictionary or not (samples as Dictionary).has(index):
			continue
		var opacity := clampf(float(layer_data.get("opacity", 1.0)), 0.0, 1.0)
		if opacity <= 0.0:
			continue
		var sample: Dictionary = (samples as Dictionary)[index]
		var coverage := clampf(float(sample.get("coverage", 0.0)), 0.0, 1.0)
		var alpha := clampf(opacity * coverage, 0.0, 1.0)
		if alpha <= 0.0:
			continue
		var paint: int = int(sample.get("rgb", 0))
		var mask_data: Variant = layer_data.get("mask", null)
		if mask_data is Dictionary and bool((mask_data as Dictionary).get("enabled", true)):
			var mask_samples: Variant = (mask_data as Dictionary).get("samples", {})
			var strength := float((mask_data as Dictionary).get("default", 0.0))
			if mask_samples is Dictionary and (mask_samples as Dictionary).has(index):
				strength = float((mask_samples as Dictionary)[index])
			alpha *= clampf(strength, 0.0, 1.0)
		if alpha > 0.0:
			word = blend_word(word, paint, alpha)
	return word


static func blend_word(background: int, foreground: int, alpha: float) -> int:
	if alpha <= 0.0:
		return background & 0xffffff
	if alpha >= 1.0:
		return foreground & 0xffffff
	var a := clampf(alpha, 0.0, 1.0)
	var r := clampi(int(roundf(lerpf(float((background >> 16) & 255), float((foreground >> 16) & 255), a))), 0, 255)
	var g := clampi(int(roundf(lerpf(float((background >> 8) & 255), float((foreground >> 8) & 255), a))), 0, 255)
	var b := clampi(int(roundf(lerpf(float(background & 255), float(foreground & 255), a))), 0, 255)
	return (r << 16) | (g << 8) | b


## Sparse composition: only indices whose final word differs from the native
## source are produced. Preview and export call the same function, so a dirty
## dab never rescans the map.
static func compose_changed(terrain: Terrain, stack: Array, indices: Array, edits: Dictionary = {}) -> Dictionary:
	var result := {}
	for raw_index in indices:
		var index := int(raw_index)
		if index < 0 or index >= terrain.heights.size():
			continue
		var source := terrain.source_material_value(Terrain.Layer.COLOR, index)
		var word := compose_word(source, edits, stack, index)
		if word != source:
			result[index] = word
	return result


static func compose_all(terrain: Terrain, stack: Array, edits: Dictionary = {}) -> Dictionary:
	# The candidate set is every committed edit plus every sample touched by an
	# enabled, nonzero-opacity layer. Samples outside that set keep native RGB
	# and must not be written into the export channel.
	var candidates: Dictionary = {}
	for index: int in edits:
		candidates[index] = true
	for layer_v in stack:
		if not layer_v is Dictionary:
			continue
		var layer_data := layer_v as Dictionary
		if not bool(layer_data.get("enabled", true)) or float(layer_data.get("opacity", 1.0)) <= 0.0:
			continue
		var samples: Variant = layer_data.get("samples", {})
		if samples is Dictionary:
			for index: int in (samples as Dictionary):
				candidates[index] = true
	return compose_changed(terrain, stack, candidates.keys(), edits)
