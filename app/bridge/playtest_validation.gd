extends RefCounted

const Package := preload("res://formats/map_package.gd")
const Layouts := preload("res://formats/bzn_layouts.gd")
const ModRegistry := preload("res://core/mod_registry.gd")
const CompatibilityEngine := preload("res://core/compatibility_engine.gd")


static func validate(mission: String, options: Dictionary = {}) -> Dictionary:
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
	var odfs: Array[String] = []
	var seen_odfs := {}
	for object: Dictionary in package.objects:
		var sequence: int = object["sequence"]
		if sequences.has(sequence):
			return {"error": "The BZN object table contains duplicate sequence numbers."}
		sequences[sequence] = true
		var raw_odf := String(object.get("odf", "")).strip_edges()
		if not raw_odf.is_empty():
			var odf_file := raw_odf if raw_odf.to_lower().ends_with(".odf") else raw_odf + ".odf"
			var key := odf_file.to_lower()
			if not seen_odfs.has(key):
				seen_odfs[key] = true
				odfs.append(odf_file)
	odfs.sort()
	if not package.check_sources():
		return {"error": package.error}

	var result := {"route": route, "version": version, "files": package.files, "odfs": odfs}
	if not options.is_empty():
		var game_dir := String(options.get("game", "")).strip_edges()
		var vrv_dir := String(options.get("vrv", "")).strip_edges()
		var mod_id := String(options.get("mod", "")).strip_edges().to_lower()
		var mis_id := String(options.get("mission", "")).strip_edges().to_lower()
		var asset_profile := String(options.get("asset_profile", "")).strip_edges()
		var extra_roots: Array = options.get("asset_roots", [])
		var noscript := bool(options.get("noscript", false))
		var reg := ModRegistry.new()
		if not game_dir.is_empty():
			reg.discover_installed(game_dir, vrv_dir)
		var detected := ModRegistry.detect_map_profiles(package, reg)
		if mod_id.is_empty():
			mod_id = String(detected.get("recommendedMod", "stock"))
		if mis_id.is_empty():
			mis_id = String(detected.get("recommendedMission", "blank"))
		var compat := CompatibilityEngine.evaluate(
			package, reg, mod_id, mis_id, "bzcc-2.0.185",
			game_dir, vrv_dir, {}, noscript, null, asset_profile, extra_roots)
		result["compatibility"] = compat
	return result
