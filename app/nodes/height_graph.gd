extends RefCounted

const Terrain := preload("res://formats/terrain_v5.gd")

enum Port { HEIGHT, DELTA, RGB, TILE, SLOPE, MASK }

const INPUT := "Input"
const NOISE := "Noise"
const BLEND := "Blend"
const CLAMP := "Clamp"
const OUTPUT := "Output"
const EXISTING_COLOR := "Existing Color"
const EXISTING_TILE := "Existing Tile"
const SLOPE := "Slope"
const MASK := "Mask"
const COLOR_BLEND := "Blend Color"
const COLOR_RAMP := "Color Ramp"
const HEIGHT_MASK := "Height Range Mask"
const SLOPE_MASK := "Slope Mask"
const THRESHOLD := "Threshold"
const TILE_SELECT := "Tile Select"
const COLOR_OUTPUT := "Color Output"
const TILE_OUTPUT := "Tile Output"
const NODE_NAMES := [INPUT, NOISE, BLEND, CLAMP, OUTPUT, EXISTING_COLOR, EXISTING_TILE, SLOPE, MASK,
	COLOR_BLEND, COLOR_RAMP, HEIGHT_MASK, SLOPE_MASK, THRESHOLD, TILE_SELECT, COLOR_OUTPUT, TILE_OUTPUT]
const OUTPUT_NODES := [OUTPUT, COLOR_OUTPUT, TILE_OUTPUT]
const MATERIAL_NODES := [COLOR_BLEND, COLOR_RAMP, HEIGHT_MASK, SLOPE_MASK, THRESHOLD, TILE_SELECT, COLOR_OUTPUT, TILE_OUTPUT]
const PORTS := {
	INPUT: [], NOISE: [], BLEND: [Port.HEIGHT, Port.DELTA], CLAMP: [Port.HEIGHT], OUTPUT: [Port.HEIGHT],
	EXISTING_COLOR: [], EXISTING_TILE: [], SLOPE: [], MASK: [],
	COLOR_BLEND: [Port.RGB, Port.RGB, Port.MASK], COLOR_RAMP: [Port.HEIGHT],
	HEIGHT_MASK: [Port.HEIGHT], SLOPE_MASK: [Port.SLOPE], THRESHOLD: [Port.HEIGHT],
	TILE_SELECT: [Port.HEIGHT, Port.MASK], COLOR_OUTPUT: [Port.RGB], TILE_OUTPUT: [Port.TILE]
}
const MATERIAL_DEFAULTS := {
	"color_low": 0x665841, "color_high": 0xe2d4aa, "tile_low": 0, "tile_high": 1, "tile_height": 100.0,
	"slope_low": 5.0, "slope_high": 30.0, "mask_weight": 1.0
}
const INTEGER_PARAMETERS := ["color_low", "color_high", "tile_low", "tile_high"]
const MAX_LAYERS := 8

var error := ""


static func layer() -> Dictionary:
	return normalize_layer({
		"enabled": true, "opacity": 1.0, "seed": 42.0, "scale": 28.0, "amplitude": 10.0,
		"low": -200.0, "high": 250.0,
		"links": {BLEND: [INPUT, NOISE], CLAMP: [BLEND], OUTPUT: [CLAMP]}
	})


