extends RefCounted

const VSR_STREAMS := ["VSR", "3532748119", "1329659846", "2785557433", "2785542655", "2814914461", "2049956570", "3493379153", "2467249743"]
const ASSET_EXTENSIONS := ["odf", "msh", "material", "dds", "png", "tga"]
const MAX_INDEXED_FILES := 250_000

var index := {}
var indexed_roots: Array[String] = []


func index_game(game: String, map_folder: String, extra_roots: Array = [], mod_profile: String = "stock") -> void:
	index.clear()
	indexed_roots.clear()
	var roots: Array[String] = []
	if not map_folder.is_empty():
		roots.append(map_folder)
	for r_v in extra_roots:
		var r := String(r_v).strip_edges()
		if not r.is_empty() and not (r in roots):
			roots.append(r)
	# Never unconditionally mount VRV/Core or VRV/deps for Stock maps!
	if mod_profile != "stock" and extra_roots.is_empty() and not game.is_empty():
		if mod_profile == "vrv":
			roots.append(game.path_join("VRV/Core"))
		if mod_profile in ["vsr", "vrv"]:
			for name: String in VSR_STREAMS:
				roots.append(game.path_join("VRV/deps").path_join(name))
	if not game.is_empty():
		var res_dir := game.path_join("bz2r_res")
		if not (res_dir in roots):
			roots.append(res_dir)
	for root: String in roots:
		indexed_roots.append(root)
		add_root(root)


func load_objects(game: String, map_folder: String, adapter: String, objects: Array, extra_roots: Array = [], mod_profile: String = "stock") -> Dictionary:
	index_game(game, map_folder, extra_roots, mod_profile)
	var geometry := {}
	var definitions := {}
	var instances := []
	var missing := {}
	var pools := 0
	for index_in_map in objects.size():
		var record: Dictionary = objects[index_in_map]
		var odf := normalize(record["odf"], "odf")
		if not definitions.has(odf):
			definitions[odf] = find_definition(odf)
		var entry: Dictionary = definitions[odf]
		var mesh_path: String = entry.get("mesh", "")
		var pool: bool = entry.get("pool", false)
		if pool:
			pools += 1
		if mesh_path != "" and not geometry.has(mesh_path):
			geometry[mesh_path] = convert_mesh(adapter, mesh_path)
		if mesh_path.is_empty() or geometry[mesh_path].is_empty():
			missing[odf] = true
		else:
			instances.append({"index": index_in_map, "mesh": mesh_path, "transform": record["transform"], "scale": entry["scale"], "pool": pool})
	return {"geometry": geometry, "instances": instances, "missing": missing, "pools": pools, "textures": index, "adapter": adapter}


func add_root(root: String) -> void:
	var pending := PackedStringArray([root])
	while not pending.is_empty() and index.size() < MAX_INDEXED_FILES:
		var path := pending[-1]
		pending.remove_at(pending.size() - 1)
		var directory := DirAccess.open(path)
		if directory == null:
			continue
		for name in directory.get_files():
			var key := name.to_lower()
			if key.get_extension() in ASSET_EXTENSIONS and not index.has(key):
				index[key] = path.path_join(name)
		var children := directory.get_directories()
		children.reverse()
		for name in children:
			if not directory.is_link(name):
				pending.append(path.path_join(name))


func normalize(name: String, extension: String) -> String:
	var key := name.get_file().to_lower()
	return key if key.ends_with("." + extension) else key + "." + extension


func find_definition(odf: String, depth := 0) -> Dictionary:
	if depth >= 16:
		return {}
	var source: String = index.get(odf, "")
	if source.is_empty():
		return {}
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > 256 * 1024:
		return {}
	var text := file.get_buffer(file.get_length()).get_string_from_ascii()
	var section := RegEx.new()
	section.compile("(?im)^\\s*\\[GameObjectClass\\]\\s*\\r?\\n([^\\[]*)")
	var main := section.search(text)
	if main == null:
		return {}
	var properties := {}
	for line in main.get_string(1).split("\n"):
		var clean := line.get_slice("//", 0).strip_edges()
		if clean.contains("="):
			properties[clean.get_slice("=", 0).strip_edges().to_lower()] = clean.substr(clean.find("=") + 1).strip_edges().trim_prefix('"').trim_suffix('"')
	var name: String = properties.get("geometryname", "")
	var stem := name.get_file().get_basename().to_lower()
	var label := String(properties.get("classlabel", "")).to_lower()
	var parent := normalize(label, "odf")
	var inherited := find_definition(parent, depth + 1) if parent != odf and index.has(parent) else {}
	var mesh: String = index.get(stem + ".msh", "") if stem != "" else inherited.get("mesh", "")
	var scale := String(properties.get("geometryscale", str(inherited.get("scale", 1.0)))).to_float()
	if not is_finite(scale) or scale <= 0 or scale > 100:
		scale = 1.0
	return {"mesh": mesh, "scale": scale, "pool": "pool" in label or inherited.get("pool", false)}


func convert_mesh(adapter: String, source: String) -> PackedByteArray:
	return bridge_output(adapter, PackedStringArray([source]), 32 * 1024 * 1024)


static func read_image(adapter: String, source: String) -> Image:
	if source.get_extension().to_lower() not in ["dds", "tga"]:
		return Image.load_from_file(source)
	if source.get_extension().to_lower() == "tga":
		var buffer := FileAccess.get_file_as_bytes(source)
		var image := Image.new()
		return image if image.load_tga_from_buffer(buffer) == OK else null
	var pixels := bridge_output(adapter, PackedStringArray(["--dds", source]), 12 + 512 * 512 * 4)
	if pixels.size() < 12 or pixels.slice(0, 4).get_string_from_ascii() != "BZT1":
		return null
	var width := pixels.decode_u32(4)
	var height := pixels.decode_u32(8)
	if width == 0 or height == 0 or width > 512 or height > 512 or pixels.size() != 12 + width * height * 4:
		return null
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels.slice(12))


static func bridge_output(adapter: String, arguments: PackedStringArray, limit: int) -> PackedByteArray:
	var path := OS.get_environment("TEMP").path_join("bzmesh-" + Crypto.new().generate_random_bytes(16).hex_encode() + ".bzm")
	arguments.append(path)
	var code := OS.execute(adapter, arguments)
	var bytes := PackedByteArray()
	if code == 0:
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null and file.get_length() <= limit:
			bytes = file.get_buffer(file.get_length())
		if file:
			file.close()
	DirAccess.remove_absolute(path)
	return bytes
