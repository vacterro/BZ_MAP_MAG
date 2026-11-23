extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Document := preload("res://core/map_document.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const BznPaths := preload("res://formats/bzn_paths.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const Water := preload("res://formats/water_v5.gd")
const SkyEnv := preload("res://formats/sky_env.gd")

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


## Creates a verified flat map package directly without requiring VRV templates.
## Copies the source blank BZN + companions into a staged folder, updates TRN
## [Size] to the requested dimensions/height, synthesizes a verified native TER
## v5 file via Terrain.create_flat (or copies an explicit template TER), and
## validates by full Package.open() before atomic publish.
func create_native_flat_map(source_bzn: String, target: String, size_m: int = 2048, height: float = 100.0, template_ter: String = "", options: Dictionary = {}) -> bool:
	if not source_bzn.is_absolute_path() or not FileAccess.file_exists(source_bzn) or source_bzn.get_extension().to_lower() != "bzn":
		return fail("Choose an existing blank BZN source file.")
	if not target.is_absolute_path() or exists(target):
		return fail("Choose a new destination folder for the map.")
	var samples := size_m / int(Terrain.SPACING)
	if size_m < 128 or size_m > 4096 or samples % Terrain.BLOCK != 0 or not is_finite(height) or absf(height) > 50000.0:
		return fail("Map size must be between 128 m and 4096 m in 32 m steps, with a finite initial height.")
	var src_dir := source_bzn.get_base_dir()
	var stem := source_bzn.get_file().get_basename()
	var trn_name := ""
	var inf_name := ""
	var extra_files: Array[String] = []
	for fname in DirAccess.get_files_at(src_dir):
		var lower := fname.to_lower()
		if lower.get_basename() != stem.to_lower():
			continue
		var ext := lower.get_extension()
		if ext == "ter":
			continue
		elif ext == "trn":
			trn_name = fname
		elif ext == "inf":
			inf_name = fname
		elif ext in ["bzn", "lua", "sky", "des"]:
			extra_files.append(fname)
	if trn_name.is_empty():
		return fail("Source blank map must include a same-stem .trn companion.")
	var ter_bytes := PackedByteArray()
	var half := samples / 2
	var origin := Vector2i(-half, -half)
	var dims := Vector2i(samples, samples)
	if not template_ter.strip_edges().is_empty():
		if not FileAccess.file_exists(template_ter):
			return fail("Selected TER template file was not found.")
		ter_bytes = FileAccess.get_file_as_bytes(template_ter)
		var check_ter := Terrain.new()
		if not check_ter.decode(ter_bytes):
			return fail("Invalid TER template: " + check_ter.error)
		origin = check_ter.origin
		dims = check_ter.dimensions
		samples = dims.x
		size_m = samples * int(Terrain.SPACING)
		height = check_ter.min_height
	else:
		ter_bytes = Terrain.create_flat(origin, dims, height, 0)
		if ter_bytes.is_empty():
			return fail("Could not generate native flat TER v5 data.")
	var stage := target.get_base_dir().path_join(".bzmag-new-" + nonce())
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		return fail("Could not reserve staging folder for the new map.")
	var written: PackedStringArray = []
	for fname in extra_files:
		if DirAccess.copy_absolute(src_dir.path_join(fname), stage.path_join(fname)) != OK:
			return rollback(stage, written, "Could not copy " + fname)
		written.append(fname)
	var bzn_file := source_bzn.get_file()
	if not options.is_empty():
		var flat_ter := Terrain.new()
		if not flat_ter.decode(ter_bytes):
			return rollback(stage, written, "Could not decode generated TER.")
		var configured_bzn := _configure_mission_bzn(FileAccess.get_file_as_bytes(stage.path_join(bzn_file)), flat_ter, height, options)
		if configured_bzn.is_empty():
			return rollback(stage, written, error if not error.is_empty() else "Could not configure native mission BZN.")
		if not write_bytes(stage.path_join(bzn_file), configured_bzn):
			return rollback(stage, written, "Could not write configured " + bzn_file)
		if String(options.get("mission_profile", "")) == "lua":
			var lua_name := stem + ".lua"
			if not FileAccess.file_exists(stage.path_join(lua_name)):
				var lua_stub := "-- Auto-generated BZCC LuaMission companion\r\nfunction Start()\r\nend\r\nfunction Update(timestep)\r\nend\r\n"
				if not write_bytes(stage.path_join(lua_name), lua_stub.to_utf8_buffer()):
					return rollback(stage, written, "Could not write " + lua_name)
				written.append(lua_name)
	if inf_name.is_empty():
		var synth_inf := stem + ".inf"
		var synth_text := "[DESCRIPTION]\r\nmissionName = \"%s\"\r\n" % stem
		if not write_bytes(stage.path_join(synth_inf), synth_text.to_utf8_buffer()):
			return rollback(stage, written, "Could not write " + synth_inf)
		written.append(synth_inf)
	else:
		if DirAccess.copy_absolute(src_dir.path_join(inf_name), stage.path_join(inf_name)) != OK:
			return rollback(stage, written, "Could not copy " + inf_name)
		written.append(inf_name)
	var trn_text := _rewrite_trn_size(FileAccess.get_file_as_string(src_dir.path_join(trn_name)), origin, dims, height)
	var trn_bytes := trn_text.to_utf8_buffer()
	if not write_bytes(stage.path_join(trn_name), trn_bytes):
		return rollback(stage, written, "Could not write " + trn_name)
	written.append(trn_name)
	var ter_name := stem + ".ter"
	if not write_bytes(stage.path_join(ter_name), ter_bytes):
		return rollback(stage, written, "Could not write " + ter_name)
	written.append(ter_name)
	var verify := Package.new()
	if not verify.open(stage.path_join(source_bzn.get_file())):
		return rollback(stage, written, "New map failed native package verification: " + verify.error)
	if exists(target) or DirAccess.rename_absolute(stage, target) != OK:
		return rollback(stage, written, "Could not publish new map folder.")
	return true


func _configure_mission_bzn(source_bytes: PackedByteArray, terrain: Terrain, height: float, options: Dictionary) -> PackedByteArray:
	var mod_id := String(options.get("mod_profile", "stock")).strip_edges().to_lower()
	var mis_id := String(options.get("mission_profile", "blank")).strip_edges().to_lower()
	var configure_mission := bool(options.get("configure_mission", false))
	var sanitize_stock := bool(options.get("sanitize_stock_objects", false))
	var allow_drop_vrv := bool(options.get("allow_drop_vrv_objects", false))
	var manual_odf_map: Dictionary = options.get("manual_odf_map", {})
	var layout := Layouts.recognize(source_bytes)
	var ver := int(layout.get("version", 0))
	if ver <= 0:
		fail("Unrecognized BZN layout in template.")
		return PackedByteArray()
	var path_codec := BznPaths.new()
	if not path_codec.read(source_bytes, ver):
		fail("Could not decode BZN path table in template.")
		return PackedByteArray()
	var obj_codec := BznObjects.new()
	if not obj_codec.read(source_bytes, ver, path_codec.table_start):
		fail("Could not decode BZN object table in template.")
		return PackedByteArray()

	var current_bytes := source_bytes
	var table_start := path_codec.table_start
	var ptr_counts := path_codec.pointer_counts(current_bytes)

	# 1. Validate & apply semantic ODF conversion (never heuristic _vsr stripping!)
	if mod_id in ["stock", "vsr"]:
		var plan := ModRegistry.plan_bzn_odf_conversion(obj_codec.objects, ptr_counts, mod_id, manual_odf_map, allow_drop_vrv)
		var odf_edits: Dictionary = plan["odfEdits"]
		var removals: Array = plan["removals"].duplicate()
		var unsupported: Array = plan["unsupported"]
		if not unsupported.is_empty():
			fail("Incompatible template ODF(s) for '%s': %s" % [mod_id, "; ".join(unsupported)])
			return PackedByteArray()
		if (not odf_edits.is_empty() or not removals.is_empty()) and not sanitize_stock:
			var needed: Array = plan["summaryLines"]
			fail("Source template requires explicit verified ODF conversion for '%s': %s" % [mod_id, "; ".join(needed)])
			return PackedByteArray()

		# Trim unreferenced PLGR playground showcase objects (obj[1..N]) when creating a clean Stock map from plgr.bzn
		var is_plgr_showcase := (mod_id == "stock" and obj_codec.mission_dll.to_lower() == "luamission.dll"
			and obj_codec.objects.size() > 20 and String(obj_codec.objects[0].get("odf", "")).to_lower() == "player")
		if is_plgr_showcase and bool(options.get("trim_showcase_objects", true)):
			for idx in range(1, obj_codec.objects.size()):
				var pid := int(obj_codec.objects[idx].get("flag8", 0))
				if pid <= 0 or int(ptr_counts.get(pid, 0)) <= 1:
					if not (idx in removals):
						removals.append(idx)
			if mis_id in ["strategy", "instant", "mpi", "duel"] and not odf_edits.has(0):
				odf_edits[0] = "ivscout"

		var xform_edits := {}
		for idx in obj_codec.objects.size():
			if idx in removals:
				continue
			var entry: Dictionary = obj_codec.objects[idx]
			if odf_edits.has(idx) or is_plgr_showcase or configure_mission:
				var xf: Transform3D = entry["transform"]
				if not is_equal_approx(xf.origin.y, height):
					xf.origin.y = height
					xform_edits[idx] = xf

		var insert_blocks: Array = []
		if configure_mission and mod_id == "stock" and mis_id in ["strategy", "instant", "mpi", "duel"]:
			var spawn_count := 0
			for idx in obj_codec.objects.size():
				if not (idx in removals) and String(obj_codec.objects[idx].get("odf", "")).to_lower() == "pspwn_1":
					spawn_count += 1
			if spawn_count < 2:
				var next_ptr := 1
				for pid: int in ptr_counts:
					if pid < 4294967295:
						next_ptr = maxi(next_ptr, pid + 1)
				var max_seq := 1
				for entry: Dictionary in obj_codec.objects:
					max_seq = maxi(max_seq, (int(entry["sequence"]) & ~0x800000) + 1)
				var p1_pts := MissionProfiles.preset_points("Player_1", terrain, Vector2.INF)
				var p2_pts := MissionProfiles.preset_points("RecyclerEnemy", terrain, Vector2.INF)
				var p1_xz := p1_pts[0] if not p1_pts.is_empty() else Vector2(-256.0, -256.0)
				var p2_xz := p2_pts[0] if not p2_pts.is_empty() else Vector2(256.0, 256.0)
				for sp_xz: Vector2 in [p1_xz, p2_xz]:
					if spawn_count >= 2:
						break
					var alloc_ptr := allocate_unique_pointer_id(ptr_counts, next_ptr)
					if alloc_ptr <= 0:
						fail("Could not allocate unique pointer ID for spawnpoint.")
						return PackedByteArray()
					ptr_counts[alloc_ptr] = 1
					next_ptr = alloc_ptr + 1
					var sp_xf := Transform3D(Basis.IDENTITY, Vector3(sp_xz.x, height, sp_xz.y))
					insert_blocks.append(BznObjects.build_spawnpoint_block(max_seq, sp_xf, alloc_ptr, 0))
					max_seq += 1
					spawn_count += 1

		if not odf_edits.is_empty() or not removals.is_empty() or not xform_edits.is_empty() or not insert_blocks.is_empty():
			var patched_obj := BznObjects.patch_objects(current_bytes, obj_codec.objects, xform_edits, removals, insert_blocks, obj_codec.count_offset, obj_codec.insert_offset, {}, odf_edits)
			if patched_obj.is_empty():
				fail("Could not patch template objects for %s mission." % mod_id)
				return PackedByteArray()
			current_bytes = patched_obj["bytes"]
			if not path_codec.read(current_bytes, ver) or not obj_codec.read(current_bytes, ver, path_codec.table_start):
				fail("Re-reading patched object table failed.")
				return PackedByteArray()
			table_start = path_codec.table_start

	var sync_dll := bool(options.get("sync_mission_dll", false))
	if not configure_mission and not sanitize_stock and not sync_dll:
		return current_bytes

	# 2. Configure Mission DLL & Required Paths when configure_mission or sync_mission_dll is enabled
	if configure_mission or sync_dll or (mod_id == "stock" and mis_id == "blank" and obj_codec.mission_dll.to_lower() == "luamission.dll"):
		var contract := MissionProfiles.contract_for(mis_id, mod_id)
		var target_dll := String(contract.get("dll", "")).strip_edges()
		if not target_dll.is_empty() or mis_id == "blank":
			var with_dll := BznObjects.patch_mission_dll(current_bytes, obj_codec.insert_offset, table_start, target_dll)
			if with_dll.is_empty():
				fail("Could not patch BZN mission DLL.")
				return PackedByteArray()
			current_bytes = with_dll
			if not path_codec.read(current_bytes, ver):
				fail("Could not decode BZN path table after DLL update.")
				return PackedByteArray()
		if not configure_mission:
			return current_bytes
		var req_paths: Array = contract.get("required", [])
		var rec_paths: Array = contract.get("recommended", [])
		var wanted: Array[String] = []
		for r_v in req_paths:
			var r := String(r_v)
			if not (r in wanted):
				wanted.append(r)
		if mis_id in ["strategy", "instant", "mpi", "duel"]:
			for r_v in rec_paths:
				var r := String(r_v)
				if r in ["Player_1", "Player_2", "Recycler", "RecyclerEnemy", "gtow1", "gtow2", "gtow3", "gtow4", "gtow5", "turretEnemy1", "turretEnemy2", "hold1", "hold2", "stage1", "Stage1"] and not (r in wanted):
					wanted.append(r)
		var existing_by_lower := {}
		for idx in path_codec.paths.size():
			existing_by_lower[String(path_codec.paths[idx]["name"]).to_lower()] = idx
		var path_edits := {}
		var ptr_ids := path_codec.pointer_counts(current_bytes)
		var next_id := 1
		for p: Dictionary in path_codec.paths:
			next_id = maxi(next_id, int(p["id"]) + 1)
		var next_slot := path_codec.paths.size()
		# Update existing edge_path to fit new terrain bounds
		if existing_by_lower.has("edge_path"):
			var e_idx: int = existing_by_lower["edge_path"]
			var e_rec: Dictionary = path_codec.paths[e_idx]
			path_edits[e_idx] = {
				"id": e_rec["id"],
				"name": e_rec["name"],
				"points": MissionProfiles.propose_edge_path(terrain),
				"type": 2,
			}
		for pname: String in wanted:
			var key := pname.to_lower()
			if existing_by_lower.has(key):
				continue
			var alloc_id := allocate_unique_pointer_id(ptr_ids, next_id)
			if alloc_id <= 0:
				alloc_id = next_id
			ptr_ids[alloc_id] = 1
			next_id = alloc_id + 1
			path_edits[next_slot] = {
				"id": alloc_id,
				"name": pname,
				"points": MissionProfiles.preset_points(pname, terrain, Vector2.INF),
				"type": MissionProfiles.preset_type(pname),
			}
			next_slot += 1
		if not path_edits.is_empty():
			current_bytes = path_codec.patch(current_bytes, path_edits)
	return current_bytes


static func _rewrite_trn_size(content: String, origin: Vector2i, dims: Vector2i, height: float) -> String:
	var min_x := origin.x * int(Terrain.SPACING)
	var min_z := origin.y * int(Terrain.SPACING)
	var width_m := dims.x * int(Terrain.SPACING)
	var depth_m := dims.y * int(Terrain.SPACING)
	var lines := content.replace("\r\n", "\n").split("\n")
	var out: PackedStringArray = []
	var in_size := false
	var wrote := {"minx": false, "minz": false, "width": false, "depth": false, "height": false}
	var values := {
		"minx": "MinX = %d" % min_x,
		"minz": "MinZ = %d" % min_z,
		"width": "Width = %d" % width_m,
		"depth": "Depth = %d" % depth_m,
		"height": "Height = %.1f" % height,
	}
	for line in lines:
		var trimmed := line.strip_edges()
		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			if in_size:
				for k in wrote:
					if not wrote[k]:
						out.append(values[k])
			in_size = trimmed.to_lower() == "[size]"
			out.append(line)
			continue
		if in_size and trimmed.contains("="):
			var key := trimmed.get_slice("=", 0).strip_edges().to_lower()
			if values.has(key):
				out.append(values[key])
				wrote[key] = true
				continue
		out.append(line)
	if in_size:
		for k in wrote:
			if not wrote[k]:
				out.append(values[k])
	return "\r\n".join(out)


func save_project(document: Document, target: String) -> bool:
	if document.has_active_edit_transaction():
		return fail("Finish the active brush or drag transaction before saving.")
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
		var ins_rec := {"template": addition["template"], "id": addition["id"], "label": addition["label"],
			"sequence": addition["sequence"], "position": [addition["transform"].origin.x, addition["transform"].origin.y, addition["transform"].origin.z],
			"basis": basis_array(addition["transform"].basis)}
		if bool(addition.get("native_class", false)):
			ins_rec["native_class"] = true
			ins_rec["odf"] = String(addition.get("odf", ""))
			ins_rec["team"] = int(addition.get("team", 0))
			ins_rec["builder"] = String(addition.get("builder", ""))
		object_inserts.append(ins_rec)
	var object_label_edits := {}
	for index: int in document.object_label_edits:
		object_label_edits[str(index)] = String(document.object_label_edits[index])
	var object_odf_edits := {}
	for index: int in document.object_odf_edits:
		object_odf_edits[str(index)] = String(document.object_odf_edits[index])
	var water_records := {}
	for layer: int in document.water_heights:
		water_records[str(layer)] = {"height": float(document.water_heights[layer])}
	for layer: int in document.water_edits:
		var cover := {}
		for block: int in document.water_edits[layer]:
			cover[str(block)] = bool(document.water_edits[layer][block])
		if water_records.has(str(layer)):
			water_records[str(layer)]["cover"] = cover
		else:
			water_records[str(layer)] = {"cover": cover}
	document.ensure_layer_uids()
	var record := {"schema": 1, "source": document.package.source_path, "files": document.package.files, "edits": edits,
		"layers": document.layers, "layerUids": document.layer_uids.duplicate(), "sculptLayers": document.sculpt_layers.duplicate(true), "activeSculptUid": document.active_sculpt_uid, "colorLayers": document.color_layers.duplicate(true), "activeColorUid": document.active_color_uid, "pathEdits": path_edits, "objectEdits": object_edits, "objectLabelEdits": object_label_edits,
		"objectOdfEdits": object_odf_edits, "objectRemovals": object_removals, "objectInserts": object_inserts, "waterEdits": water_records,
		"target": {
			"engineProfile": document.engine_profile,
			"modProfile": document.mod_profile,
			"missionProfile": document.mission_profile,
			"formatProfile": document.package.layout_id,
			"explicit": document.profile_explicit,
		},
		"dependencies": {
			"assetProfile": document.asset_profile,
		}}
	if not document.asset_profile.is_empty():
		record["assetProfile"] = document.asset_profile
	if document.has_mission_dll_edit():
		record["missionDllOverride"] = document.effective_mission_dll()
	if document.has_environment_edits():
		record["environmentEdits"] = document.environment_edits.duplicate(true)
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
	if document.has_active_edit_transaction():
		return fail("Finish the active brush or drag transaction before exporting.")
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
	var wat := PackedByteArray()
	var sky := PackedByteArray()
	if document.has_water_file_edits():
		wat = Water.encode(package.water_bytes, document.water_edits, document.water_heights)
		if wat.is_empty():
			return fail("The native water edits could not be applied to this map.")
	if document.has_environment_edits():
		if package.sky_name.is_empty() or package.sky_bytes.is_empty() or not SkyEnv.is_writable(package.sky_env):
			return fail("Cannot export environment edits: " + String(package.sky_env.get("writeRefusalReason", "this map has no verified writable native .SKY layout.")))
		sky = SkyEnv.encode_sky(package.sky_bytes, document.environment_edits)
		if sky.is_empty():
			return fail("The native .SKY environment edits could not be encoded.")
	if not document.path_edits.is_empty() or document.has_object_file_edits() or document.has_mission_dll_edit():
		var source_bzn := FileAccess.get_file_as_bytes(package.source_path.get_base_dir().path_join(package.bzn_name))
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		if digest.update(source_bzn) != OK or digest.finish().hex_encode() != package.files[package.bzn_name]:
			return fail("BZN changed while preparing mission edits.")
		suffix = source_bzn.slice(package.path_codec.table_end)
		if document.has_object_file_edits():
			if package.object_count_offset < 0 or package.object_insert_offset <= package.object_count_offset or package.object_insert_offset >= package.path_codec.table_start - 7:
				return fail("This BZN layout does not support native object edits yet.")
			if document.object_count() > BznObjects.MAX_OBJECTS:
				return fail("Object count exceeds the native BZN limit (%d)." % BznObjects.MAX_OBJECTS)
			var pointer_counts := package.path_codec.pointer_counts(source_bzn)
			var next_pointer_id := 1
			for ptr_id: int in pointer_counts:
				if ptr_id < 4294967295:
					next_pointer_id = maxi(next_pointer_id, ptr_id + 1)
			var blocks: Array = []
			for addition: Dictionary in document.object_additions:
				var allocated_ptr := allocate_unique_pointer_id(pointer_counts, next_pointer_id)
				if allocated_ptr <= 0:
					return fail("No unused native object pointer ID is available.")
				pointer_counts[allocated_ptr] = 1
				next_pointer_id = 1 if allocated_ptr >= 4294967295 else allocated_ptr + 1
				var add_label := String(addition["label"])
				var add_seq := int(addition["sequence"])
				if add_label.is_empty():
					add_seq = add_seq | 0x800000
				else:
					add_seq = add_seq & ~0x800000
				var block := PackedByteArray()
				if bool(addition.get("native_class", false)):
					var add_odf := String(addition.get("odf", ""))
					var add_team := int(addition.get("team", 0))
					block = BznObjects.build_native_class_block(add_odf, add_seq, add_label, addition["transform"], allocated_ptr, add_team, package.bzn_version)
					if block.is_empty():
						return fail("No verified native class builder for ODF '%s' on BZN %d." % [add_odf, package.bzn_version])
				else:
					var template_idx := int(addition.get("template", -1))
					if template_idx < 0 or template_idx >= package.objects.size():
						return fail("Missing native object template for insertion.")
					var template: Dictionary = package.objects[template_idx]
					var add_odf := String(addition.get("odf", ""))
					if add_odf.is_empty() and document.object_odf_edits.has(template_idx):
						add_odf = String(document.object_odf_edits[template_idx])
					block = BznObjects.build_block(source_bzn, template, add_seq, add_label, addition["transform"], allocated_ptr, add_odf)
				blocks.append(block)
			var removals: Array = []
			for index: int in document.object_removals:
				if index < 0 or index >= package.objects.size():
					return fail("Invalid object removal index.")
				var ptr_id := int(package.objects[index]["flag8"])
				if ptr_id > 0 and int(pointer_counts.get(ptr_id, 0)) > 1:
					return fail("Cannot remove an object referenced by another mission record.")
				removals.append(index)
			var patch := BznObjects.patch_objects(source_bzn, package.objects, document.object_export_edits(),
				removals, blocks, package.object_count_offset, package.object_insert_offset, document.object_label_edits, document.object_odf_edits)
			if patch.is_empty():
				return fail("The native object edits could not be applied to this BZN.")
			bzn = patch["bytes"]
			object_shift = int(patch["shift"])
			package.path_codec.shift(object_shift)
		else:
			bzn = source_bzn
		if document.has_mission_dll_edit():
			if package.object_insert_offset < 0 or package.object_insert_offset + object_shift >= package.path_codec.table_start - 7:
				package.path_codec.shift(-object_shift)
				return fail("This BZN layout does not support native mission DLL edits.")
			var shifted_insert := package.object_insert_offset + object_shift
			var shifted_table := package.path_codec.table_start
			var before_dll_len := bzn.size()
			var dll_patched := BznObjects.patch_mission_dll(bzn, shifted_insert, shifted_table, document.effective_mission_dll())
			if dll_patched.is_empty():
				package.path_codec.shift(-object_shift)
				return fail("Could not patch native BZN mission DLL.")
			var dll_shift := dll_patched.size() - before_dll_len
			bzn = dll_patched
			object_shift += dll_shift
			package.path_codec.shift(dll_shift)
		if not document.path_edits.is_empty():
			bzn = package.path_codec.patch(bzn, document.path_edits)
		package.path_codec.shift(-object_shift)
	var stage := target.get_base_dir().path_join(".bzmag-" + nonce())
	if DirAccess.make_dir_absolute(stage) != OK:
		return fail("Could not reserve export staging folder.")
	# Compose enabled sculpt and color layers into export staging only. The
	# editable document, its BZMAG layers and its Undo history stay untouched.
	var export_edits := document.export_heights()
	var export_colors := document.export_colors()
	var terrain := package.terrain.encode(export_edits, export_colors)
	var names := PackedStringArray(package.files.keys())
	var hashes := {}
	for name in names:
		var output := stage.path_join(name)
		var expected: String = package.files[name]
		if name == package.terrain_name and (not export_edits.is_empty() or not export_colors.is_empty() or package.terrain.has_material_edits()):
			if not write_bytes(output, terrain) or FileAccess.get_file_as_bytes(output) != terrain:
				return rollback(stage, names, "Could not write and verify " + name)
			expected = FileAccess.get_sha256(output)
		elif name == package.bzn_name and not bzn.is_empty():
			if not write_bytes(output, bzn) or FileAccess.get_file_as_bytes(output) != bzn:
				return rollback(stage, names, "Could not write and verify " + name)
			expected = FileAccess.get_sha256(output)
		elif name == package.water_name and not wat.is_empty():
			if not write_bytes(output, wat) or FileAccess.get_file_as_bytes(output) != wat:
				return rollback(stage, names, "Could not write and verify " + name)
			expected = FileAccess.get_sha256(output)
		elif name == package.sky_name and not sky.is_empty():
			if not write_bytes(output, sky) or FileAccess.get_file_as_bytes(output) != sky:
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
	# Verify against the composed export heights, which may include unbaked
	# sculpt deltas that are intentionally absent from the editable document.
	var expected_heights := package.terrain.heights.duplicate()
	for index: int in export_edits:
		if index >= 0 and index < expected_heights.size():
			expected_heights[index] = float(export_edits[index])
	if not reimport.open(stage.path_join(package.source_path.get_file())) or reimport.files != hashes or reimport.terrain.heights != expected_heights:
		return rollback(stage, names, "Export re-import failed. " + reimport.error)
	for layer in [Terrain.Layer.COLOR, Terrain.Layer.TILES]:
		# Reimport oracle uses composed export colors, not the editable committed
		# edits: unbaked color layers are present in the TER but absent there.
		var edits: Dictionary = export_colors if layer == Terrain.Layer.COLOR else package.terrain.material_changes(layer)
		for index: int in edits:
			if reimport.terrain.material_value(layer, index) != edits[index]:
				return rollback(stage, names, "Modified terrain material did not re-import as edited.")
	if not wat.is_empty():
		if reimport.water == null or reimport.water.width != package.water.width or reimport.water.depth != package.water.depth or reimport.water.invalid_layer_flags != package.water.invalid_layer_flags:
			return rollback(stage, names, "Modified water did not re-import as edited.")
		var reimported := {}
		for entry: Dictionary in reimport.water.layers:
			reimported[int(entry["index"])] = entry
		for entry: Dictionary in document.water_layers_effective():
			var index := int(entry["index"])
			if not reimported.has(index) or reimported[index]["tiles"] != entry["tiles"] or absf(float(reimported[index]["height"]) - float(entry["height"])) > 0.0005:
				return rollback(stage, names, "Modified water did not re-import as edited.")
		if reimported.size() != document.water_layers_effective().size():
			return rollback(stage, names, "Modified water did not re-import as edited.")
	if not sky.is_empty():
		if not SkyEnv.is_writable(reimport.sky_env) or reimport.sky_bytes.size() != package.sky_bytes.size():
			return rollback(stage, names, "Modified .SKY did not re-import cleanly.")
		var eff_env := document.effective_environment()
		var reimp_fields: Dictionary = reimport.sky_env.get("fields", {})
		for k: String in eff_env:
			var want: Variant = eff_env[k]
			var got: Variant = reimp_fields.get(k, null)
			if want is Array and got is Array and (want as Array).size() == 4 and (got as Array).size() == 4:
				for ci in 4:
					if absf(float(want[ci]) - float(got[ci])) > 0.0005:
						return rollback(stage, names, "Modified .SKY color '%s' did not re-import as edited." % k)
			elif (want is float or want is int) and (got is float or got is int):
				if absf(float(want) - float(got)) > 0.0005:
					return rollback(stage, names, "Modified .SKY value '%s' did not re-import as edited." % k)
	if not bzn.is_empty():
		var path_indices := document.path_indices()
		if reimport.path_codec.table_start != package.path_codec.table_start + object_shift or reimport.paths.size() != path_indices.size() or bzn.slice(reimport.path_codec.table_end) != suffix:
			return rollback(stage, names, "Modified BZN did not retain the expected path table and original trailer.")
		if reimport.mission_dll != document.effective_mission_dll():
			return rollback(stage, names, "Modified BZN mission DLL did not re-import as edited.")
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


static func allocate_unique_pointer_id(used_ids: Dictionary, start: int = 1, max_probes: int = 65536) -> int:
	var candidate := start if start >= 1 and start <= 4294967295 else 1
	var limit := mini(max_probes, 4294967295)
	for _attempt in limit:
		if not used_ids.has(candidate):
			return candidate
		candidate = 1 if candidate >= 4294967295 else candidate + 1
	return -1


static func expected_object_fields(document: Document, view: int) -> Dictionary:
	return {"odf": document.object_odf(view), "label": document.object_label(view), "team": document.object_team(view),
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
