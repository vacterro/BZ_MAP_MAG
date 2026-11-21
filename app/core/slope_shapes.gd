extends RefCounted
## Advanced terrain sculptor geometry: deterministic heightfield shapes evaluated
## in world metres on the native terrain grid. Pure static functions; the
## document command applies their result through the regular preview/bake
## pipeline. Everything here is heightfield-compatible by construction: a
## single height per X/Z sample, no overhangs.

const SPACING := 2.0
const MAX_ANGLE_DEG := 89.9
const MAX_ABS_HEIGHT := 100000.0
const MAX_BATCH_COUNT := 64

const PROFILES := ["flat", "rounded", "soft", "terrace", "cliff", "plateau", "berm", "ridge", "valley", "trench", "excavation"]


static func _is_valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


## Validates shape and batch parameters before any instance materialization or
## terrain evaluation. Returns an empty string on valid input.
static func validate(params: Dictionary, batch: Dictionary = {}) -> String:
	var raw_start: Variant = params.get("start")
	var raw_end: Variant = params.get("end")
	if not raw_start is Vector2 or not (raw_start as Vector2).is_finite() or not raw_end is Vector2 or not (raw_end as Vector2).is_finite():
		return "Start and end coordinates must be finite."
	var start: Vector2 = raw_start
	var finish: Vector2 = raw_end
	var axis := finish - start
	var length := axis.length()
	if not is_finite(length) or length < SPACING:
		return "The shape needs a span of at least one terrain sample."
	var max_abs_height := MAX_ABS_HEIGHT
	if params.has("max_abs_height"):
		var raw_limit: Variant = params["max_abs_height"]
		if not _is_valid_number(raw_limit) or float(raw_limit) <= 0.0:
			return "Height limit must be positive and finite."
		max_abs_height = float(raw_limit)
	if not params.has("start_height") or not _is_valid_number(params["start_height"]):
		return "The shape needs finite heights."
	var start_height := float(params["start_height"])
	if absf(start_height) > max_abs_height:
		return "The shape exceeds the terrain height range."
	var mode := String(params.get("mode", "elevation"))
	if mode == "angle":
		var raw_angle: Variant = params.get("angle_deg", 0.0)
		if not _is_valid_number(raw_angle):
			return "Angle must be finite."
		var angle_deg := float(raw_angle)
		if absf(angle_deg) >= MAX_ANGLE_DEG:
			return "Angle must stay strictly between -90 and 90 degrees."
		var target := start_height + length * tan(deg_to_rad(angle_deg))
		if not is_finite(target) or absf(target) > max_abs_height:
			return "The shape exceeds the terrain height range."
	else:
		var raw_target: Variant = params.get("target_height", start_height)
		if not _is_valid_number(raw_target):
			return "The shape needs finite heights."
		var target := float(raw_target)
		if absf(target) > max_abs_height:
			return "The shape exceeds the terrain height range."
	var raw_width: Variant = params.get("width_m", 8.0)
	if not _is_valid_number(raw_width) or float(raw_width) <= 0.0:
		return "Width must be positive and finite."
	var raw_falloff: Variant = params.get("falloff_m", 0.0)
	if not _is_valid_number(raw_falloff) or float(raw_falloff) < 0.0:
		return "Edge falloff must be non-negative and finite."
	var raw_amplitude: Variant = params.get("amplitude_m", 10.0)
	if not _is_valid_number(raw_amplitude) or float(raw_amplitude) < 0.0:
		return "Amplitude must be non-negative and finite."
	var raw_levels: Variant = params.get("terrace_levels", 4)
	if not _is_valid_number(raw_levels) or int(raw_levels) < 1:
		return "Terrace levels must be at least 1."
	var raw_granularity: Variant = params.get("granularity", 0.1)
	if not _is_valid_number(raw_granularity) or float(raw_granularity) <= 0.0:
		return "Granularity must be positive and finite."
	if params.has("height_min") and not _is_valid_number(params["height_min"]):
		return "Height minimum mask must be finite."
	if params.has("height_max") and not _is_valid_number(params["height_max"]):
		return "Height maximum mask must be finite."
	if params.has("slope_max_percent") and (not _is_valid_number(params["slope_max_percent"]) or float(params["slope_max_percent"]) < 0.0):
		return "Maximum slope mask must be non-negative and finite."
	var raw_count: Variant = batch.get("count", 1)
	if not _is_valid_number(raw_count) or int(raw_count) < 1 or int(raw_count) > MAX_BATCH_COUNT:
		return "Instance count must be between 1 and %d." % MAX_BATCH_COUNT
	var raw_spacing: Variant = batch.get("spacing_m", 32.0)
	if not _is_valid_number(raw_spacing) or float(raw_spacing) <= 0.0:
		return "Instance spacing must be positive and finite."
	if batch.has("symmetry_origin"):
		var raw_origin: Variant = batch["symmetry_origin"]
		if not raw_origin is Vector2 or not (raw_origin as Vector2).is_finite():
			return "Symmetry origin must be finite."
	return ""


