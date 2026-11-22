extends RefCounted

const BLOCK := 16
const SPACING := 2.0
const MAX_POINTS := 4_194_304
const SIZES := [4, 3, 1, 1, 1, 1, 2, 2]
enum Layer { HEIGHT = 0, COLOR = 1, TILES = 6 }

var origin: Vector2i
var dimensions: Vector2i
var heights := PackedFloat32Array()
var block_offsets := PackedInt32Array()
var original: PackedByteArray
var color_edits := {}
var tile_edits := {}
var material_previews := {}
var min_height: float
var max_height: float
var error := ""


func decode(bytes: PackedByteArray) -> bool:
	color_edits.clear()
	tile_edits.clear()
	material_previews.clear()
	if bytes.size() < 16 or bytes.slice(0, 4).get_string_from_ascii() != "TERR" or bytes.decode_u32(4) != 5:
		return fail("Expected a TERR version 5 header.")
	origin = Vector2i(bytes.decode_s16(8), bytes.decode_s16(10))
	dimensions = Vector2i(bytes.decode_s16(12), bytes.decode_s16(14)) - origin
	var count := dimensions.x * dimensions.y
	if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x % BLOCK or dimensions.y % BLOCK or count > MAX_POINTS:
		return fail("Invalid terrain dimensions or editor sample limit exceeded.")
	var columns := dimensions.x / BLOCK
	var rows := dimensions.y / BLOCK
	if bytes.size() < 16 + columns * rows * 16:
		return fail("Truncated terrain blocks.")
	heights.resize(count)
	block_offsets.clear()
	min_height = INF
	max_height = -INF
	var offset := 16
	for bz in rows:
		for bx in columns:
			if offset >= bytes.size():
				return fail("Missing terrain block.")
			block_offsets.append(offset)
			var flags := bytes[offset]
			if flags & 192:
				return fail("Unsupported per-sample block material metadata.")
			var end := offset + 1
			for layer in SIZES.size():
				end += SIZES[layer] * (256 if (flags & (1 << layer)) else 1)
			if end > bytes.size():
				return fail("Truncated terrain layer.")
			var first := bytes.decode_float(offset + 1)
			for z in BLOCK:
				var row := (bz * BLOCK + z) * dimensions.x + bx * BLOCK
				for x in BLOCK:
					var height := bytes.decode_float(offset + 1 + (z * BLOCK + x) * 4) if flags & 1 else first
					if not is_finite(height):
						return fail("Terrain contains a non-finite elevation.")
					heights[row + x] = height
					min_height = minf(min_height, height)
					max_height = maxf(max_height, height)
			offset = end
	if offset != bytes.size():
		return fail("Unexpected data after last terrain block.")
	block_offsets.append(offset)
	original = bytes
	error = ""
	return true


func encode(dirty: Dictionary) -> PackedByteArray:
	if dirty.is_empty() and not has_material_edits():
		return original
	var changed_blocks := {}
	for index: int in dirty:
		var block := block_at(sample_at(index))
		changed_blocks[block] = changed_blocks.get(block, 0) | (1 << Layer.HEIGHT)
	for index: int in color_edits:
		var block := block_at(sample_at(index))
		changed_blocks[block] = changed_blocks.get(block, 0) | (1 << Layer.COLOR)
	for block: int in tile_edits:
		changed_blocks[block] = changed_blocks.get(block, 0) | (1 << Layer.TILES)
	var bytes := original.slice(0, 16)
	for block in block_offsets.size() - 1:
		var start := block_offsets[block]
		var end := block_offsets[block + 1]
		var changed: int = changed_blocks.get(block, 0)
		if changed == 0:
			bytes.append_array(original.slice(start, end))
			continue
		var flags := original[start]
		var encoded := PackedByteArray([flags])
		var offset := start + 1
		for layer in SIZES.size():
			var bit := 1 << layer
			var length: int = SIZES[layer] * (256 if flags & bit else 1)
			if not changed & bit:
				encoded.append_array(original.slice(offset, offset + length))
			elif layer == Layer.TILES:
				var word := PackedByteArray([0, 0])
				word.encode_u16(0, tile_edits[block])
				encoded.append_array(word)
			else:
				var pixels := encoded_samples(block, layer, dirty)
				if pixels.size() == SIZES[layer]:
					encoded[0] &= ~bit
				else:
					encoded[0] |= bit
				encoded.append_array(pixels)
			offset += length
		bytes.append_array(encoded)
	return bytes


