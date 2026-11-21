extends RefCounted

const Terrain := preload("res://formats/terrain_v5.gd")
const BznPaths := preload("res://formats/bzn_paths.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const Water := preload("res://formats/water_v5.gd")
const MAX_MEMBER_BYTES := 128 * 1024 * 1024
const MAP_EXTENSIONS := ["bzn", "ter", "trn", "inf", "wat", "sky", "des", "dds", "tga", "png", "lua", "dll", "odf", "aip"]

var error := ""
var source_path := ""
var files: Dictionary = {}
var terrain_name := ""
var bzn_name := ""
var terrain: Terrain
var water: Water
var bzn_version := 0
var mission_name := ""
var granularity := 0.1
var metadata: Dictionary = {}
var paths: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var object_count_offset := -1
var object_insert_offset := -1
var path_codec := BznPaths.new()


func open(path: String) -> bool:
	source_path = path
	var folder := path.get_base_dir()
	var stem := path.get_file().get_basename().to_lower()
	var roles := {}
	for name in DirAccess.get_files_at(folder):
		var lower := name.to_lower()
		if lower.get_basename() != stem and lower != stem + "_load.dds":
			continue
		var extension := lower.get_extension()
		if extension not in MAP_EXTENSIONS:
			continue
		if lower.get_basename() == stem:
			if roles.has(extension):
				return fail("Case-colliding package members.")
			roles[extension] = name
		var member := folder.path_join(name)
		var read := FileAccess.open(member, FileAccess.READ)
		if read == null or read.get_length() > MAX_MEMBER_BYTES:
			return fail("Could not read bounded package member " + name)
		files[name] = read.get_sha256(member)
		if files[name] == "":
			return fail("Could not hash " + name)
	for role in ["bzn", "trn", "inf"]:
		if not roles.has(role):
			return fail("Missing same-stem ." + role)
	bzn_name = roles["bzn"]
	var bzn_path := folder.path_join(bzn_name)
	if not read_header(bzn_path):
		return false
	var bzn_bytes := FileAccess.get_file_as_bytes(bzn_path)
	if path_codec.read(bzn_bytes, bzn_version):
		paths = path_codec.paths
		var object_reader := BznObjects.new()
		if object_reader.read(bzn_bytes, bzn_version, path_codec.table_start):
			objects = object_reader.objects
			object_count_offset = object_reader.count_offset
			object_insert_offset = object_reader.insert_offset
	for role in ["trn", "inf"]:
		metadata[role] = read_settings(FileAccess.get_file_as_string(folder.path_join(roles[role])))
	var info: Dictionary = metadata["inf"].get("description", {})
	for key in ["maptga", "mapdesc", "maploadtga"]:
		var asset: String = info.get(key, "").strip_edges().trim_prefix('"').trim_suffix('"')
		if asset == "" or asset.get_file() != asset or ":" in asset or asset in [".", ".."]:
			continue
		# These three INF fields may name local companions with a different stem.
		for name in DirAccess.get_files_at(folder):
			if name.nocasecmp_to(asset) == 0 and not files.has(name):
				var local := folder.path_join(name)
				var input := FileAccess.open(local, FileAccess.READ)
				if input == null or input.get_length() > MAX_MEMBER_BYTES:
					return fail("Could not read metadata companion " + name)
				files[name] = FileAccess.get_sha256(local)
				if files[name] == "":
					return fail("Could not hash " + name)
	mission_name = info.get("missionname", stem).strip_edges().trim_prefix('"').trim_suffix('"')
	var value: String = metadata["trn"].get("size", {}).get("heightgranularity", "0.1")
	if not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float() < 0.00001:
		return fail("Invalid TRN HeightGranularity.")
	granularity = value.to_float()
	if not roles.has("ter"):
		return fail("No TER companion. Use New Map with a matching flat TER.")
	terrain_name = roles["ter"]
	terrain = Terrain.new()
	var bytes := FileAccess.get_file_as_bytes(folder.path_join(terrain_name))
	if not terrain.decode(bytes):
		return fail(terrain.error)
	if roles.has("wat"):
		var preview := Water.new()
		if preview.decode(FileAccess.get_file_as_bytes(folder.path_join(roles["wat"])), terrain):
			water = preview
	return true


func read_header(path: String) -> bool:
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return fail("Unable to read BZN header.")
	var header := input.get_buffer(256).get_string_from_ascii()
	var pattern := RegEx.new()
	pattern.compile("(?i)^version[ \\t]+\\[1\\][ \\t]*=[ \\t]*\\r?\\n[ \\t]*([0-9]+)[ \\t]*\\r?\\n")
	var result := pattern.search(header)
	if result == null:
		return fail("Unrecognized BZN header.")
	bzn_version = result.get_string(1).to_int()
	return true


func read_settings(content: String) -> Dictionary:
	var result := {}
	var section := ""
	for raw in content.split("\n"):
		var line := raw.get_slice("//", 0).strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).to_lower()
			if not result.has(section):
				result[section] = {}
		elif section != "" and line.contains("="):
			result[section][line.get_slice("=", 0).strip_edges().to_lower()] = line.substr(line.find("=") + 1).strip_edges()
	return result


func check_sources() -> bool:
	for name: String in files:
		if files[name] != FileAccess.get_sha256(source_path.get_base_dir().path_join(name)):
			return fail("Source changed or disappeared: " + name)
	return true


func fail(message: String) -> bool:
	error = message
	return false
