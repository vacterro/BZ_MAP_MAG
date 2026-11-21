extends Node3D

const Assets := preload("res://formats/native_assets.gd")

var materials := {}
var models := {}
var instances := {}
var specs := {}
var specs_by_odf := {}
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
		model.set_meta("native_scale", float(item["scale"]))
		model.set_meta("native_mesh", key)
		model.set_meta("native_pool", item["pool"])
		add_child(model)
		instances[item["index"]] = model
		var spec_entry := {"mesh": key, "scale": float(item["scale"]), "pool": item["pool"]}
		specs[item["index"]] = spec_entry
		var item_odf := String(item.get("odf", "")).to_lower()
		if not item_odf.is_empty():
			specs_by_odf[item_odf] = spec_entry
		count += 1
	return count


func clear_models() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	models.clear()
	instances.clear()
	materials.clear()
	specs.clear()
	specs_by_odf.clear()


func move_instance(index: int, position: Vector3) -> void:
	var instance: MeshInstance3D = instances.get(index)
	if instance:
		instance.position = position


func set_instance_transform(index: int, transform: Transform3D) -> void:
	var instance: MeshInstance3D = instances.get(index)
	if instance:
		instance.transform = transform.scaled_local(Vector3.ONE * float(instance.get_meta("native_scale", 1.0)))


func rebuild(document) -> void:
	# Reassign the loaded meshes to the document's current topological view.
	var pool := {}
	for child in get_children():
		var node: MeshInstance3D = child
		var key: String = node.get_meta("native_mesh", "")
		remove_child(node)
		if key.is_empty():
			node.queue_free()
			continue
		if not pool.has(key):
			pool[key] = []
		pool[key].append(node)
	instances.clear()
	for view in document.object_count():
		var ref_idx: int = document.object_pool_reference(view)
		var spec: Dictionary = specs.get(ref_idx, {}) if ref_idx >= 0 else {}
		if spec.is_empty():
			spec = specs_by_odf.get(document.object_odf(view).to_lower(), {})
		if spec.is_empty() or not models.has(spec["mesh"]):
			continue
		var candidates: Array = pool.get(String(spec["mesh"]), [])
		var model: MeshInstance3D = null
		if candidates.is_empty():
			model = MeshInstance3D.new()
			model.mesh = models[spec["mesh"]]
			model.set_meta("native_mesh", String(spec["mesh"]))
			model.set_meta("native_scale", float(spec["scale"]))
			model.set_meta("native_pool", bool(spec["pool"]))
		else:
			model = candidates.pop_back()
		model.transform = document.object_transform(view).scaled_local(Vector3.ONE * float(spec["scale"]))
		add_child(model)
		instances[view] = model
	for key in pool:
		for node: MeshInstance3D in pool[key]:
			node.queue_free()


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
