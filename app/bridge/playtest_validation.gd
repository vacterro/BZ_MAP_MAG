extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")


static func validate(mission: String) -> Dictionary:
	var input := FileAccess.open(mission, FileAccess.READ)
	if input == null or input.get_length() > Package.MAX_MEMBER_BYTES:
		return {"error": "Could not read a bounded BZN."}
	var layout := Layouts.recognize(input.get_buffer(Layouts.MAX_HEADER_BYTES))
	var version: int = layout["version"]
	if version == 0:
		return {"error": layout["reason"]}
	var route := Layouts.playtest_route(version, layout["encoding"])
	if route == "refuse":
		return {"error": "BZN version %d has no verified 2.0.185 launch route for this layout." % version}
	var package := Package.new()
	if not package.open(mission):
		return {"error": package.error}
	if package.layout_id != layout["profile"] or not package.path_codec.can_resize or package.object_count_offset < 0:
		return {"error": "The BZN path table, trailer or object records do not match the verified layout."}
	var sequences := {}
	for object in package.objects:
		var sequence: int = object["sequence"]
		if sequences.has(sequence):
			return {"error": "The BZN object table contains duplicate sequence numbers."}
		sequences[sequence] = true
	if not package.check_sources():
		return {"error": package.error}
	return {"route": route, "version": version, "files": package.files}
