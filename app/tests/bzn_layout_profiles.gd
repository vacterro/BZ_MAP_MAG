extends SceneTree

const Layouts := preload("res://formats/bzn_layouts.gd")
const Codec := preload("res://formats/bzn_paths.gd")
const Objects := preload("res://formats/bzn_objects.gd")
const Package := preload("res://formats/map_package.gd")
const HEADER_DIGITS_AT := 15
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 6:
		printerr("Pass Brave, blank, Terrace 2, Volcano and text Bolt BZNs plus a scratch directory.")
		quit(2)
		return
	var brave := FileAccess.get_file_as_bytes(args[0])
	var blank := FileAccess.get_file_as_bytes(args[1])
	var terrace := FileAccess.get_file_as_bytes(args[2])
	var volcano := FileAccess.get_file_as_bytes(args[3])
	var bolt := FileAccess.get_file_as_bytes(args[4])
	if brave.is_empty() or blank.is_empty() or terrace.is_empty() or volcano.is_empty() or bolt.is_empty():
		printerr("Could not read the supplied BZN fixtures.")
		quit(2)
		return
	var sources: Array[String] = [args[0], args[1], args[2], args[3], args[4]]
	var originals: Array[PackedByteArray] = [brave, blank, terrace, volcano, bolt]

	# --- Positive recognition of every verified layout ---
	check_recognized(brave, "binary-1196", 1196, "binary", "Brave Lil Toaster")
	check_recognized(blank, "binary-1192", 1192, "binary", "blank map")
	check_recognized(terrace, "binary-1197", 1197, "binary", "VSR Terrace 2")
	check_recognized(volcano, "binary-1197", 1197, "binary", "AdMemorium Volcano")
	check_recognized(bolt, "text-1200", 1200, "text", "Bolt")

	# --- Negative recognition: malformed, truncated and marker-less samples ---
	var rejected: Array[PackedByteArray] = [
		PackedByteArray(),
		brave.slice(0, 4),
		brave.slice(0, 30),
		PackedByteArray("garbage bytes with no header at all".to_ascii_buffer()),
		PackedByteArray("version [1] =\n1196\n".to_ascii_buffer()),
		PackedByteArray("version [1] =\n1196\nsaveType [1] =\n0\nbinarySave [1] =\nmaybe\n".to_ascii_buffer()),
	]
	for index in rejected.size():
		var result: Dictionary = Layouts.recognize(rejected[index])
		check(result["profile"].is_empty(), "refuse recognition of malformed sample %d (%s)" % [index, result["reason"]])

	# A spoofed header number only changes the header-shape class. It never
	# grants capabilities: the codecs still consult the registry per version.
	var spoof_1197 := renumber(brave, "1197")
	check(String(Layouts.recognize(spoof_1197)["profile"]) == "binary-1197",
		"a renumbered header classifies by header shape only")
	var spoof_1199 := renumber(brave, "1199")
	check(Layouts.recognize(spoof_1199)["profile"].is_empty(),
		"refuse an unregistered header version (reason: %s)" % String(Layouts.recognize(spoof_1199)["reason"]))
	var spoof_paths := Codec.new()
	check(spoof_paths.read(spoof_1197, 1197),
		"a renumbered Brave still decodes its shared binary path framing under 1197")
	check(not Objects.new().read(spoof_1197, 1197, spoof_paths.table_start),
		"object edits are refused for a spoofed 1197 header by capability")

	# --- Capability classification follows recorded evidence, not the number ---
	check(Layouts.capability_status("binary-1192", Layouts.INSPECT_PATHS) == "NATIVE", "1192 path inspection is NATIVE")
	check(Layouts.capability_status("binary-1192", Layouts.ENGINE_PLAYTEST) == "NATIVE", "1192 native playtest is NATIVE")
	check(Layouts.capability_status("binary-1192", Layouts.CONVERT_TO_185) == "UNSUPPORTED", "1192 conversion is UNSUPPORTED")
	check(Layouts.capability_status("binary-1192", Layouts.EDIT_OBJECT_COUNT) == "EDITOR_ONLY", "1192 count edits stay EDITOR_ONLY")
	check(Layouts.capability_status("binary-1196", Layouts.EDIT_PATH_POINTS) == "NATIVE", "1196 path point edits are engine NATIVE")
	check(Layouts.capability_status("binary-1196", Layouts.EDIT_OBJECT_TRANSFORM) == "NATIVE", "1196 transform edits are engine NATIVE")
	check(Layouts.capability_status("binary-1196", Layouts.EDIT_OBJECT_COUNT) == "EDITOR_ONLY", "1196 count edits stay EDITOR_ONLY")
	check(Layouts.capability_status("binary-1196", Layouts.ENGINE_PLAYTEST) == "UNSUPPORTED", "1196 has no direct native launch")
	check(Layouts.capability_status("binary-1196", Layouts.CONVERT_TO_185) == "NATIVE", "1196 conversion is the verified adapter route")
	check(Layouts.capability_status("binary-1197", Layouts.EDIT_PATH_POINTS) == "BAKED", "1197 path point edits are BAKED only")
	check(Layouts.capability_status("binary-1197", Layouts.INSPECT_OBJECTS) == "UNSUPPORTED", "1197 object tables stay UNSUPPORTED")
	check(Layouts.capability_status("binary-1197", Layouts.EDIT_OBJECT_TRANSFORM) == "UNSUPPORTED", "1197 object edits stay UNSUPPORTED")
	check(Layouts.capability_status("binary-1197", Layouts.EDIT_OBJECT_COUNT) == "UNSUPPORTED", "1197 count edits stay UNSUPPORTED")
	check(Layouts.capability_status("text-1200", Layouts.INSPECT_PATHS) == "UNSUPPORTED", "text path tables stay UNSUPPORTED")
	check(Layouts.capability_status("text-1200", Layouts.EDIT_OBJECT_COUNT) == "UNSUPPORTED", "text count edits stay UNSUPPORTED")

	# --- Playtest routes for the verified 2.0.185 adapter ---
	check(Layouts.playtest_route(1192, "binary") == "native", "1192 launches natively")
	check(Layouts.playtest_route(1196, "binary") == "convert", "1196 needs the conversion adapter")
	check(Layouts.playtest_route(1197, "binary") == "refuse", "1197 is refused for playtest")
	check(Layouts.playtest_route(1200, "text") == "refuse", "text 1200 is refused for playtest")
	check(Layouts.playtest_route(1199, "binary") == "refuse", "unknown versions are refused for playtest")

	# --- Codec gates consult the registry ---
	var codec := Codec.new()
	check(not codec.read(bolt, 1200), "the path codec refuses the text 1200 layout")
	check(not codec.read(volcano, 1198), "the path codec refuses an unregistered version argument")
	check(not codec.read(brave.slice(0, 200), 1196), "the path codec refuses a truncated Brave")
	check(codec.read(brave, 1196) and codec.paths.size() == 23, "Brave decodes 23 paths (independent BZNTools count)")
	var objects := Objects.new()
	check(objects.read(brave, 1196, codec.table_start) and objects.objects.size() == 76,
		"Brave decodes 76 objects (independent BZNTools count)")
	check(not objects.read(brave, 1196, brave.size()), "the object codec refuses an invalid record boundary")
	var volcano_codec := Codec.new()
	check(volcano_codec.read(volcano, 1197) and not objects.read(volcano, 1197, volcano_codec.table_start),
		"the object codec refuses 1197 by capability")
	check(not objects.read(brave, 1197, codec.table_start), "the object codec refuses a mismatched header version")
	check(Layouts.supports_object_table(1192) and Layouts.supports_object_table(1196)
		and not Layouts.supports_object_table(1197) and not Layouts.supports_object_table(1200),
		"object table support covers exactly the verified layouts")
	check(codec.read(volcano, 1197) and Layouts.path_table_versions().has(1197),
		"1197 stays in the verified path table version set")

	# --- Package-level refusal of unverifiable layouts ---
	test_package_refusal(bolt, sources[0], args[5], "the text 1200 package")
	test_package_refusal(spoof_1199, sources[0], args[5], "the unregistered 1199 package")
	var terrace_package := Package.new()
	scratch_package(terrace, sources[0], args[5], "vsrterrace2")
	check(terrace_package.open(args[5].path_join("pkg-vsrterrace2/vsrterrace2.bzn")),
		"the verified 1197 package still opens for path editing")

	# --- Source preservation: reads never mutate the fixtures ---
	for index in sources.size():
		var current := FileAccess.get_file_as_bytes(sources[index])
		check(current == originals[index], "fixture %s remains byte-identical after all checks" % sources[index].get_file())
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func renumber(data: PackedByteArray, version: String) -> PackedByteArray:
	var result := data.duplicate()
	var ascii: PackedByteArray = version.to_ascii_buffer()
	for i in ascii.size():
		result[HEADER_DIGITS_AT + i] = ascii[i]
	return result


