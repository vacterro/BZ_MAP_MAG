extends RefCounted

const MARKER := [2, 1, 0, 6, 2, 6, 0, 65, 105, 80, 97, 116, 104]
const TRAILER_PREFIX := [1, 1, 0]
const MAP_TRAILER_BYTES := 8031
const BINARY_MAP_VERSIONS := [1192, 1196, 1197]
const BINARY_MAP_HEADER := "saveType [1] =\n0\nbinarySave [1] =\ntrue\n"
const MAX_PATHS := 2048
const MAX_POINTS := 8191

var paths: Array[Dictionary] = []
var bytes: PackedByteArray
var next := 0
var table_end := 0
var table_start := 0
var can_resize := false


func read(data: PackedByteArray, version: int) -> bool:
	paths.clear()
	table_end = 0
	table_start = 0
	can_resize = false
	if version not in BINARY_MAP_VERSIONS or data.size() > 16 * 1024 * 1024:
		return false
	var header := data.slice(0, 128).get_string_from_ascii().replace("\r", "").split("\n", true, 2)
	if header.size() != 3 or not header[2].begins_with(BINARY_MAP_HEADER):
		return false
	var version_text := header[1].strip_edges()
	if not version_text.is_valid_int() or version_text.to_int() != version:
		return false
	bytes = data
	var found := false
	var candidate := bytes.find(2, 64)
	while candidate != -1:
		if candidate >= 7 and matches(candidate, MARKER) and token(candidate - 7, 4, 4):
			var count := bytes.decode_s32(candidate - 4)
			if count > 0 and count <= MAX_PATHS and read_table(candidate, count):
				if found:
					paths.clear()
					table_start = 0
					table_end = 0
					bytes = PackedByteArray()
					return false
				found = true
				candidate = bytes.find(2, table_end)
				continue
		candidate = bytes.find(2, candidate + 1)
	var tail := bytes.size() - MAP_TRAILER_BYTES
	if not found and resize_trailer(tail) and token(tail - 7, 4, 4) and bytes.decode_s32(tail - 4) == 0:
		found = read_table(tail, 0)
	can_resize = found and resize_trailer(table_end)
	bytes = PackedByteArray()
	return found


func resize_trailer(start: int) -> bool:
	return start >= 64 and start + MAP_TRAILER_BYTES == bytes.size() and token(start + 25, 0, 5824) and token(start + 5852, 0, 2176)


func read_table(start: int, count: int) -> bool:
	var table: Array[Dictionary] = []
	var ids := {}
	next = start
	for i in count:
		var record_start := next
		if not matches(next, MARKER):
			return false
		next += MARKER.size()
		if not consume(8, 4):
			return false
		var id := bytes.decode_u32(next - 4)
		if ids.has(id):
			return false
		ids[id] = true
		if not consume(4, 4):
			return false
		var name_start := next - 7
		var name_length := bytes.decode_s32(next - 4)
		if name_length < 1 or name_length > 255 or not consume(2, name_length):
			return false
		var label := bytes.slice(next - name_length, next).get_string_from_ascii()
		if not consume(4, 4):
			return false
		var point_start := next - 7
		var point_count := bytes.decode_s32(next - 4)
		if point_count <= 0 or point_count > MAX_POINTS or not consume(10, point_count * 8):
			return false
		var points := PackedVector2Array()
		var offset := next - point_count * 8
		for p in point_count:
			var point := Vector2(bytes.decode_float(offset), bytes.decode_float(offset + 4))
			if not point.is_finite():
				return false
			points.append(point)
			offset += 8
		if not consume(0, 4):
			return false
		table.append({
			"name": label, "type": bytes.decode_u32(next - 4), "id": id, "points": points,
			"start": record_start, "name_start": name_start, "point_start": point_start, "type_start": next - 7, "end": next
		})
	if not matches(next, TRAILER_PREFIX) or not token(next + 4, 4, 4) or not token(next + 11, 4, 4) or not token(next + 18, 4, 4):
		return false
	paths = table
	table_start = start
	table_end = next
	return true


