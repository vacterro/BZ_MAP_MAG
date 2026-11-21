extends SceneTree

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")
const Package := preload("res://formats/map_package.gd")
const Terrain := preload("res://formats/terrain_v5.gd")


func _initialize() -> void:
	call_deferred("run")


func _stats(samples: PackedFloat32Array) -> Dictionary:
	if samples.is_empty():
		return {"avg": 0.0, "med": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0, "min_fps": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in sorted:
		sum += v
	var n := sorted.size()
	var max_ms := sorted[n - 1]
	return {
		"avg": sum / float(n),
		"med": sorted[n / 2],
		"p95": sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)],
		"p99": sorted[mini(n - 1, int(ceil(n * 0.99)) - 1)],
		"max": max_ms,
		"min_fps": 1000.0 / maxf(0.001, max_ms),
	}


func _print_scenario(label: String, samples: PackedFloat32Array, rebuilds: int) -> void:
	var s := _stats(samples)
	print("BENCH %-18s | n=%2d | avg=%5.2f ms | med=%5.2f ms | p95=%5.2f ms | p99=%5.2f ms | max=%5.2f ms | minFPS=%6.1f | chunks=%d" % [
		label, samples.size(), s["avg"], s["med"], s["p95"], s["p99"], s["max"], s["min_fps"], rebuilds])


func run_4096_sustained() -> int:
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1120, 690)
	var doc := Document.new()
	doc.package = Package.new()
	var terrain := Terrain.new()
	terrain.dimensions = Vector2i(2048, 2048)
	terrain.origin = Vector2i(-1024, -1024)
	terrain.heights.resize(terrain.dimensions.x * terrain.dimensions.y)
	terrain.heights.fill(100.0)
	terrain.min_height = 80.0
	terrain.max_height = 160.0
	doc.package.terrain = terrain
	doc.base_heights = terrain.heights.duplicate()
	editor.document = doc
	editor.top.document = doc
	editor.scene_view.document = doc
	doc.terrain_changed.connect(editor.mark_refresh)

	var t0 := Time.get_ticks_usec()
	editor.scene_view.bind(doc)
	editor.scene_view.center = editor.scene_view.point_world(Vector2(1024, 1024))
	editor.scene_view.distance = 180.0
	editor.scene_view.update_camera()
	editor.scene_view.update_lod(0)
	var bind_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("4096 m bind+focus: %.1f ms | viewport=%s | chunks=%d" % [bind_ms, str(editor.scene_view.size), editor.scene_view.meshes.size()])
	await process_frame
	await process_frame

	# 1. Idle viewport (30 frames)
	var idle_ms := PackedFloat32Array()
	var r0: int = editor.scene_view.total_chunk_rebuilds
	for _i in 30:
		var ft := Time.get_ticks_usec()
		await process_frame
		idle_ms.append((Time.get_ticks_usec() - ft) / 1000.0)
	_print_scenario("idle", idle_ms, editor.scene_view.total_chunk_rebuilds - r0)

	# 2. Camera orbit (30 frames)
	var orbit_ms := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	for _i in 30:
		var ft := Time.get_ticks_usec()
		editor.scene_view.orbit(Vector2(8.0, 2.0))
		await process_frame
		orbit_ms.append((Time.get_ticks_usec() - ft) / 1000.0)
	_print_scenario("orbit", orbit_ms, editor.scene_view.total_chunk_rebuilds - r0)

	# 3. Zoom (20 frames)
	var zoom_ms := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	for i in 20:
		var ft := Time.get_ticks_usec()
		editor.scene_view.zoom(0.95 if i < 10 else 1.05)
		await process_frame
		zoom_ms.append((Time.get_ticks_usec() - ft) / 1000.0)
	_print_scenario("zoom", zoom_ms, editor.scene_view.total_chunk_rebuilds - r0)

	# 4. Fly (30 frames)
	var fly_ms := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.set_fly(true)
	for _i in 30:
		var ft := Time.get_ticks_usec()
		editor.scene_view.fly_step(1.0, 0.25, 0.0, 0.016)
		await process_frame
		fly_ms.append((Time.get_ticks_usec() - ft) / 1000.0)
	editor.scene_view.set_fly(false)
	_print_scenario("fly", fly_ms, editor.scene_view.total_chunk_rebuilds - r0)

	# 5. Brush hover + continuous brush stroke (25 frames)
	var stroke_ms := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.center = editor.scene_view.point_world(Vector2(1024, 1024))
	editor.scene_view.update_camera()
	editor.scene_view.update_lod(0)
	await process_frame
	r0 = editor.scene_view.total_chunk_rebuilds
	doc.begin_stroke()
	for i in 25:
		var ft := Time.get_ticks_usec()
		var pt := Vector2(960 + i * 5, 1024 + (i % 5) * 3)
		editor.scene_view.show_cursor(pt)
		doc.dab(pt, 32.0, 6.0)
		editor._process(0.016)
		await process_frame
		stroke_ms.append((Time.get_ticks_usec() - ft) / 1000.0)
	doc.end_stroke()
	_print_scenario("brush_stroke_2m", stroke_ms, editor.scene_view.total_chunk_rebuilds - r0)

	# 6. Rapid teleport + deferred LOD convergence (stationary drain)
	var jump_ms := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	var ft0 := Time.get_ticks_usec()
	editor.scene_view.center = editor.scene_view.point_world(Vector2(256, 256))
	editor.scene_view.update_camera()
	await process_frame
	jump_ms.append((Time.get_ticks_usec() - ft0) / 1000.0)
	var drain_frames := 0
	while editor.scene_view.lod_pending_count > 0 and drain_frames < 120:
		var ft := Time.get_ticks_usec()
		await process_frame
		jump_ms.append((Time.get_ticks_usec() - ft) / 1000.0)
		drain_frames += 1
	_print_scenario("teleport_converge", jump_ms, editor.scene_view.total_chunk_rebuilds - r0)
	print("Deferred LOD pending after drain: %d (converged in %d frames)" % [editor.scene_view.lod_pending_count, drain_frames])
	print("Engine static memory %.1f MiB, peak %.1f MiB" % [OS.get_static_memory_usage() / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0])
	var ok: bool = editor.scene_view.lod_pending_count == 0
	editor.free()
	return 0 if ok else 1


func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 1 and arguments[0] == "--4096":
		var code := await run_4096_sustained()
		quit(code)
		return
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
