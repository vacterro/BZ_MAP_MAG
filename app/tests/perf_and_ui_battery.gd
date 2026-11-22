extends SceneTree
## Wave 7/8 Product Performance Battery & Multi-Resolution UI Acceptance Suite.
##
## Measures real timings (median, P95, P99, max, frame count, peak RAM, draw calls,
## chunk rebuilds, hardware, resolution) for:
##   - Genuine 4096 m x 4096 m (2048x2048 samples, 1024 chunks) map load, idle,
##     orbit, fly, brush hover, brush stroke, and LOD teleport/drain
##   - Real Brave map load + water preview toggle
##   - Dense object placement (200 native objects on Stock 1192)
##   - Object Browser search (0 full asset rescans)
##   - Mod profile switching (stock -> vrv -> stock)
##   - Native export latency (203 objects)
## Also verifies Golden Default Wintage + all 4 themes across 1120x690, 1280x720,
## 1920x1080, 2560x1440, ALL 9 major dialogs (including Environment Studio compactness,
## Water & Sound Point), and Environment Studio Houdini Value Ladder gestures!

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")
const Package := preload("res://formats/map_package.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Wintage := preload("res://themes/wintage.gd")
const SliderField := preload("res://themes/slider_field.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(cond: bool, desc: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + desc)


func _stats(samples: PackedFloat32Array) -> Dictionary:
	if samples.is_empty():
		return {"avg": 0.0, "med": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := samples.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in sorted:
		sum += v
	var n := sorted.size()
	return {
		"avg": sum / float(n),
		"med": sorted[n / 2],
		"p95": sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)],
		"p99": sorted[mini(n - 1, int(ceil(n * 0.99)) - 1)],
		"max": sorted[n - 1],
	}


func _log_metric(label: String, samples: PackedFloat32Array, chunks: int, extra: String = "") -> void:
	var s := _stats(samples)
	var draw_calls := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var ram_mib := OS.get_static_memory_usage() / 1048576.0
	var peak_mib := OS.get_static_memory_peak_usage() / 1048576.0
	print("PERF %-22s | n=%2d | med=%6.2f ms | p95=%6.2f ms | p99=%6.2f ms | max=%6.2f ms | chunks=%4d | draws=%4d | ram=%.1f/%.1f MiB%s" % [
		label, samples.size(), s["med"], s["p95"], s["p99"], s["max"], chunks, draw_calls, ram_mib, peak_mib, (" | " + extra) if not extra.is_empty() else ""])


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("Pass brave_bzn plgr_bzn game_dir scratch_dir [optional_vrv_dir]")
		quit(2)
		return
	var brave_bzn := args[0]
	var plgr_bzn := args[1]
	var game_dir := args[2]
	var scratch := args[3]
	var vrv_dir := args[4] if args.size() >= 5 else ""

	var gpu_name := RenderingServer.get_video_adapter_name()
	var gpu_vendor := RenderingServer.get_video_adapter_vendor()
	var disp_name := DisplayServer.get_name()
	var cpu_name := OS.get_processor_name()
	print("PERF_ENV display=%s | gpu=%s (%s) | cpu=%s | os=%s | res=1280x720" % [
		disp_name, gpu_name if not gpu_name.is_empty() else "headless", gpu_vendor, cpu_name, OS.get_name()])

	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.settings_path = scratch.path_join("perf-ui.cfg")
	editor.game_path.text = game_dir
	editor.vrv_path.text = vrv_dir
	editor.mod_registry.discover_installed(game_dir, vrv_dir)
	editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1280, 720)
	await process_frame

	# Check Golden Default theme on first run
	check(editor.theme_slug == Wintage.DEFAULT_THEME,
		"UI first-run default theme is %s (Golden Default Wintage)" % Wintage.DEFAULT_THEME)

	# =========================================================================
	# 1. Genuine 4096 m x 4096 m (2048x2048 samples, 1024 chunks) Stress Battery
	# =========================================================================
	var writer := Snapshots.new()
	var map4096_dir := scratch.path_join("perf-4096m-stock")
	check(writer.create_native_flat_map(plgr_bzn, map4096_dir, 4096, 100.0, "", {
		"mod_profile": "stock",
		"mission_profile": "strategy",
		"configure_mission": true,
		"sync_mission_dll": true,
		"sanitize_stock_objects": true,
	}), "PERF stage genuine 4096 m x 4096 m Stock map: " + writer.error)
	var map4096_bzn := map4096_dir.path_join(plgr_bzn.get_file())

	var t_load4k := Time.get_ticks_usec()
	check(editor.open_map(map4096_bzn), "PERF open genuine 4096 m map")
	await process_frame
	await process_frame
	var load4k_ms := (Time.get_ticks_usec() - t_load4k) / 1000.0
	var dims4k: Vector2i = editor.document.package.terrain.dimensions
	check(dims4k == Vector2i(2048, 2048), "PERF 4096 m map has 2048x2048 native 2 m samples (got %s)" % str(dims4k))
	_log_metric("4096m_map_load", PackedFloat32Array([load4k_ms]), editor.scene_view.total_chunk_rebuilds,
		"samples=%dx%d meshes=%d" % [dims4k.x, dims4k.y, editor.scene_view.meshes.size()])

	# Idle (24 frames)
	var s_idle := PackedFloat32Array()
	var r0: int = editor.scene_view.total_chunk_rebuilds
	for _i in 24:
		var t0 := Time.get_ticks_usec()
		await process_frame
		s_idle.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("4096m_idle", s_idle, editor.scene_view.total_chunk_rebuilds - r0)

	# Orbit (24 frames of actual camera rotation + frustum/LOD check)
	var s_orbit := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	for _i in 24:
		var t0 := Time.get_ticks_usec()
		editor.scene_view.orbit(Vector2(7.5, 1.8))
		await process_frame
		s_orbit.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("4096m_orbit", s_orbit, editor.scene_view.total_chunk_rebuilds - r0)

	# Fly (24 frames)
	var s_fly := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.set_fly(true)
	for _i in 24:
		var t0 := Time.get_ticks_usec()
		editor.scene_view.fly_step(1.0, 0.25, 0.05, 0.016)
		await process_frame
		s_fly.append((Time.get_ticks_usec() - t0) / 1000.0)
	editor.scene_view.set_fly(false)
	_log_metric("4096m_fly", s_fly, editor.scene_view.total_chunk_rebuilds - r0)

	# Brush hover across 4096 m grid (24 frames)
	var s_hover := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	for i in 24:
		var t0 := Time.get_ticks_usec()
		editor.scene_view.show_cursor(Vector2(dims4k.x * 0.5 + i * 3, dims4k.y * 0.5))
		await process_frame
		s_hover.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("4096m_brush_hover", s_hover, editor.scene_view.total_chunk_rebuilds - r0)

	# Brush stroke on 4096 m map (24 real terrain sculpt + mesh dirty rebuild frames)
	var s_stroke := PackedFloat32Array()
	var s_stroke_work := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.document.begin_stroke()
	for i in 24:
		var t0 := Time.get_ticks_usec()
		var pt := Vector2(dims4k.x * 0.5 + i * 4, dims4k.y * 0.5 + (i % 4) * 3)
		editor.scene_view.show_cursor(pt)
		editor.document.dab(pt, 48.0, 4.0)
		editor._process(0.016)
		var work_ms := (Time.get_ticks_usec() - t0) / 1000.0
		s_stroke_work.append(work_ms)
		await process_frame
		s_stroke.append((Time.get_ticks_usec() - t0) / 1000.0)
	editor.document.end_stroke()
	var stroke_rebuilds: int = editor.scene_view.total_chunk_rebuilds - r0
	check(stroke_rebuilds > 0, "PERF 4096 m brush stroke triggers genuine terrain chunk rebuilds (%d)" % stroke_rebuilds)
	_log_metric("4096m_brush_stroke", s_stroke, stroke_rebuilds, "cpu_med=%.2fms" % float(_stats(s_stroke_work)["med"]))

	# LOD switching (teleport across 4096 m map + drain deferred queue)
	var s_lod := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.center = editor.scene_view.point_world(Vector2(192, 192))
	editor.scene_view.distance = 160.0
	editor.scene_view.update_camera()
	for _i in 80:
		var t0 := Time.get_ticks_usec()
		await process_frame
		s_lod.append((Time.get_ticks_usec() - t0) / 1000.0)
		if editor.scene_view.lod_pending_count == 0 and s_lod.size() >= 6:
			break
	var lod_rebuilds: int = editor.scene_view.total_chunk_rebuilds - r0
	check(lod_rebuilds > 0 and editor.scene_view.lod_pending_count == 0,
		"PERF 4096 m LOD teleport triggers real rebuilds (%d) and converges to 0 pending" % lod_rebuilds)
	_log_metric("4096m_lod_switch", s_lod, lod_rebuilds, "pending=%d" % editor.scene_view.lod_pending_count)

	# =========================================================================
	# 2. Real Brave 2048 m Map Load + Water Preview + Sound/Water Dialog Coverage
	# =========================================================================
	var t_brave := Time.get_ticks_usec()
	check(editor.open_map(brave_bzn), "PERF open real Brave map")
	await process_frame
	await process_frame
	var brave_ms := (Time.get_ticks_usec() - t_brave) / 1000.0
	_log_metric("brave_2048m_load", PackedFloat32Array([brave_ms]), editor.scene_view.total_chunk_rebuilds, "objs=%d" % editor.document.object_count())

	if editor.document.package.water != null:
		var t_wat := Time.get_ticks_usec()
		editor.water_button.button_pressed = true
		editor.toggle_water()
		await process_frame
		var wat_ms := (Time.get_ticks_usec() - t_wat) / 1000.0
		_log_metric("water_preview", PackedFloat32Array([wat_ms]), 0)
		editor.water_button.button_pressed = false
		editor.toggle_water()

	# Check Water and Sound Point dialogs fit cleanly while Brave (which has WAT & objects) is open
	editor.water_tools.begin(editor.document)
	await process_frame
	check(editor.water_tools.visible and editor.water_tools.size.x <= 1280 and editor.water_tools.size.y <= 720,
		"UI dialog 'water_tools' fits cleanly inside 1280x720 (%dx%d)" % [editor.water_tools.size.x, editor.water_tools.size.y])
	editor.water_tools.hide()
	editor.open_sound_editor()
	await process_frame
	check(editor.sound_editor.visible and editor.sound_editor.size.x <= 1280 and editor.sound_editor.size.y <= 720,
		"UI dialog 'sound_editor' fits cleanly inside 1280x720 (%dx%d)" % [editor.sound_editor.size.x, editor.sound_editor.size.y])
	editor.sound_editor.hide()

	# =========================================================================
	# 3. Dense Object Placement (200 native objects), Object Browser Search,
	#    Profile Switch & Native Export
	# =========================================================================
	var dense_dir := scratch.path_join("perf-dense-stock")
	check(writer.create_native_flat_map(plgr_bzn, dense_dir, 1024, 100.0, "", {
		"mod_profile": "stock", "mission_profile": "strategy", "configure_mission": true, "sync_mission_dll": true, "sanitize_stock_objects": true,
	}), "PERF stage Stock 1192 map for dense objects & export")
	var dense_bzn := dense_dir.path_join(plgr_bzn.get_file())
	check(editor.open_map(dense_bzn), "PERF open Stock map")
	editor.document.mod_profile = "stock"
	editor.document.mission_profile = "strategy"
	var s_dense := PackedFloat32Array()
	var odf_cycle := ["morock03", "morock01", "mopalm02", "npscrx", "iblite", "ibwseg"]
	for i in 200:
		var t0 := Time.get_ticks_usec()
		var gx := -300.0 + float(i % 20) * 30.0
		var gz := -300.0 + float(i / 20) * 30.0
		var v: int = editor.document.place_native_object(odf_cycle[i % odf_cycle.size()], Vector3(gx, 100.0, gz), 0)
		check(v >= 0, "PERF place dense object #%d" % i)
		s_dense.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("dense_place_200", s_dense, 0, "total_objs=%d" % editor.document.object_count())

	# Object Browser search (10 searches; verify catalog_revision unchanged -> ZERO asset rescans!)
	editor.open_object_browser()
	var rev_before: int = editor.object_browser.catalog_revision
	var s_search := PackedFloat32Array()
	for q in ["rock", "pool", "ib", "tank", "scout", "scrap", "power", "wall", "tree", ""]:
		var t0 := Time.get_ticks_usec()
		editor.object_browser.search_box.text = q
		editor.object_browser.rebuild_list()
		s_search.append((Time.get_ticks_usec() - t0) / 1000.0)
	check(editor.object_browser.catalog_revision == rev_before,
		"PERF Object Browser search triggers 0 full asset rescans")
	_log_metric("browser_search", s_search, 0, "catalog=%d" % editor.object_browser.catalog_entries.size())
	editor.object_browser.hide()

	# Mod profile switch (stock -> vrv -> stock)
	var s_prof := PackedFloat32Array()
	for tgt_m in ["vrv", "stock", "vrv", "stock"]:
		var t0 := Time.get_ticks_usec()
		editor.document.set_target_profile(tgt_m, "strategy")
		await process_frame
		s_prof.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("profile_switch", s_prof, 0)

	# Native export latency (with 203 objects!)
	var t_exp := Time.get_ticks_usec()
	check(writer.export_native(editor.document, scratch.path_join("perf-dense-export")), "PERF native export with 203 objects: " + writer.error)
	var exp_ms := (Time.get_ticks_usec() - t_exp) / 1000.0
	_log_metric("native_export_203", PackedFloat32Array([exp_ms]), 0)

	# =========================================================================
	# 4. Environment Studio Houdini Value Ladder Integration & Compactness
	# =========================================================================
	editor.open_environment_studio()
	await process_frame
	var env_dlg = editor.environment_studio
	var fs_field: SliderField = env_dlg.fog_start_field
	var orig_fs: float = fs_field.value
	fs_field.begin_ladder(Vector2(200, 200))
	fs_field.step_ladder_by(2)
	check(fs_field.value != orig_fs, "UI Environment Studio Value Ladder scrubs fog_start_field live (%.1f -> %.1f)" % [orig_fs, fs_field.value])
	fs_field.end_ladder(false) # cancel restores initial value!
	check(is_equal_approx(fs_field.value, orig_fs), "UI Environment Studio Value Ladder cancel restores original fog_start_field")
	fs_field.begin_ladder(Vector2(200, 200))
	fs_field.step_ladder_by(-1)
	fs_field.end_ladder(true) # commit
	check(fs_field.value < orig_fs, "UI Environment Studio Value Ladder commit retains new fog_start_field (%.1f)" % fs_field.value)
	check(env_dlg.size.x <= 720 and env_dlg.size.y <= 540,
		"UI Environment Studio remains compact without empty bloat (%dx%d)" % [env_dlg.size.x, env_dlg.size.y])
	env_dlg.hide()

	# =========================================================================
	# 5. Multi-Resolution UI Acceptance (1120x690, 1280x720, 1920x1080, 2560x1440)
	#    x All 4 Wintage Themes x All Major Dialogs
	# =========================================================================
	var resolutions := [Vector2i(1120, 690), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
	var dialog_openers := [
		["new_map_wizard", func(): editor.open_new_map_wizard(); return editor.new_map_wizard],
		["target_profile_dialog", func(): editor.open_target_profile(0); return editor.target_profile_dialog],
		["object_browser", func(): editor.open_object_browser(); return editor.object_browser],
		["mission_studio", func(): editor.open_mission_studio(); return editor.mission_studio],
		["slope_studio", func(): editor.open_slope_studio(); return editor.slope_studio],
		["environment_studio", func(): editor.open_environment_studio(); return editor.environment_studio],
		["node_studio", func(): editor.open_studio(); return editor.studio],
	]
	for res: Vector2i in resolutions:
		root.size = res
		editor.size = Vector2(res)
		await process_frame
		await process_frame
		var sv_rect: Rect2 = editor.scene_view.get_global_rect()
		var top_rect: Rect2 = editor.top.get_global_rect()
		check(sv_rect.size.x >= 320.0 and sv_rect.size.y >= 260.0 and top_rect.size.x >= 150.0 and top_rect.size.y >= 260.0,
			"UI %dx%d preserves healthy 3D (%.0fx%.0f) and 2D (%.0fx%.0f) viewports" % [
				res.x, res.y, sv_rect.size.x, sv_rect.size.y, top_rect.size.x, top_rect.size.y])
		check(sv_rect.end.x <= float(res.x) + 2.0 and sv_rect.end.y <= float(res.y) + 2.0,
			"UI %dx%d 3D viewport fits within window bounds" % [res.x, res.y])
		# Check every major dialog fits within the current viewport at EVERY resolution!
		for item in dialog_openers:
			var dname: String = item[0]
			var dlg: Window = item[1].call()
			await process_frame
			check(dlg.visible and dlg.size.x <= res.x and dlg.size.y <= res.y and dlg.size.x >= 320 and dlg.size.y >= 180,
				"UI %dx%d dialog '%s' fits cleanly (%dx%d)" % [res.x, res.y, dname, dlg.size.x, dlg.size.y])
			if DisplayServer.get_name() != "headless" and res == Vector2i(1280, 720) and dname in ["object_browser", "environment_studio", "mission_studio"]:
				var img := root.get_texture().get_image()
				if img != null:
					img.save_png(scratch.path_join("ui-%s-1280x720.png" % dname))
			dlg.hide()
			await process_frame

	# Verify all 4 Wintage themes across main editor + Environment Studio
	root.size = Vector2i(1280, 720)
	editor.size = Vector2(1280, 720)
	await process_frame
	for slug: String in Wintage.theme_slugs():
		editor.set_wintage_theme(slug, false, false)
		await process_frame
		check(editor.scene_view.size.x >= 320.0 and editor.scene_view.size.y >= 260.0,
			"UI theme '%s' preserves healthy 3D viewport layout" % slug)
		editor.open_environment_studio()
		await process_frame
		check(editor.environment_studio.visible and editor.environment_studio.size.x <= 1280 and editor.environment_studio.size.y <= 720,
			"UI theme '%s' keeps Environment Studio compact (%dx%d)" % [slug, editor.environment_studio.size.x, editor.environment_studio.size.y])
		editor.environment_studio.hide()
		await process_frame
	editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
	await process_frame

	if DisplayServer.get_name() != "headless":
		var main_img := root.get_texture().get_image()
		if main_img != null:
			main_img.save_png(scratch.path_join("ui-main-golden-1280x720.png"))

	editor.free()
	print("Wave 7/8 Product Performance Battery & Multi-Resolution UI Acceptance complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
