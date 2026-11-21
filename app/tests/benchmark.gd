extends SceneTree

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		quit(2)
		return
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1120, 690)
	var timer := Time.get_ticks_usec()
	if not editor.open_map(arguments[0]):
		printerr(editor.status.text)
		quit(1)
		return
	var doc: Document = editor.document
	var terrain := doc.package.terrain
	print("%s: %d x %d m, package and two views %.1f ms" % [arguments[0].get_file(), 2 * terrain.dimensions.x, 2 * terrain.dimensions.y, (Time.get_ticks_usec() - timer) / 1000.0])
	var timings := PackedFloat32Array()
	for stroke in 10:
		timer = Time.get_ticks_usec()
		doc.begin_stroke()
		doc.dab(Vector2(terrain.dimensions / 2) + Vector2(stroke * 2, stroke * 2), 48, 8)
		doc.end_stroke()
		editor._process(0)
		timings.append((Time.get_ticks_usec() - timer) / 1000.0)
		await process_frame
	for stroke in 10:
		doc.undo()
		editor._process(0)
		await process_frame
	timings.sort()
	print("48 m brush + CPU dirty updates median %.1f ms, max %.1f ms" % [timings[5], timings[9]])
	print("Engine static memory %.1f MiB, peak %.1f MiB" % [OS.get_static_memory_usage() / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0])
	quit(0 if doc.edits.is_empty() else 1)