func check_recognized(data: PackedByteArray, id: String, version: int, encoding: String, name: String) -> void:
	var result: Dictionary = Layouts.recognize(data)
	if not check(result["profile"] == id, "%s recognizes as %s (reason: %s)" % [name, id, result["reason"]]):
		return
	check(int(result["version"]) == version and String(result["encoding"]) == encoding,
		"%s reports version %d and %s encoding" % [name, version, encoding])
	var entry: Dictionary = Layouts.profile(id)
	check(not entry["fixtures"].is_empty() and not entry["evidence"].is_empty(),
		"%s profile records its fixtures and evidence" % id)


func scratch_package(bzn: PackedByteArray, brave: String, scratch: String, stem: String) -> String:
	var folder := scratch.path_join("pkg-" + stem.to_lower())
	DirAccess.make_dir_recursive_absolute(folder)
	var handle := FileAccess.open(folder.path_join(stem + ".bzn"), FileAccess.WRITE)
	handle.store_buffer(bzn)
	handle.close()
	for purpose in ["trn", "inf", "ter"]:
		var source := brave.get_base_dir().path_join("braveliltoaster." + purpose)
		var companion := FileAccess.open(folder.path_join("%s.%s" % [stem.to_lower(), purpose]), FileAccess.WRITE)
		companion.store_buffer(FileAccess.get_file_as_bytes(source))
		companion.close()
	return folder.path_join(stem + ".bzn")


var refusal_count := 0


func test_package_refusal(bzn: PackedByteArray, brave: String, scratch: String, name: String) -> void:
	refusal_count += 1
	var stem := "refused-%d" % refusal_count
	var target := scratch_package(bzn, brave, scratch, stem)
	var package := Package.new()
	if package.open(target):
		check(false, "package open must refuse " + name)
		return
	check(package.error.contains("refuse") or package.error.contains("refuses")
		or package.error.contains("no verified layout profile") or package.error.contains("This editor decodes only"),
		name + " open explains the layout refusal (got: " + package.error + ")")


func check(condition: bool, description: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	return condition
