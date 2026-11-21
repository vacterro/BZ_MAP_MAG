extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Document := preload("res://core/map_document.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const Terrain := preload("res://formats/terrain_v5.gd")

var error := ""


func create_flat_map(mission: String, template: String, target: String, helper: String) -> bool:
	if OS.get_name() != "Windows" or not FileAccess.file_exists(helper):
		return fail("The Windows flat-map helper is unavailable.")
	if not mission.is_absolute_path() or not template.is_absolute_path() or not target.is_absolute_path() or exists(target):
		return fail("Choose a blank BZN, a TER template and a new map folder.")
	var stage := target.get_base_dir().path_join(".bzmag-new-" + nonce())
	var arguments := PackedStringArray(["-NoProfile", "-NonInteractive", "-File", helper, "-Mission", mission,
		"-VrvTemplate", template, "-Destination", stage])
	var output := []
	if OS.execute("powershell.exe", arguments, output, true) != 0:
		return fail(str(output[0]).strip_edges() if not output.is_empty() else "Could not create the flat map.")
	var names := DirAccess.get_files_at(stage)
	var package := Package.new()
	if not package.open(stage.path_join(mission.get_file())):
		return rollback(stage, names, "The new map failed verification. " + package.error)
	if exists(target) or DirAccess.rename_absolute(stage, target) != OK:
		return rollback(stage, names, "Could not publish the new map to the chosen folder.")
	return true


func save_project(document: Document, target: String) -> bool:
	if not target.is_absolute_path() or target.get_extension().to_lower() != "bzmag" or exists(target):
		return fail("Choose a new .bzmag file in an existing folder.")
	if not document.package.check_sources():
		return fail(document.package.error)
	var edits := {}
	for index: int in document.edits:
		edits[str(index)] = document.edits[index]
	var path_edits := {}
	for index: int in document.path_edits:
		var path: Dictionary = document.path_edits[index]
		if path.is_empty():
			path_edits[str(index)] = null
			continue
		var coordinates := []
		for point: Vector2 in path["points"]:
			coordinates.append([point.x, point.y])
		var record := {"name": path["name"], "type": path["type"], "points": coordinates}
		if index >= document.package.paths.size():
			record["id"] = path["id"]
		path_edits[str(index)] = record
	var object_edits := {}
	for index: int in document.object_edits:
		var edit: Dictionary = document.object_edits[index]
		var transform := Transform3D(edit["basis"], edit["position"])
		object_edits[str(index)] = {"position": [transform.origin.x, transform.origin.y, transform.origin.z],
			"basis": basis_array(transform.basis)}
	var object_removals := []
	for index: int in document.object_removals:
		object_removals.append(index)
	var object_inserts := []
	for addition: Dictionary in document.object_additions:
		object_inserts.append({"template": addition["template"], "id": addition["id"], "label": addition["label"],
			"sequence": addition["sequence"], "position": [addition["transform"].origin.x, addition["transform"].origin.y, addition["transform"].origin.z],
			"basis": basis_array(addition["transform"].basis)})
	var record := {"schema": 1, "source": document.package.source_path, "files": document.package.files, "edits": edits,
		"layers": document.layers, "pathEdits": path_edits, "objectEdits": object_edits,
		"objectRemovals": object_removals, "objectInserts": object_inserts}
	if not document.asset_profile.is_empty():
		record["assetProfile"] = document.asset_profile
	var terrain := document.package.terrain
	if not terrain.color_edits.is_empty():
		record["colorEdits"] = indexed_record(terrain.color_edits)
	if not terrain.tile_edits.is_empty():
		record["tileEdits"] = indexed_record(terrain.tile_edits)
	var stage := target.get_base_dir().path_join(".bzmag-" + nonce())
	if DirAccess.make_dir_absolute(stage) != OK:
		return fail("Could not reserve staging folder.")
	var temporary := stage.path_join("project.bzmag")
	var bytes := JSON.stringify(record, "", true, true).to_utf8_buffer()
	var ok := write_bytes(temporary, bytes) and FileAccess.get_file_as_bytes(temporary) == bytes
	if ok:
		ok = not exists(target) and DirAccess.rename_absolute(temporary, target) == OK
	discard(stage, PackedStringArray(["project.bzmag"]))
	return true if ok else fail("Project save failed. Choose a new writable path.")


func indexed_record(values: Dictionary) -> Dictionary:
	var record := {}
	for index: int in values:
		record[str(index)] = values[index]
	return record


static func basis_array(basis: Basis) -> Array:
	var values := []
	for axis in 3:
		var vector: Vector3 = basis.x if axis == 0 else (basis.y if axis == 1 else basis.z)
		values.append(vector.x)
		values.append(vector.y)
		values.append(vector.z)
	return values


func export_native(document: Document, target: String) -> bool:
	if document.has_preview():
		return fail("Apply or clear the terrain preview before exporting.")
	target = target.simplify_path()
	if not target.is_absolute_path() or exists(target):
		return fail("Choose a new export folder.")
	var package := document.package
	if not package.check_sources():
		return fail(package.error)
	var bzn := PackedByteArray()
	var suffix := PackedByteArray()
	var object_shift := 0
	if not document.path_edits.is_empty() or not document.object_edits.is_empty() or not document.object_removals.is_empty() or not document.object_additions.is_empty():
		var source_bzn := FileAccess.get_file_as_bytes(package.source_path.get_base_dir().path_join(package.bzn_name))
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		if digest.update(source_bzn) != OK or digest.finish().hex_encode() != package.files[package.bzn_name]:
			return fail("BZN changed while preparing mission edits.")
		suffix = source_bzn.slice(package.path_codec.table_end)
		if document.has_object_file_edits():
			if package.object_count_offset < 0 or package.object_insert_offset != package.path_codec.table_start - 7:
				return fail("This BZN layout does not support native object edits yet.")
			var blocks: Array = []
			for addition: Dictionary in document.object_additions:
				var template: Dictionary = package.objects[addition["template"]]
				var block := BznObjects.build_block(source_bzn, template, int(addition["sequence"]), String(addition["label"]), addition["transform"])
				blocks.append(block)
			var removals: Array = []
			for index: int in document.object_removals:
				removals.append(index)
			var patch := BznObjects.patch_objects(source_bzn, package.objects, document.object_export_edits(),
				removals, blocks, package.object_count_offset, package.object_insert_offset)
			if patch.is_empty():
				return fail("The native object edits could not be applied to this BZN.")
			bzn = patch["bytes"]
			object_shift = int(patch["shift"])
			package.path_codec.shift(object_shift)
		else:
			bzn = source_bzn
		bzn = package.path_codec.patch(bzn, document.path_edits)
		package.path_codec.shift(-object_shift)
	var stage := target.get_base_dir().path_join(".bzmag-" + nonce())
	if DirAccess.make_dir_absolute(stage) != OK:
		return fail("Could not reserve export staging folder.")
	var terrain := package.terrain.encode(document.edits)
	var names := PackedStringArray(package.files.keys())
	var hashes := {}
	for name in names:
		var output := stage.path_join(name)
		var expected: String = package.files[name]
		if name == package.terrain_name and (not document.edits.is_empty() or package.terrain.has_material_edits()):
			if not write_bytes(output, terrain) or FileAccess.get_file_as_bytes(output) != terrain:
				return rollback(stage, names, "Could not write and verify " + name)
			expected = FileAccess.get_sha256(output)
		elif name == package.bzn_name and not bzn.is_empty():
			if not write_bytes(output, bzn) or FileAccess.get_file_as_bytes(output) != bzn:
				return rollback(stage, names, "Could not write and verify " + name)
			expected = FileAccess.get_sha256(output)
		else:
			var source := package.source_path.get_base_dir().path_join(name)
			if DirAccess.copy_absolute(source, output) != OK:
				return rollback(stage, names, "Could not copy " + name)
		if expected == "" or FileAccess.get_sha256(output) != expected:
			return rollback(stage, names, "Member verification failed for " + name)
		hashes[name] = expected
	var reimport := Package.new()
	if not reimport.open(stage.path_join(package.source_path.get_file())) or reimport.files != hashes or reimport.terrain.heights != package.terrain.heights:
		return rollback(stage, names, "Export re-import failed. " + reimport.error)
	for layer in [Terrain.Layer.COLOR, Terrain.Layer.TILES]:
		var edits := package.terrain.material_changes(layer)
		for index: int in edits:
			if reimport.terrain.material_value(layer, index) != edits[index]:
				return rollback(stage, names, "Modified terrain material did not re-import as edited.")
	if not bzn.is_empty():
		var path_indices := document.path_indices()
		if reimport.path_codec.table_start != package.path_codec.table_start + object_shift or reimport.paths.size() != path_indices.size() or bzn.slice(reimport.path_codec.table_end) != suffix:
			return rollback(stage, names, "Modified BZN did not retain the expected path table and original trailer.")
		for index in reimport.paths.size():
			if not Document.same_path_fields(reimport.paths[index], document.path_at(path_indices[index])):
				return rollback(stage, names, "Modified BZN path did not re-import as edited.")
		if reimport.objects.size() != document.object_count():
			return rollback(stage, names, "Modified BZN did not re-import the expected native object count.")
		for index in reimport.objects.size():
			if BznObjects.fields(reimport.objects[index]) != expected_object_fields(document, index):
				return rollback(stage, names, "Modified BZN object did not re-import as edited.")
	if not package.check_sources():
		return rollback(stage, names, package.error)
	if exists(target) or DirAccess.rename_absolute(stage, target) != OK:
		return rollback(stage, names, "Could not publish export to the new folder.")
	return true


static func expected_object_fields(document: Document, view: int) -> Dictionary:
	var template: Dictionary = document.object_template(view)
	return {"odf": template["odf"], "label": document.object_label(view), "team": document.object_team(view),
		"sequence": document.object_sequence(view), "transform": document.object_transform(view)}


func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return false
	output.store_buffer(bytes)
	output.flush()
	var ok := output.get_error() == OK
	output.close()
	return ok


func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


func nonce() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func discard(stage: String, names: PackedStringArray) -> void:
	for name in names:
		DirAccess.remove_absolute(stage.path_join(name))
	DirAccess.remove_absolute(stage)


func rollback(stage: String, names: PackedStringArray, message: String) -> bool:
	discard(stage, names)
	return fail(message)


func fail(message: String) -> bool:
	error = message
	return false
