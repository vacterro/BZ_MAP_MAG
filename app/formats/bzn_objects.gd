extends RefCounted

const MAX_RECORDS := 150_000
const MAX_OBJECTS := 8192
const MAX_LABEL_LENGTH := 64

var objects: Array[Dictionary] = []
var bytes := PackedByteArray()
var records: Array[Vector3i] = []
var count_offset := -1
var object_count := 0
var insert_offset := -1


func read(data: PackedByteArray, version: int, stop: int) -> bool:
	objects.clear()
	records.clear()
	count_offset = -1
	object_count = 0
	insert_offset = -1
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
	if mission.x < 0 or not is_record(count_at, 4, 4) or not is_record(records.size() - 1, 4, 4):
		bytes = PackedByteArray()
		records.clear()
		return false
	insert_offset = records[records.size() - 1].z - 3
	count_offset = records[count_at].z
	object_count = bytes.decode_u32(count_offset)
	if object_count > MAX_OBJECTS or insert_offset <= count_offset:
		bytes = PackedByteArray()
		records.clear()
		return false
	for index in range(count_at + 1, records.size()):
		if objects.size() >= object_count:
			break
		var item := read_object(index)
		if not item.is_empty():
			if not objects.is_empty():
				objects[objects.size() - 1]["end"] = item["start"]
			objects.append(item)
	if not objects.is_empty():
		objects[objects.size() - 1]["end"] = insert_offset
	bytes = PackedByteArray()
	records.clear()
	if objects.size() != object_count:
		objects.clear()
		object_count = 0
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
	return index >= 0 and index < records.size() and records[index].x == tag and records[index].y == size


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


func vector_at(offset: int) -> Vector3:
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))


func read_object(index: int) -> Dictionary:
	var start := records[index].z - 3
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
	var team_record := records[cursor]
	var team := bytes[team_record.z] if team_record.y == 1 else bytes.decode_u32(team_record.z)
	cursor += 1
	var label := ""
	if not (sequence & 0x800000):
		var found := read_string(cursor)
		if found.x < 0:
			return {}
		label = string_value(found.x)
		cursor = found.y
	if not is_record(cursor, 1, 1) or not is_record(cursor + 1, 8, 4) or not is_record(cursor + 2, 12, 64):
		return {}
	var flag1 := bytes[records[cursor].z]
	var flag8 := bytes.decode_u32(records[cursor + 1].z)
	var position_at := records[cursor + 2].z
	var placement := Transform3D(Basis(vector_at(position_at), vector_at(position_at + 16), vector_at(position_at + 32)), vector_at(position_at + 48))
	if not placement.is_finite():
		return {}
	return {"odf": odf, "label": label, "team": team, "sequence": sequence, "transform": placement,
		"position_offset": position_at + 48, "matrix_offset": position_at, "start": start,
		"end": 0, "flag1": flag1, "flag8": flag8, "team_is_byte": team_record.y == 1}


static func fields(entry: Dictionary) -> Dictionary:
	return {"odf": entry["odf"], "label": entry["label"], "team": entry["team"], "sequence": entry["sequence"], "transform": entry["transform"]}


static func u16(value: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(2)
	payload.encode_u16(0, value)
	return payload


static func u32(value: int) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, value)
	return payload


static func tag_record(tag: int, payload: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray([tag])
	result.append_array(u16(payload.size()))
	result.append_array(payload)
	return result


static func string_record(label: String) -> PackedByteArray:
	var payload: PackedByteArray = label.to_ascii_buffer()
	var result := PackedByteArray([2, 1, 0, payload.size()])
	result.append(2)
	result.append_array(u16(payload.size()))
	result.append_array(payload)
	return result


static func write_transform(data: PackedByteArray, matrix_offset: int, origin_offset: int, transform: Transform3D) -> void:
	for axis in 3:
		var vector: Vector3 = transform.basis.x if axis == 0 else (transform.basis.y if axis == 1 else transform.basis.z)
		var at: int = matrix_offset + axis * 16
		data.encode_float(at, vector.x)
		data.encode_float(at + 4, vector.y)
		data.encode_float(at + 8, vector.z)
	data.encode_float(origin_offset, transform.origin.x)
	data.encode_float(origin_offset + 4, transform.origin.y)
	data.encode_float(origin_offset + 8, transform.origin.z)


static func build_block(source: PackedByteArray, entry: Dictionary, sequence: int, label: String, transform: Transform3D) -> PackedByteArray:
	var result := string_record(entry["odf"])
	result.append_array(tag_record(4, u32(sequence)))
	var team: int = entry["team"]
	if entry["team_is_byte"]:
		result.append_array(tag_record(2, PackedByteArray([team & 0xff])))
	else:
		result.append_array(tag_record(4, u32(team)))
	if label != "":
		result.append_array(string_record(label))
	var flag1: PackedByteArray = PackedByteArray()
	flag1.resize(1)
	flag1[0] = entry["flag1"]
	result.append_array(tag_record(1, flag1))
	result.append_array(tag_record(8, u32(entry["flag8"])))
	var matrix: PackedByteArray = source.slice(entry["matrix_offset"], entry["matrix_offset"] + 64)
	write_transform(matrix, 0, 48, transform)
	result.append(12)
	result.append_array(u16(64))
	result.append_array(matrix)
	result.append_array(source.slice(entry["matrix_offset"] + 64, entry["end"]))
	return result


static func patch_objects(source: PackedByteArray, entries: Array[Dictionary], transforms: Dictionary,
		removals: Array, insert_blocks: Array, count_offset: int, insert_offset: int) -> Dictionary:
	if count_offset < 0 or insert_offset <= 0 or insert_offset + 7 > source.size():
		return {}
	var result := PackedByteArray()
	var cursor := 0
	var shift := 0
	var removed := {}
	for index in removals:
		removed[index] = true
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if removed.has(index):
			result.append_array(source.slice(cursor, int(entry["start"])))
			cursor = int(entry["end"])
			continue
		var start: int = entry["start"]
		var end: int = entry["end"]
		if start < cursor or end <= start or end > insert_offset:
			return {}
		result.append_array(source.slice(cursor, start))
		var block := source.slice(start, end)
		if transforms.has(index):
			var transform: Transform3D = transforms[index]
			write_transform(block, entry["matrix_offset"] - start, entry["position_offset"] - start, transform)
		result.append_array(block)
		cursor = end
	if cursor > insert_offset:
		return {}
	var count := entries.size() - removed.size()
	var inserted := 0
	for block in insert_blocks:
		result.append_array(block)
		shift += block.size()
		inserted += 1
	for index in removed:
		shift -= entries[index]["end"] - entries[index]["start"]
	result.append_array(source.slice(insert_offset))
	if count_offset + 4 > insert_offset:
		return {}
	result.encode_u32(count_offset, count + inserted)
	return {"bytes": result, "shift": shift}