func encoded_samples(block: int, layer: int, dirty: Dictionary = {}) -> PackedByteArray:
	var start := block_origin(block)
	var size: int = SIZES[layer]
	var bytes := PackedByteArray()
	bytes.resize(256 * size)
	for z in BLOCK:
		var row := (start.y + z) * dimensions.x + start.x
		for x in BLOCK:
			var dst := (z * BLOCK + x) * size
			if layer == Layer.HEIGHT:
				bytes.encode_float(dst, float(dirty.get(row + x, heights[row + x])))
			else:
				var rgb := committed_material_value(Layer.COLOR, row + x)
				bytes[dst] = (rgb >> 16) & 255
				bytes[dst + 1] = (rgb >> 8) & 255
				bytes[dst + 2] = rgb & 255
	var first := bytes.slice(0, size)
	for dst in range(size, bytes.size(), size):
		if bytes.slice(dst, dst + size) != first:
			return bytes
	return first


func sample_at(index: int) -> Vector2i:
	return Vector2i(index % dimensions.x, index / dimensions.x)


func block_at(sample: Vector2i) -> int:
	return (sample.y / BLOCK) * (dimensions.x / BLOCK) + sample.x / BLOCK


func block_origin(block: int) -> Vector2i:
	var columns := dimensions.x / BLOCK
	return Vector2i(block % columns, block / columns) * BLOCK


func layer_start(block: int, layer: int) -> int:
	var start := block_offsets[block]
	var flags := original[start]
	var cursor := start + 1
	for index in layer:
		cursor += SIZES[index] * (256 if flags & (1 << index) else 1)
	return cursor


func source_material_value(layer: int, index: int) -> int:
	if layer == Layer.TILES:
		return original.decode_u16(layer_start(index, Layer.TILES))
	var sample := sample_at(index)
	var block := block_at(sample)
	var offset := layer_start(block, Layer.COLOR)
	if original[block_offsets[block]] & (1 << Layer.COLOR):
		offset += ((sample.y % BLOCK) * BLOCK + sample.x % BLOCK) * 3
	return (original[offset] << 16) | (original[offset + 1] << 8) | original[offset + 2]


func material_changes(layer: int) -> Dictionary:
	return tile_edits if layer == Layer.TILES else color_edits


func material_value(layer: int, index: int) -> int:
	var preview: Dictionary = material_previews.get(layer, {})
	if preview.has(index):
		return preview[index]
	return committed_material_value(layer, index)


func committed_material_value(layer: int, index: int) -> int:
	var edits := material_changes(layer)
	if edits.has(index):
		return edits[index]
	return source_material_value(layer, index)


func displayed_material_changes(layer: int) -> Dictionary:
	var edits := material_changes(layer)
	if not material_previews.has(layer):
		return edits
	var visible := edits.duplicate()
	visible.merge(material_previews[layer], true)
	return visible


func set_material(layer: int, index: int, value: int) -> void:
	var edits := material_changes(layer)
	if value == source_material_value(layer, index):
		edits.erase(index)
	else:
		edits[index] = value


func has_material_edits() -> bool:
	return not color_edits.is_empty() or not tile_edits.is_empty()


static func rgb_word(color: Color) -> int:
	return (color.r8 << 16) | (color.g8 << 8) | color.b8


static func word_color(value: int) -> Color:
	return Color8((value >> 16) & 255, (value >> 8) & 255, value & 255)


func color_at(x: int, z: int) -> Color:
	return word_color(material_value(Layer.COLOR, z * dimensions.x + x))


func slot_color(block: int) -> Color:
	var word := material_value(Layer.TILES, block)
	var drawn := original.decode_u16(layer_start(block, 7))
	return Color8(word & 15, (word >> 4) & 15 if drawn & 2 else 255,
		(word >> 8) & 15 if drawn & 4 else 255, (word >> 12) & 15 if drawn & 8 else 255)