static func normalize_layer(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.merge(MATERIAL_DEFAULTS)
	for key: String in INTEGER_PARAMETERS:
		var parameter: Variant = result[key]
		if parameter is float and parameter >= 0 and parameter <= 0xffffff and parameter == floorf(parameter):
			result[key] = int(parameter)
	result["links"] = normalize_links(result["links"])
	return result


static func normalize_links(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for node: String in MATERIAL_NODES:
		if not result.has(node):
			var empty := []
			empty.resize(PORTS[node].size())
			empty.fill("")
			result[node] = empty
	var tile_inputs: Variant = result[TILE_SELECT]
	if tile_inputs is Array and tile_inputs.size() == 1:
		tile_inputs.append("")
	return result


static func output_type(node: String) -> int:
	match node:
		NOISE:
			return Port.DELTA
		EXISTING_COLOR, COLOR_BLEND, COLOR_RAMP:
			return Port.RGB
		EXISTING_TILE, TILE_SELECT:
			return Port.TILE
		SLOPE:
			return Port.SLOPE
		MASK, HEIGHT_MASK, SLOPE_MASK, THRESHOLD:
			return Port.MASK
		_:
			return Port.HEIGHT


func validate_stack(layers: Array) -> bool:
	if layers.is_empty() or layers.size() > MAX_LAYERS:
		return fail("A node stack needs one to eight layers.")
	for value: Variant in layers:
		if not value is Dictionary or not value.get("enabled") is bool or not value.get("links") is Dictionary:
			return fail("Invalid layer record.")
		var item := normalize_layer(value)
		var definitions := {"opacity": Vector2(0, 1), "seed": Vector2(0, 999999),
			"scale": Vector2(2, 512), "amplitude": Vector2(0, 100),
			"low": Vector2(-3000, 3000), "high": Vector2(-3000, 3000),
			"color_low": Vector2(0, 0xffffff), "color_high": Vector2(0, 0xffffff),
			"tile_low": Vector2(0, 15), "tile_high": Vector2(0, 15), "tile_height": Vector2(-100000, 100000),
			"slope_low": Vector2(0, 90), "slope_high": Vector2(0, 90), "mask_weight": Vector2(0, 1)}
		for key: String in definitions:
			var field: Variant = item.get(key)
			var limits: Vector2 = definitions[key]
			if not (field is int or field is float) or not is_finite(field) or field < limits.x or field > limits.y:
				return fail("Invalid layer parameter " + key)
			if key in INTEGER_PARAMETERS and field != floorf(field):
				return fail("Invalid integer layer parameter " + key)
		if value["low"] > value["high"]:
			return fail("Clamp minimum exceeds maximum.")
		if item["slope_low"] > item["slope_high"]:
			return fail("Slope minimum exceeds maximum.")
		if not validate_links(item["links"]):
			return false
	return true


func validate_links(value: Dictionary, allow_unconnected := false) -> bool:
	var links := normalize_links(value)
	for node in links:
		if node not in NODE_NAMES or PORTS[node].is_empty():
			return fail("Invalid input node " + str(node))
	for node: String in links:
		var list: Variant = links.get(node)
		var ports: Array = PORTS[node]
		if not list is Array or list.size() != ports.size():
			return fail("Invalid ports on " + node)
		for port in ports.size():
			var source: Variant = list[port]
			if source == "":
				continue
			if not source is String or source not in NODE_NAMES or source in OUTPUT_NODES or output_type(source) != ports[port]:
				return fail("Connect matching ports on " + node)
	for node: String in NODE_NAMES:
		if not PORTS[node].is_empty() and not links.has(node):
			return fail("Missing input record on " + node)
		if not visit(node, links, {}, []):
			return false
	if not allow_unconnected:
		var roots := connected_outputs(links)
		if roots.is_empty():
			return fail("Connect at least one graph output.")
		var ordered := []
		var visited := {}
		for root: String in roots:
			visit(root, links, visited, ordered)
		for node: String in ordered:
			var inputs: Array = links.get(node, [])
			var incomplete := inputs == ["", ""] if node == TILE_SELECT else "" in inputs
			if incomplete:
				return fail("Complete the input connection on " + node)
	error = ""
	return true


func connected_outputs(links: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for node: String in OUTPUT_NODES:
		if links[node][0] != "":
			result.append(node)
	return result


func visit(node: String, links: Dictionary, state: Dictionary, sorted: Array) -> bool:
	if state.get(node) == 1:
		return fail("The graph contains a cycle.")
	if state.get(node) == 2 or node == "":
		return true
	state[node] = 1
	for parent: String in links.get(node, []):
		if not visit(parent, links, state, sorted):
			return false
	state[node] = 2
	sorted.append(node)
	return true


static func region_at(size: Vector2i, focus: Vector2i, radius_m: float) -> Rect2i:
	var extent := Vector2i.ONE * ceili(radius_m / Terrain.SPACING)
	var low := (focus - extent).max(Vector2i.ZERO)
	var high := (focus + extent).min(size - Vector2i.ONE)
	return Rect2i(low, high - low + Vector2i.ONE)


func material_snapshot(layers: Array, terrain: Terrain, focus: Vector2i, radius_m: float) -> Dictionary:
	var wants_color := false
	var wants_tiles := false
	for raw: Dictionary in layers:
		if not raw["enabled"] or raw["opacity"] == 0:
			continue
		var links := normalize_links(raw["links"])
		wants_color = wants_color or links[COLOR_OUTPUT][0] != ""
		wants_tiles = wants_tiles or links[TILE_OUTPUT][0] != ""
	var surface := {Terrain.Layer.COLOR: {}, Terrain.Layer.TILES: {}}
	if not wants_color and not wants_tiles:
		return surface
	var region := region_at(terrain.dimensions, focus, radius_m)
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if wants_color:
				var index := z * terrain.dimensions.x + x
				surface[Terrain.Layer.COLOR][index] = terrain.committed_material_value(Terrain.Layer.COLOR, index)
			if wants_tiles and is_block_center(x, z):
				var block := terrain.block_at(Vector2i(x, z))
				surface[Terrain.Layer.TILES][block] = terrain.committed_material_value(Terrain.Layer.TILES, block)
	return surface


static func is_block_center(x: int, z: int) -> bool:
	return x % Terrain.BLOCK == Terrain.BLOCK / 2 and z % Terrain.BLOCK == Terrain.BLOCK / 2


func compute(layers: Array, source: PackedFloat32Array, size: Vector2i, origin: Vector2i, focus: Vector2i, radius: float, granularity: float) -> Dictionary:
	return compute_channels(layers, source, size, origin, focus, radius, granularity, {})["heights"]


func compute_channels(layers: Array, source: PackedFloat32Array, size: Vector2i, origin: Vector2i, focus: Vector2i, radius: float, granularity: float, surface: Dictionary) -> Dictionary:
	var output := {"heights": {}, "materials": {Terrain.Layer.COLOR: {}, Terrain.Layer.TILES: {}}}
	if size.x <= 0 or size.y <= 0 or source.size() != size.x * size.y or not is_finite(radius) or radius <= 0 or not is_finite(granularity) or granularity <= 0:
		return output
	var compiled := []
	var rgb_source: Dictionary = surface.get(Terrain.Layer.COLOR, {})
	var tile_source: Dictionary = surface.get(Terrain.Layer.TILES, {})
	var needs_slope := false
	for raw: Dictionary in layers:
		if not raw["enabled"] or raw["opacity"] == 0:
			continue
		var item := normalize_layer(raw)
		var roots := connected_outputs(item["links"])
		var order := []
		var visited := {}
		for root: String in roots:
			if (root == COLOR_OUTPUT and rgb_source.is_empty()) or (root == TILE_OUTPUT and tile_source.is_empty()):
				continue
			visit(root, item["links"], visited, order)
		needs_slope = needs_slope or visited.has(SLOPE)
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.seed = int(item["seed"])
		noise.frequency = 1.0 / item["scale"]
		compiled.append({"layer": item, "order": order, "noise": noise, "roots": visited})
	var region := region_at(size, focus, radius)
	var r := radius / Terrain.SPACING
	var values := {}
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var sample := Vector2i(x, z)
			var coverage := smoothstep(0.0, 1.0, 1.0 - Vector2(sample - focus).length() / r)
			if coverage <= 0:
				continue
			var index := z * size.x + x
			var base := source[index]
			var height := base
			var rgb: int = rgb_source.get(index, -1)
			var color := Terrain.word_color(rgb)
			var block := (z / Terrain.BLOCK) * (size.x / Terrain.BLOCK) + x / Terrain.BLOCK
			var tile: int = tile_source.get(block, -1) if is_block_center(x, z) else -1
			var tile_result := tile
			var slope := source_slope(source, size, sample) if needs_slope else 0.0
			for entry: Dictionary in compiled:
				var item: Dictionary = entry["layer"]
				var weight: float = item["opacity"]
				evaluate_layer(entry, sample + origin, height, color, tile_result & 15, slope, values)
				var roots: Dictionary = entry["roots"]
				if roots.has(OUTPUT):
					height = lerpf(height, values[OUTPUT], weight)
				if roots.has(COLOR_OUTPUT) and rgb >= 0:
					color = color.lerp(values[COLOR_OUTPUT], coverage * weight)
				if roots.has(TILE_OUTPUT) and tile >= 0 and coverage * weight >= 0.5:
					tile_result = (tile_result & ~15) | values[TILE_OUTPUT]
			if height != base:
				var target := snappedf(lerpf(base, height, coverage), granularity)
				if is_finite(target) and absf(target) <= minf(100000.0, granularity * 32000) and target != base:
					output["heights"][index] = target
			if rgb >= 0 and Terrain.rgb_word(color) != rgb:
				output["materials"][Terrain.Layer.COLOR][index] = Terrain.rgb_word(color)
			if tile >= 0 and tile_result != tile:
				output["materials"][Terrain.Layer.TILES][block] = tile_result
	return output


static func source_slope(source: PackedFloat32Array, size: Vector2i, sample: Vector2i) -> float:
	var left := maxi(0, sample.x - 1)
	var right := mini(size.x - 1, sample.x + 1)
	var near := maxi(0, sample.y - 1)
	var far := mini(size.y - 1, sample.y + 1)
	var row := sample.y * size.x
	var dx := (source[row + right] - source[row + left]) / (maxi(1, right - left) * Terrain.SPACING)
	var dz := (source[far * size.x + sample.x] - source[near * size.x + sample.x]) / (maxi(1, far - near) * Terrain.SPACING)
	return rad_to_deg(atan(Vector2(dx, dz).length()))


func evaluate_layer(entry: Dictionary, world_sample: Vector2i, height: float, color: Color, tile: int, slope: float, values: Dictionary) -> void:
	var item: Dictionary = entry["layer"]
	var links: Dictionary = item["links"]
	for node: String in entry["order"]:
		match node:
			INPUT:
				values[node] = height
			NOISE:
				values[node] = entry["noise"].get_noise_2d(world_sample.x * Terrain.SPACING, world_sample.y * Terrain.SPACING) * item["amplitude"]
			BLEND:
				values[node] = values[links[node][0]] + values[links[node][1]]
			CLAMP:
				values[node] = clampf(values[links[node][0]], item["low"], item["high"])
			EXISTING_COLOR:
				values[node] = color
			EXISTING_TILE:
				values[node] = tile
			SLOPE:
				values[node] = slope
			MASK:
				values[node] = item["mask_weight"]
			COLOR_BLEND:
				var background: Color = values[links[node][0]]
				values[node] = background.lerp(values[links[node][1]], values[links[node][2]])
			COLOR_RAMP:
				var elevation: float = values[links[node][0]]
				var band: float = item["high"] - item["low"]
				var fraction := clampf((elevation - item["low"]) / band, 0.0, 1.0) if band > 0.0 else float(elevation >= item["low"])
				values[node] = Terrain.word_color(int(item["color_low"])).lerp(Terrain.word_color(int(item["color_high"])), fraction)
			HEIGHT_MASK:
				var elevation: float = values[links[node][0]]
				values[node] = float(elevation >= item["low"] and elevation <= item["high"])
			SLOPE_MASK:
				var angle: float = values[links[node][0]]
				values[node] = float(angle >= item["slope_low"] and angle <= item["slope_high"])
			THRESHOLD:
				values[node] = float(values[links[node][0]] >= item["tile_height"])
			TILE_SELECT:
				var selected: bool
				if links[node][1] != "":
					selected = values[links[node][1]] >= 0.5
				else:
					selected = values[links[node][0]] >= item["tile_height"]
				values[node] = int(item["tile_high"] if selected else item["tile_low"])
			OUTPUT, COLOR_OUTPUT, TILE_OUTPUT:
				values[node] = values[links[node][0]]


func fail(message: String) -> bool:
	error = message
	return false
