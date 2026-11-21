extends RefCounted
## VRV TerrainShape algorithms ported from vrv/src/shared/TerrainShape.h:
## Smooth (3-pass separable box blur), Rough +/- (multi-octave quintic lattice
## noise with grain, softness, contrast, deterministic seed and symmetry fold),
## and Relief +/- (mean-centered amplitude scaling).

const Terrain := preload("res://formats/terrain_v5.gd")


static func grain_points(grain_m: int) -> int:
	return maxi(1, mini(grain_m, 64) / 2)


static func fraction(percent: int) -> float:
	return float(clampi(percent, 0, 100)) / 100.0


static func _limit_value(h: float, limit: float) -> float:
	return clampf(h, -limit, limit)


static func _region_rect(dimensions: Vector2i, region: Rect2i) -> Rect2i:
	var full := Rect2i(Vector2i.ZERO, dimensions)
	if not region.has_area():
		return full
	var clipped := region.intersection(full)
	return clipped if clipped.has_area() else full


static func _blur(heights: PackedFloat32Array, dimensions: Vector2i, radius: int) -> PackedFloat32Array:
	var out := heights.duplicate()
	var w := dimensions.x
	var d := dimensions.y
	var line := PackedFloat64Array()
	# Horizontal pass
	line.resize(w)
	for z in d:
		var row := z * w
		for k in w:
			line[k] = out[row + k]
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += line[clampi(k, 0, w - 1)]
		var denom := float(2 * radius + 1)
		for k in w:
			out[row + k] = float(sum / denom)
			sum += line[mini(k + radius + 1, w - 1)] - line[maxi(k - radius, 0)]
	# Vertical pass
	line.resize(d)
	for x in w:
		for k in d:
			line[k] = out[k * w + x]
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += line[clampi(k, 0, d - 1)]
		var denom := float(2 * radius + 1)
		for k in d:
			out[k * w + x] = float(sum / denom)
			sum += line[mini(k + radius + 1, d - 1)] - line[maxi(k - radius, 0)]
	return out


static func smooth(heights: PackedFloat32Array, dimensions: Vector2i, region: Rect2i,
		strength: int, grain_m: int, granularity: float, limit: float) -> Dictionary:
	var values := {}
	var t := fraction(strength)
	if t <= 0.0 or dimensions.x <= 0 or dimensions.y <= 0:
		return values
	var rect := _region_rect(dimensions, region)
	var work := heights.duplicate()
	var radius := maxi(1, grain_points(grain_m) / 2)
	for _pass in 3:
		var blurred := _blur(work, dimensions, radius)
		for z in range(rect.position.y, rect.end.y):
			var row := z * dimensions.x
			for x in range(rect.position.x, rect.end.x):
				var idx := row + x
				work[idx] = _limit_value(work[idx] + t * (blurred[idx] - work[idx]), limit)
	for z in range(rect.position.y, rect.end.y):
		var row := z * dimensions.x
		for x in range(rect.position.x, rect.end.x):
			var idx := row + x
			var snapped := snappedf(work[idx], granularity)
			if is_finite(snapped) and snapped != heights[idx]:
				values[idx] = snapped
	return values


static func lattice(i: int, j: int, octave: int, seed_val: int) -> float:
	var h: int = ((i * 0x8da6b343) ^ (j * 0xd8163841) ^ (octave * 0xcb1ab31f) ^ (seed_val * 0x9e3779b9)) & 0xffffffff
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0xffffffff
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0xffffffff
	h = (h ^ (h >> 15)) & 0xffffffff
	return float(h & 0xffffff) / 8388607.5 - 1.0


static func _noise(x: float, z: float, spacing: float, octave: int, seed_val: int) -> float:
	var gx := x / spacing
	var gz := z / spacing
	var ix := int(floor(gx))
	var iz := int(floor(gz))
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	fx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	fz = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
	var a := lattice(ix, iz, octave, seed_val)
	var b := lattice(ix + 1, iz, octave, seed_val)
	var c := lattice(ix, iz + 1, octave, seed_val)
	var d := lattice(ix + 1, iz + 1, octave, seed_val)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


static func bumps(x: float, z: float, grain_m: int, softness: int, contrast: int, seed_val: int) -> float:
	var soft := fraction(softness)
	var cont := fraction(contrast)
	var octaves := 1 + int(floor(3.0 * (1.0 - soft) + 0.5))
	var persistence := 0.5 - 0.2 * soft
	var n := 0.0
	var weight := 1.0
	var total := 0.0
	var spacing := float(grain_points(grain_m))
	for o in octaves:
		n += weight * _noise(x, z, spacing, o, seed_val)
		total += weight
		weight *= persistence
		spacing = maxf(1.0, spacing * 0.5)
	n /= total
	if cont > 0.0:
		var k := 4.0 * cont
		n = tanh(k * n) / tanh(k)
	return n


static func rough(heights: PackedFloat32Array, dimensions: Vector2i, origin: Vector2i, region: Rect2i,
		strength: int, grain_m: int, softness: int, contrast: int, seed_val: int, sign_dir: int,
		symmetry: String, granularity: float, limit: float) -> Dictionary:
	var values := {}
	if dimensions.x <= 0 or dimensions.y <= 0:
		return values
	var rect := _region_rect(dimensions, region)
	var amplitude := fraction(strength) * float(clampi(grain_m, 2, 64)) * 0.5 * (-1.0 if sign_dir < 0 else 1.0)
	if amplitude == 0.0:
		return values
	var sym_x := symmetry in ["x", "xz"]
	var sym_z := symmetry in ["z", "xz"]
	for z in range(rect.position.y, rect.end.y):
		var row := z * dimensions.x
		var sz := mini(z, dimensions.y - 1 - z) if sym_z else z
		var wz := float(origin.y + sz)
		for x in range(rect.position.x, rect.end.x):
			var sx := mini(x, dimensions.x - 1 - x) if sym_x else x
			var wx := float(origin.x + sx)
			var idx := row + x
			var next_h := _limit_value(heights[idx] + amplitude * bumps(wx, wz, grain_m, softness, contrast, seed_val), limit)
			var snapped := snappedf(next_h, granularity)
			if is_finite(snapped) and snapped != heights[idx]:
				values[idx] = snapped
	return values


static func relief(heights: PackedFloat32Array, dimensions: Vector2i, region: Rect2i,
		strength: int, sign_dir: int, granularity: float, limit: float) -> Dictionary:
	var values := {}
	if dimensions.x <= 0 or dimensions.y <= 0:
		return values
	var rect := _region_rect(dimensions, region)
	var count := rect.get_area()
	if count <= 0:
		return values
	var sum := 0.0
	for z in range(rect.position.y, rect.end.y):
		var row := z * dimensions.x
		for x in range(rect.position.x, rect.end.x):
			sum += heights[row + x]
	var mean := sum / float(count)
	var factor := 1.0 + (-1.0 if sign_dir < 0 else 1.0) * fraction(strength)
	for z in range(rect.position.y, rect.end.y):
		var row := z * dimensions.x
		for x in range(rect.position.x, rect.end.x):
			var idx := row + x
			var next_h := _limit_value(mean + (heights[idx] - mean) * factor, limit)
			var snapped := snappedf(next_h, granularity)
			if is_finite(snapped) and snapped != heights[idx]:
				values[idx] = snapped
	return values