## Evaluates one shape instance against the current terrain heights.
## params keys: start (Vector2, world m), end (Vector2), start_height (float),
## mode ("elevation"|"angle"), target_height (float), angle_deg (float),
## width_m, falloff_m, profile (PROFILES), amplitude_m, terrace_levels,
## angle_deg, height_min/height_max (optional masks), slope_max_percent
## (optional mask). Returns { "values": {index: float}, "region": Rect2i }.
static func evaluate(params: Dictionary, dimensions: Vector2i, origin: Vector2i, heights: PackedFloat32Array) -> Dictionary:
	var error := validate(params)
	if not error.is_empty():
		return {"values": {}, "region": Rect2i(), "error": error}
	var values := {}
	var bounds := Rect2i(Vector2i.ZERO, dimensions)
	var profile := String(params.get("profile", "flat"))
	var start: Vector2 = params["start"]
	var finish: Vector2 = params["end"]
	var axis: Vector2 = finish - start
	var length := axis.length()
	if length < SPACING or not axis.is_finite():
		return {"values": {}, "region": Rect2i(), "error": "The shape needs a span of at least one terrain sample."}
	var unit := axis / length
	var side := Vector2(-unit.y, unit.x)
	var width: float = maxf(float(params.get("width_m", 8.0)), SPACING)
	var falloff: float = clampf(float(params.get("falloff_m", 0.0)), 0.0, width * 0.5)
	var half := width * 0.5
	var reach := half + falloff
	var start_height := float(params["start_height"])
	var target := start_height
	var mode := String(params.get("mode", "elevation"))
	if mode == "angle":
		target = start_height + length * tan(deg_to_rad(float(params.get("angle_deg", 0.0))))
	else:
		target = float(params.get("target_height", start_height))
	if not is_finite(target) or not is_finite(start_height):
		return {"values": {}, "region": Rect2i(), "error": "The shape needs finite heights."}
	var amplitude := float(params.get("amplitude_m", 10.0))
	var levels: int = maxi(int(params.get("terrace_levels", 4)), 1)
	var mask_min: float = params.get("height_min", NAN) if params.has("height_min") else NAN
	var mask_max: float = params.get("height_max", NAN) if params.has("height_max") else NAN
	var slope_max: float = params.get("slope_max_percent", NAN) if params.has("slope_max_percent") else NAN
	var smooth_lateral := profile == "berm" or profile == "valley"

	# Bounding box of the shape footprint in sample coordinates, clamped to the map.
	@warning_ignore("narrowing_conversion")
	var from_x: int = maxi(int(floor((minf(start.x, finish.x) - reach) / SPACING - origin.x)), 0)
	@warning_ignore("narrowing_conversion")
	var to_x: int = mini(int(ceil((maxf(start.x, finish.x) + reach) / SPACING - origin.x)) + 1, dimensions.x - 1)
	@warning_ignore("narrowing_conversion")
	var from_z: int = maxi(int(floor((minf(start.y, finish.y) - reach) / SPACING - origin.y)), 0)
	@warning_ignore("narrowing_conversion")
	var to_z: int = mini(int(ceil((maxf(start.y, finish.y) + reach) / SPACING - origin.y)) + 1, dimensions.y - 1)

	var region := Rect2i()
	for z in range(from_z, to_z + 1):
		for x in range(from_x, to_x + 1):
			var world := Vector2((origin.x + x) * SPACING, (origin.y + z) * SPACING)
			var rel := world - start
			var along := rel.dot(unit)
			var lateral := absf(rel.dot(side))
			if along < -falloff or along > length + falloff or lateral > reach:
				continue
			var index := z * dimensions.x + x
			var current := heights[index]
			if is_finite(mask_min) and current < mask_min:
				continue
			if is_finite(mask_max) and current > mask_max:
				continue
			if is_finite(slope_max) and exceeds_slope(heights, dimensions, x, z, slope_max):
				continue
			var weight := lateral_weight(lateral, half, reach, smooth_lateral)
			weight *= longitudinal_weight(along, length, falloff)
			if weight <= 0.0:
				continue
			var progress := clampf(along / length, 0.0, 1.0)
			var shaped := shape_height(profile, start_height, target, amplitude, levels, progress, along, length, falloff)
			var blended := lerpf(current, shaped, weight)
			if not is_finite(blended):
				continue
			values[index] = snappedf(blended, float(params.get("granularity", 0.1)))
			var point := Vector2i(x, z)
			if region == Rect2i():
				region = Rect2i(point, Vector2i.ONE)
			else:
				region = region.expand(point)
	return {"values": values, "region": region, "error": ""}


