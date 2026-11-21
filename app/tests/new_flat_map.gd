extends SceneTree

const EditorScene := preload("res://editor.tscn")
const Snapshots := preload("res://bridge/snapshots.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Pass a blank BZN, its matching flat TER template, and a fresh scratch directory.")
		quit(2)
		return
	var editor := EditorScene.instantiate()
	editor.settings_path = args[2].path_join("settings.cfg")
	root.add_child(editor)
	await process_frame
	editor.blank_dialog.file_selected.emit(args[0])
	editor.flat_template_dialog.file_selected.emit(args[1])
	editor.flat_output_dialog.dir_selected.emit(args[2])
	if editor.document == null:
		check(false, "new map workflow opened a verified package: " + editor.status.text)
	else:
		var package: RefCounted = editor.document.package
		var folder: String = package.source_path.get_base_dir()
		check(folder.get_base_dir() == args[2], "creates a fresh package in the selected folder")
		check(package.terrain.dimensions == Vector2i(1024, 1024) and package.terrain.origin == Vector2i(-512, -512), "generated native terrain is 2048 m square at the expected origin")
		check(absf(package.terrain.min_height - 100.0) <= 0.0001 and package.terrain.max_height == package.terrain.min_height, "terrain has the expected uniform height")
		check(FileAccess.get_sha256(package.source_path) == FileAccess.get_sha256(args[0]), "source BZN remains byte-identical")
		check(FileAccess.get_sha256(folder.path_join(package.terrain_name)) == FileAccess.get_sha256(args[1]), "published TER matches the checked template")
		check(not FileAccess.file_exists(args[0].get_basename() + ".TER"), "blank source remains without terrain")
		print("PACKAGE: " + folder)
	var bridge := Snapshots.new()
	var helper: String = editor.tool_root().path_join("tools/New-FlatTerrainSnapshot.ps1")
	var shorter := FileAccess.get_file_as_bytes(args[1]).slice(0, 32784)
	shorter.encode_s16(12, 0)
	var wrong_template := args[2].path_join("wrong-width.ter")
	check(bridge.write_bytes(wrong_template, shorter), "write a different but uniform template")
	var bad_target := args[2].path_join("bad-width")
	check(not bridge.create_flat_map(args[0], wrong_template, bad_target, helper)
		and bridge.error.contains("dimensions") and not DirAccess.dir_exists_absolute(bad_target), "reject incompatible TRN dimensions before publishing")
	editor.engine_editor_mode.button_pressed = true
	editor.store_playtest_settings()
	var settings := ConfigFile.new()
	check(settings.load(editor.settings_path) == OK and settings.get_value("playtest", "engine_editor", false), "engine editor mode is saved separately from mission playtest")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
