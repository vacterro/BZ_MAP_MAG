extends SceneTree

const Codec := preload("res://formats/bzn_paths.gd")
const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		printerr("Pass binary Terrace 2 and AdMemorium Volcano BZNs, text Bolt BZN, and a fresh scratch directory.")
		quit(2)
		return
	var terrace := FileAccess.get_file_as_bytes(args[0])
	var volcano := FileAccess.get_file_as_bytes(args[1])
	var bolt := FileAccess.get_file_as_bytes(args[2])
	if terrace.is_empty() or volcano.is_empty() or bolt.is_empty():
		printerr("Could not read the supplied BZN fixtures.")
		quit(2)
		return
	var codec := Codec.new()
	check(not codec.read(terrace, 1196), "reject a mismatched binary profile")
	check(not codec.read(bolt, 1200), "reject the unverified Bolt text profile")
	check(not codec.read(bolt, 1197), "do not treat text as a supported binary profile")
	if check(codec.read(volcano, 1197) and codec.paths.size() == 1, "Volcano has one 1197 path"):
		check_path(codec.paths[0], 2)
	if check(codec.read(terrace, 1197) and codec.paths.size() == 16, "Terrace 2 has 16 paths in binary 1197"):
		check_path(codec.paths[0], 5)
		var start := codec.table_start
		var first: Dictionary = codec.paths[0]
		var second: Dictionary = codec.paths[1]
		var truncated := terrace.slice(0, codec.table_end + 24)
		check(not codec.read(truncated, 1197) and codec.paths.is_empty(), "reject a truncated path trailer")
		var duplicate_id := terrace.duplicate()
		duplicate_id.encode_u32(second["name_start"] - 4, first["id"])
		check(not codec.read(duplicate_id, 1197), "reject a repeated path ID")
		var wrong_count := terrace.duplicate()
		wrong_count.encode_s32(start - 4, 15)
		check(not codec.read(wrong_count, 1197), "reject a count inconsistent with the table")
		test_export(args[0], terrace, args[3])
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func check_path(path: Dictionary, point_count: int) -> void:
	check(path["name"] == "edge_path" and path["type"] == 0 and path["points"].size() == point_count,
		"first path matches the independent BZNTools read")


func test_export(source: String, original: PackedByteArray, scratch: String) -> void:
	var document := Document.new()
	if not check(document.open(source), "open the 1197 map package: " + document.error):
		return
	var before := document.path_at(0)
	if not check(document.edit_path(0, "audit_path", before["points"], before["type"]), "edit one native path"):
		return
	var snapshots := Snapshots.new()
	var target := scratch.path_join("path-edit")
	if not check(snapshots.export_native(document, target), "export and verify the modified BZN: " + snapshots.error):
		return
	var output := target.path_join(source.get_file())
	var after := Document.new()
	if not check(after.open(output), "reopen the native 1197 export: " + after.error):
		return
	var record := after.path_at(0)
	var patched := FileAccess.get_file_as_bytes(output)
	check(record["id"] == before["id"] and record["name"] == "audit_path", "patch preserves the ID and updates the label")
	check(patched.slice(0, record["name_start"]) == original.slice(0, before["name_start"])
		and patched.slice(record["point_start"]) == original.slice(before["point_start"]),
		"all bytes outside the renamed field are preserved")
	check(FileAccess.get_file_as_bytes(source) == original, "source package remains byte-identical")


func check(condition: bool, description: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	return condition