static func shape_height(profile: String, start_height: float, target: float, amplitude: float, levels: int, progress: float, along: float, length: float, falloff: float) -> float:
	var line := lerpf(start_height, target, progress)
	match profile:
		"flat":
			return line
		"rounded":
			return lerpf(start_height, target, smoothstepf(progress))
		"soft":
			return lerpf(start_height, target, cosine_ease(progress))
		"terrace":
			var level: int = clampi(int(round(progress * levels)), 0, levels)
			return lerpf(start_height, target, float(level) / float(levels))
		"cliff":
			# Flat at the start height, steep smooth rise over the last falloff.
			var span: float = maxf(falloff, SPACING)
			var transition := clampf((along - (length - span)) / span, 0.0, 1.0)
			return lerpf(start_height, target, smoothstepf(transition))
		"plateau":
			# Steep smooth rise over the first falloff, then a flat top at the target.
			var span: float = maxf(falloff, SPACING)
			return lerpf(start_height, target, smoothstepf(clampf(along / span, 0.0, 1.0)))
		"berm":
			return line + amplitude * pow(sin(PI * progress), 2.0)
		"ridge":
			return line + maxf(amplitude, 0.0)
		"valley":
			return line - maxf(amplitude, 0.0)
		"trench":
			return line - maxf(amplitude, 0.0)
		"excavation":
			# Flat cut below the start height, with ramps at both ends.
			var bottom := start_height - maxf(amplitude, 0.0)
			var span: float = maxf(falloff, SPACING)
			var entry := smoothstepf(clampf(along / span, 0.0, 1.0))
			var exit := smoothstepf(clampf((length - along) / span, 0.0, 1.0))
			return lerpf(start_height, bottom, entry * exit)
	return line


static func lateral_weight(lateral: float, half: float, reach: float, smooth: bool) -> float:
	if smooth:
		# Cosine crest: a rounded hill/valley cross-section across the full width.
		if reach <= 0.0 or lateral >= reach:
			return 0.0
		var angle: float = lateral / reach * PI * 0.5
		return pow(cos(angle), 2.0)
	if lateral <= half:
		return 1.0
	if reach <= half:
		return 0.0
	return smoothstepf(clampf((reach - lateral) / (reach - half), 0.0, 1.0))


static func longitudinal_weight(along: float, length: float, falloff: float) -> float:
	if falloff <= 0.0 or (along >= 0.0 and along <= length):
		return 1.0
	if along < 0.0:
		return smoothstepf(clampf((falloff + along) / falloff, 0.0, 1.0))
	return smoothstepf(clampf((length + falloff - along) / falloff, 0.0, 1.0))


