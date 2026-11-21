extends SceneTree

const EditorScene := preload("res://editor.tscn")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4:
		printerr("Pass mission BZN, game installation, VRV source, and isolated scratch folder.")
		quit(2)
		return
	var editor := EditorScene.instantiate()
	editor.settings_path = args[3].path_join("test-editor.cfg")
	root.add_child(editor)
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1120, 690)
	if not editor.open_map(args[0]):
		printerr(editor.status.text)
		quit(1)
		return
	editor.game_path.text = "" if args[1] == "-" else args[1]
	editor.vrv_path.text = "" if args[2] == "-" else args[2]
	var started := Time.get_ticks_msec()
	editor.playtest()
	var deadline := Time.get_ticks_msec() + 25000
	while editor.launcher_pid > 0 and editor.game_pid <= 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	var launched: bool = editor.game_pid > 0 and editor.launcher_pid > 0 and not editor.playtest_dialog.visible
	print(editor.status.text)
	if launched:
		print("DETECTED " + editor.game_path.text)
		print("LAUNCH MS %d" % (Time.get_ticks_msec() - started))
		print("GAME PID %d" % editor.game_pid)
		deadline = Time.get_ticks_msec() + 50000
		while editor.launcher_pid > 0 and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
		launched = editor.launcher_pid == -1 and editor.status.text.begins_with("Battlezone closed")
		print(editor.status.text)
	quit(0 if launched else 1)