func material_maps(include_edits := true) -> Dictionary:
	var columns := dimensions.x / BLOCK
	var rows := dimensions.y / BLOCK
	var slots := PackedByteArray()
	var colors := PackedByteArray()
	var weights := PackedByteArray()
	slots.resize(columns * rows * 4)
	colors.resize(heights.size() * 3)
	weights.resize(heights.size() * 3)
	var visible_tiles := displayed_material_changes(Layer.TILES) if include_edits else {}
	for row in rows:
		for column in columns:
			var block := row * columns + column
			var start := block_offsets[block]
			var flags := original[start]
			var offset := start + 1
			var bases := PackedInt32Array()
			for layer in 6:
				bases.append(offset)
				offset += SIZES[layer] * (256 if flags & (1 << layer) else 1)
			var texture_ids: int = visible_tiles.get(block, original.decode_u16(offset))
			var drawn := original.decode_u16(offset + 2)
			for layer in 4:
				slots[block * 4 + layer] = (texture_ids >> (layer * 4)) & 15 if layer == 0 or (drawn & (1 << layer)) else 255
			for z in BLOCK:
				for x in BLOCK:
					var serial := z * BLOCK + x
					var output := ((row * BLOCK + z) * dimensions.x + column * BLOCK + x) * 3
					var pixel := bases[1] + serial * 3 if flags & 2 else bases[1]
					for channel in 3:
						colors[output + channel] = original[pixel + channel]
						var layer := channel + 2
						weights[output + channel] = original[bases[layer] + (serial if flags & (1 << layer) else 0)]
	if include_edits:
		var visible_colors := displayed_material_changes(Layer.COLOR)
		for index: int in visible_colors:
			var rgb: int = visible_colors[index]
			colors[index * 3] = (rgb >> 16) & 255
			colors[index * 3 + 1] = (rgb >> 8) & 255
			colors[index * 3 + 2] = rgb & 255
	return {"slots": Image.create_from_data(columns, rows, false, Image.FORMAT_RGBA8, slots),
		"colors": Image.create_from_data(dimensions.x, dimensions.y, false, Image.FORMAT_RGB8, colors),
		"weights": Image.create_from_data(dimensions.x, dimensions.y, false, Image.FORMAT_RGB8, weights)}


static func create_flat(origin_coord: Vector2i, size_samples: Vector2i, height: float = 100.0, tile: int = 0) -> PackedByteArray:
	if size_samples.x <= 0 or size_samples.y <= 0 or size_samples.x % BLOCK != 0 or size_samples.y % BLOCK != 0:
		return PackedByteArray()
	if size_samples.x * size_samples.y > MAX_POINTS or not is_finite(height):
		return PackedByteArray()
	var max_coord := origin_coord + size_samples
	if origin_coord.x < -32768 or origin_coord.y < -32768 or max_coord.x > 32767 or max_coord.y > 32767:
		return PackedByteArray()
	var columns := size_samples.x / BLOCK
	var rows := size_samples.y / BLOCK
	var block_count := columns * rows
	var out := PackedByteArray()
	out.resize(16 + block_count * 16)
	out[0] = 84 # 'T'
	out[1] = 69 # 'E'
	out[2] = 82 # 'R'
	out[3] = 82 # 'R'
	out.encode_u32(4, 5)
	out.encode_s16(8, origin_coord.x)
	out.encode_s16(10, origin_coord.y)
	out.encode_s16(12, max_coord.x)
	out.encode_s16(14, max_coord.y)
	var tile_word := clampi(tile, 0, 15)
	for b in block_count:
		var at := 16 + b * 16
		out[at] = 0
		out.encode_float(at + 1, height)
		out[at + 5] = 255
		out[at + 6] = 255
		out[at + 7] = 255
		out[at + 8] = 0
		out[at + 9] = 0
		out[at + 10] = 0
		out[at + 11] = 0
		out.encode_u16(at + 12, tile_word)
		out.encode_u16(at + 14, 0x0101)
	return out


func fail(message: String) -> bool:
	error = message
	return false