static func smoothstepf(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func cosine_ease(value: float) -> float:
	return (1.0 - cos(clampf(value, 0.0, 1.0) * PI)) * 0.5


## Slope mask: the steepest neighbour rise over one sample step, in percent.
static func exceeds_slope(heights: PackedFloat32Array, dimensions: Vector2i, x: int, z: int, limit_percent: float) -> bool:
	var index := z * dimensions.x + x
	var current := heights[index]
	var steepest := 0.0
	for offset: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var nx: int = x + offset.x
		var nz: int = z + offset.y
		if nx < 0 or nz < 0 or nx >= dimensions.x or nz >= dimensions.y:
			continue
		steepest = maxf(steepest, absf(heights[nz * dimensions.x + nx] - current))
	return steepest / SPACING * 100.0 > limit_percent


## Batch arrangement: returns the validated instance list plus any error before
## materialization.
static func instances_checked(params: Dictionary, batch: Dictionary = {}) -> Dictionary:
	var result: Array[Dictionary] = []
	var error := validate(params, batch)
	if not error.is_empty():
		return {"instances": result, "error": error}
	var mode := String(batch.get("mode", "single"))
	var count := int(batch.get("count", 1))
	var mirror_x := bool(batch.get("mirror_x", false))
	var mirror_z := bool(batch.get("mirror_z", false))
	if mode == "single" and not mirror_x and not mirror_z:
		result.append(params)
		return {"instances": result, "error": ""}
	var start: Vector2 = params["start"]
	var finish: Vector2 = params["end"]
	var axis := finish - start
	var length := axis.length()
	if not is_finite(length) or length < SPACING:
		return {"instances": result, "error": "The shape needs a span of at least one terrain sample."}
	var unit := axis / length
	var side := Vector2(-unit.y, unit.x)
	var spacing := maxf(float(batch.get("spacing_m", 32.0)), SPACING)
	var copies: Array[Dictionary] = []
	if mode == "radial":
		# Fan instances around the start point through equal angles.
		for i in count:
			var angle := TAU * float(i) / float(count)
			var rotated := Vector2(unit.x * cos(angle) - unit.y * sin(angle), unit.x * sin(angle) + unit.y * cos(angle)) * length
			copies.append(shaped(params, start, start + rotated))
	elif mode == "single":
		copies.append(shaped(params, start, finish))
	else:
		# Parallel copies offset laterally on both sides of the centre line.
		for i in count:
			var offset_side := float(i - (count - 1) * 0.5) * spacing
			copies.append(shaped(params, start + side * offset_side, finish + side * offset_side))
	for copy in copies:
		if not (copy["start"] as Vector2).is_finite() or not (copy["end"] as Vector2).is_finite():
			return {"instances": [], "error": "Batch instance coordinates must remain finite."}
		result.append(copy)
		if mirror_x:
			var center: Vector2 = batch.get("symmetry_origin", Vector2(start.x, 0.0))
			var mx_start := Vector2(2.0 * center.x - copy["start"].x, copy["start"].y)
			var mx_end := Vector2(2.0 * center.x - copy["end"].x, copy["end"].y)
			if not mx_start.is_finite() or not mx_end.is_finite():
				return {"instances": [], "error": "Mirrored coordinates must remain finite."}
			result.append(shaped(params, mx_start, mx_end, true))
		if mirror_z:
			var center_z: Vector2 = batch.get("symmetry_origin", Vector2(0.0, start.y))
			var mz_start := Vector2(copy["start"].x, 2.0 * center_z.y - copy["start"].y)
			var mz_end := Vector2(copy["end"].x, 2.0 * center_z.y - copy["end"].y)
			if not mz_start.is_finite() or not mz_end.is_finite():
				return {"instances": [], "error": "Mirrored coordinates must remain finite."}
			result.append(shaped(params, mz_start, mz_end, false, true))
	return {"instances": result, "error": ""}


## Batch arrangement: returns the instance parameter list for one base shape.
## batch keys: mode ("single"|"linear"|"radial"), count, spacing_m,
## mirror_x, mirror_z, symmetry_origin (Vector2 world m).
static func instances(params: Dictionary, batch: Dictionary) -> Array[Dictionary]:
	var checked := instances_checked(params, batch)
	return checked["instances"]


static func shaped(params: Dictionary, start: Vector2, finish: Vector2, mirror_x := false, mirror_z := false) -> Dictionary:
	var copy := params.duplicate()
	copy["start"] = start
	copy["end"] = finish
	copy["mirrored"] = mirror_x or mirror_z
	return copy
