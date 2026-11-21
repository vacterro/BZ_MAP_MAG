extends RefCounted

const MAX_RECORDS := 150_000
const MAX_OBJECTS := 8192

var objects: Array[Dictionary] = []
var bytes := PackedByteArray()
var records: Array[Vector3i] = []


func read(data: PackedByteArray, version: int, stop: int) -> bool:
	objects.clear()
	records.clear()
	if version not in [1192, 1196] or stop <= 0 or stop > data.size():
		return false
	var header := RegEx.new()
	header.compile("^version \\[1\\] =\\r?\\n[0-9]+\\r?\\nsaveType \\[1\\] =\\r?\\n0\\r?\\nbinarySave \\[1\\] =\\r?\\ntrue\\r?\\n")
	var match_header := header.search(data.slice(0, 128).get_string_from_ascii())
	if match_header == null:
		return false
	bytes = data
	if not decode_records(match_header.get_end(), stop):
		bytes = PackedByteArray()
		return false
	var mission := read_string(0)
	var count_at := mission.y + 3
	if mission.x < 0 or not is_record(count_at, 4, 4):
		bytes = PackedByteArray()
		return false
	var object_count := bytes.decode_u32(records[count_at].z)
	if object_count > MAX_OBJECTS:
		bytes = PackedByteArray()
		return false
	for index in range(count_at + 1, records.size()):
		var item := read_object(index)
		if not item.is_empty():
			objects.append(item)
	bytes = PackedByteArray()
	records.clear()
	if objects.size() != object_count:
		objects.clear()
		return false
	return true


func decode_records(start: int, stop: int) -> bool:
	var offset := start
	while offset + 3 <= stop and records.size() < MAX_RECORDS:
		var tag := bytes[offset]
		var size := bytes.decode_u16(offset + 1)
		var begin := offset + 3
		if tag > 14 or begin + size > stop:
			return false
		if tag == 13:
			var null_at := bytes.find(0, begin)
			if null_at < begin or null_at >= begin + size:
				return false
			size = null_at - begin + 1
		records.append(Vector3i(tag, size, begin))
		offset = begin + size
	return offset == stop


func is_record(index: int, tag: int, size: int) -> bool:
	return index < records.size() and records[index].x == tag and records[index].y == size


func read_string(index: int) -> Vector2i:
	if not is_record(index, 2, 1):
		return Vector2i(-1, index)
	var length := bytes[records[index].z]
	if is_record(index + 1, 2, length):
		return Vector2i(index + 1, index + 2)
	if length == 0:
		return Vector2i(index, index + 1)
	return Vector2i(-1, index)


func string_value(index: int) -> String:
	var record := records[index]
	return bytes.slice(record.z, record.z + record.y).get_string_from_ascii()


func read_object(index: int) -> Dictionary:
	var class_record := read_string(index)
	var cursor := class_record.y
	if class_record.x < 0 or not is_record(cursor, 4, 4):
		return {}
	var odf := string_value(class_record.x)
	if odf.is_empty() or odf.length() > 127 or odf.get_file() != odf or ":" in odf:
		return {}
	var sequence := bytes.decode_u32(records[cursor].z)
	cursor += 1
	if not is_record(cursor, 2, 1) and not is_record(cursor, 4, 4):
		return {}
	var team := bytes[records[cursor].z] if records[cursor].y == 1 else bytes.decode_u32(records[cursor].z)
	cursor += 1
	var label := ""
	if not sequence & 0x800000:
		var found := read_string(cursor)
		if found.x < 0:
			return {}
		label = string_value(found.x)
		cursor = found.y
	if not is_record(cursor, 1, 1) or not is_record(cursor + 1, 8, 4) or not is_record(cursor + 2, 12, 64):
		return {}
	var position_at := records[cursor + 2].z
	var placement := Transform3D(Basis(vector_at(position_at), vector_at(position_at + 16), vector_at(position_at + 32)), vector_at(position_at + 48))
	if not placement.is_finite():
		return {}
	return {"odf": odf, "label": label, "team": team, "sequence": sequence, "transform": placement, "position_offset": position_at + 48}


static func patch_positions(source: PackedByteArray, entries: Array[Dictionary], changes: Dictionary) -> PackedByteArray:
	var result := source
	for index: int in changes:
		var offset: int = entries[index]["position_offset"]
		var position: Vector3 = changes[index]
		result.encode_float(offset, position.x)
		result.encode_float(offset + 4, position.y)
		result.encode_float(offset + 8, position.z)
	return result


func vector_at(offset: int) -> Vector3:
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))
