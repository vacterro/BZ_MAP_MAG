extends RefCounted

const Terrain := preload("res://formats/terrain_v5.gd")
const MASK_START := 2416
const LAYER_START := 16
const LAYER_SIZE := 160
const LAYERS := 8
const MAX_HEIGHT := 100000.0

var first_height := 0.0
var first_tiles := PackedVector2Array()
var width := 0
var depth := 0
var other_flags := 0
var layers: Array[Dictionary] = []
var invalid_layer_flags := 0


func decode(bytes: PackedByteArray, terrain: Terrain) -> bool:
	first_tiles.clear()
	other_flags = 0
	layers.clear()
	invalid_layer_flags = 0
	if bytes.size() < MASK_START or bytes.slice(0, 4).get_string_from_ascii() != "WATR" or bytes.decode_u32(4) != 5:
		return false
	var origin := Vector2i(bytes.decode_s16(8), bytes.decode_s16(10))
	var end := Vector2i(bytes.decode_s16(12), bytes.decode_s16(14))
	if origin != terrain.origin or end - origin != terrain.dimensions:
		return false
	width = terrain.dimensions.x / terrain.BLOCK
	depth = terrain.dimensions.y / terrain.BLOCK
	if bytes.size() != MASK_START + width * depth:
		return false
	first_height = bytes.decode_float(16)
	var tiles: Array[PackedVector2Array] = []
	for index in 8:
		tiles.append(PackedVector2Array())
	for row in depth:
		for column in width:
			var flags := bytes[MASK_START + row * width + column]
			for index in 8:
				if flags & (1 << index):
					tiles[index].append(Vector2(column, row))
			other_flags |= flags & 254
	for index in 8:
		if tiles[index].is_empty():
			continue
		var height := bytes.decode_float(LAYER_START + index * LAYER_SIZE)
		if not is_finite(height) or absf(height) > MAX_HEIGHT:
			invalid_layer_flags |= 1 << index
			continue
		layers.append({"index": index, "height": height, "tiles": tiles[index]})
		if index == 0:
			first_tiles = tiles[index]
	return true


static func layer_height(source: PackedByteArray, layer: int) -> float:
	return source.decode_float(LAYER_START + layer * LAYER_SIZE)


static func block_covered(source: PackedByteArray, block: int, layer: int) -> bool:
	return (source[MASK_START + block] & (1 << layer)) != 0


static func encode(source: PackedByteArray, coverage: Dictionary, heights: Dictionary) -> PackedByteArray:
	var result := source
	var limit := result.size() - MASK_START
	if limit < 0:
		return PackedByteArray()
	for layer: int in coverage:
		if not coverage[layer] is Dictionary or layer < 0 or layer >= LAYERS:
			return PackedByteArray()
		for block: int in coverage[layer]:
			var value: Variant = coverage[layer][block]
			if not value is bool or block < 0 or block >= limit:
				return PackedByteArray()
			var flags := result[MASK_START + block]
			flags = flags | (1 << layer) if value else flags & ~(1 << layer)
			result[MASK_START + block] = flags
	for layer: int in height_layers(heights):
		var height: float = float(heights[layer])
		if not is_finite(height) or absf(height) > MAX_HEIGHT:
			return PackedByteArray()
		result.encode_float(LAYER_START + layer * LAYER_SIZE, height)
	return result


static func height_layers(heights: Dictionary) -> Array:
	var keys := heights.keys()
	var valid: Array = []
	for key: int in keys:
		if key < 0 or key >= LAYERS:
			return []
		valid.append(key)
	valid.sort()
	return valid
