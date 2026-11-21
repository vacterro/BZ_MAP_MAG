extends RefCounted

const Terrain := preload("res://formats/terrain_v5.gd")
const MASK_START := 2416
const LAYER_START := 16
const LAYER_SIZE := 160

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
		if not is_finite(height) or absf(height) > 100000.0:
			invalid_layer_flags |= 1 << index
			continue
		layers.append({"index": index, "height": height, "tiles": tiles[index]})
		if index == 0:
			first_tiles = tiles[index]
	return true
