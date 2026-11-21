extends Node3D

const Assets := preload("res://formats/native_assets.gd")

var materials := {}
var models := {}
var instances := {}
var adapter := ""


func display(assets: Dictionary) -> int:
	clear_models()
	adapter = assets["adapter"]
	for key: String in assets["geometry"]:
		var input: PackedByteArray = assets["geometry"][key]
		if not input.is_empty():
			var mesh := read_mesh(input, assets["textures"])
			if mesh:
				models[key] = mesh
	var count := 0
	for item: Dictionary in assets["instances"]:
		var key: String = item["mesh"]
		if not models.has(key):
			continue
		var model := MeshInstance3D.new()
		model.mesh = models[key]
		var world: Transform3D = item["transform"]
		model.transform = world.scaled_local(Vector3.ONE * float(item["scale"]))
		model.set_meta("native_pool", item["pool"])
		add_child(model)
		instances[item["index"]] = model
		count += 1
	return count


func clear_models() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	models.clear()
	instances.clear()
	materials.clear()


func move_instance(index: int, position: Vector3) -> void:
	var instance: MeshInstance3D = instances.get(index)
	if instance:
		instance.position = position


func read_mesh(bytes: PackedByteArray, textures: Dictionary) -> ArrayMesh:
	if bytes.size() < 8 or bytes.slice(0, 4).get_string_from_ascii() != "BZM1":
		return null
	var layers := bytes.decode_u32(4)
	if layers == 0 or layers > 4096:
		return null
	var mesh := ArrayMesh.new()
	var offset := 8
	for surface in layers:
		if offset + 4 > bytes.size():
			return null
		var length := bytes.decode_u32(offset)
		offset += 4
		if length > 512 or offset + length + 16 > bytes.size():
			return null
		var texture := bytes.slice(offset, offset + length).get_string_from_ascii().get_file().to_lower()
		offset += length
		var count := bytes.decode_u32(offset)
		var diffuse := Color(bytes.decode_float(offset + 4), bytes.decode_float(offset + 8), bytes.decode_float(offset + 12))
		offset += 16
		if count < 3 or count > 600_000 or count % 3 != 0 or offset + count * 32 > bytes.size() or not Vector3(diffuse.r, diffuse.g, diffuse.b).is_finite():
			return null
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		vertices.resize(count)
		normals.resize(count)
		uv.resize(count)
		for i in count:
			vertices[i] = Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))
			normals[i] = Vector3(bytes.decode_float(offset + 12), bytes.decode_float(offset + 16), bytes.decode_float(offset + 20)).normalized()
			uv[i] = Vector2(bytes.decode_float(offset + 24), bytes.decode_float(offset + 28))
			if not vertices[i].is_finite() or not normals[i].is_finite() or not uv[i].is_finite():
				return null
			offset += 32
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, material_for(texture, diffuse, textures))
	return mesh if offset == bytes.size() else null


func material_for(name: String, diffuse: Color, textures: Dictionary) -> StandardMaterial3D:
	var key := name + str(diffuse)
	if materials.has(key):
		return materials[key]
	var result := StandardMaterial3D.new()
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.albedo_color = diffuse
	var binding := diffuse_binding(name, textures)
	var path: String = textures.get(binding, "")
	if path == "" and binding != "":
		path = textures.get(binding.get_basename() + ".dds", "")
	if path != "":
		var texture := Assets.read_image(adapter, path)
		if texture != null and not texture.is_empty():
			result.albedo_texture = ImageTexture.create_from_image(texture)
			result.albedo_color = Color.WHITE
	materials[key] = result
	return result


func diffuse_binding(name: String, textures: Dictionary) -> String:
	if name.get_extension() != "material":
		return name
	var file := FileAccess.open(textures.get(name, ""), FileAccess.READ)
	if file == null or file.get_length() > 128 * 1024:
		return ""
	var text := file.get_buffer(file.get_length()).get_string_from_ascii()
	var inside := false
	for line in text.split("\n"):
		var trimmed := line.strip_edges().to_lower()
		if trimmed.begins_with("["):
			inside = trimmed == "[texture]"
		elif inside and trimmed.get_slice("=", 0).strip_edges() == "diffuse":
			return trimmed.get_slice("=", 1).strip_edges().trim_prefix('"').trim_suffix('"').get_file()
	return ""
