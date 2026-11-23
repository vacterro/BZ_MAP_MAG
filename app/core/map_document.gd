extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Graph := preload("res://nodes/height_graph.gd")
const PathCodec := preload("res://formats/bzn_paths.gd")
const BznObjects := preload("res://formats/bzn_objects.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const Water := preload("res://formats/water_v5.gd")
const SkyEnv := preload("res://formats/sky_env.gd")
const Sculpt := preload("res://core/sculpt_layers.gd")
const ColorLayers := preload("res://core/color_layers.gd")
const SlopeShapes := preload("res://core/slope_shapes.gd")
const VrvShapes := preload("res://core/vrv_shapes.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const MissionProfiles := preload("res://core/mission_profiles.gd")
const HISTORY_LIMIT := 64
const MAX_EDITOR_ABS_HEIGHT := 100000.0
enum Brush { OFFSET, SMOOTH, FLATTEN, SPRAY }
enum BrushShape { SQUARE, CIRCLE, CONE, BELL }
enum MirrorDirection { MIN_X_TO_MAX_X, MAX_X_TO_MIN_X, MIN_Z_TO_MAX_Z, MAX_Z_TO_MIN_Z }

signal terrain_changed(region: Rect2i)
signal materials_changed(region: Rect2i, layer: int)
signal paths_changed
signal object_moved(view_index: int)
signal objects_changed
signal water_changed
signal profile_changed
signal environment_changed
signal layers_changed(selected_index: int)

const WATER_LAYERS := 8
const WATER_BLOCK := 16

static var _next_document_id := 0

var document_id := 0
var package: Package
var base_heights := PackedFloat32Array()
var edits := {}
var path_edits := {}
var native_path_ids := {}
var asset_profile := ""
var engine_profile := "bzcc-2.0.185"
var mod_profile := "stock"
var mission_profile := "blank"
var profile_explicit := false
var detected_profile_info: Dictionary = {}
var mission_dll_override := ""
var has_mission_dll_override := false
var environment_edits: Dictionary = {}
var object_edits := {}
var object_label_edits := {}
var object_odf_edits := {}
var object_additions: Array = []
var object_removals := {}
var next_object_id := 1
var water_edits := {}
var water_heights := {}
var water_base := {}
var water_stroke := {}
var water_stroke_active := false
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var stroke := {}
var stroke_weights := {}
var stroke_exact := {}
var stroke_tick := 0
var stroke_active := false
var stroke_layer := Terrain.Layer.HEIGHT
var layers: Array = [Graph.layer()]
var layer_uids: Array[int] = [1]
var next_layer_id := 2
var layer_stack_revision := 0
var sculpt_layers: Array = []
var next_sculpt_uid := 1
var active_sculpt_uid := -1
var sculpt_revision := 0
var sculpt_stroke_active := false
var sculpt_mask_stroke_active := false
var _sculpt_mask_before: Array = []
var _sculpt_mask_uid := -1
var _sculpt_mask_journal := {}
var _sculpt_mask_journal_present := {}
var _sculpt_mask_restore_preview := false
var _sculpt_stroke_before: Array = []
var _sculpt_stroke_uid := -1
var _sculpt_stroke_touched := false
var _sculpt_live_preview := false
var _sculpt_live_base := {}
var _sculpt_composition_active := false
var _sculpt_opacity_preview_uid := -1
var _sculpt_opacity_preview_value := NAN
var _sculpt_opacity_restore_preview := false
signal sculpt_layers_changed(selected_uid: int)
var color_layers: Array = []
var next_color_uid := 1
var active_color_uid := -1
var color_revision := 0
var color_stroke_active := false
var color_mask_stroke_active := false
var _color_mask_before: Array = []
var _color_mask_uid := -1
var _color_stroke_before: Array = []
var _color_stroke_uid := -1
var _color_stroke_touched := false
var _color_stroke_sample_value: Dictionary = {}
var _color_stroke_coverage: Dictionary = {}
var _color_live_preview := false
var _color_composition_active := false
var _color_opacity_preview_uid := -1
var _color_opacity_preview_value := NAN
signal color_layers_changed(selected_uid: int)
var preview_before := {}
var preview_after := {}
var preview_owner := ""
var preview_source_revision := ""
var preview_sculpt_revision := -1
var edit_revision := 0
var error := ""


func _init() -> void:
	_next_document_id += 1
	document_id = _next_document_id


## Single admission check for operations that must never serialize a partial
## user gesture. Covers terrain, water and sculpt brush transactions as well as
## object/path drags tracked by the editor through `external_transaction`.
var external_transaction := false

func has_active_edit_transaction() -> bool:
	return stroke_active or water_stroke_active or sculpt_stroke_active or sculpt_mask_stroke_active or color_stroke_active or color_mask_stroke_active or external_transaction


func open(path: String) -> bool:
	var source := path
	var saved: Dictionary = {}
	if path.get_extension().to_lower() == "bzmag":
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null or input.get_length() > 64 * 1024 * 1024:
			return fail("Could not read bounded project file.")
		var data: Variant = JSON.parse_string(input.get_as_text())
		if not data is Dictionary or data.get("schema") != 1 or not data.get("source") is String or not data.get("files") is Dictionary or not data.get("edits") is Dictionary:
			return fail("Invalid BZMAG project schema.")
		saved = data
		source = saved["source"]
		if not source.is_absolute_path() or source.get_extension().to_lower() != "bzn":
			return fail("Project source must be an absolute BZN path.")
	native_path_ids.clear()
	asset_profile = ""
	engine_profile = "bzcc-2.0.185"
	mod_profile = "stock"
	mission_profile = "blank"
	profile_explicit = false
	detected_profile_info = {}
	mission_dll_override = ""
	has_mission_dll_override = false
	environment_edits = {}
	object_edits = {}
	object_additions = []
	object_removals = {}
	next_object_id = 1
	water_edits = {}
	water_heights = {}
	water_base = {}
	water_stroke = {}
	water_stroke_active = false
	object_label_edits = {}
	object_odf_edits = {}
	layers = [Graph.layer()]
	layer_uids.clear()
	next_layer_id = 1
	layer_stack_revision = 0
	sculpt_layers.clear()
	next_sculpt_uid = 1
	active_sculpt_uid = -1
	sculpt_revision = 0
	color_layers.clear()
	next_color_uid = 1
	active_color_uid = -1
	color_revision = 0
	color_stroke_active = false
	color_mask_stroke_active = false
	_color_mask_before = []
	_color_mask_uid = -1
	_color_stroke_before = []
	_color_stroke_uid = -1
	_color_stroke_touched = false
	_color_stroke_sample_value = {}
	_color_stroke_coverage = {}
	_color_live_preview = false
	_color_composition_active = false
	_color_opacity_preview_uid = -1
	_color_opacity_preview_value = NAN
	preview_owner = ""
	preview_source_revision = ""
	preview_sculpt_revision = -1
	sculpt_stroke_active = false
	sculpt_mask_stroke_active = false
	_sculpt_mask_before = []
	_sculpt_mask_uid = -1
	_sculpt_mask_journal = {}
	_sculpt_mask_journal_present = {}
	_sculpt_mask_restore_preview = false
	_sculpt_stroke_before = []
	_sculpt_stroke_uid = -1
	_sculpt_stroke_touched = false
	_sculpt_live_preview = false
	_sculpt_live_base = {}
	_sculpt_composition_active = false
	_sculpt_opacity_preview_uid = -1
	_sculpt_opacity_preview_value = NAN
	_sculpt_opacity_restore_preview = false
	package = Package.new()
	if not package.open(source):
		return fail(package.error)
	var terrain := package.terrain
	base_heights = terrain.heights.duplicate()
	detected_profile_info = ModRegistry.detect_map_profiles(package)
	mod_profile = String(detected_profile_info.get("recommendedMod", "stock"))
	mission_profile = String(detected_profile_info.get("recommendedMission", "blank"))
	profile_explicit = false
	if not saved.is_empty():
		if saved["files"] != package.files:
			return fail("Project source revisions differ from the saved project.")
		var saved_profile: Variant = saved.get("assetProfile", "")
		var deps_block: Variant = saved.get("dependencies", null)
		if deps_block is Dictionary and saved_profile is String and String(saved_profile).is_empty():
			saved_profile = deps_block.get("assetProfile", "")
		if not valid_asset_profile(saved_profile):
			return fail("The project asset profile must be an absolute JSON path.")
		asset_profile = saved_profile
		if saved.has("target"):
			if not read_target_profile(saved["target"]):
				return false
		if saved.has("missionDllOverride"):
			var saved_dll: Variant = saved["missionDllOverride"]
			if not valid_mission_dll_name(saved_dll):
				return fail("Invalid saved mission DLL override.")
			mission_dll_override = String(saved_dll).strip_edges()
			has_mission_dll_override = mission_dll_override != String(package.mission_dll)
		var graph := Graph.new()
		if not saved.get("layers", layers) is Array or not graph.validate_stack(saved.get("layers", layers)):
			return fail("Invalid node stack. " + graph.error)
		layers = saved.get("layers", layers).map(Graph.normalize_layer)
		if saved.has("layerUids"):
			var raw_uids: Variant = saved["layerUids"]
			if not raw_uids is Array or (raw_uids as Array).size() != layers.size():
				return fail("Invalid saved layer identity metadata.")
			var seen_uids := {}
			for raw_uid in (raw_uids as Array):
				if not (raw_uid is int or raw_uid is float) or not is_finite(float(raw_uid)):
					return fail("Invalid saved layer identity metadata.")
				var uid_number := float(raw_uid)
				if uid_number <= 0.0 or uid_number != floorf(uid_number) or uid_number > ColorLayers.MAX_UID:
					return fail("Invalid saved layer identity metadata.")
				var uid := int(uid_number)
				if seen_uids.has(uid):
					return fail("Invalid saved layer identity metadata.")
				seen_uids[uid] = true
				layer_uids.append(uid)
				next_layer_id = maxi(next_layer_id, uid + 1)
		if saved.has("sculptLayers"):
			var raw_sculpt: Variant = saved["sculptLayers"]
			if not raw_sculpt is Array:
				return fail("Invalid sculpt layer metadata.")
			if not Sculpt.validate_stack_raw(raw_sculpt as Array, base_heights.size()):
				return fail("Malformed sculpt layer payload rejected before normalization.")
			for item in (raw_sculpt as Array):
				if not item is Dictionary:
					return fail("Invalid sculpt layer record.")
				var clean := Sculpt.normalize(item as Dictionary)
				if int(clean["uid"]) <= 0 or next_sculpt_uid <= int(clean["uid"]):
					next_sculpt_uid = int(clean["uid"]) + 1
				sculpt_layers.append(clean)
			if not Sculpt.validate_stack(sculpt_layers, base_heights.size()):
				return fail("Invalid sculpt layer deltas.")
			if not sculpt_layers.is_empty():
				active_sculpt_uid = int((sculpt_layers[0] as Dictionary)["uid"])
				if saved.has("activeSculptUid"):
					var saved_active: Variant = saved["activeSculptUid"]
					if saved_active == null:
						active_sculpt_uid = -1
					elif not (saved_active is int or saved_active is float):
						return fail("Invalid saved active sculpt selection.")
					else:
						var active_number := float(saved_active)
						if not is_finite(active_number) or active_number != floorf(active_number) or absf(active_number) > 9007199254740992.0:
							return fail("Invalid saved active sculpt selection.")
						var saved_active_uid := int(active_number)
						if saved_active_uid == -1:
							active_sculpt_uid = -1
						elif saved_active_uid <= 0 or sculpt_index_by_uid(saved_active_uid) < 0:
							return fail("Invalid saved active sculpt selection.")
						else:
							active_sculpt_uid = saved_active_uid
			if saved.has("colorLayers"):
				var raw_color: Variant = saved["colorLayers"]
				if not raw_color is Array:
					return fail("Invalid color layer metadata.")
				if not ColorLayers.validate_stack_raw(raw_color as Array, terrain.heights.size()):
					return fail("Malformed color layer payload rejected before normalization.")
				for item in (raw_color as Array):
					var clean := ColorLayers.normalize(item as Dictionary)
					if int(clean["uid"]) <= 0 or next_color_uid <= int(clean["uid"]):
						next_color_uid = int(clean["uid"]) + 1
					color_layers.append(clean)
				if not ColorLayers.validate_stack(color_layers, terrain.heights.size()):
					return fail("Invalid color layer samples.")
				if not color_layers.is_empty():
					active_color_uid = int((color_layers[0] as Dictionary)["uid"])
				if saved.has("activeColorUid"):
					var saved_color_active: Variant = saved["activeColorUid"]
					if saved_color_active == null:
						active_color_uid = -1
					elif not (saved_color_active is int or saved_color_active is float):
						return fail("Invalid saved active color selection.")
					else:
						var color_number := float(saved_color_active)
						if not is_finite(color_number) or color_number != floorf(color_number) or absf(color_number) > ColorLayers.MAX_UID:
							return fail("Invalid saved active color selection.")
						var saved_color_uid := int(color_number)
						if saved_color_uid == -1:
							active_color_uid = -1
						elif saved_color_uid <= 0 or color_index_by_uid(saved_color_uid) < 0:
							return fail("Invalid saved active color selection.")
						else:
							active_color_uid = saved_color_uid
		for key: String in saved["edits"]:
			var value: Variant = saved["edits"][key]
			var index := key.to_int()
			if not key.is_valid_int() or str(index) != key or index < 0 or index >= base_heights.size() or not (value is float or value is int) or not is_finite(value) or absf(value) > MAX_EDITOR_ABS_HEIGHT:
				return fail("Invalid project height edit.")
			set_height(index, value)
		if not read_material_edits(saved.get("colorEdits", {}), Terrain.Layer.COLOR) or not read_material_edits(saved.get("tileEdits", {}), Terrain.Layer.TILES):
			return false
		if not read_path_edits(saved.get("pathEdits", {})):
			return false
		if not read_object_edits(saved.get("objectEdits", {})):
			return false
		if not read_object_label_edits(saved.get("objectLabelEdits", {})):
			return false
		if not read_object_odf_edits(saved.get("objectOdfEdits", {})):
			return false
		if not read_object_removals(saved.get("objectRemovals", [])):
			return false
		if not read_object_additions(saved.get("objectInserts", [])):
			return false
		if not read_water_edits(saved.get("waterEdits", {})):
			return false
		if saved.has("environmentEdits"):
			var raw_env: Variant = saved["environmentEdits"]
			if raw_env is Dictionary and not (raw_env as Dictionary).is_empty() and not can_edit_environment():
				return fail("Invalid project environment edits: " + String(package.sky_env.get("writeRefusalReason", "Map does not have a verified writable native .SKY layout.")))
			var base_env_fields: Dictionary = package.sky_env.get("fields", {}) if package != null else {}
			var env_err := SkyEnv.validate_edits(raw_env, base_env_fields)
			if not env_err.is_empty():
				return fail("Invalid project environment edits: " + env_err)
			environment_edits = (raw_env as Dictionary).duplicate(true)
	if not package.check_sources():
		return fail(package.error)
	ensure_layer_uids()
	layer_stack_revision += 1
	edit_revision += 1
	return true


const SOUND_POINT_ODF := "vrv_sndpoint"


static func is_sound_point_odf(odf: String) -> bool:
	var stem := odf.strip_edges().to_lower()
	if stem.ends_with(".odf"):
		stem = stem.substr(0, stem.length() - 4)
	return stem == SOUND_POINT_ODF


static func valid_object_label(label: String) -> bool:
	if label.length() > 128:
		return false
	for i in label.length():
		var code := label.unicode_at(i)
		if code < 32 or code > 126:
			return false
	return true


func object_is_sound_point(view: int) -> bool:
	return valid_view_object(view) and is_sound_point_odf(object_odf(view))


func sound_point_views() -> Array[int]:
	var result: Array[int] = []
	for view in object_count():
		if object_is_sound_point(view):
			result.append(view)
	return result


static func sound_point(label: String) -> Dictionary:
	# VRV sound points are plain BZN objects of vrv_sndpoint whose label carries
	# vrvsnd:<sound>:<volume>:<range>:<interval>:<jitter>:<pitch>:<near>
	# (VRV src/shared/SoundPoints.h). Playback stays VRV-managed.
	if not label.begins_with("vrvsnd:"):
		return {}
	var parts := label.split(":")
	if parts.size() != 8:
		return {}
	var sound := parts[1]
	if sound.is_empty() or sound.length() > 48:
		return {}
	for character in sound:
		if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."):
			return {}
	var extension := sound.get_extension().to_lower()
	if extension != "wav" and extension != "ogg":
		return {}
	var values: Array[int] = []
	for index in range(2, 8):
		if not parts[index].is_valid_int():
			return {}
		values.append(int(parts[index]))
	return {"odf": "vrv_sndpoint", "sound": sound, "volume": values[0], "range": values[1],
		"interval": values[2], "jitter": values[3], "pitch": values[4], "near": values[5]}


static func format_sound_point(settings: Dictionary) -> Dictionary:
	var sound := String(settings.get("sound", "")).strip_edges()
	if sound.is_empty() or sound.length() > 48:
		return {"label": "", "error": "Enter a sound filename between 1 and 48 characters."}
	for character in sound:
		if not (character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."):
			return {"label": "", "error": "Sound filename may only use A-Z, 0-9, '_', '-' and '.'."}
	var extension := sound.get_extension().to_lower()
	if extension != "wav" and extension != "ogg":
		return {"label": "", "error": "Sound filename must end with .wav or .ogg."}
	var volume := clampi(int(settings.get("volume", 70)), 0, 100)
	var rng := clampi(int(settings.get("range", 150)), 10, 2000)
	var interval := clampi(int(settings.get("interval", 0)), 0, 600)
	var jitter := clampi(int(settings.get("jitter", 0)), 0, 100)
	var pitch := clampi(int(settings.get("pitch", 100)), 25, 200)
	var near := clampi(int(settings.get("near", 20)), 0, 90)
	return {
		"label": "vrvsnd:%s:%d:%d:%d:%d:%d:%d" % [sound, volume, rng, interval, jitter, pitch, near],
		"error": "",
	}


static func valid_asset_profile(value: Variant) -> bool:
	return value is String and (value.is_empty() or (value.is_absolute_path() and value.get_extension().to_lower() == "json"))


static func valid_mod_profile_id(value: Variant) -> bool:
	if not (value is String):
		return false
	var id := String(value).strip_edges()
	if id.is_empty():
		return false
	var re := RegEx.new()
	re.compile("^[a-z0-9][a-z0-9._:-]{0,63}$")
	return re.search(id) != null


static func valid_mission_profile_id(value: Variant) -> bool:
	return value is String and String(value).strip_edges().to_lower() in MissionProfiles.MISSION_MODES


static func valid_engine_profile_id(value: Variant) -> bool:
	return value is String and ModRegistry.ENGINE_PROFILES.has(String(value).strip_edges())


func read_target_profile(saved_target: Variant) -> bool:
	if not (saved_target is Dictionary):
		return fail("Invalid project target profile metadata.")
	var eng: Variant = saved_target.get("engineProfile", "bzcc-2.0.185")
	var mod: Variant = saved_target.get("modProfile", "stock")
	var mis: Variant = saved_target.get("missionProfile", "blank")
	if not valid_engine_profile_id(eng) or not valid_mod_profile_id(mod) or not valid_mission_profile_id(mis):
		return fail("Invalid project target profile identifiers.")
	engine_profile = String(eng).strip_edges()
	mod_profile = String(mod).strip_edges().to_lower()
	mission_profile = String(mis).strip_edges().to_lower()
	profile_explicit = bool(saved_target.get("explicit", true))
	return true


func set_target_profile(next_mod: String, next_mission: String, next_engine: String = "") -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit before switching target profiles.")
	var mod_clean := next_mod.strip_edges().to_lower()
	var mis_clean := next_mission.strip_edges().to_lower()
	var eng_clean := next_engine.strip_edges() if not next_engine.strip_edges().is_empty() else engine_profile
	if not valid_mod_profile_id(mod_clean):
		return fail("Invalid target mod profile identifier.")
	if not valid_mission_profile_id(mis_clean):
		return fail("Invalid target mission profile identifier.")
	if not valid_engine_profile_id(eng_clean):
		return fail("Invalid target engine profile identifier.")
	var before := {"engine": engine_profile, "mod": mod_profile, "mission": mission_profile, "explicit": profile_explicit}
	var after := {"engine": eng_clean, "mod": mod_clean, "mission": mis_clean, "explicit": true}
	if before == after:
		return true
	push_history({"target_profile": true, "before": before, "after": after})
	_apply_target_profile(after)
	return true


func _apply_target_profile(state: Dictionary) -> void:
	engine_profile = String(state["engine"])
	mod_profile = String(state["mod"])
	mission_profile = String(state["mission"])
	profile_explicit = bool(state["explicit"])
	profile_changed.emit()


static func valid_mission_dll_name(value: Variant) -> bool:
	if not (value is String):
		return false
	var clean := String(value).strip_edges()
	if clean.is_empty():
		return true
	if clean.length() > 127 or clean.get_file() != clean or ":" in clean:
		return false
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_][A-Za-z0-9_. -]*\\.dll$")
	return re.search(clean) != null


func effective_mission_dll() -> String:
	if has_mission_dll_override:
		return mission_dll_override
	return String(package.mission_dll) if package != null else ""


func has_mission_dll_edit() -> bool:
	return has_mission_dll_override and mission_dll_override != (String(package.mission_dll) if package != null else "")


func set_mission_dll(next_dll: String) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit before changing the mission DLL.")
	if not valid_mission_dll_name(next_dll):
		return fail("Invalid mission DLL filename (expected empty or *.dll).")
	var clean := next_dll.strip_edges()
	var before := {"has": has_mission_dll_override, "dll": mission_dll_override}
	var base_dll := String(package.mission_dll) if package != null else ""
	var after := {"has": clean != base_dll, "dll": clean if clean != base_dll else ""}
	if before == after:
		return true
	push_history({"mission_dll": true, "before": before, "after": after})
	_apply_mission_dll(after)
	return true


func _apply_mission_dll(state: Dictionary) -> void:
	has_mission_dll_override = bool(state.get("has", false))
	mission_dll_override = String(state.get("dll", ""))
	profile_changed.emit()


func has_readable_environment() -> bool:
	return package != null and not package.sky_name.is_empty() and bool(package.sky_env.get("readable", false))


func can_edit_environment() -> bool:
	return package != null and not package.sky_name.is_empty() and SkyEnv.is_writable(package.sky_env)


func has_environment_edits() -> bool:
	return not environment_edits.is_empty()


func effective_environment() -> Dictionary:
	if not has_readable_environment():
		return {}
	var base: Dictionary = (package.sky_env.get("fields", {}) as Dictionary).duplicate(true)
	for k: String in environment_edits:
		base[k] = environment_edits[k].duplicate(true) if environment_edits[k] is Array else environment_edits[k]
	return base


func set_environment_edits(next_edits: Dictionary) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit before changing environment settings.")
	if not can_edit_environment():
		var reason := String(package.sky_env.get("writeRefusalReason", "")) if package != null else ""
		if reason.is_empty() and package != null:
			reason = String(package.sky_env.get("error", ""))
		if reason.is_empty():
			reason = "This map does not have a verified writable native .SKY layout."
		return fail(reason)
	var base_fields: Dictionary = package.sky_env.get("fields", {})
	var err := SkyEnv.validate_edits(next_edits, base_fields)
	if not err.is_empty():
		return fail(err)
	var pruned := {}
	for k: String in next_edits:
		var val: Variant = next_edits[k]
		var base_val: Variant = base_fields.get(k, null)
		if val is Array and base_val is Array and (val as Array).size() == 4 and (base_val as Array).size() == 4:
			var same := true
			for i in 4:
				if absf(float(val[i]) - float(base_val[i])) > 0.0005:
					same = false
					break
			if not same:
				pruned[k] = [float(val[0]), float(val[1]), float(val[2]), float(val[3])]
		elif (val is float or val is int) and (base_val is float or base_val is int):
			if absf(float(val) - float(base_val)) > 0.0005:
				pruned[k] = float(val)
	var before := environment_edits.duplicate(true)
	if before == pruned:
		return true
	push_history({"environment": true, "before": before, "after": pruned.duplicate(true)})
	_apply_environment_edits(pruned)
	return true


func _apply_environment_edits(state: Dictionary) -> void:
	environment_edits = state.duplicate(true)
	environment_changed.emit()


static func _to_int_array(raw: Variant) -> Array[int]:
	var out: Array[int] = []
	if raw is Array:
		for item in (raw as Array):
			out.append(int(item))
	return out


func ensure_layer_uids() -> void:
	if layers.is_empty():
		layers = [Graph.layer()]
	while layer_uids.size() < layers.size():
		layer_uids.append(next_layer_id)
		next_layer_id += 1
	if layer_uids.size() > layers.size():
		layer_uids.resize(layers.size())


func layer_uid(index: int) -> int:
	ensure_layer_uids()
	if index < 0 or index >= layer_uids.size():
		return -1
	return layer_uids[index]


func layer_index_by_uid(uid: int) -> int:
	ensure_layer_uids()
	return layer_uids.find(uid)


func _normalized_layer_stack(raw_layers: Array) -> Array:
	var result: Array = []
	for item in raw_layers:
		result.append(Graph.normalize_layer(item as Dictionary))
	return result


func commit_procedural_layers(next_layers: Array, next_uids: Array[int] = [], focus_index: int = -1, clear_active_preview: bool = true) -> bool:
	if package == null:
		return fail("Open a map before editing procedural layers.")
	if stroke_active or water_stroke_active:
		return fail("Finish the current stroke before editing procedural layers.")
	if next_layers.is_empty() or next_layers.size() > Graph.MAX_LAYERS:
		return fail("A node stack needs one to %d layers." % Graph.MAX_LAYERS)
	var graph := Graph.new()
	if not graph.validate_stack(next_layers):
		return fail(graph.error)
	ensure_layer_uids()
	var before_layers := _normalized_layer_stack(layers)
	var before_uids: Array[int] = layer_uids.duplicate()
	var after_layers := _normalized_layer_stack(next_layers)
	var after_uids: Array[int] = []
	if next_uids.size() == after_layers.size():
		var seen := {}
		for uid in next_uids:
			var clean_uid := int(uid)
			if clean_uid <= 0 or seen.has(clean_uid):
				clean_uid = next_layer_id
				next_layer_id += 1
			seen[clean_uid] = true
			after_uids.append(clean_uid)
			next_layer_id = maxi(next_layer_id, clean_uid + 1)
	else:
		for i in after_layers.size():
			if i < before_uids.size():
				after_uids.append(before_uids[i])
			else:
				after_uids.append(next_layer_id)
				next_layer_id += 1
	if before_layers == after_layers and before_uids == after_uids:
		return true
	if clear_active_preview and has_preview():
		clear_preview()
	var focus_before := clampi(focus_index if focus_index >= 0 else 0, 0, maxi(0, before_layers.size() - 1))
	var focus_after := clampi(focus_index if focus_index >= 0 else 0, 0, maxi(0, after_layers.size() - 1))
	push_history({
		"layers": true,
		"before": before_layers.duplicate(true),
		"after": after_layers.duplicate(true),
		"uids_before": before_uids.duplicate(),
		"uids_after": after_uids.duplicate(),
		"focus_before": focus_before,
		"focus_after": focus_after,
	})
	_apply_procedural_layers(after_layers, after_uids, focus_after)
	return true


func add_procedural_layer(template_layer: Dictionary = {}) -> int:
	if package == null:
		fail("Open a map before adding procedural layers.")
		return -1
	ensure_layer_uids()
	if layers.size() >= Graph.MAX_LAYERS:
		fail("Maximum procedural layer count (%d) reached." % Graph.MAX_LAYERS)
		return -1
	var item := Graph.normalize_layer(template_layer) if not template_layer.is_empty() else Graph.layer()
	var staged := _normalized_layer_stack(layers)
	staged.append(item)
	var staged_uids: Array[int] = layer_uids.duplicate()
	var new_uid := next_layer_id
	next_layer_id += 1
	staged_uids.append(new_uid)
	var target_idx := staged.size() - 1
	if not commit_procedural_layers(staged, staged_uids, target_idx):
		return -1
	return target_idx


func remove_procedural_layer(index: int) -> bool:
	if package == null:
		return fail("Open a map before removing procedural layers.")
	ensure_layer_uids()
	if index < 0 or index >= layers.size():
		return fail("Invalid procedural layer index.")
	if layers.size() <= 1:
		return fail("At least one procedural layer must remain.")
	var staged := _normalized_layer_stack(layers)
	var staged_uids: Array[int] = layer_uids.duplicate()
	staged.remove_at(index)
	staged_uids.remove_at(index)
	var next_focus := mini(index, staged.size() - 1)
	return commit_procedural_layers(staged, staged_uids, next_focus)


func move_procedural_layer(index: int, target: int) -> bool:
	if package == null:
		return fail("Open a map before reordering procedural layers.")
	ensure_layer_uids()
	if index < 0 or index >= layers.size() or target < 0 or target >= layers.size():
		return fail("Invalid procedural layer index.")
	if index == target:
		return true
	var staged := _normalized_layer_stack(layers)
	var staged_uids: Array[int] = layer_uids.duplicate()
	var moved_layer: Dictionary = staged.pop_at(index)
	var moved_uid: int = staged_uids.pop_at(index)
	staged.insert(target, moved_layer)
	staged_uids.insert(target, moved_uid)
	return commit_procedural_layers(staged, staged_uids, target)


func set_procedural_layer_enabled(index: int, enabled: bool) -> bool:
	if package == null:
		return fail("Open a map before editing procedural layers.")
	ensure_layer_uids()
	if index < 0 or index >= layers.size():
		return fail("Invalid procedural layer index.")
	var staged := _normalized_layer_stack(layers)
	if bool(staged[index].get("enabled", true)) == enabled:
		return true
	staged[index]["enabled"] = enabled
	return commit_procedural_layers(staged, layer_uids.duplicate(), index)


func set_procedural_layer_opacity(index: int, value: float) -> bool:
	if package == null:
		return fail("Open a map before editing procedural layers.")
	ensure_layer_uids()
	if index < 0 or index >= layers.size():
		return fail("Invalid procedural layer index.")
	if not is_finite(value) or value < 0.0 or value > 1.0:
		return fail("Layer opacity must be between 0.0 and 1.0.")
	var staged := _normalized_layer_stack(layers)
	if is_equal_approx(float(staged[index].get("opacity", 1.0)), value):
		return true
	staged[index]["opacity"] = value
	return commit_procedural_layers(staged, layer_uids.duplicate(), index)


func replace_procedural_layers(staged_stack: Array, focus_index: int = -1, staged_uids: Array[int] = []) -> bool:
	return commit_procedural_layers(staged_stack, staged_uids, focus_index)


func _apply_procedural_layers(state_layers: Array, state_uids: Array[int], focus_index: int = -1) -> void:
	layers = _normalized_layer_stack(state_layers)
	layer_uids = state_uids.duplicate()
	ensure_layer_uids()
	layer_stack_revision += 1
	var sel := clampi(focus_index, 0, maxi(0, layers.size() - 1)) if focus_index >= 0 else -1
	layers_changed.emit(sel)


# --- Non-destructive color layers --------------------------------------------

func _color_snapshot() -> Array:
	var out: Array = []
	for item in color_layers:
		out.append(ColorLayers.normalize(item as Dictionary))
	return out


func _apply_color_layers(state: Array, active_uid: int) -> void:
	color_layers = []
	for item in state:
		color_layers.append(ColorLayers.normalize(item as Dictionary))
	active_color_uid = active_uid
	if active_color_uid < 0 and not color_layers.is_empty():
		active_color_uid = int((color_layers[0] as Dictionary)["uid"])
	color_revision += 1
	color_layers_changed.emit(active_color_uid)


func _commit_color_layers(state: Array, active_uid: int) -> bool:
	if package == null or has_active_edit_transaction():
		return fail("Finish the current stroke before editing color layers.")
	if not ColorLayers.validate_stack(state, package.terrain.heights.size()):
		return fail("Invalid color layer stack.")
	var before := _color_snapshot()
	var after: Array = []
	for item in state:
		after.append(ColorLayers.normalize(item as Dictionary))
	if before == after and active_color_uid == active_uid:
		return true
	var color_preview_active := _color_live_preview or _color_composition_active
	if color_preview_active:
		_clear_color_live_preview()
		if _color_composition_active:
			clear_preview()
	push_history({"color": true, "before": before, "after": after,
		"active_before": active_color_uid, "active_after": active_uid})
	_apply_color_layers(after, active_uid)
	if color_preview_active:
		color_preview()
	return true


func add_color_layer() -> int:
	if package == null or color_layers.size() >= ColorLayers.MAX_LAYERS or has_active_edit_transaction():
		return -1
	var state := _color_snapshot()
	var uid := next_color_uid
	state.append(ColorLayers.layer(uid))
	if not _commit_color_layers(state, uid):
		return -1
	next_color_uid += 1
	return color_layers.size() - 1


func remove_color_layer(index: int) -> bool:
	if index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var state := _color_snapshot()
	var removed_uid := int((state[index] as Dictionary)["uid"])
	state.remove_at(index)
	var next_uid := active_color_uid
	if removed_uid == next_uid:
		next_uid = -1 if state.is_empty() else int((state[mini(index, state.size() - 1)] as Dictionary)["uid"])
	return _commit_color_layers(state, next_uid)


func set_color_layer_enabled(index: int, enabled: bool) -> bool:
	if index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var state := _color_snapshot()
	if bool((state[index] as Dictionary)["enabled"]) == enabled:
		return true
	(state[index] as Dictionary)["enabled"] = enabled
	return _commit_color_layers(state, active_color_uid)


## Color masks are sparse per-sample strength multipliers stored on the color
## layer. No mask means strength 1. A mask has an explicit default plus sparse
## overrides, so a missing key never ambiguously means 0 or 1.
func add_color_mask(index: int, default_strength: float = 0.0) -> bool:
	if package == null or index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	if (color_layers[index] as Dictionary).get("mask", null) != null:
		return fail("Color layer already has a mask.")
	if not is_finite(default_strength) or default_strength < 0.0 or default_strength > 1.0:
		return fail("Invalid color mask default strength.")
	var state := _color_snapshot()
	(state[index] as Dictionary)["mask"] = ColorLayers.mask(default_strength)
	return _commit_color_layers(state, active_color_uid)


func remove_color_mask(index: int) -> bool:
	if package == null or index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var state := _color_snapshot()
	if (state[index] as Dictionary).get("mask", null) == null:
		return true
	(state[index] as Dictionary)["mask"] = null
	return _commit_color_layers(state, active_color_uid)


func set_color_mask_enabled(index: int, enabled: bool) -> bool:
	if package == null or index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var state := _color_snapshot()
	var mask_data: Variant = (state[index] as Dictionary).get("mask", null)
	if not mask_data is Dictionary:
		return fail("Color layer has no mask.")
	if bool((mask_data as Dictionary)["enabled"]) == enabled:
		return true
	(mask_data as Dictionary)["enabled"] = enabled
	return _commit_color_layers(state, active_color_uid)


func set_color_mask_default(index: int, strength: float) -> bool:
	if package == null or index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var state := _color_snapshot()
	var mask_data: Variant = (state[index] as Dictionary).get("mask", null)
	if not mask_data is Dictionary:
		return fail("Color layer has no mask.")
	if not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return fail("Invalid color mask strength.")
	(mask_data as Dictionary)["default"] = strength
	return _commit_color_layers(state, active_color_uid)


## Sparse mask utilities: Fill, Clear and Invert operate on the canonical
## mask record and commit through the existing one-Undo layer lifecycle.
func _mask_op_guard_color(index: int) -> Array:
	if package == null or index < 0 or index >= color_layers.size():
		fail("Invalid color layer index.")
		return []
	if has_active_edit_transaction():
		fail("Finish the current stroke before editing a color mask.")
		return []
	var state := _color_snapshot()
	var mask_data: Variant = (state[index] as Dictionary).get("mask", null)
	if not mask_data is Dictionary:
		fail("Color layer has no mask.")
		return []
	return state


func fill_color_mask(index: int, strength: float) -> bool:
	var state := _mask_op_guard_color(index)
	if state.is_empty() or not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return fail("Invalid color mask fill strength.")
	var mask_data: Dictionary = (state[index] as Dictionary)["mask"]
	mask_data["default"] = strength
	mask_data["samples"] = {}
	return _commit_color_layers(state, active_color_uid)


func clear_color_mask_overrides(index: int) -> bool:
	var state := _mask_op_guard_color(index)
	if state.is_empty():
		return false
	var mask_data: Dictionary = (state[index] as Dictionary)["mask"]
	(mask_data["samples"] as Dictionary).clear()
	return _commit_color_layers(state, active_color_uid)


func invert_color_mask(index: int) -> bool:
	var state := _mask_op_guard_color(index)
	if state.is_empty():
		return false
	var mask_data: Dictionary = (state[index] as Dictionary)["mask"]
	var new_default := 1.0 - float(mask_data["default"])
	var inverted: Dictionary = {}
	for key: Variant in (mask_data["samples"] as Dictionary):
		var value := 1.0 - float((mask_data["samples"] as Dictionary)[key])
		if not is_equal_approx(value, new_default):
			inverted[key] = value
	mask_data["default"] = new_default
	mask_data["samples"] = inverted
	return _commit_color_layers(state, active_color_uid)


func begin_color_mask_stroke() -> bool:
	if package == null or has_active_edit_transaction() or _color_opacity_preview_uid >= 0:
		return fail("Finish the current edit before painting a color mask.")
	if has_active_preview_context() and preview_owner != "color" and not _color_composition_active:
		return fail("Cancel the foreign preview before painting a color mask.")
	var index := color_index_by_uid(active_color_uid)
	if index < 0 or (color_layers[index] as Dictionary).get("mask", null) == null:
		return fail("Select a color layer with a mask.")
	color_mask_stroke_active = true
	_color_mask_before = _color_snapshot()
	_color_mask_uid = active_color_uid
	return true


func color_mask_dab(point: Vector2, radius_m: float, strength: float, shape := BrushShape.BELL, flow := 1.0) -> bool:
	if not color_mask_stroke_active or not is_finite(strength) \
		or strength < 0.0 or strength > 1.0 \
		or not is_finite(flow) or flow < 0.0 or flow > 1.0 \
		or not point.is_finite() or not is_finite(radius_m) \
		or radius_m <= 0.0 or radius_m > 256.0:
		return fail("Invalid color mask dab.")
	var index := color_index_by_uid(_color_mask_uid)
	if index < 0:
		return fail("The masked color layer is no longer available.")
	var terrain := package.terrain
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return true
	var radius := radius_m / terrain.SPACING
	var layer_data: Dictionary = color_layers[index]
	var mask_data: Dictionary = layer_data["mask"]
	var samples: Dictionary = mask_data["samples"]
	var default_value := float(mask_data["default"])
	var journal: Dictionary = {}
	var journal_present: Dictionary = {}
	var changed_indices: Array[int] = []
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0.0:
				continue
			var sample_index := z * terrain.dimensions.x + x
			if sample_index < 0 or sample_index >= terrain.heights.size():
				continue
			if not journal.has(sample_index):
				journal[sample_index] = float(samples.get(sample_index, default_value))
				journal_present[sample_index] = samples.has(sample_index)
			var previous := float(journal[sample_index])
			var next := clampf(lerpf(previous, strength, clampf(weight * flow, 0.0, 1.0)), 0.0, 1.0)
			if is_equal_approx(next, default_value):
				samples.erase(sample_index)
			else:
				samples[sample_index] = next
			changed_indices.append(sample_index)
	if changed_indices.is_empty():
		return true
	if not ColorLayers.validate_stack([layer_data], terrain.heights.size()):
		for restore_index: int in journal:
			if bool(journal_present[restore_index]):
				samples[restore_index] = float(journal[restore_index])
			else:
				samples.erase(restore_index)
		return fail("Invalid color mask sample produced by stroke.")
	color_revision += 1
	_update_color_live_preview(changed_indices)
	return true


func end_color_mask_stroke() -> bool:
	if not color_mask_stroke_active:
		return false
	var before := _color_mask_before
	var after := _color_snapshot()
	var uid := _color_mask_uid
	var changed := after != before
	color_mask_stroke_active = false
	_color_mask_before = []
	_color_mask_uid = -1
	if not changed:
		_clear_color_live_preview()
		return true
	push_history({"color": true, "before": before, "after": after,
		"active_before": uid, "active_after": active_color_uid})
	_clear_color_live_preview()
	return true


func cancel_color_mask_stroke() -> void:
	if not color_mask_stroke_active:
		return
	var before := _color_mask_before
	var uid := _color_mask_uid
	color_mask_stroke_active = false
	_color_mask_before = []
	_color_mask_uid = -1
	_clear_color_live_preview()
	_apply_color_layers(before, uid)
	if _color_composition_active:
		color_preview()


func begin_color_opacity_preview(index: int) -> bool:
	if package == null or index < 0 or index >= color_layers.size():
		return fail("Invalid color layer opacity gesture.")
	if has_active_edit_transaction() or _color_live_preview:
		return fail("Finish the current stroke before editing color opacity.")
	if _color_opacity_preview_uid >= 0:
		return fail("Finish the current color opacity gesture first.")
	if has_active_preview_context() and preview_owner != "color":
		return fail("Cancel the foreign preview before editing color opacity.")
	_color_opacity_preview_uid = int((color_layers[index] as Dictionary)["uid"])
	_color_opacity_preview_value = float((color_layers[index] as Dictionary)["opacity"])
	return true


func preview_color_layer_opacity(uid: int, value: float) -> bool:
	if package == null or _color_opacity_preview_uid < 0 or uid != _color_opacity_preview_uid:
		return false
	if stroke_active or color_stroke_active:
		return false
	if not is_finite(value) or value < 0.0 or value > 1.0:
		return false
	if has_active_preview_context() and preview_owner != "color":
		return false
	var index := color_index_by_uid(uid)
	if index < 0:
		return false
	_color_opacity_preview_value = clampf(value, 0.0, 1.0)
	var staged := _color_snapshot()
	(staged[index] as Dictionary)["opacity"] = _color_opacity_preview_value
	var preview := ColorLayers.compose_all(package.terrain, staged, package.terrain.color_edits)
	return show_color_preview(preview)


func cancel_color_opacity_preview(uid: int = -1) -> void:
	if _color_opacity_preview_uid < 0:
		return
	if uid >= 0 and uid != _color_opacity_preview_uid:
		return
	_color_opacity_preview_uid = -1
	_color_opacity_preview_value = NAN
	if _color_composition_active:
		show_color_preview(ColorLayers.compose_all(package.terrain, color_layers, package.terrain.color_edits))


func commit_color_opacity_preview(uid: int, value: float) -> bool:
	if _color_opacity_preview_uid < 0 or uid != _color_opacity_preview_uid:
		return false
	var index := color_index_by_uid(uid)
	var final_value := _color_opacity_preview_value if not is_finite(value) else clampf(value, 0.0, 1.0)
	var had_preview := _color_composition_active
	_color_opacity_preview_uid = -1
	_color_opacity_preview_value = NAN
	if index < 0 or not is_finite(final_value) or final_value < 0.0 or final_value > 1.0:
		if had_preview:
			show_color_preview(ColorLayers.compose_all(package.terrain, color_layers, package.terrain.color_edits))
		return false
	var changed := not is_equal_approx(float((color_layers[index] as Dictionary)["opacity"]), final_value)
	var ok := true
	if changed:
		ok = set_color_layer_opacity(index, final_value)
	if had_preview:
		show_color_preview(ColorLayers.compose_all(package.terrain, color_layers, package.terrain.color_edits))
	return ok


func set_color_layer_opacity(index: int, value: float) -> bool:
	if index < 0 or index >= color_layers.size() or not is_finite(value) or value < 0.0 or value > 1.0:
		return fail("Invalid color layer opacity.")
	var state := _color_snapshot()
	if is_equal_approx(float((state[index] as Dictionary)["opacity"]), value):
		return true
	(state[index] as Dictionary)["opacity"] = value
	return _commit_color_layers(state, active_color_uid)


func rename_color_layer(index: int, name: String) -> bool:
	if index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var state := _color_snapshot()
	var clean := name.strip_edges().substr(0, ColorLayers.MAX_NAME_LENGTH)
	if String((state[index] as Dictionary).get("name", "")) == clean:
		return true
	(state[index] as Dictionary)["name"] = clean
	return _commit_color_layers(state, active_color_uid)


func move_color_layer(from: int, to: int) -> bool:
	if from < 0 or to < 0 or from >= color_layers.size() or to >= color_layers.size() or from == to:
		return false
	var state := _color_snapshot()
	var moved: Dictionary = state[from]
	state.remove_at(from)
	state.insert(clampi(to, 0, state.size()), moved)
	return _commit_color_layers(state, active_color_uid)


func set_active_color_layer(index: int) -> bool:
	if index < 0 or index >= color_layers.size():
		return fail("Invalid color layer index.")
	var uid := int((color_layers[index] as Dictionary)["uid"])
	if uid == active_color_uid:
		return true
	active_color_uid = uid
	color_layers_changed.emit(active_color_uid)
	return true


func color_index_by_uid(uid: int) -> int:
	for i in color_layers.size():
		if int((color_layers[i] as Dictionary)["uid"]) == uid:
			return i
	return -1


## One color stroke = one Undo entry, including every mirror dab. Dabs stage
## RGB words and coverage into the active layer's sparse dictionary; rollback
## restores only touched samples. Native color_edits are never written.
func begin_color_stroke() -> bool:
	if package == null or has_active_edit_transaction() or _color_opacity_preview_uid >= 0:
		return fail("Finish the current stroke or opacity gesture before color layer painting.")
	if has_active_preview_context() and preview_owner != "color":
		return fail("Cancel the foreign preview before color layer painting.")
	if color_index_by_uid(active_color_uid) < 0:
		return fail("Create or activate a color layer first.")
	color_stroke_active = true
	_color_stroke_before = _color_snapshot()
	_color_stroke_uid = active_color_uid
	_color_stroke_touched = false
	_color_stroke_sample_value = {}
	_color_stroke_coverage = {}
	return true


func _stage_color_dab(point: Vector2, radius_m: float, value: int, shape: int, pressure: float) -> bool:
	var index_active := color_index_by_uid(active_color_uid)
	if index_active < 0:
		return fail("Create or activate a color layer first.")
	if value < 0 or value > 0xffffff or not is_finite(pressure):
		return true
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return true
	var terrain := package.terrain
	var radius := radius_m / terrain.SPACING
	var p := clampf(pressure, 0.0, 1.0)
	var layer_data: Dictionary = color_layers[index_active]
	var samples: Dictionary = layer_data["samples"]
	var journal: Dictionary = {}
	var changed_indices: Array[int] = []
	var touched := false
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0.0:
				continue
			var index := z * terrain.dimensions.x + x
			if index < 0 or index >= terrain.heights.size():
				continue
			var coverage := clampf(weight * p, 0.0, 1.0)
			if coverage <= 0.0:
				continue
			if color_stroke_active and not journal.has(index):
				journal[index] = (samples[index] as Dictionary).duplicate() if samples.has(index) else null
			var old_value: int = int((samples[index] as Dictionary)["rgb"]) if samples.has(index) else -1
			var old_coverage := float((samples[index] as Dictionary)["coverage"]) if samples.has(index) else 0.0
			# Inside one stroke, repeated or mirrored dabs keep the strongest
			# coverage across every dab. A new stroke replaces committed coverage.
			var new_coverage := coverage
			if color_stroke_active and _color_stroke_coverage.has(index):
				new_coverage = maxf(coverage, float(_color_stroke_coverage[index]))
			if old_value == value and is_equal_approx(old_coverage, new_coverage):
				continue
			samples[index] = {"rgb": value, "coverage": new_coverage}
			if color_stroke_active:
				_color_stroke_coverage[index] = new_coverage
			changed_indices.append(index)
			touched = true
	if not touched:
		return true
	if not ColorLayers.validate_stack([layer_data], terrain.heights.size()):
		for index: int in journal:
			if journal[index] != null:
				samples[index] = journal[index]
			else:
				samples.erase(index)
		return fail("Invalid color layer sample produced by stroke.")
	if color_stroke_active:
		for index: int in changed_indices:
			_color_stroke_sample_value[index] = (samples[index] as Dictionary).duplicate()
		color_revision += 1
		_color_stroke_touched = true
		_update_color_live_preview(changed_indices)
	else:
		_apply_color_layers(_color_snapshot(), active_color_uid)
	return true


func _update_color_live_preview(changed_indices: Array[int]) -> void:
	if package == null or not (color_stroke_active or color_mask_stroke_active) or changed_indices.is_empty():
		return
	if not _color_live_preview:
		_color_live_preview = true
		preview_owner = "color"
		preview_source_revision = document_id_source_revision()
	var terrain := package.terrain
	var existing: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	var preview := existing.duplicate()
	var repaint: Dictionary = {}
	for index: int in changed_indices:
		if index < 0 or index >= terrain.heights.size():
			continue
		var word := ColorLayers.compose_word(terrain.source_material_value(Terrain.Layer.COLOR, index),
			terrain.color_edits, color_layers, index)
		if word == terrain.committed_material_value(Terrain.Layer.COLOR, index):
			preview.erase(index)
		else:
			preview[index] = word
		repaint[index] = preview.get(index, terrain.committed_material_value(Terrain.Layer.COLOR, index))
	show_color_preview(preview, repaint)


## A Color preview is allowed only when no live stroke or foreign-tool context
## owns the document. An empty composition still owns the preview, so admission
## checks the semantic context instead of the presence of changed samples.
func _admit_color_preview() -> bool:
	if package == null or stroke_active:
		return false
	if color_stroke_active or _color_live_preview:
		return true
	return not has_active_preview_context() or preview_owner == "color"


func show_color_preview(values: Dictionary, repaint: Dictionary = {}) -> bool:
	if not _admit_color_preview():
		return fail("Cancel the active stroke or foreign preview before showing color composition.")
	if not valid_preview({}, {Terrain.Layer.COLOR: values}):
		return fail("Invalid color preview.")
	var terrain := package.terrain
	var previous: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	var changes := {}
	for index: int in values:
		if values[index] != terrain.committed_material_value(Terrain.Layer.COLOR, index):
			changes[index] = values[index]
	if changes.is_empty():
		terrain.material_previews.erase(Terrain.Layer.COLOR)
	else:
		terrain.material_previews[Terrain.Layer.COLOR] = changes
	preview_owner = "color"
	preview_source_revision = document_id_source_revision()
	_color_composition_active = true
	var dirty := repaint.duplicate()
	if dirty.is_empty():
		dirty = previous.duplicate()
		for index: int in changes:
			dirty[index] = changes[index]
	for index: int in dirty:
		if not changes.has(index) and not previous.has(index):
			continue
		dirty[index] = changes.get(index, terrain.committed_material_value(Terrain.Layer.COLOR, index))
	refresh_materials(Terrain.Layer.COLOR, dirty)
	return true


func color_preview() -> bool:
	if package == null or color_layers.is_empty():
		return fail("Create a color layer before previewing.")
	var edits := ColorLayers.compose_all(package.terrain, color_layers, package.terrain.color_edits)
	return show_color_preview(edits)


func _clear_color_live_preview() -> void:
	if not _color_live_preview:
		return
	_color_live_preview = false
	_color_composition_active = false
	preview_owner = ""
	preview_source_revision = ""
	var terrain := package.terrain
	var previous: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	terrain.material_previews.erase(Terrain.Layer.COLOR)
	refresh_materials(Terrain.Layer.COLOR, previous)
	if not color_layers.is_empty():
		color_preview()


func end_color_stroke() -> bool:
	if not color_stroke_active:
		return false
	var before := _color_stroke_before
	var uid := _color_stroke_uid
	var after := _color_snapshot()
	var changed := _color_stroke_touched and after != before
	color_stroke_active = false
	_color_stroke_before = []
	_color_stroke_uid = -1
	_color_stroke_touched = false
	_color_stroke_sample_value = {}
	_color_stroke_coverage = {}
	_clear_color_live_preview()
	if not changed:
		return true
	push_history({"color": true, "before": before, "after": after,
		"active_before": uid, "active_after": active_color_uid})
	return true


func cancel_color_stroke() -> void:
	if not color_stroke_active:
		return
	var before := _color_stroke_before
	var uid := _color_stroke_uid
	color_stroke_active = false
	_color_stroke_before = []
	_color_stroke_uid = -1
	_color_stroke_touched = false
	_color_stroke_sample_value = {}
	_color_stroke_coverage = {}
	_clear_color_live_preview()
	_apply_color_layers(before, uid)


func color_dab(point: Vector2, radius_m: float, value: int, shape := BrushShape.BELL, pressure := 1.0) -> bool:
	if package == null or stroke_active or (has_preview() and not _color_live_preview and preview_owner != "color"):
		return fail("Finish the current stroke and cancel previews before color layer painting.")
	if color_stroke_active:
		return _stage_color_dab(point, radius_m, value, shape, pressure)
	if not begin_color_stroke():
		return false
	if not _stage_color_dab(point, radius_m, value, shape, pressure):
		cancel_color_stroke()
		return false
	return end_color_stroke()


## Final RGB words for native export: committed native edits composited with
## every enabled color layer. Export staging uses this without mutating
## Terrain.color_edits, so the editable document keeps its native RGB history.
func export_colors() -> Dictionary:
	if package == null:
		return {}
	return ColorLayers.compose_all(package.terrain, color_layers, package.terrain.color_edits)


# --- Non-destructive sculpt layers -------------------------------------------

func _sculpt_snapshot() -> Array:
	var out: Array = []
	for item in sculpt_layers:
		out.append(Sculpt.normalize(item as Dictionary))
	return out


func _apply_sculpt_layers(state: Array, active_uid: int) -> void:
	sculpt_layers = []
	for item in state:
		sculpt_layers.append(Sculpt.normalize(item as Dictionary))
	active_sculpt_uid = active_uid
	if active_sculpt_uid < 0 and not sculpt_layers.is_empty():
		active_sculpt_uid = int((sculpt_layers[0] as Dictionary)["uid"])
	sculpt_revision += 1
	sculpt_layers_changed.emit(active_sculpt_uid)


func _commit_sculpt_layers(state: Array, active_uid: int) -> bool:
	if package == null or has_active_edit_transaction():
		return fail("Finish the current stroke before editing sculpt layers.")
	if not Sculpt.validate_stack(state, package.terrain.heights.size()):
		return fail("Invalid sculpt layer stack.")
	var before := _sculpt_snapshot()
	var after: Array = []
	for item in state:
		after.append(Sculpt.normalize(item as Dictionary))
	if before == after and active_sculpt_uid == active_uid:
		return true
	# A validated layer mutation invalidates the old composite. Clear only a
	# sculpt-owned preview, then recompose from the new stack; a foreign tool's
	# preview must stay untouched and must not be silently replaced.
	var sculpt_preview_active := (has_preview() and preview_owner == "sculpt") or _sculpt_composition_active
	if sculpt_preview_active:
		clear_preview()
	push_history({"sculpt": true, "before": before, "after": after,
		"active_before": active_sculpt_uid, "active_after": active_uid})
	_apply_sculpt_layers(after, active_uid)
	if sculpt_preview_active:
		# An empty recompose is still an active sculpt composition (e.g. a
		# zero default mask). Keep ownership so the next mutation recomposes.
		_sculpt_composition_active = true
		sculpt_preview()
	return true


func add_sculpt_layer() -> int:
	if package == null or sculpt_layers.size() >= Sculpt.MAX_LAYERS:
		return -1
	var state := _sculpt_snapshot()
	var uid := next_sculpt_uid
	next_sculpt_uid += 1
	state.append(Sculpt.layer(uid))
	if not _commit_sculpt_layers(state, uid):
		return -1
	return sculpt_layers.size() - 1


func remove_sculpt_layer(index: int) -> bool:
	if index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var state := _sculpt_snapshot()
	var removed_uid := int((state[index] as Dictionary)["uid"])
	state.remove_at(index)
	var next_uid := active_sculpt_uid
	if removed_uid == next_uid:
		next_uid = -1 if state.is_empty() else int((state[mini(index, state.size() - 1)] as Dictionary)["uid"])
	return _commit_sculpt_layers(state, next_uid)


func set_sculpt_layer_enabled(index: int, enabled: bool) -> bool:
	if index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var state := _sculpt_snapshot()
	if bool((state[index] as Dictionary)["enabled"]) == enabled:
		return true
	(state[index] as Dictionary)["enabled"] = enabled
	return _commit_sculpt_layers(state, active_sculpt_uid)


## Opacity gestures stage the displayed value only. The committed layer, its
## Undo history and the composed preview are untouched until commit; each
## preview recomputes from the same composer Native Export uses.
func begin_sculpt_opacity_preview(index: int) -> bool:
	if package == null or index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer opacity gesture.")
	if has_active_edit_transaction():
		return fail("Finish the current stroke before editing sculpt opacity.")
	if has_active_preview_context() and preview_owner != "sculpt":
		return fail("Cancel the foreign preview before editing sculpt opacity.")
	_sculpt_opacity_preview_uid = int((sculpt_layers[index] as Dictionary)["uid"])
	_sculpt_opacity_preview_value = float((sculpt_layers[index] as Dictionary)["opacity"])
	_sculpt_opacity_restore_preview = has_preview() and preview_owner == "sculpt"
	return true


func preview_sculpt_layer_opacity(uid: int, value: float) -> bool:
	if package == null or _sculpt_opacity_preview_uid < 0 or uid != _sculpt_opacity_preview_uid:
		return false
	if has_active_edit_transaction():
		return false
	if not is_finite(value) or value < 0.0 or value > 1.0:
		return false
	var index := sculpt_index_by_uid(uid)
	if index < 0:
		return false
	if has_active_preview_context() and preview_owner != "sculpt":
		return false
	_sculpt_opacity_preview_value = clampf(value, 0.0, 1.0)
	var staged := _sculpt_snapshot()
	(staged[index] as Dictionary)["opacity"] = _sculpt_opacity_preview_value
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var values := Sculpt.compose(base_heights, staged, limit, edits)
	if values.is_empty():
		if has_preview():
			clear_preview()
		return true
	return show_preview(values, {}, "sculpt")


func cancel_sculpt_opacity_preview(uid: int = -1) -> void:
	if _sculpt_opacity_preview_uid < 0:
		return
	if uid >= 0 and uid != _sculpt_opacity_preview_uid:
		return
	_sculpt_opacity_preview_uid = -1
	_sculpt_opacity_preview_value = NAN
	var restore := _sculpt_opacity_restore_preview
	_sculpt_opacity_restore_preview = false
	if preview_owner == "sculpt" and has_preview():
		clear_preview()
	if restore:
		sculpt_preview()


func commit_sculpt_opacity_preview(uid: int, value: float) -> bool:
	if _sculpt_opacity_preview_uid < 0 or uid != _sculpt_opacity_preview_uid:
		return false
	var index := sculpt_index_by_uid(uid)
	var final_value := _sculpt_opacity_preview_value if not is_finite(value) else clampf(value, 0.0, 1.0)
	var had_preview := has_preview() and preview_owner == "sculpt"
	_sculpt_opacity_preview_uid = -1
	_sculpt_opacity_preview_value = NAN
	_sculpt_opacity_restore_preview = false
	if had_preview:
		clear_preview()
	if index < 0 or not is_finite(final_value) or final_value < 0.0 or final_value > 1.0:
		return false
	var changed := not is_equal_approx(float((sculpt_layers[index] as Dictionary)["opacity"]), final_value)
	var ok := true
	if changed:
		ok = set_sculpt_layer_opacity(index, final_value)
	if ok and had_preview:
		sculpt_preview()
	return ok


func set_sculpt_layer_opacity(index: int, value: float) -> bool:
	if index < 0 or index >= sculpt_layers.size() or not is_finite(value) or value < 0.0 or value > 1.0:
		return fail("Invalid sculpt layer opacity.")
	var state := _sculpt_snapshot()
	if is_equal_approx(float((state[index] as Dictionary)["opacity"]), value):
		return true
	(state[index] as Dictionary)["opacity"] = value
	return _commit_sculpt_layers(state, active_sculpt_uid)


func rename_sculpt_layer(index: int, name: String) -> bool:
	if index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var state := _sculpt_snapshot()
	var clean := name.strip_edges().substr(0, 64)
	if String((state[index] as Dictionary).get("name", "")) == clean:
		return true
	(state[index] as Dictionary)["name"] = clean
	return _commit_sculpt_layers(state, active_sculpt_uid)


func move_sculpt_layer(from: int, to: int) -> bool:
	if from < 0 or to < 0 or from >= sculpt_layers.size() or to >= sculpt_layers.size() or from == to:
		return false
	var state := _sculpt_snapshot()
	var moved: Dictionary = state[from]
	state.remove_at(from)
	state.insert(clampi(to, 0, state.size()), moved)
	return _commit_sculpt_layers(state, active_sculpt_uid)


## Active sculpt layer is editor selection, not a terrain edit: no history
## entry, no dirty revision, no preview invalidation, no layer-content change.
func set_active_sculpt_layer(index: int) -> bool:
	if index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var uid := int((sculpt_layers[index] as Dictionary)["uid"])
	if uid == active_sculpt_uid:
		return true
	active_sculpt_uid = uid
	sculpt_layers_changed.emit(active_sculpt_uid)
	return true


func sculpt_index_by_uid(uid: int) -> int:
	for i in sculpt_layers.size():
		if int((sculpt_layers[i] as Dictionary)["uid"]) == uid:
			return i
	return -1


## A sculpt stroke groups any number of dabs (including interpolated segments
## and mirrored dabs) into one Undo entry. Dabs accumulate directly in the live
## layer state; only end_sculpt_stroke() records history. Cancel restores the
## snapshot taken at BEGIN and records nothing.
func begin_sculpt_stroke() -> bool:
	if package == null or stroke_active or water_stroke_active or sculpt_stroke_active \
		or sculpt_mask_stroke_active or color_stroke_active or color_mask_stroke_active \
		or external_transaction or (has_active_preview_context() and preview_owner != "sculpt"):
		return fail("Finish the current stroke and cancel previews before sculpting.")
	if sculpt_index_by_uid(active_sculpt_uid) < 0:
		return fail("Create or activate a sculpt layer first.")
	sculpt_stroke_active = true
	_sculpt_stroke_before = _sculpt_snapshot()
	_sculpt_stroke_uid = active_sculpt_uid
	_sculpt_stroke_touched = false
	return true


func _stage_sculpt_dab(point: Vector2, radius_m: float, amount: float, shape: int) -> bool:
	var index_active := sculpt_index_by_uid(active_sculpt_uid)
	if index_active < 0:
		return fail("Create or activate a sculpt layer first.")
	if not is_finite(amount) or amount == 0.0:
		return true
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return true
	var terrain := package.terrain
	var radius := radius_m / terrain.SPACING
	# Inside a stroke the layer snapshot was already taken at BEGIN, so mutate
	# the canonical live deltas directly. Deep-copying and revalidating the whole
	# stack per dab grows linearly with all layers and is unnecessary here.
	var state: Array = []
	var deltas: Dictionary
	# Rollback covers only samples this dab touches. Copying every prior sample
	# made a small brush grow with the size of a large sparse layer.
	var journal: Dictionary = {}
	var journal_present: Dictionary = {}
	if sculpt_stroke_active:
		deltas = (sculpt_layers[index_active] as Dictionary)["deltas"]
	else:
		state = _sculpt_snapshot()
		deltas = (state[index_active] as Dictionary)["deltas"]
	var changed_indices: Array[int] = []
	var touched := false
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0.0:
				continue
			var index := z * terrain.dimensions.x + x
			if index < 0 or index >= terrain.heights.size():
				continue
			if sculpt_stroke_active and not journal.has(index):
				journal[index] = float(deltas.get(index, 0.0))
				journal_present[index] = deltas.has(index)
			var next := float(deltas.get(index, 0.0)) + amount * weight
			next = snappedf(next, package.granularity)
			if absf(next) <= package.granularity * 0.5:
				deltas.erase(index)
			else:
				deltas[index] = next
			changed_indices.append(index)
			touched = true
	if not touched:
		return true
	if sculpt_stroke_active:
		var touched_before := 0
		for index: int in changed_indices:
			var next_value: float = float(deltas.get(index, 0.0))
			if not is_finite(next_value) or absf(next_value) > Sculpt.MAX_ABS_DELTA:
				for restore_index: int in journal:
					if bool(journal_present[restore_index]):
						deltas[restore_index] = float(journal[restore_index])
					else:
						deltas.erase(restore_index)
				return fail("Sculpt delta exceeded the editable range.")
			if float(journal[index]) != next_value or bool(journal_present[index]) != deltas.has(index):
				touched_before += 1
		if touched_before == 0:
			return true
		sculpt_revision += 1
	else:
		if not Sculpt.validate_stack(state, terrain.heights.size()):
			return fail("Sculpt delta exceeded the editable range.")
		_apply_sculpt_layers(state, active_sculpt_uid)
	_sculpt_stroke_touched = true
	_update_sculpt_live_preview(changed_indices)
	return true


## During a stroke the visible surface must track the mouse without creating a
## second Undo entry or changing preview ownership. Compose every active layer
## only over samples this dab touched, then apply just the changed heights.
## preview_before keeps the original committed height for cancel/finish.
func _update_sculpt_live_preview(changed_indices: Array[int]) -> void:
	if package == null or changed_indices.is_empty():
		return
	var live := sculpt_stroke_active or sculpt_mask_stroke_active
	if not live:
		return
	if not _sculpt_live_preview:
		_sculpt_live_preview = true
		preview_owner = "sculpt"
		preview_source_revision = document_id_source_revision()
		preview_sculpt_revision = sculpt_revision
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var values := Sculpt.compose_canonical(base_heights, sculpt_layers, limit, edits, changed_indices)
	var frame := {}
	for index: int in values:
		var target: float = values[index]
		if not _sculpt_live_base.has(index):
			_sculpt_live_base[index] = float(edits.get(index, base_heights[index]))
		var base := float(_sculpt_live_base[index])
		if is_equal_approx(target, base):
			preview_after.erase(index)
			preview_before.erase(index)
			if package.terrain.heights[index] != base:
				frame[index] = base
			continue
		preview_before[index] = base
		preview_after[index] = target
		if package.terrain.heights[index] != target:
			frame[index] = target
	apply(frame, false)


func _clear_sculpt_live_preview() -> void:
	if not _sculpt_live_preview:
		return
	var previous := preview_before.duplicate()
	_sculpt_live_preview = false
	_sculpt_live_base = {}
	preview_before = {}
	preview_after = {}
	preview_owner = ""
	preview_source_revision = ""
	preview_sculpt_revision = -1
	apply(previous, false)


func end_sculpt_stroke() -> bool:
	if not sculpt_stroke_active:
		return false
	var before := _sculpt_stroke_before
	var uid := _sculpt_stroke_uid
	var after := _sculpt_snapshot()
	var changed := _sculpt_stroke_touched and after != before
	sculpt_stroke_active = false
	_sculpt_stroke_before = []
	_sculpt_stroke_uid = -1
	_sculpt_stroke_touched = false
	_clear_sculpt_live_preview()
	if not changed:
		return true
	push_history({"sculpt": true, "before": before, "after": after,
		"active_before": uid, "active_after": active_sculpt_uid})
	return true


func cancel_sculpt_stroke() -> void:
	if not sculpt_stroke_active:
		return
	var before := _sculpt_stroke_before
	var uid := _sculpt_stroke_uid
	sculpt_stroke_active = false
	_sculpt_stroke_before = []
	_sculpt_stroke_uid = -1
	_sculpt_stroke_touched = false
	_clear_sculpt_live_preview()
	_apply_sculpt_layers(before, uid)


## Paint one brush dab into the active sculpt layer. Deltas are relative to the
## committed terrain, so enable/disable and opacity remain reversible. Within
## an active stroke, dabs accumulate without creating Undo entries.
func sculpt_dab(point: Vector2, radius_m: float, amount: float, shape := BrushShape.BELL) -> bool:
	if package == null or (has_active_edit_transaction() and not sculpt_stroke_active) or (has_preview() and not _sculpt_live_preview):
		return fail("Finish the current stroke and cancel previews before sculpting.")
	if sculpt_stroke_active:
		return _stage_sculpt_dab(point, radius_m, amount, shape)
	if not begin_sculpt_stroke():
		return false
	if not _stage_sculpt_dab(point, radius_m, amount, shape):
		cancel_sculpt_stroke()
		return false
	return end_sculpt_stroke()


# --- Non-destructive sculpt layer masks --------------------------------------

func add_sculpt_mask(index: int, default_strength: float = 0.0) -> bool:
	if package == null or index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	if (sculpt_layers[index] as Dictionary).get("mask", null) != null:
		return fail("Sculpt layer already has a mask.")
	if not is_finite(default_strength) or default_strength < 0.0 or default_strength > 1.0:
		return fail("Invalid sculpt mask default strength.")
	var state := _sculpt_snapshot()
	(state[index] as Dictionary)["mask"] = Sculpt.mask(default_strength)
	return _commit_sculpt_layers(state, active_sculpt_uid)


func remove_sculpt_mask(index: int) -> bool:
	if package == null or index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var state := _sculpt_snapshot()
	if (state[index] as Dictionary).get("mask", null) == null:
		return true
	(state[index] as Dictionary)["mask"] = null
	return _commit_sculpt_layers(state, active_sculpt_uid)


func set_sculpt_mask_enabled(index: int, enabled: bool) -> bool:
	if package == null or index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var state := _sculpt_snapshot()
	var mask_data: Variant = (state[index] as Dictionary).get("mask", null)
	if not mask_data is Dictionary:
		return fail("Sculpt layer has no mask.")
	if bool((mask_data as Dictionary)["enabled"]) == enabled:
		return true
	(mask_data as Dictionary)["enabled"] = enabled
	return _commit_sculpt_layers(state, active_sculpt_uid)


func set_sculpt_mask_default(index: int, strength: float) -> bool:
	if package == null or index < 0 or index >= sculpt_layers.size():
		return fail("Invalid sculpt layer index.")
	var state := _sculpt_snapshot()
	var mask_data: Variant = (state[index] as Dictionary).get("mask", null)
	if not mask_data is Dictionary:
		return fail("Sculpt layer has no mask.")
	if not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return fail("Invalid sculpt mask strength.")
	(mask_data as Dictionary)["default"] = strength
	return _commit_sculpt_layers(state, active_sculpt_uid)


func _mask_op_guard_sculpt(index: int) -> Array:
	if package == null or index < 0 or index >= sculpt_layers.size():
		fail("Invalid sculpt layer index.")
		return []
	if has_active_edit_transaction():
		fail("Finish the current stroke before editing a sculpt mask.")
		return []
	var state := _sculpt_snapshot()
	var mask_data: Variant = (state[index] as Dictionary).get("mask", null)
	if not mask_data is Dictionary:
		fail("Sculpt layer has no mask.")
		return []
	return state


func fill_sculpt_mask(index: int, strength: float) -> bool:
	var state := _mask_op_guard_sculpt(index)
	if state.is_empty() or not is_finite(strength) or strength < 0.0 or strength > 1.0:
		return fail("Invalid sculpt mask fill strength.")
	var mask_data: Dictionary = (state[index] as Dictionary)["mask"]
	mask_data["default"] = strength
	mask_data["samples"] = {}
	return _commit_sculpt_layers(state, active_sculpt_uid)


func clear_sculpt_mask_overrides(index: int) -> bool:
	var state := _mask_op_guard_sculpt(index)
	if state.is_empty():
		return false
	var mask_data: Dictionary = (state[index] as Dictionary)["mask"]
	(mask_data["samples"] as Dictionary).clear()
	return _commit_sculpt_layers(state, active_sculpt_uid)


func invert_sculpt_mask(index: int) -> bool:
	var state := _mask_op_guard_sculpt(index)
	if state.is_empty():
		return false
	var mask_data: Dictionary = (state[index] as Dictionary)["mask"]
	var new_default := 1.0 - float(mask_data["default"])
	var inverted: Dictionary = {}
	for key: Variant in (mask_data["samples"] as Dictionary):
		var value := 1.0 - float((mask_data["samples"] as Dictionary)[key])
		if not is_equal_approx(value, new_default):
			inverted[key] = value
	mask_data["default"] = new_default
	mask_data["samples"] = inverted
	return _commit_sculpt_layers(state, active_sculpt_uid)


func _mask_stroke_live_base(index: int) -> float:
	return float(edits.get(index, base_heights[index]))


## Sculpt masks reuse the sculpt-owned live preview. Admission is strict: a
## foreign preview, another stroke or a staged opacity gesture all refuse, but
## an existing sculpt-owned preview is compatible and may stay visible.
func begin_sculpt_mask_stroke() -> bool:
	if package == null or has_active_edit_transaction() or _sculpt_opacity_preview_uid >= 0:
		return fail("Finish the current edit before painting a sculpt mask.")
	if has_active_preview_context() and preview_owner != "sculpt" and not _sculpt_live_preview:
		return fail("Cancel the foreign preview before painting a sculpt mask.")
	var index := sculpt_index_by_uid(active_sculpt_uid)
	if index < 0 or (sculpt_layers[index] as Dictionary).get("mask", null) == null:
		return fail("Select a sculpt layer with a mask.")
	_sculpt_mask_restore_preview = has_preview() and preview_owner == "sculpt" and not _sculpt_live_preview
	sculpt_mask_stroke_active = true
	_sculpt_mask_before = _sculpt_snapshot()
	_sculpt_mask_uid = active_sculpt_uid
	_sculpt_mask_journal = {}
	_sculpt_mask_journal_present = {}
	return true


## One dab blends toward `target_strength` at every affected sample; the blend
## step is `brush_weight × flow`. BrushPanel feeds pressure × hold into `flow`,
## never into the target, so Reveal and Hide move samples the same distance:
## 20% flow takes 0 -> 0.2 and 1 -> 0.8 at the brush centre. Sparse overrides
## equal to the mask default are removed. Only touched samples are journalled;
## an invalid dab rolls back this dab alone.
func sculpt_mask_dab(point: Vector2, radius_m: float, target_strength: float, shape := BrushShape.BELL, flow := 1.0) -> bool:
	if not sculpt_mask_stroke_active or not is_finite(target_strength) \
		or target_strength < 0.0 or target_strength > 1.0 \
		or not is_finite(flow) or flow < 0.0 or flow > 1.0 \
		or not point.is_finite() or not is_finite(radius_m) \
		or radius_m <= 0.0 or radius_m > 256.0:
		return fail("Invalid sculpt mask dab.")
	var terrain := package.terrain
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return true
	var radius := radius_m / terrain.SPACING
	var index_active := sculpt_index_by_uid(_sculpt_mask_uid)
	if index_active < 0:
		return fail("The masked sculpt layer is no longer available.")
	var mask_data: Dictionary = (sculpt_layers[index_active] as Dictionary)["mask"]
	var samples: Dictionary = mask_data["samples"]
	var default_value := float(mask_data["default"])
	var journal: Dictionary = {}
	var journal_present: Dictionary = {}
	var changed_indices: Array[int] = []
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0.0:
				continue
			var sample_index := z * terrain.dimensions.x + x
			if sample_index < 0 or sample_index >= terrain.heights.size():
				continue
			if not journal.has(sample_index):
				journal[sample_index] = float(samples.get(sample_index, default_value))
				journal_present[sample_index] = samples.has(sample_index)
			var previous := float(journal[sample_index])
			var next := clampf(lerpf(previous, target_strength, clampf(weight * flow, 0.0, 1.0)), 0.0, 1.0)
			if is_equal_approx(next, default_value):
				samples.erase(sample_index)
			else:
				samples[sample_index] = next
			changed_indices.append(sample_index)
	if changed_indices.is_empty():
		return true
	if not Sculpt.validate_stack([sculpt_layers[index_active]], terrain.heights.size()):
		for restore_index: int in journal:
			if bool(journal_present[restore_index]):
				samples[restore_index] = float(journal[restore_index])
			else:
				samples.erase(restore_index)
		return fail("Invalid sculpt mask sample produced by stroke.")
	for restore_index: int in journal:
		if not _sculpt_mask_journal.has(restore_index):
			_sculpt_mask_journal[restore_index] = journal[restore_index]
			_sculpt_mask_journal_present[restore_index] = journal_present[restore_index]
	sculpt_revision += 1
	_update_sculpt_live_preview(changed_indices)
	return true


func end_sculpt_mask_stroke() -> bool:
	if not sculpt_mask_stroke_active:
		return false
	var before := _sculpt_mask_before
	var after := _sculpt_snapshot()
	var uid := _sculpt_mask_uid
	var changed := after != before
	var restore := _sculpt_mask_restore_preview
	var had_live := _sculpt_live_preview
	var touched_indices: Array[int] = []
	for index: int in _sculpt_mask_journal:
		touched_indices.append(index)
	sculpt_mask_stroke_active = false
	_sculpt_mask_before = []
	_sculpt_mask_uid = -1
	_sculpt_mask_journal = {}
	_sculpt_mask_journal_present = {}
	_sculpt_mask_restore_preview = false
	# Keep the final composed surface visible before releasing stroke ownership.
	if had_live:
		_sculpt_live_preview = true
		preview_owner = "sculpt"
		preview_source_revision = document_id_source_revision()
		preview_sculpt_revision = sculpt_revision
		_update_sculpt_live_preview(touched_indices)
	_clear_sculpt_live_preview()
	if changed:
		push_history({"sculpt": true, "before": before, "after": after,
			"active_before": uid, "active_after": active_sculpt_uid})
	if sculpt_layers.size() > 0 and not Sculpt.compose(base_heights, sculpt_layers,
		minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0), edits).is_empty():
		sculpt_preview()
	elif restore:
		_mark_empty_sculpt_composition()
	return true


func cancel_sculpt_mask_stroke() -> void:
	if not sculpt_mask_stroke_active:
		return
	var before := _sculpt_mask_before
	var uid := _sculpt_mask_uid
	var restore := _sculpt_mask_restore_preview
	sculpt_mask_stroke_active = false
	_sculpt_mask_before = []
	_sculpt_mask_uid = -1
	_sculpt_mask_journal = {}
	_sculpt_mask_journal_present = {}
	_sculpt_mask_restore_preview = false
	_clear_sculpt_live_preview()
	_apply_sculpt_layers(before, uid)
	if restore and sculpt_layers.size() > 0:
		sculpt_preview()


func _mark_empty_sculpt_composition() -> void:
	# An active sculpt composition can legitimately equal the baseline (e.g. a
	# default-zero mask). Keep ownership explicit so mask OFF restores the delta
	# without confusing an empty result with "no compositor".
	_sculpt_composition_active = true
	preview_owner = "sculpt"
	preview_source_revision = document_id_source_revision()
	preview_sculpt_revision = sculpt_revision


func sculpt_preview() -> bool:
	if package == null or has_active_edit_transaction() or sculpt_layers.is_empty():
		return fail("Create a sculpt layer before previewing.")
	if _sculpt_live_preview:
		_clear_sculpt_live_preview()
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var values := Sculpt.compose(base_heights, sculpt_layers, limit, edits)
	if values.is_empty():
		if _sculpt_composition_active:
			_mark_empty_sculpt_composition()
			return true
		return fail("The sculpt layer has no deltas to preview.")
	return show_preview(values, {}, "sculpt")


## Final terrain heights for a lossless native export: committed edits plus
## every enabled sculpt layer, evaluated through the same deterministic
## composer as the preview. The document and its Undo history are untouched.
func export_heights() -> Dictionary:
	var result := edits.duplicate()
	if sculpt_layers.is_empty():
		return result
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var values := Sculpt.compose(base_heights, sculpt_layers, limit, edits)
	for index: int in values:
		result[index] = values[index]
	return result


func bake_sculpt_layers() -> bool:
	if package == null or not has_preview() or sculpt_layers.is_empty():
		return fail("Preview an active sculpt layer before baking.")
	if preview_owner != "sculpt":
		return fail("This preview belongs to another tool. Compose a Sculpt Preview before Sculpt Bake.")
	if preview_source_revision != document_id_source_revision():
		return fail("The project changed since the Sculpt Preview. Recompose before Sculpt Bake.")
	if preview_sculpt_revision != sculpt_revision:
		return fail("Sculpt layers changed since the preview. Recompose before Sculpt Bake.")
	var heights := preview_after.duplicate()
	var history := {"before": preview_before.duplicate(), "after": heights, "materials": {}}
	for layer: int in package.terrain.material_previews:
		var previous := {}
		for index: int in package.terrain.material_previews[layer]:
			previous[index] = package.terrain.committed_material_value(layer, index)
		history["materials"][layer] = {"before": previous, "after": package.terrain.material_previews[layer].duplicate()}
	var baked_layers := _sculpt_snapshot()
	history["sculpt_before"] = baked_layers
	history["sculpt_after"] = []
	clear_preview()
	apply(heights)
	for layer: int in history["materials"]:
		refresh_materials(layer, history["materials"][layer]["after"])
	push_history(history)
	_apply_sculpt_layers([], -1)
	return true


func begin_stroke(layer := Terrain.Layer.HEIGHT) -> bool:
	if has_active_edit_transaction():
		return fail("Finish the current edit before painting terrain.")
	if has_preview():
		return fail("Clear the terrain preview before painting terrain.")
	stroke_active = true
	stroke_layer = layer
	stroke = {}
	stroke_weights = {}
	stroke_exact = {}
	stroke_tick = 0
	return true


func dab(point: Vector2, radius_m: float, amount: float, mode := Brush.OFFSET, shape := BrushShape.BELL, pressure := 1.0, accumulate := false) -> void:
	if not stroke_active or stroke_layer != Terrain.Layer.HEIGHT or not is_finite(amount):
		return
	var terrain := package.terrain
	var radius := radius_m / terrain.SPACING
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var touched := false
	if accumulate:
		stroke_tick += 1
		var p := clampf(pressure, 0.0, 1.0)
		var smooth_updates: Array = []
		for z in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var weight := brush_weight(point - Vector2(x, z), radius, shape)
				if weight <= 0.0:
					continue
				if mode == Brush.SPRAY and hash(Vector3i(x, z, stroke_tick)) % 5 > 1:
					continue
				var index := z * terrain.dimensions.x + x
				var old := terrain.heights[index]
				var start: float = stroke.get(index, old)
				var current_exact: float = stroke_exact.get(index, old)
				var next_exact := current_exact
				match mode:
					Brush.OFFSET:
						next_exact = clampf(current_exact + amount * p * weight, -limit, limit)
					Brush.SMOOTH:
						var avg := neighborhood_average_current(Vector2i(x, z), terrain.dimensions)
						next_exact = lerpf(current_exact, avg, clampf(amount / 100.0, 0.0, 1.0) * p * weight)
					Brush.FLATTEN, Brush.SPRAY:
						var clamped_goal := clampf(amount, -limit, limit)
						next_exact = lerpf(current_exact, clamped_goal, p * weight)
						if absf(clamped_goal - next_exact) < package.granularity * 0.5:
							next_exact = clamped_goal
				if not is_finite(next_exact):
					continue
				var target := snappedf(next_exact, package.granularity)
				if not is_finite(target) or absf(target) > limit:
					continue
				if mode == Brush.SMOOTH:
					smooth_updates.append([index, start, next_exact, target, old])
				else:
					stroke_exact[index] = next_exact
					if target != old:
						stroke[index] = start
						set_height(index, target)
						touched = true
		if mode == Brush.SMOOTH:
			for item: Array in smooth_updates:
				var idx: int = item[0]
				var st: float = item[1]
				var exact_val: float = item[2]
				var tgt: float = item[3]
				var prev: float = item[4]
				stroke_exact[idx] = exact_val
				if tgt != prev:
					stroke[idx] = st
					set_height(idx, tgt)
					touched = true
		if touched:
			terrain_changed.emit(region)
		return
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0.0:
				continue
			var index := z * terrain.dimensions.x + x
			if mode == Brush.SPRAY and hash(Vector2i(x, z)) % 5 > 1:
				continue
			var old := terrain.heights[index]
			var start: float = stroke.get(index, old)
			if weight <= stroke_weights.get(index, 0.0):
				continue
			var requested := start + amount
			match mode:
				Brush.SMOOTH:
					requested = lerpf(start, neighborhood_average(Vector2i(x, z), terrain.dimensions), clampf(amount / 100.0, 0, 1))
				Brush.FLATTEN, Brush.SPRAY:
					requested = amount
			requested = lerpf(start, requested, clampf(pressure, 0, 1))
			if requested == start:
				continue
			var target := snappedf(lerpf(start, requested, weight), package.granularity)
			if not is_finite(target) or absf(target) > limit:
				continue
			if (requested > start and target <= old) or (requested < start and target >= old):
				continue
			stroke[index] = start
			stroke_weights[index] = weight
			stroke_exact[index] = target
			set_height(index, target)
			touched = true
	if touched:
		terrain_changed.emit(region)


func brush_region(point: Vector2, radius_m: float) -> Rect2i:
	if not point.is_finite() or not is_finite(radius_m) or radius_m <= 0.0 or radius_m > 256.0:
		return Rect2i()
	var radius := radius_m / Terrain.SPACING
	var low := Vector2i(floori(point.x - radius), floori(point.y - radius)).max(Vector2i.ZERO)
	var high := Vector2i(ceili(point.x + radius), ceili(point.y + radius)).min(package.terrain.dimensions - Vector2i.ONE)
	return Rect2i(low, high - low + Vector2i.ONE)


func brush_weight(offset: Vector2, radius: float, shape: int) -> float:
	var distance := maxf(absf(offset.x), absf(offset.y)) if shape == BrushShape.SQUARE else offset.length()
	var influence := 1.0 - distance / radius
	if influence <= 0.0:
		return 0.0
	if shape == BrushShape.SQUARE or shape == BrushShape.CIRCLE:
		return 1.0
	return influence if shape == BrushShape.CONE else smoothstep(0.0, 1.0, influence)


func _color_dist_sq(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return dr * dr + dg * dg + db * db


func dab_material(point: Vector2, radius_m: float, value: int, shape: int, pressure: float, lane := 0, accumulate := false) -> void:
	if not stroke_active or stroke_layer not in [Terrain.Layer.COLOR, Terrain.Layer.TILES] or not is_finite(pressure):
		return
	var tiles := stroke_layer == Terrain.Layer.TILES
	if value < 0 or value > (15 if tiles else 0xffffff) or lane not in [0, 1, 2, 3]:
		return
	var region := brush_region(point, radius_m)
	if not region.has_area():
		return
	var terrain := package.terrain
	var radius := radius_m / Terrain.SPACING
	var target_col := Color.BLACK if tiles else Terrain.word_color(value)
	var p := clampf(pressure, 0.0, 1.0)
	var changes := {}
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var weight := brush_weight(point - Vector2(x, z), radius, shape)
			if weight <= 0:
				continue
			var index := terrain.block_at(Vector2i(x, z)) if tiles else z * terrain.dimensions.x + x
			if changes.has(index):
				continue
			if not accumulate and weight <= stroke_weights.get(index, 0.0):
				continue
			var current := terrain.material_value(stroke_layer, index)
			var start: int = stroke.get(index, current)
			var paint: int
			if tiles:
				var shift := lane * 4
				paint = (start & ~(15 << shift)) | (value << shift)
			else:
				var current_col: Color = stroke_exact.get(index, Terrain.word_color(current))
				var next_col: Color
				if accumulate:
					next_col = current_col.lerp(target_col, clampf(weight * p, 0.0, 1.0))
					if _color_dist_sq(next_col, target_col) < 0.00001:
						next_col = target_col
					stroke_exact[index] = next_col
				else:
					next_col = Terrain.word_color(start).lerp(target_col, weight * p)
					if stroke_exact.has(index) and _color_dist_sq(next_col, target_col) >= _color_dist_sq(current_col, target_col):
						continue
					stroke_exact[index] = next_col
				paint = Terrain.rgb_word(next_col)
			if paint != current:
				stroke[index] = start
				if not accumulate:
					stroke_weights[index] = weight
				changes[index] = paint
	apply_materials(stroke_layer, changes)


func apply_materials(layer: int, values: Dictionary) -> void:
	for index: int in values:
		package.terrain.set_material(layer, index, values[index])
	refresh_materials(layer, values)


func refresh_materials(layer: int, values: Dictionary) -> void:
	if values.is_empty():
		return
	var terrain := package.terrain
	var low := terrain.dimensions
	var high := Vector2i.ZERO
	var extent := Vector2i.ONE * (Terrain.BLOCK if layer == Terrain.Layer.TILES else 1)
	for index: int in values:
		var point := terrain.block_origin(index) if layer == Terrain.Layer.TILES else terrain.sample_at(index)
		low = low.min(point)
		high = high.max(point + extent)
	materials_changed.emit(Rect2i(low, high - low), layer)


func read_material_edits(saved: Variant, layer: int) -> bool:
	var terrain := package.terrain
	var limit := terrain.block_offsets.size() - 1 if layer == Terrain.Layer.TILES else terrain.heights.size()
	var max_value := 0xffff if layer == Terrain.Layer.TILES else 0xffffff
	if not saved is Dictionary or saved.size() > limit:
		return fail("Invalid project material edits.")
	for key: String in saved:
		var index := key.to_int()
		var value: Variant = saved[key]
		if str(index) != key or index < 0 or index >= limit or not valid_native_integer(value) or value > max_value:
			return fail("Invalid project terrain material value.")
		terrain.set_material(layer, index, int(value))
	return true


func neighborhood_average(point: Vector2i, size: Vector2i) -> float:
	var sum := 0.0
	var count := 0
	for z in range(maxi(0, point.y - 1), mini(size.y, point.y + 2)):
		for x in range(maxi(0, point.x - 1), mini(size.x, point.x + 2)):
			var index := z * size.x + x
			sum += stroke.get(index, package.terrain.heights[index])
			count += 1
	return sum / count


func neighborhood_average_current(point: Vector2i, size: Vector2i) -> float:
	var sum := 0.0
	var count := 0
	for z in range(maxi(0, point.y - 1), mini(size.y, point.y + 2)):
		for x in range(maxi(0, point.x - 1), mini(size.x, point.x + 2)):
			var index := z * size.x + x
			sum += float(stroke_exact.get(index, package.terrain.heights[index]))
			count += 1
	return sum / count


func end_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	stroke_exact = {}
	stroke_weights = {}
	stroke_tick = 0
	if stroke.is_empty():
		return
	var after := {}
	for index: int in stroke:
		after[index] = package.terrain.heights[index] if stroke_layer == Terrain.Layer.HEIGHT else package.terrain.material_value(stroke_layer, index)
	if stroke_layer == Terrain.Layer.HEIGHT:
		record_change(stroke, after)
	else:
		push_history({"material": stroke_layer, "before": stroke, "after": after})
	stroke = {}


## History navigation cannot happen under a foreign preview. Sculpt-owned
## previews are recomputed from the restored stack afterwards so the visible
## surface keeps matching export after undo/redo.
## History navigation cannot happen under a foreign preview. A sculpt-owned
## preview is cleared for the mutation and recomposed from the restored stack,
## so the visible surface keeps matching export after undo/redo.
func _prepare_history_preview() -> bool:
	if not has_preview() and not _color_composition_active and not _sculpt_composition_active and not _sculpt_live_preview:
		return true
	if _color_composition_active or preview_owner == "color" or _color_live_preview:
		if _color_live_preview:
			_clear_color_live_preview()
		terrain_color_preview_suspend()
		return true
	if preview_owner != "sculpt" and not _sculpt_live_preview and not _sculpt_composition_active:
		return false
	if _sculpt_live_preview:
		_clear_sculpt_live_preview()
	else:
		clear_preview()
	return true


func terrain_color_preview_suspend() -> void:
	if package == null:
		return
	var terrain := package.terrain
	if not terrain.material_previews.has(Terrain.Layer.COLOR):
		return
	var changes: Dictionary = terrain.material_previews[Terrain.Layer.COLOR]
	terrain.material_previews.erase(Terrain.Layer.COLOR)
	refresh_materials(Terrain.Layer.COLOR, changes)


func _restore_history_preview(was_sculpt: bool, was_color: bool = false) -> bool:
	if was_color and not color_layers.is_empty():
		return color_preview()
	if was_sculpt and not sculpt_layers.is_empty():
		var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
		var values := Sculpt.compose(base_heights, sculpt_layers, limit, edits)
		if values.is_empty():
			_mark_empty_sculpt_composition()
			return true
		return show_preview(values, {}, "sculpt")
	return false


func undo() -> void:
	if has_active_edit_transaction() or undo_stack.is_empty():
		return
	var was_sculpt := _sculpt_composition_active or _sculpt_live_preview or (has_preview() and preview_owner == "sculpt")
	var was_color := _color_composition_active or _color_live_preview
	var was_visible := was_sculpt and (has_preview() or _sculpt_composition_active)
	if not _prepare_history_preview():
		return
	var change: Dictionary = undo_stack.pop_back()
	apply_history(change, "before")
	redo_stack.append(change)
	if was_visible:
		_restore_history_preview(was_sculpt, was_color)
	else:
		_restore_history_preview(false, was_color)


func redo() -> void:
	if has_active_edit_transaction() or redo_stack.is_empty():
		return
	var was_sculpt := _sculpt_composition_active or _sculpt_live_preview or (has_preview() and preview_owner == "sculpt")
	var was_color := _color_composition_active or _color_live_preview
	var was_visible := was_sculpt and (has_preview() or _sculpt_composition_active)
	if not _prepare_history_preview():
		return
	var change: Dictionary = redo_stack.pop_back()
	apply_history(change, "after")
	undo_stack.append(change)
	if was_visible:
		_restore_history_preview(was_sculpt, was_color)
	else:
		_restore_history_preview(false, was_color)


func record_change(before: Dictionary, after: Dictionary) -> void:
	push_history({"before": before, "after": after})


func push_history(change: Dictionary) -> void:
	edit_revision += 1
	undo_stack.append(change)
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()


func apply_history(change: Dictionary, direction: String) -> void:
	edit_revision += 1
	if change.has("path"):
		set_path_edit(change["path"], change[direction])
	elif change.has("path_batch"):
		var batch: Array = change["path_batch"]
		var ordered := batch.duplicate()
		if direction == "before":
			ordered.reverse()
		for item: Dictionary in ordered:
			set_path_edit_silent(int(item["index"]), item[direction])
		paths_changed.emit()
	elif change.has("object"):
		apply_object_transform(change["object"], change[direction])
	elif change.has("object_batch"):
		var obj_batch: Array = change["object_batch"]
		var ordered_objs := obj_batch.duplicate()
		if direction == "before":
			ordered_objs.reverse()
		for item: Dictionary in ordered_objs:
			apply_object_transform(item["key"], item[direction])
	elif change.has("object_label"):
		apply_object_label(change["object_label"], String(change[direction]))
	elif change.has("object_add") or change.has("object_add_removed"):
		var addition: Dictionary = change["object_add"] if change.has("object_add") else change["object_add_removed"]
		var restore := (change.has("object_add") and direction == "after") or (change.has("object_add_removed") and direction == "before")
		if restore:
			while object_additions.size() < change["slot"]:
				object_additions.append({})
			object_additions.insert(mini(int(change["slot"]), object_additions.size()), addition)
		else:
			for slot in range(object_additions.size() - 1, -1, -1):
				if object_additions[slot] and int(object_additions[slot].get("id", -1)) == int(addition["id"]):
					object_additions.remove_at(slot)
		objects_changed.emit()
	elif change.has("object_remove"):
		var base := int(change["object_remove"])
		if direction == "after":
			object_removals[base] = true
		else:
			object_removals.erase(base)
		objects_changed.emit()
	elif change.has("material"):
		apply_materials(change["material"], change[direction])
	elif change.has("water"):
		var layer := int(change["water"])
		for block: int in change[direction]:
			set_water_cover(layer, block, change[direction][block])
		water_changed.emit()
	elif change.has("water_height"):
		set_water_height_internal(int(change["water_height"]), float(change[direction]))
		water_changed.emit()
	elif change.has("target_profile"):
		_apply_target_profile(change[direction])
	elif change.has("mission_dll"):
		_apply_mission_dll(change[direction])
	elif change.has("environment"):
		_apply_environment_edits(change[direction])
	elif change.has("profile_conversion"):
		_apply_profile_conversion(change[direction])
	elif change.has("layers"):
		if has_preview():
			clear_preview()
		var uid_key := "uids_before" if direction == "before" else "uids_after"
		var focus_key := "focus_before" if direction == "before" else "focus_after"
		_apply_procedural_layers(change[direction] as Array, _to_int_array(change.get(uid_key, [])), int(change.get(focus_key, -1)))
	elif change.has("sculpt"):
		var active_key := "active_before" if direction == "before" else "active_after"
		_apply_sculpt_layers(change[direction] as Array, int(change.get(active_key, -1)))
	elif change.has("color"):
		var active_key := "active_before" if direction == "before" else "active_after"
		_apply_color_layers(change[direction] as Array, int(change.get(active_key, -1)))
	else:
		var materials := {}
		for layer: int in change.get("materials", {}):
			materials[layer] = change["materials"][layer][direction]
		apply_channels(change[direction], materials)
		if change.has("sculpt_before") and change.has("sculpt_after"):
			var s_key := "sculpt_before" if direction == "before" else "sculpt_after"
			_apply_sculpt_layers(change[s_key] as Array, -1)
		if change.has("layers_before") and change.has("layers_after"):
			var l_key := "layers_before" if direction == "before" else "layers_after"
			var u_key := "uids_before" if direction == "before" else "uids_after"
			_apply_procedural_layers(change[l_key] as Array, _to_int_array(change.get(u_key, [])), -1)


func path_at(index: int) -> Dictionary:
	if path_edits.has(index):
		return path_edits[index]
	return source_path_at(index)


func source_path_at(index: int) -> Dictionary:
	return package.paths[index] if index >= 0 and index < package.paths.size() else {}


func path_indices() -> Array[int]:
	var indices: Array[int] = []
	for index in package.paths.size():
		if not path_at(index).is_empty():
			indices.append(index)
	for index: int in path_edits:
		if index >= package.paths.size():
			indices.append(index)
	indices.sort()
	return indices


func edit_path(index: int, label: String, points: PackedVector2Array, kind: int) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	var before := path_at(index)
	if before.is_empty():
		return fail("Select a supported native path.")
	var base := source_path_at(index)
	if not valid_path_fields(label, points, kind, base) or not unique_path_name(index, label):
		return false
	var updated := {"id": before["id"], "name": label, "points": points.duplicate(), "type": kind}
	if same_path_fields(updated, before):
		return true
	push_history({"path": index, "before": before, "after": updated})
	set_path_edit(index, updated)
	return true


func create_path(label: String, points: PackedVector2Array, kind: int) -> int:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return -1
	if not package.path_codec.can_resize or path_indices().size() >= PathCodec.MAX_PATHS:
		fail("This native path table cannot accept another path.")
		return -1
	var index := package.paths.size()
	while path_edits.has(index):
		index += 1
	if not valid_path_fields(label, points, kind, {}) or not unique_path_name(index, label):
		return -1
	var ids := path_pointer_counts().duplicate()
	var id := 1
	for record in package.paths:
		id = maxi(id, int(record["id"]) + 1)
	if id > 4294967295:
		id = 1
	for slot in path_indices():
		ids[path_at(slot)["id"]] = true
	while ids.has(id):
		id = 1 if id == 4294967295 else id + 1
	var path := {"id": id, "name": label, "points": points.duplicate(), "type": kind}
	push_history({"path": index, "before": {}, "after": path})
	set_path_edit(index, path)
	return index


func remove_path(index: int) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	var before := path_at(index)
	if before.is_empty() or not package.path_codec.can_resize:
		return fail("Select a path from a supported native path table.")
	if not can_remove_source_path(index):
		return false
	push_history({"path": index, "before": before, "after": {}})
	set_path_edit(index, {})
	return true


func path_pointer_counts() -> Dictionary:
	if native_path_ids.is_empty():
		native_path_ids = package.path_codec.pointer_counts(path_source_bytes())
	return native_path_ids


func path_source_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(package.source_path.get_base_dir().path_join(package.bzn_name))


func can_remove_source_path(index: int) -> bool:
	var base := source_path_at(index)
	if base.is_empty():
		return true
	var label: String = base["name"].to_lower()
	var spawn := RegEx.new()
	spawn.compile("^(player|enemy)_[0-9]+$")
	if label == "edge_path" or spawn.search(label) != null:
		return fail("The mission may require the path named %s." % base["name"])
	if path_pointer_counts().get(base["id"], 0) != 1:
		return fail("The BZN may reference the native ID of %s." % base["name"])
	if package.path_codec.has_name_reference(path_source_bytes(), label):
		return fail("The BZN may refer to the name %s." % base["name"])
	for member: String in package.files:
		if member.get_extension().to_lower() in ["lua", "aip", "trn", "inf"]:
			var content := FileAccess.get_file_as_string(package.source_path.get_base_dir().path_join(member))
			if content.to_lower().contains(label):
				return fail("%s may refer to %s." % [member, base["name"]])
	return true


func valid_path_fields(label: Variant, points: PackedVector2Array, kind: int, base: Dictionary) -> bool:
	var base_kind: int = base.get("type", -1)
	if not label is String or points.is_empty() or points.size() > PathCodec.MAX_POINTS or (kind != base_kind and kind not in [0, 1, 2]):
		return fail("Choose a valid path type and provide at least one point, or three for a loop.")
	if kind == 2 and points.size() < 3 and (base_kind != 2 or points.size() != base["points"].size()):
		return fail("A loop needs at least three points.")
	if label != base.get("name", "") or base.is_empty():
		var permitted := RegEx.new()
		permitted.compile("^[A-Za-z0-9_][A-Za-z0-9_. -]{0,63}$")
		if permitted.search(label) == null or label != label.strip_edges():
			return fail("Choose a path name using 1–64 ASCII letters, digits, spaces, underscores, dots or hyphens.")
	for point in points:
		if not point.is_finite():
			return fail("All path coordinates must be finite.")
	return true


func unique_path_name(index: int, label: String) -> bool:
	for other in path_indices():
		if other != index and label.nocasecmp_to(path_at(other)["name"]) == 0:
			if label != source_path_at(index).get("name") or path_at(other)["name"] != source_path_at(other).get("name"):
				return fail("Choose a unique path name.")
	return true


func set_path_edit_silent(index: int, data: Dictionary) -> void:
	if same_path_fields(source_path_at(index), data):
		path_edits.erase(index)
	else:
		path_edits[index] = data


func set_path_edit(index: int, data: Dictionary) -> void:
	set_path_edit_silent(index, data)
	paths_changed.emit()


func allocate_path_id() -> int:
	var ids := path_pointer_counts().duplicate()
	var id := 1
	for record in package.paths:
		id = maxi(id, int(record["id"]) + 1)
	if id > 4294967295:
		id = 1
	for slot in path_indices():
		ids[path_at(slot)["id"]] = true
	while ids.has(id):
		id = 1 if id == 4294967295 else id + 1
	return id


func create_paths_batch(specs: Array[Dictionary]) -> Array[int]:
	var created: Array[int] = []
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return created
	if not package.path_codec.can_resize or path_indices().size() + specs.size() > PathCodec.MAX_PATHS:
		fail("This native path table cannot accept that many paths.")
		return created
	var batch: Array[Dictionary] = []
	var next_index := package.paths.size()
	var taken_names := {}
	for slot in path_indices():
		taken_names[String(path_at(slot)["name"]).to_lower()] = true
	var used_ids := path_pointer_counts().duplicate()
	for slot in path_indices():
		used_ids[path_at(slot)["id"]] = true
	var next_id := allocate_path_id()
	for spec: Dictionary in specs:
		var label := String(spec.get("name", ""))
		var points: PackedVector2Array = spec.get("points", PackedVector2Array())
		var kind := int(spec.get("type", 0))
		if not valid_path_fields(label, points, kind, {}):
			return []
		if taken_names.has(label.to_lower()):
			fail("Choose a unique path name (duplicate: %s)." % label)
			return []
		taken_names[label.to_lower()] = true
		while path_edits.has(next_index):
			next_index += 1
		while used_ids.has(next_id):
			next_id = 1 if next_id == 4294967295 else next_id + 1
		used_ids[next_id] = true
		var data := {"id": next_id, "name": label, "points": points.duplicate(), "type": kind}
		batch.append({"index": next_index, "before": {}, "after": data})
		created.append(next_index)
		next_index += 1
	if batch.is_empty():
		return created
	push_history({"path_batch": batch})
	for item: Dictionary in batch:
		set_path_edit_silent(int(item["index"]), item["after"])
	paths_changed.emit()
	return created


func path_is_mission_referenced(index: int) -> bool:
	var base := source_path_at(index)
	if base.is_empty():
		return false
	var label: String = String(base["name"]).to_lower()
	var spawn := RegEx.new()
	spawn.compile("^(player|enemy)_[0-9]+$")
	if label == "edge_path" or spawn.search(label) != null:
		return true
	if package.path_codec.has_name_reference(path_source_bytes(), label):
		return true
	for member: String in package.files:
		if member.get_extension().to_lower() in ["lua", "aip", "trn", "inf"]:
			var content := FileAccess.get_file_as_string(package.source_path.get_base_dir().path_join(member))
			if content.to_lower().contains(label):
				return true
	return false


func edit_paths_batch(changes: Array[Dictionary]) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if changes.is_empty():
		return true
	var active_indices := path_indices()
	if active_indices.size() > PathCodec.MAX_PATHS:
		return fail("The path table exceeds the maximum supported path count.")
	var staged := {}
	for slot: int in active_indices:
		var current := path_at(slot)
		staged[slot] = {
			"id": int(current["id"]),
			"name": String(current["name"]),
			"points": (current["points"] as PackedVector2Array).duplicate(),
			"type": int(current["type"]),
		}
	var seen_indices := {}
	var renamed_sources: Array[int] = []
	var candidate_batch: Array[Dictionary] = []
	for item: Dictionary in changes:
		if not item.has("index") or not item.has("name") or not item.has("points") or not item.has("type"):
			return fail("Invalid path batch item.")
		if not (item["index"] is int) or not (item["points"] is PackedVector2Array):
			return fail("Invalid path batch item fields.")
		var index := int(item["index"])
		if seen_indices.has(index):
			return fail("Batch contains duplicate path index %d." % index)
		seen_indices[index] = true
		if not staged.has(index):
			return fail("Select a supported native path.")
		var before: Dictionary = staged[index]
		var label := String(item["name"])
		var points: PackedVector2Array = item["points"]
		var kind := int(item["type"])
		var base := source_path_at(index)
		if not valid_path_fields(label, points, kind, base):
			return false
		for pt in points:
			if absf(pt.x) > MAX_EDITOR_ABS_HEIGHT or absf(pt.y) > MAX_EDITOR_ABS_HEIGHT:
				return fail("Path coordinates exceed supported map bounds.")
		var native_id := int(before["id"])
		if native_id <= 0 or native_id > 4294967295:
			return fail("Invalid native path ID.")
		var after := {"id": native_id, "name": label, "points": points.duplicate(), "type": kind}
		if label.nocasecmp_to(String(before["name"])) != 0 and not base.is_empty():
			renamed_sources.append(index)
		staged[index] = after
		if not same_path_fields(after, before):
			candidate_batch.append({"index": index, "before": before, "after": after})
	# Validate global invariants on the full proposed path table before mutating anything.
	var lower_names := {}
	var used_ids := {}
	for slot: int in staged:
		var entry: Dictionary = staged[slot]
		var lower := String(entry["name"]).to_lower()
		if lower_names.has(lower):
			var other: int = int(lower_names[lower])
			var both_untouched: bool = (String(entry["name"]) == String(source_path_at(slot).get("name", ""))
				and String(staged[other]["name"]) == String(source_path_at(other).get("name", ""))
				and not seen_indices.has(slot) and not seen_indices.has(other))
			if not both_untouched:
				return fail("Choose a unique path name (batch collision: %s)." % entry["name"])
		else:
			lower_names[lower] = slot
		var pid := int(entry["id"])
		if used_ids.has(pid):
			return fail("Duplicate native path ID %d in batch." % pid)
		used_ids[pid] = slot
	for index in renamed_sources:
		var orig_name := String(source_path_at(index).get("name", "")).to_lower()
		if not lower_names.has(orig_name) and path_is_mission_referenced(index):
			return fail("Cannot drop mission-referenced path name %s in batch." % source_path_at(index)["name"])
	if candidate_batch.is_empty():
		return true
	push_history({"path_batch": candidate_batch})
	for item: Dictionary in candidate_batch:
		set_path_edit_silent(int(item["index"]), item["after"])
	paths_changed.emit()
	return true


func clone_path(index: int, offset := Vector2(32.0, 32.0)) -> int:
	var source := path_at(index)
	if source.is_empty():
		fail("Select a path to clone.")
		return -1
	var base_name := String(source["name"])
	var candidate := ""
	for suffix in range(2, 999):
		var try_name := "%s_%d" % [base_name, suffix]
		if try_name.length() > 64:
			try_name = base_name.substr(0, maxi(1, 64 - str(suffix).length() - 1)) + "_" + str(suffix)
		var taken := false
		for other in path_indices():
			if try_name.nocasecmp_to(String(path_at(other)["name"])) == 0:
				taken = true
				break
		if not taken:
			candidate = try_name
			break
	if candidate.is_empty():
		fail("No unique clone path name available.")
		return -1
	var terrain := package.terrain
	var rect := Rect2(Vector2(terrain.origin) * Terrain.SPACING, Vector2((terrain.dimensions - Vector2i.ONE).maxi(1)) * Terrain.SPACING)
	var pts := PackedVector2Array()
	for pt: Vector2 in source["points"]:
		var shifted := pt + offset
		pts.append(Vector2(clampf(shifted.x, rect.position.x, rect.end.x), clampf(shifted.y, rect.position.y, rect.end.y)))
	return create_path(candidate, pts, int(source["type"]))


static func same_path_fields(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return left.is_empty() and right.is_empty()
	return left["id"] == right["id"] and left["name"] == right["name"] and left["points"] == right["points"] and left["type"] == right["type"]


func read_path_edits(saved: Variant) -> bool:
	if not saved is Dictionary or saved.size() > 2 * PathCodec.MAX_PATHS:
		return fail("Invalid project path edits.")
	var added_ids := {}
	for key: String in saved:
		var index := key.to_int()
		if str(index) != key or index < 0 or index >= package.paths.size() + PathCodec.MAX_PATHS:
			return fail("Invalid project path reference.")
		var entry: Variant = saved[key]
		var base := source_path_at(index)
		if entry == null:
			if base.is_empty() or not package.path_codec.can_resize:
				return fail("Invalid saved path removal.")
			if not can_remove_source_path(index):
				return false
			path_edits[index] = {}
			continue
		if not entry is Dictionary:
			return fail("Invalid project path record.")
		var id: int = base.get("id", 0)
		if base.is_empty():
			var new_id: Variant = entry.get("id")
			if not package.path_codec.can_resize or not valid_native_integer(new_id) or new_id == 0:
				return fail("Invalid saved native path ID.")
			id = int(new_id)
			if added_ids.has(id) or path_pointer_counts().has(id):
				return fail("Saved path IDs conflict with another native record.")
			added_ids[id] = true
		var position_list: Variant = entry.get("points")
		var kind: Variant = entry.get("type")
		if not position_list is Array or position_list.size() > PathCodec.MAX_POINTS or not valid_native_integer(kind):
			return fail("Invalid saved path geometry or type.")
		var points := PackedVector2Array()
		for pair: Variant in position_list:
			if not pair is Array or pair.size() != 2 or not (pair[0] is int or pair[0] is float) or not (pair[1] is int or pair[1] is float):
				return fail("Invalid saved path coordinate.")
			points.append(Vector2(pair[0], pair[1]))
		if not valid_path_fields(entry.get("name"), points, int(kind), base):
			return false
		path_edits[index] = {"id": id, "name": entry["name"], "points": points, "type": int(kind)}
	if path_indices().size() > PathCodec.MAX_PATHS:
		return fail("The project has too many paths.")
	for index: int in path_edits:
		var entry := path_at(index)
		if not entry.is_empty() and not unique_path_name(index, entry["name"]):
			return false
	return true


func valid_native_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value <= 4294967295 and value == floorf(value)


func read_object_edits(saved: Variant) -> bool:
	if not saved is Dictionary or saved.size() > package.objects.size():
		return fail("Invalid project object edits.")
	for key: String in saved:
		var index := key.to_int()
		var fields: Variant = saved[key]
		if str(index) != key or index < 0 or index >= package.objects.size():
			return fail("Invalid project object reference.")
		if fields is Array and fields.size() == 3:
			for value in fields:
				if not (value is float or value is int) or not is_finite(value):
					return fail("Invalid saved object coordinate.")
			var legacy := Vector3(fields[0], fields[1], fields[2])
			if not valid_object_position(legacy):
				return fail("Saved object position is outside the supported map.")
			set_object_edit(index, Transform3D(package.objects[index]["transform"].basis, legacy))
			continue
		if not fields is Dictionary or not valid_object_edit(index, fields):
			return fail("Invalid saved object edit.")
		set_object_edit(index, Transform3D(read_saved_basis(fields["basis"]), Vector3(fields["position"][0], fields["position"][1], fields["position"][2])))
	return true


func read_object_label_edits(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary or saved.size() > package.objects.size():
		return fail("Invalid project object label edits.")
	for key: String in saved:
		var index := key.to_int()
		var value: Variant = saved[key]
		if str(index) != key or index < 0 or index >= package.objects.size() or not (value is String) or String(value).length() > 128:
			return fail("Invalid saved object label edit.")
		set_base_object_label(index, String(value))
	return true


func read_object_odf_edits(saved: Variant) -> bool:
	if saved == null:
		return true
	if not saved is Dictionary or saved.size() > package.objects.size():
		return fail("Invalid project object ODF edits.")
	for key: String in saved:
		var index := key.to_int()
		var value: Variant = saved[key]
		if str(index) != key or index < 0 or index >= package.objects.size() or not (value is String):
			return fail("Invalid saved object ODF edit.")
		var clean := String(value).strip_edges()
		if clean.is_empty() or clean.length() > 127 or clean.get_file() != clean or ":" in clean:
			return fail("Invalid saved object ODF identifier.")
		set_base_object_odf(index, clean)
	return true


func read_water_edits(saved: Variant) -> bool:
	if package.water == null:
		return true if saved == null or (saved is Dictionary and saved.is_empty()) else fail("This map has no native water.")
	if not saved is Dictionary or saved.size() > WATER_LAYERS:
		return fail("Invalid project water edits.")
	for key: String in saved:
		var layer := key.to_int()
		if str(layer) != key or not valid_water_layer(layer):
			return fail("Invalid project water layer.")
		var entry: Variant = saved[key]
		if not entry is Dictionary:
			return fail("Invalid project water record.")
		var height: Variant = entry.get("height", null)
		if height != null:
			if not (height is float or height is int) or not is_finite(float(height)) or absf(float(height)) > Water.MAX_HEIGHT:
				return fail("Invalid saved water elevation.")
			set_water_height(layer, float(height), false)
		var cover: Variant = entry.get("cover", null)
		if cover != null:
			if not cover is Dictionary or cover.size() > package.water.width * package.water.depth:
				return fail("Invalid saved water coverage.")
			for block_key: String in cover:
				var block := block_key.to_int()
				if str(block) != block_key or block < 0 or block >= package.water.width * package.water.depth:
					return fail("Invalid saved water coverage reference.")
				var value: Variant = cover[block_key]
				if not (value is bool):
					return fail("Invalid saved water coverage value.")
				set_water_cover(layer, block, value)
	return true


func valid_water_layer(layer: int) -> bool:
	return package.water != null and layer >= 0 and layer < WATER_LAYERS


func water_block_count() -> int:
	var water := package.water
	return water.width * water.depth if water != null else 0


func water_base_cover(layer: int) -> Dictionary:
	if not water_base.has(layer):
		var result := {}
		for record: Dictionary in package.water.layers:
			if int(record["index"]) == layer:
				for tile: Vector2 in record["tiles"]:
					result[int(tile.y) * package.water.width + int(tile.x)] = true
				break
		water_base[layer] = result
	return water_base[layer]


func water_effective_cover(layer: int) -> Dictionary:
	var result := water_base_cover(layer).duplicate()
	if water_edits.has(layer):
		for block: int in water_edits[layer]:
			if water_edits[layer][block]:
				result[block] = true
			else:
				result.erase(block)
	return result


func water_cover_count(layer: int) -> int:
	return water_effective_cover(layer).size()


func water_layer_height(layer: int) -> float:
	if water_heights.has(layer):
		return float(water_heights[layer])
	return Water.layer_height(package.water_bytes, layer)


func water_layers_effective() -> Array:
	var result: Array = []
	if package.water == null:
		return result
	for layer in WATER_LAYERS:
		var cover := water_effective_cover(layer)
		if cover.is_empty():
			continue
		var blocks := cover.keys()
		blocks.sort()
		var tiles := PackedVector2Array()
		for block: int in blocks:
			tiles.append(Vector2(block % package.water.width, block / package.water.width))
		result.append({"index": layer, "height": water_layer_height(layer), "tiles": tiles})
	return result


func set_water_height(layer: int, height: float, announce := true) -> bool:
	if not valid_water_layer(layer) or not is_finite(height) or absf(height) > Water.MAX_HEIGHT:
		return fail("Choose a water layer and a finite elevation within ±100000 m.")
	var before := water_layer_height(layer)
	if before == height:
		return true
	set_water_height_internal(layer, height)
	if announce:
		push_history({"water_height": layer, "before": before, "after": height})
	water_changed.emit()
	return true


func set_water_height_internal(layer: int, height: float) -> void:
	if height == Water.layer_height(package.water_bytes, layer):
		water_heights.erase(layer)
	else:
		water_heights[layer] = height


func set_water_cover(layer: int, block: int, value: bool) -> void:
	if water_base_cover(layer).get(block, false) == value:
		var record: Dictionary = water_edits.get(layer, {})
		record.erase(block)
		if record.is_empty():
			water_edits.erase(layer)
		else:
			water_edits[layer] = record
		return
	if not water_edits.has(layer):
		water_edits[layer] = {}
	water_edits[layer][block] = value


func begin_water_stroke() -> bool:
	if has_active_edit_transaction():
		return fail("Finish the current edit before painting water.")
	if has_preview():
		return fail("Clear the terrain preview before painting water.")
	water_stroke = {}
	water_stroke_active = true
	return true


func water_dab(point: Vector2, radius_m: float, layer: int, add: bool) -> void:
	if not water_stroke_active or not valid_water_layer(layer) or not is_finite(radius_m) or radius_m <= 0.0 or radius_m > 1024.0:
		return
	var water := package.water
	var block_m := Terrain.SPACING * Terrain.BLOCK
	var radius := radius_m / block_m
	var center := Vector2(point.x, point.y) / WATER_BLOCK
	var cover := water_effective_cover(layer)
	for block in water_block_count():
		var column := block % water.width
		var row := block / water.width
		var nearest := center.clamp(Vector2(column, row), Vector2(column + 1.0, row + 1.0))
		if center.distance_to(nearest) > radius:
			continue
		if not water_stroke.has(block):
			water_stroke[block] = cover.get(block, false)
		set_water_cover(layer, block, add)
	water_changed.emit()


func end_water_stroke(layer: int) -> void:
	if not water_stroke_active:
		return
	water_stroke_active = false
	if water_stroke.is_empty():
		return
	var after := {}
	for block: int in water_stroke:
		after[block] = water_effective_cover(layer).get(block, false)
	push_history({"water": layer, "before": water_stroke.duplicate(), "after": after})
	water_stroke = {}


func has_water_file_edits() -> bool:
	return not water_edits.is_empty() or not water_heights.is_empty()


func read_object_removals(saved: Variant) -> bool:
	if saved == null:
		saved = []
	if not saved is Array or saved.size() > package.objects.size() or object_removals.size() + saved.size() > package.objects.size():
		return fail("Invalid project object removals.")
	for value: Variant in saved:
		if not valid_native_integer(value):
			return fail("Invalid project object removal reference.")
		var index := int(value)
		if index < 0 or index >= package.objects.size() or object_removals.has(index):
			return fail("Invalid project object removal reference.")
		remove_base_object(index, false)
	return true


func read_object_additions(saved: Variant) -> bool:
	if not saved is Array or saved.size() > 8192 - package.objects.size():
		return fail("Invalid project object insertions.")
	for item: Variant in saved:
		if not item is Dictionary or not valid_object_insertion(item):
			return fail("Invalid project object insertion.")
		var addition: Dictionary = item.duplicate()
		addition["transform"] = Transform3D(read_saved_basis(item["basis"]), Vector3(item["position"][0], item["position"][1], item["position"][2]))
		next_object_id = maxi(next_object_id, int(item["id"]) + 1)
		object_additions.append(addition)
	return true


func valid_object_edit(index: int, fields: Dictionary) -> bool:
	var position: Variant = fields.get("position")
	if not position is Array or position.size() != 3:
		return false
	for value in position:
		if not (value is float or value is int) or not is_finite(value):
			return false
	if not valid_object_position(Vector3(position[0], position[1], position[2])):
		return false
	return valid_basis_array(fields.get("basis", []))


func valid_object_insertion(item: Dictionary) -> bool:
	var template: Variant = item.get("template")
	var is_native_class := bool(item.get("native_class", false))
	var index := -1
	if is_native_class:
		if not ((template is int or template is float) and is_finite(template) and int(template) == -1):
			return false
		var odf_v: Variant = item.get("odf", "")
		if not (odf_v is String) or not BznObjects.supports_native_new_class(String(odf_v), package.bzn_version):
			return false
		var team_v: Variant = item.get("team", 0)
		if not valid_native_integer(team_v) or int(team_v) < 0 or int(team_v) > 15:
			return false
	else:
		if not valid_native_integer(template):
			return false
		index = int(template)
		if index < 0 or index >= package.objects.size():
			return false
	if not valid_native_integer(item.get("sequence")) or not valid_native_integer(item.get("id")):
		return false
	if sequence_taken(int(item["sequence"])):
		return false
	var label: Variant = item.get("label", "")
	if not label is String or not valid_object_label(String(label)):
		return false
	return valid_object_edit(index, item)


func valid_basis_array(values: Variant) -> bool:
	if not values is Array or values.size() not in [0, 9]:
		return false
	for value in values:
		if not (value is float or value is int) or not is_finite(value):
			return false
	return true


func read_saved_basis(values: Variant) -> Basis:
	if values is Array and values.size() == 9:
		return Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8]))
	return Basis()


func object_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in package.objects.size():
		if not object_removals.has(index):
			result.append({"base": index})
	for slot in object_additions.size():
		result.append({"added": slot})
	return result


func object_stable_key_for_entry(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	if entry.has("added"):
		var slot := int(entry["added"])
		if slot >= 0 and slot < object_additions.size():
			return "obj:add:%d" % int(object_additions[slot].get("id", slot))
		return ""
	var base := int(entry.get("base", -1))
	return "obj:base:%d" % base if base >= 0 else ""


func object_stable_key(view: int) -> String:
	return object_stable_key_for_entry(object_entry(view))


func view_for_object_stable_key(key: String) -> int:
	if key.is_empty():
		return -1
	var entries := object_entries()
	for view in entries.size():
		if object_stable_key_for_entry(entries[view]) == key:
			return view
	return -1


func object_odf_for_entry(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	if entry.has("added"):
		var slot := int(entry["added"])
		if slot < 0 or slot >= object_additions.size():
			return ""
		var add: Dictionary = object_additions[slot]
		if add.has("odf") and not String(add["odf"]).is_empty():
			return String(add["odf"])
		var tpl_idx := int(add.get("template", -1))
		if object_odf_edits.has(tpl_idx):
			return String(object_odf_edits[tpl_idx])
		return String(package.objects[tpl_idx].get("odf", "")) if tpl_idx >= 0 and tpl_idx < package.objects.size() else ""
	var base := int(entry.get("base", -1))
	if base < 0 or base >= package.objects.size():
		return ""
	if object_odf_edits.has(base):
		return String(object_odf_edits[base])
	return String(package.objects[base].get("odf", ""))


func object_team_for_entry(entry: Dictionary) -> int:
	if entry.is_empty():
		return 0
	if entry.has("added"):
		var slot := int(entry["added"])
		if slot < 0 or slot >= object_additions.size():
			return 0
		var add: Dictionary = object_additions[slot]
		if add.has("team"):
			return int(add["team"])
		var tpl_idx := int(add.get("template", -1))
		return int(package.objects[tpl_idx].get("team", 0)) if tpl_idx >= 0 and tpl_idx < package.objects.size() else 0
	var base := int(entry.get("base", -1))
	return int(package.objects[base].get("team", 0)) if base >= 0 and base < package.objects.size() else 0


func object_label_for_entry(entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	if entry.has("added"):
		var slot := int(entry["added"])
		if slot < 0 or slot >= object_additions.size():
			return ""
		return String(object_additions[slot].get("label", ""))
	var base := int(entry.get("base", -1))
	if base < 0 or base >= package.objects.size():
		return ""
	if object_label_edits.has(base):
		return String(object_label_edits[base])
	return String(package.objects[base].get("label", ""))


func object_count() -> int:
	return package.objects.size() - object_removals.size() + object_additions.size()


func object_entry(view: int) -> Dictionary:
	if view < 0:
		return {}
	var entries := object_entries()
	return entries[view] if view < entries.size() else {}


func object_is_added(view: int) -> bool:
	return view >= 0 and object_entry(view).has("added")


func object_addition(view: int) -> Dictionary:
	var entry := object_entry(view)
	var slot: int = entry.get("added", -1)
	return object_additions[slot] if slot >= 0 and slot < object_additions.size() else {}


func object_template(view: int) -> Dictionary:
	var entry := object_entry(view)
	if entry.has("added"):
		var template: int = int(object_addition(view)["template"])
		return package.objects[template] if template >= 0 and template < package.objects.size() else {}
	if entry.is_empty():
		return {}
	return package.objects[int(entry["base"])]


func object_actual_index(view: int) -> int:
	var entry := object_entry(view)
	return int(entry["base"]) if not entry.is_empty() else -1


func object_position(view: int) -> Vector3:
	if object_is_added(view):
		return object_addition(view)["transform"].origin
	var base := object_actual_index(view)
	if base < 0:
		return Vector3.INF
	var edit: Dictionary = object_edits.get(base, {})
	if edit.is_empty():
		return package.objects[base]["transform"].origin
	return Transform3D(edit["basis"], edit["position"]).origin


func object_transform(view: int) -> Transform3D:
	if object_is_added(view):
		return object_addition(view)["transform"]
	var base := object_actual_index(view)
	if base < 0:
		return Transform3D()
	var edit: Dictionary = object_edits.get(base, {})
	if edit.is_empty():
		return package.objects[base]["transform"]
	return Transform3D(edit["basis"], edit["position"])


func object_odf(view: int) -> String:
	if object_is_added(view):
		var add := object_addition(view)
		if add.has("odf") and not String(add["odf"]).is_empty():
			return String(add["odf"])
		var tpl_idx := int(add.get("template", -1))
		if object_odf_edits.has(tpl_idx):
			return String(object_odf_edits[tpl_idx])
	else:
		var base := object_actual_index(view)
		if object_odf_edits.has(base):
			return String(object_odf_edits[base])
	return String(object_template(view).get("odf", ""))


func set_base_object_odf(base: int, new_odf: String) -> void:
	if base < 0 or base >= package.objects.size():
		return
	var orig := String(package.objects[base].get("odf", ""))
	if orig == new_odf or new_odf.is_empty():
		object_odf_edits.erase(base)
	else:
		object_odf_edits[base] = new_odf


func convert_objects_to_profile(target_mod_id: String, target_mission_id: String = "", manual_map: Dictionary = {}, allow_drop_vrv: bool = false) -> Dictionary:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit before converting objects.")
		return {"ok": false, "error": error}
	var tgt_mod := target_mod_id.strip_edges().to_lower()
	var tgt_mis := target_mission_id.strip_edges().to_lower() if not target_mission_id.strip_edges().is_empty() else mission_profile
	if not valid_mod_profile_id(tgt_mod) or not valid_mission_profile_id(tgt_mis):
		fail("Invalid target profile identifiers for conversion.")
		return {"ok": false, "error": error}
	var effective_entries: Array = []
	var base_for_slot: Array[int] = []
	for base in package.objects.size():
		if object_removals.has(base):
			continue
		var entry: Dictionary = package.objects[base].duplicate(true)
		if object_odf_edits.has(base):
			entry["odf"] = String(object_odf_edits[base])
		if object_label_edits.has(base):
			entry["label"] = String(object_label_edits[base])
		effective_entries.append(entry)
		base_for_slot.append(base)
	var ptr_counts := path_pointer_counts()
	var plan := ModRegistry.plan_bzn_odf_conversion(effective_entries, ptr_counts, tgt_mod, manual_map, allow_drop_vrv)
	if not bool(plan.get("ok", false)):
		var msg := "; ".join(plan.get("unsupported", ["Unsupported ODF conversion"]))
		fail(msg)
		return {"ok": false, "error": msg, "plan": plan}
	var before_state := {
		"engine": engine_profile,
		"mod": mod_profile,
		"mission": mission_profile,
		"explicit": profile_explicit,
		"odf_edits": object_odf_edits.duplicate(),
		"removals": object_removals.duplicate(),
		"has_dll": has_mission_dll_override,
		"dll": mission_dll_override,
	}
	var next_odf_edits := object_odf_edits.duplicate()
	var plan_edits: Dictionary = plan["odfEdits"]
	for slot_idx: int in plan_edits:
		var base_idx := base_for_slot[slot_idx]
		var next_odf := String(plan_edits[slot_idx])
		if String(package.objects[base_idx].get("odf", "")) == next_odf:
			next_odf_edits.erase(base_idx)
		else:
			next_odf_edits[base_idx] = next_odf
	var next_removals := object_removals.duplicate()
	for slot_idx: int in plan["removals"]:
		next_removals[base_for_slot[slot_idx]] = true
	var next_has_dll := has_mission_dll_override
	var next_dll := mission_dll_override
	if tgt_mis != "custom-dll":
		var expected_dll := String(MissionProfiles.expected_dll(tgt_mis, tgt_mod)).strip_edges()
		var base_dll := String(package.mission_dll) if package != null else ""
		next_has_dll = expected_dll != base_dll
		next_dll = expected_dll if next_has_dll else ""
	var after_state := {
		"engine": engine_profile,
		"mod": tgt_mod,
		"mission": tgt_mis,
		"explicit": true,
		"odf_edits": next_odf_edits,
		"removals": next_removals,
		"has_dll": next_has_dll,
		"dll": next_dll,
	}
	if before_state != after_state:
		push_history({"profile_conversion": true, "before": before_state, "after": after_state})
		_apply_profile_conversion(after_state)
	return {"ok": true, "error": "", "plan": plan, "replacedCount": plan_edits.size(), "removedCount": (plan["removals"] as Array).size()}


func _apply_profile_conversion(state: Dictionary) -> void:
	engine_profile = String(state["engine"])
	mod_profile = String(state["mod"])
	mission_profile = String(state["mission"])
	profile_explicit = bool(state["explicit"])
	object_odf_edits = (state["odf_edits"] as Dictionary).duplicate()
	object_removals = (state["removals"] as Dictionary).duplicate()
	has_mission_dll_override = bool(state.get("has_dll", false))
	mission_dll_override = String(state.get("dll", ""))
	objects_changed.emit()
	profile_changed.emit()


func object_label(view: int) -> String:
	if object_is_added(view):
		return String(object_addition(view).get("label", ""))
	var base := object_actual_index(view)
	if object_label_edits.has(base):
		return String(object_label_edits[base])
	return String(object_template(view).get("label", ""))


func object_team(view: int) -> int:
	if object_is_added(view):
		var add := object_addition(view)
		if add.has("team"):
			return int(add["team"])
	return int(object_template(view).get("team", 0))


func object_sequence(view: int) -> int:
	var seq := int(object_addition(view).get("sequence", 0)) if object_is_added(view) else int(object_template(view).get("sequence", 0))
	var lbl := object_label(view)
	if not lbl.is_empty():
		return seq & ~0x800000
	if object_is_added(view) or object_label_edits.has(object_actual_index(view)):
		return seq | 0x800000
	return seq


func object_pool_reference(view: int) -> int:
	# The base object that supplies the mesh, team and pool for this view.
	var entry := object_entry(view)
	if entry.is_empty():
		return -1
	if entry.has("added"):
		return int(object_addition(view).get("template", -1))
	return int(entry["base"])


func has_object_file_edits() -> bool:
	return not object_edits.is_empty() or not object_label_edits.is_empty() or not object_odf_edits.is_empty() or not object_removals.is_empty() or not object_additions.is_empty()


func move_object(view: int, position: Vector3) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if not valid_view_object(view) or not valid_object_position(position):
		return fail("Choose a finite object position on the terrain.")
	var before := object_transform(view)
	var after := Transform3D(before.basis, position)
	if before == after:
		return true
	push_history({"object": object_history_key(view), "before": before, "after": after})
	set_object_transform(view, after)
	return true


func move_objects_batch(views: Array[int], delta: Vector3) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if views.is_empty() or not delta.is_finite():
		return fail("Select one or more objects and a finite offset.")
	var unique_views: Array[int] = []
	var seen := {}
	for v in views:
		if seen.has(v):
			continue
		if not valid_view_object(v):
			return fail("Selection contains an invalid object index.")
		seen[v] = true
		unique_views.append(v)
	if unique_views.is_empty():
		return fail("Select one or more valid objects.")
	if delta.length_squared() <= 1e-10:
		return true
	var batch: Array[Dictionary] = []
	for v in unique_views:
		var before := object_transform(v)
		var next_pos := before.origin + delta
		if not valid_object_position(next_pos):
			return fail("Group move places object #%d outside the supported terrain bounds." % v)
		var after := Transform3D(before.basis, next_pos)
		if before != after:
			batch.append({"key": object_history_key(v), "before": before, "after": after})
	if batch.is_empty():
		return true
	push_history({"object_batch": batch})
	for item: Dictionary in batch:
		apply_object_transform(item["key"], item["after"])
	return true


func rotate_object(view: int, radians: float) -> bool:
	if stroke_active or has_preview() or not valid_view_object(view) or not is_finite(radians):
		return fail("Select an object and finish other terrain edits first.")
	var before := object_transform(view)
	if not before.basis.is_finite():
		return fail("The object basis is not finite.")
	var rotated := before.basis.rotated(Vector3.UP, radians)
	var after := Transform3D(rotated, before.origin)
	if before == after:
		return true
	push_history({"object": object_history_key(view), "before": before, "after": after})
	set_object_transform(view, after)
	return true


func sequence_taken(sequence: int) -> bool:
	for entry in package.objects:
		if int(entry["sequence"]) == sequence:
			return true
	for addition in object_additions:
		if int(addition["sequence"]) == sequence:
			return true
	return false


func fresh_sequence(template: Dictionary) -> int:
	var mask := int(template["sequence"]) & 0x800000
	var low := int(template["sequence"]) & 0x7fffff
	for entry in package.objects:
		low = maxi(low, int(entry["sequence"]) & 0x7fffff)
	for addition in object_additions:
		low = maxi(low, int(addition["sequence"]) & 0x7fffff)
	for attempt in 65535:
		var candidate := (low + 1 + attempt) & 0x7fffff
		if not sequence_taken(candidate | mask):
			return candidate | mask
	return -1


func copy_label(template: Dictionary) -> String:
	var label: String = template.get("label", "")
	if label == "":
		return ""
	for suffix in range(2, 999):
		var candidate := label + "_" + str(suffix)
		if candidate.length() > 128:
			candidate = label.substr(0, maxf(1, 128 - str(suffix).length() - 1)) + "_" + str(suffix)
		if not label_taken(candidate):
			return candidate
	return label


func label_taken(label: String) -> bool:
	for entry in package.objects:
		if String(entry["label"]) == label:
			return true
	for addition in object_additions:
		if String(addition["label"]) == label:
			return true
	return false


func fresh_sequence_for_new(auto_label: bool = true) -> int:
	var mask := 0x800000 if auto_label else 0
	var low := 1
	for entry in package.objects:
		low = maxi(low, int(entry["sequence"]) & 0x7fffff)
	for addition in object_additions:
		low = maxi(low, int(addition["sequence"]) & 0x7fffff)
	for attempt in 65535:
		var candidate := (low + 1 + attempt) & 0x7fffff
		if candidate > 0 and not sequence_taken(candidate | mask) and not sequence_taken(candidate | (0 if auto_label else 0x800000)):
			return candidate | mask
	return -1


func place_native_object(odf: String, position: Vector3, team: int = -1, label: String = "") -> int:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return -1
	if not valid_object_position(position):
		fail("Choose a finite object position on the terrain.")
		return -1
	if object_count() >= 8192:
		fail("Object count has reached the native BZN limit (8192).")
		return -1
	var count_cap := Layouts.capability_status(package.layout_id, Layouts.EDIT_OBJECT_COUNT)
	if not (count_cap in ["NATIVE", "BAKED"]):
		fail("Native object insertion is not supported on BZN layout %s (%s)." % [package.layout_id, count_cap])
		return -1
	if not BznObjects.supports_native_new_class(odf, package.bzn_version):
		fail("No verified class-specific native BZN builder exists for '%s' on BZN %d." % [odf, package.bzn_version])
		return -1
	var clean_label := label.strip_edges()
	if not valid_object_label(clean_label):
		fail("Choose a valid ASCII label of at most 128 characters.")
		return -1
	var spec := BznObjects.native_class_spec(odf)
	var canonical_odf := String(spec["odf"])
	var chosen_team := clampi(team if team >= 0 else int(spec.get("defaultTeam", 0)), 0, 15)
	var sequence := fresh_sequence_for_new(clean_label.is_empty())
	if sequence < 0:
		fail("No unused native object sequence is available.")
		return -1
	var addition := {
		"id": next_object_id,
		"template": -1,
		"native_class": true,
		"builder": String(spec["builder"]),
		"odf": canonical_odf,
		"team": chosen_team,
		"label": clean_label,
		"sequence": sequence,
		"position": [position.x, position.y, position.z],
		"basis": [],
		"transform": Transform3D(Basis.IDENTITY, position),
	}
	push_history({"object_add": addition, "slot": object_additions.size()})
	object_additions.append(addition)
	next_object_id += 1
	objects_changed.emit()
	return object_count() - 1


func duplicate_object(view: int, position: Vector3, label_override: Variant = null) -> int:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return -1
	if not valid_view_object(view) or not valid_object_position(position):
		fail("Choose a finite object position on the terrain.")
		return -1
	if object_count() >= 8192:
		fail("Object count has reached the native BZN limit (8192).")
		return -1
	if label_override != null and (not (label_override is String) or not valid_object_label(String(label_override))):
		fail("Choose a valid ASCII label of at most 128 characters.")
		return -1
	if object_is_added(view) and bool(object_addition(view).get("native_class", false)):
		var src_add := object_addition(view)
		var next_lbl := String(label_override) if label_override != null else copy_label({"label": String(src_add.get("label", ""))})
		var placed := place_native_object(String(src_add["odf"]), position, int(src_add.get("team", 0)), next_lbl)
		if placed >= 0:
			var src_xf := object_transform(view)
			object_addition(placed)["transform"] = Transform3D(src_xf.basis, position)
		return placed
	var template := object_template(view)
	if template.is_empty():
		fail("Missing native object template.")
		return -1
	var sequence := fresh_sequence(template)
	if sequence < 0:
		fail("No unused native object sequence is available.")
		return -1
	var entry := object_entry(view)
	var template_base := int(object_addition(view)["template"]) if entry.has("added") else int(entry["base"])
	if template_base < 0 or template_base >= package.objects.size():
		fail("Missing native object template.")
		return -1
	var chosen_label := String(label_override) if label_override != null else copy_label(template)
	var addition := {"id": next_object_id, "template": template_base,
		"label": chosen_label, "sequence": sequence, "position": [0.0, 0.0, 0.0], "basis": []}
	var transform := object_transform(view)
	addition["transform"] = Transform3D(transform.basis, position)
	push_history({"object_add": addition, "slot": object_additions.size()})
	object_additions.append(addition)
	next_object_id += 1
	objects_changed.emit()
	return object_count() - 1


func duplicate_sound_point(view: int, position: Vector3, sound_label: String) -> int:
	if stroke_active or has_preview():
		fail("Finish the current terrain edit first.")
		return -1
	if not valid_view_object(view):
		fail("Select an existing %s sound point first." % SOUND_POINT_ODF)
		return -1
	if not object_is_sound_point(view):
		fail("Object #%d (%s) is not a %s sound point. Only %s objects can be duplicated as sound points." % [
			view, object_odf(view), SOUND_POINT_ODF, SOUND_POINT_ODF])
		return -1
	if sound_point(sound_label).is_empty():
		fail("Invalid VRV sound point label syntax.")
		return -1
	return duplicate_object(view, position, sound_label)


func remove_object(view: int) -> bool:
	if stroke_active or has_preview() or not valid_view_object(view):
		return fail("Select an object and finish the current terrain edit first.")
	var entry := object_entry(view)
	if entry.has("added"):
		var slot: int = int(entry["added"])
		var addition: Dictionary = object_additions[slot]
		push_history({"object_add_removed": addition, "slot": slot})
		object_additions.remove_at(slot)
		objects_changed.emit()
		return true
	var base := int(entry["base"])
	push_history({"object_remove": base})
	remove_base_object(base, true)
	return true


func remove_base_object(base: int, announce: bool) -> void:
	object_removals[base] = true
	if announce:
		objects_changed.emit()


func valid_view_object(view: int) -> bool:
	return view >= 0 and view < object_count()


func object_history_key(view: int) -> Variant:
	if object_is_added(view):
		return "add:%d" % int(object_addition(view)["id"])
	return object_actual_index(view)


static func addition_history_id(key: Variant) -> int:
	if key is String and String(key).begins_with("add:"):
		return String(key).substr(4).to_int()
	return int(key)


func set_object_transform(view: int, transform: Transform3D) -> void:
	if object_is_added(view):
		var addition := object_addition(view)
		addition["transform"] = transform
		object_moved.emit(view)
		return
	var base := object_actual_index(view)
	if package.objects[base]["transform"] == transform:
		object_edits.erase(base)
	else:
		object_edits[base] = {"basis": transform.basis, "position": transform.origin}
	object_moved.emit(view)


func set_object_edit(base: int, transform: Transform3D) -> void:
	if package.objects[base]["transform"] == transform:
		object_edits.erase(base)
	else:
		object_edits[base] = {"basis": transform.basis, "position": transform.origin}
	object_moved.emit(base)


func object_export_edits() -> Dictionary:
	var result := {}
	for base: int in object_edits:
		result[base] = Transform3D(object_edits[base]["basis"], object_edits[base]["position"])
	return result


func set_object_label(view: int, new_label: String) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if not valid_view_object(view) or not valid_object_label(new_label):
		return fail("Select a valid object with an ASCII label of at most 128 characters.")
	var before := object_label(view)
	if before == new_label:
		return true
	var key: Variant = object_history_key(view)
	push_history({"object_label": key, "before": before, "after": new_label})
	apply_object_label(key, new_label)
	return true


func set_sound_point_label(view: int, new_label: String) -> bool:
	if stroke_active or has_preview():
		return fail("Finish the current terrain edit first.")
	if not valid_view_object(view):
		return fail("Select an existing %s sound point first." % SOUND_POINT_ODF)
	if not object_is_sound_point(view):
		return fail("Object #%d (%s) is not a %s sound point. Use Object Label for ordinary object names." % [
			view, object_odf(view), SOUND_POINT_ODF])
	if sound_point(new_label).is_empty():
		return fail("Invalid VRV sound point label syntax.")
	return set_object_label(view, new_label)


func set_base_object_label(base: int, new_label: String) -> void:
	if String(package.objects[base].get("label", "")) == new_label:
		object_label_edits.erase(base)
	else:
		object_label_edits[base] = new_label


func apply_object_label(key: Variant, new_label: String) -> void:
	if key is int and key >= 0 and key < package.objects.size():
		set_base_object_label(int(key), new_label)
		object_moved.emit(view_for_base(int(key)))
		return
	var target_id := addition_history_id(key)
	for addition in object_additions:
		if int(addition["id"]) == target_id:
			addition["label"] = new_label
			object_moved.emit(find_object_view(addition))
			return


func apply_object_transform(key: Variant, transform: Transform3D) -> void:
	if key is int and key >= 0 and key < package.objects.size():
		if package.objects[key]["transform"] == transform:
			object_edits.erase(key)
		else:
			object_edits[key] = {"basis": transform.basis, "position": transform.origin}
		object_moved.emit(view_for_base(int(key)))
		return
	var target_id := addition_history_id(key)
	for addition in object_additions:
		if int(addition["id"]) == target_id:
			addition["transform"] = transform
			object_moved.emit(find_object_view(addition))
			return


func view_for_base(base: int) -> int:
	var entries := object_entries()
	for view in entries.size():
		if int(entries[view].get("base", -1)) == base:
			return view
	return -1


func find_object_view(addition: Dictionary) -> int:
	var entries := object_entries()
	for view in entries.size():
		if entries[view].has("added") and object_additions[int(entries[view]["added"])] == addition:
			return view
	return -1


func valid_object_position(position: Vector3) -> bool:
	var terrain := package.terrain
	var minimum := Vector2(terrain.origin) * terrain.SPACING
	var maximum := minimum + Vector2(terrain.dimensions - Vector2i.ONE) * terrain.SPACING
	return position.is_finite() and absf(position.y) <= MAX_EDITOR_ABS_HEIGHT and position.x >= minimum.x and position.x <= maximum.x and position.z >= minimum.y and position.z <= maximum.y


func preview_slope_plane(center: Vector2i, radius_m: float, height: float, grade: Vector2) -> bool:
	var terrain := package.terrain
	var bounds := Rect2i(Vector2i.ZERO, terrain.dimensions)
	if stroke_active or not bounds.has_point(center) or not grade.is_finite() or not is_finite(height):
		return fail("Finish the stroke and choose a finite slope anchored inside the map.")
	var region := brush_region(Vector2(center), radius_m)
	if not region.has_area():
		return fail("Choose a valid slope radius.")
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var values := {}
	var native_sample := PackedFloat32Array([0.0])
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var offset := Vector2(Vector2i(x, z) - center) * Terrain.SPACING
			if offset.length_squared() > radius_m * radius_m:
				continue
			var value := snappedf(height + offset.dot(grade), package.granularity)
			if not is_finite(value) or absf(value) > limit:
				return fail("The slope plane exceeds the terrain height range.")
			var index := z * terrain.dimensions.x + x
			native_sample[0] = value
			if native_sample[0] != preview_before.get(index, terrain.heights[index]):
				values[index] = native_sample[0]
	show_preview(values)
	return true


func preview_slope_shape(params: Dictionary, batch := {}) -> bool:
	## Advanced sculptor preview: every batch instance evaluates deterministically
	## against the heights before the batch, then the merged result goes through
	## the shared preview/bake pipeline (one undo step per apply).
	if stroke_active:
		return fail("Finish the stroke before shaping terrain.")
	clear_preview()
	var terrain := package.terrain
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var checked_params := params.duplicate()
	checked_params["max_abs_height"] = limit
	var built := SlopeShapes.instances_checked(checked_params, batch)
	if not String(built["error"]).is_empty():
		return fail(String(built["error"]))
	var values := {}
	for instance: Dictionary in built["instances"]:
		var shaped: Dictionary = SlopeShapes.evaluate(instance, terrain.dimensions, terrain.origin, terrain.heights)
		if not String(shaped["error"]).is_empty():
			return fail(shaped["error"])
		for index in shaped["values"]:
			values[index] = shaped["values"][index]
	if values.is_empty():
		return fail("The shape covers no terrain samples. Check start, end, width and masks.")
	var native_sample := PackedFloat32Array([0.0])
	for index in values:
		var value := float(values[index])
		if not is_finite(value) or absf(value) > limit:
			return fail("The shape exceeds the terrain height range.")
		native_sample[0] = value
		values[index] = native_sample[0]
	return show_preview(values)


func preview_vrv_shape(op: String, params: Dictionary, region: Rect2i = Rect2i()) -> bool:
	if stroke_active:
		return fail("Finish the stroke before shaping terrain.")
	clear_preview()
	var terrain := package.terrain
	var limit := minf(MAX_EDITOR_ABS_HEIGHT, package.granularity * 32000.0)
	var strength := clampi(int(params.get("strength", 35)), 0, 100)
	var grain_m := clampi(int(params.get("grain_m", 16)), 2, 64)
	var values: Dictionary = {}
	match op:
		"smooth":
			values = VrvShapes.smooth(terrain.heights, terrain.dimensions, region, strength, grain_m, package.granularity, limit)
		"rough_plus", "rough_minus":
			values = VrvShapes.rough(
				terrain.heights, terrain.dimensions, terrain.origin, region,
				strength, grain_m,
				clampi(int(params.get("softness", 50)), 0, 100),
				clampi(int(params.get("contrast", 35)), 0, 100),
				int(params.get("seed", 1)),
				1 if op == "rough_plus" else -1,
				String(params.get("symmetry", "none")),
				package.granularity, limit
			)
		"relief_plus", "relief_minus":
			values = VrvShapes.relief(terrain.heights, terrain.dimensions, region, strength, 1 if op == "relief_plus" else -1, package.granularity, limit)
		_:
			return fail("Unsupported VRV terrain shape operation.")
	if values.is_empty():
		return fail("The selected VRV shape produced no height changes.")
	return show_preview(values)


func mirror_heights(direction: int) -> int:
	if stroke_active or has_preview() or direction not in MirrorDirection.values():
		fail("Finish the current preview or stroke and choose a mirror direction.")
		return -1
	var terrain := package.terrain
	var size := terrain.dimensions
	var half := size / 2
	var region: Rect2i
	match direction:
		MirrorDirection.MIN_X_TO_MAX_X:
			region = Rect2i(half.x, 0, size.x - half.x, size.y)
		MirrorDirection.MAX_X_TO_MIN_X:
			region = Rect2i(0, 0, half.x, size.y)
		MirrorDirection.MIN_Z_TO_MAX_Z:
			region = Rect2i(0, half.y, size.x, size.y - half.y)
		MirrorDirection.MAX_Z_TO_MIN_Z:
			region = Rect2i(0, 0, size.x, half.y)
	var across_x := direction == MirrorDirection.MIN_X_TO_MAX_X or direction == MirrorDirection.MAX_X_TO_MIN_X
	var before := {}
	var after := {}
	for z in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var index := z * size.x + x
			var opposite := z * size.x + size.x - 1 - x if across_x else (size.y - 1 - z) * size.x + x
			if terrain.heights[index] != terrain.heights[opposite]:
				if absf(terrain.heights[opposite]) > MAX_EDITOR_ABS_HEIGHT:
					fail("The source half contains a sample outside the editable height range.")
					return -1
				before[index] = terrain.heights[index]
				after[index] = terrain.heights[opposite]
	if not after.is_empty():
		apply(after)
		record_change(before, after)
	return after.size()


func has_preview() -> bool:
	return not preview_after.is_empty() or not package.terrain.material_previews.is_empty()


## A composition can be logically active while its buffer is empty (e.g. a
## default-zero mask composes to nothing). Ownership survives that state, so
## admission checks use this predicate instead of has_preview() alone: an
## empty composition must never be silently captured by another tool.
func has_active_preview_context() -> bool:
	if package == null:
		return false
	return has_preview() or _sculpt_composition_active or _color_composition_active


func valid_preview(values: Dictionary, materials: Dictionary) -> bool:
	var terrain := package.terrain
	for index: Variant in values:
		var value: Variant = values[index]
		if not index is int or index < 0 or index >= terrain.heights.size() or not (value is float or value is int) or not is_finite(value) or absf(value) > MAX_EDITOR_ABS_HEIGHT:
			return false
	for layer: Variant in materials:
		if layer not in [Terrain.Layer.COLOR, Terrain.Layer.TILES] or not materials[layer] is Dictionary:
			return false
		var tiles: bool = layer == Terrain.Layer.TILES
		var limit := terrain.block_offsets.size() - 1 if tiles else terrain.heights.size()
		for index: Variant in materials[layer]:
			var value: Variant = materials[layer][index]
			if not index is int or index < 0 or index >= limit or not value is int or value < 0 or value > (0xffff if tiles else 0xffffff):
				return false
			if tiles and (value & 0xfff0) != (terrain.committed_material_value(layer, index) & 0xfff0):
				return false
	return true


func document_id_source_revision() -> String:
	if package == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(JSON.stringify(package.files).to_utf8_buffer())
	return context.finish().hex_encode()


func show_preview(values: Dictionary, materials := {}, owner := "") -> bool:
	if has_active_edit_transaction() or not valid_preview(values, materials):
		return fail("Finish the active stroke before showing a terrain preview.")
	clear_preview()
	error = ""
	preview_owner = owner
	preview_source_revision = document_id_source_revision()
	preview_sculpt_revision = sculpt_revision if owner == "sculpt" else -1
	_sculpt_composition_active = owner == "sculpt"
	var terrain := package.terrain
	var native_sample := PackedFloat32Array([0.0])
	for index: int in values:
		native_sample[0] = values[index]
		if native_sample[0] != terrain.heights[index]:
			preview_before[index] = terrain.heights[index]
			preview_after[index] = native_sample[0]
	for layer: int in materials:
		var changes := {}
		for index: int in materials[layer]:
			if materials[layer][index] != terrain.committed_material_value(layer, index):
				changes[index] = materials[layer][index]
		if not changes.is_empty():
			terrain.material_previews[layer] = changes
	apply(preview_after, false)
	for layer: int in terrain.material_previews:
		refresh_materials(layer, terrain.material_previews[layer])
	return true


func clear_preview() -> void:
	var heights := preview_before
	preview_before = {}
	preview_after = {}
	preview_owner = ""
	_color_composition_active = false
	_sculpt_composition_active = false
	preview_source_revision = ""
	preview_sculpt_revision = -1
	var materials := package.terrain.material_previews
	package.terrain.material_previews = {}
	apply(heights, false)
	for layer: int in materials:
		refresh_materials(layer, materials[layer])


func bake_preview(staged_layers: Array = [], staged_uids: Array[int] = []) -> bool:
	if not has_preview():
		return fail("Create a terrain preview before baking.")
	var terrain := package.terrain
	var materials := terrain.material_previews
	if not valid_preview(preview_after, materials):
		return fail("Invalid terrain preview.")
	var commit_layers := false
	var before_layers: Array = []
	var after_layers: Array = []
	var before_uids: Array[int] = []
	var after_uids: Array[int] = []
	if not staged_layers.is_empty():
		var graph := Graph.new()
		if not graph.validate_stack(staged_layers):
			return fail(graph.error)
		ensure_layer_uids()
		before_layers = _normalized_layer_stack(layers)
		before_uids = layer_uids.duplicate()
		after_layers = _normalized_layer_stack(staged_layers)
		if staged_uids.size() == after_layers.size():
			var seen := {}
			for uid in staged_uids:
				var clean_uid := int(uid)
				if clean_uid <= 0 or seen.has(clean_uid):
					clean_uid = next_layer_id
					next_layer_id += 1
				seen[clean_uid] = true
				after_uids.append(clean_uid)
				next_layer_id = maxi(next_layer_id, clean_uid + 1)
		else:
			for i in after_layers.size():
				if i < before_uids.size():
					after_uids.append(before_uids[i])
				else:
					after_uids.append(next_layer_id)
					next_layer_id += 1
		commit_layers = (before_layers != after_layers or before_uids != after_uids)
	var after := preview_after
	var history := {"before": preview_before, "after": after, "materials": {}}
	if commit_layers:
		history["layers_before"] = before_layers.duplicate(true)
		history["layers_after"] = after_layers.duplicate(true)
		history["uids_before"] = before_uids.duplicate()
		history["uids_after"] = after_uids.duplicate()
	terrain.material_previews = {}
	for layer: int in materials:
		var previous := {}
		for index: int in materials[layer]:
			previous[index] = terrain.committed_material_value(layer, index)
		history["materials"][layer] = {"before": previous, "after": materials[layer]}
	preview_before = {}
	preview_after = {}
	push_history(history)
	apply_channels(after, materials)
	if commit_layers:
		_apply_procedural_layers(after_layers, after_uids, -1)
	return true


func apply_channels(heights: Dictionary, materials: Dictionary) -> void:
	var terrain := package.terrain
	for layer: int in materials:
		for index: int in materials[layer]:
			terrain.set_material(layer, index, materials[layer][index])
	apply(heights)
	for layer: int in materials:
		refresh_materials(layer, materials[layer])


func apply(values: Dictionary, commit := true) -> void:
	if values.is_empty():
		return
	var dimensions := package.terrain.dimensions
	var low := dimensions
	var high := Vector2i.ZERO
	for index: int in values:
		var point := Vector2i(index % dimensions.x, index / dimensions.x)
		low = low.min(point)
		high = high.max(point)
		if commit:
			set_height(index, values[index])
		else:
			package.terrain.heights[index] = values[index]
	terrain_changed.emit(Rect2i(low, high - low + Vector2i.ONE))


func set_height(index: int, value: float) -> void:
	package.terrain.heights[index] = value
	var stored := package.terrain.heights[index]
	if stored == base_heights[index]:
		edits.erase(index)
	else:
		edits[index] = stored


func fail(message: String) -> bool:
	error = message
	return false