func patch(source: PackedByteArray, edits: Dictionary) -> PackedByteArray:
	if edits.is_empty():
		return source
	var result := PackedByteArray()
	var cursor := 0
	var count := paths.size()
	for index in paths.size():
		if not edits.has(index):
			continue
		var record := paths[index]
		var change: Dictionary = edits[index]
		if change.is_empty():
			result.append_array(source.slice(cursor, record["start"]))
			cursor = record["end"]
			count -= 1
			continue
		var name_at: int = record["name_start"]
		var points_at: int = record["point_start"]
		var type_at: int = record["type_start"]
		result.append_array(source.slice(cursor, name_at))
		if change["name"] == record["name"]:
			result.append_array(source.slice(name_at, points_at))
		else:
			var encoded_name: PackedByteArray = change["name"].to_ascii_buffer()
			result.append_array(token_with_count(2, encoded_name.size(), encoded_name))
		var points: PackedVector2Array = change["points"]
		if points == record["points"]:
			result.append_array(source.slice(points_at, type_at))
		else:
			result.append_array(point_records(points))
		var type_record := source.slice(type_at, record["end"])
		type_record.encode_u32(3, change["type"])
		result.append_array(type_record)
		cursor = record["end"]
	result.append_array(source.slice(cursor, table_end))
	var slots := edits.keys()
	slots.sort()
	for index: int in slots:
		if index >= paths.size():
			result.append_array(new_record(edits[index]))
			count += 1
	result.encode_s32(table_start - 4, count)
	result.append_array(source.slice(table_end))
	return result


func new_record(path: Dictionary) -> PackedByteArray:
	var record := PackedByteArray(MARKER)
	var pointer := PackedByteArray([8, 4, 0, 0, 0, 0, 0])
	pointer.encode_u32(3, path["id"])
	record.append_array(pointer)
	var name: PackedByteArray = path["name"].to_ascii_buffer()
	record.append_array(token_with_count(2, name.size(), name))
	record.append_array(point_records(path["points"]))
	var type := PackedByteArray([0, 4, 0, 0, 0, 0, 0])
	type.encode_u32(3, path["type"])
	record.append_array(type)
	return record


func point_records(points: PackedVector2Array) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(points.size() * 8)
	for i in points.size():
		payload.encode_float(i * 8, points[i].x)
		payload.encode_float(i * 8 + 4, points[i].y)
	return token_with_count(10, points.size(), payload)


func pointer_counts(source: PackedByteArray) -> Dictionary:
	var ids := {}
	var offset := source.find(8, 64)
	while offset >= 0 and offset <= source.size() - 7:
		if source.decode_u16(offset + 1) == 4:
			var id := source.decode_u32(offset + 3)
			ids[id] = ids.get(id, 0) + 1
		offset = source.find(8, offset + 1)
	return ids


func has_name_reference(source: PackedByteArray, label: String) -> bool:
	var size := label.length()
	var candidate := source.find(2, 64)
	while candidate >= 0 and candidate + 3 + size <= source.size():
		if candidate >= table_start and candidate < table_end:
			candidate = source.find(2, table_end)
			continue
		if source.decode_u16(candidate + 1) == size:
			var found := source.slice(candidate + 3, candidate + 3 + size).get_string_from_ascii()
			if found.nocasecmp_to(label) == 0:
				return true
		candidate = source.find(2, candidate + 1)
	return false


func token_with_count(tag: int, count: int, payload: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray([4, 4, 0, 0, 0, 0, 0, tag, 0, 0])
	result.encode_u32(3, count)
	result.encode_u16(8, payload.size())
	result.append_array(payload)
	return result


func consume(tag: int, length: int) -> bool:
	if not token(next, tag, length):
		return false
	next += 3 + length
	return true


func token(at: int, tag: int, length: int) -> bool:
	return at >= 0 and at + 3 + length <= bytes.size() and bytes[at] == tag and bytes.decode_u16(at + 1) == length


func matches(at: int, pattern: Array) -> bool:
	if at + pattern.size() > bytes.size():
		return false
	for i in pattern.size():
		if bytes[at + i] != pattern[i]:
			return false
	return true
