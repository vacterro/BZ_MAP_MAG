extends SceneTree
## Wave 8 Product Performance Battery & Multi-Resolution UI Acceptance Suite.
##
## Measures real timings (median, P95, P99, max, RAM, draw calls, chunk rebuilds) for:
##   idle, orbit, fly, brush_hover, brush_stroke, lod_switch, water_preview,
##   dense_objects (200 placed), object_browser_search (0 full rescans),
##   profile_switch (stock->vrv->stock), native_export, large_map_load (4096 m).
## Also verifies Golden Default Wintage + alternate theme layouts across
## 1120x690, 1280x720, 1920x1080, 2560x1440 and all major dialogs (including
## Environment Studio & Object Browser).

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")
const Package := preload("res://formats/map_package.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Wintage := preload("res://themes/wintage.gd")

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
	print("PERF %-20s | n=%2d | med=%6.2f ms | p95=%6.2f ms | p99=%6.2f ms | max=%6.2f ms | chunks=%3d | draws=%4d | ram=%.1f/%.1f MiB%s" % [
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

	# 1. Large map load (Brave 4096 m / real BZN + TER + WAT + SKY)
	var t_load := Time.get_ticks_usec()
	check(editor.open_map(brave_bzn), "PERF open Brave map")
	await process_frame
	await process_frame
	var load_ms := (Time.get_ticks_usec() - t_load) / 1000.0
	_log_metric("large_map_load", PackedFloat32Array([load_ms]), editor.scene_view.total_chunk_rebuilds, "objs=%d" % editor.document.object_count())

	# 2. Idle viewport (20 frames)
	var s_idle := PackedFloat32Array()
	var r0: int = editor.scene_view.total_chunk_rebuilds
	for _i in 20:
		var t0 := Time.get_ticks_usec()
		await process_frame
		s_idle.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("idle_viewport", s_idle, editor.scene_view.total_chunk_rebuilds - r0)

	# 3. Orbit (20 frames)
	var s_orbit := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	for _i in 20:
		var t0 := Time.get_ticks_usec()
		editor.scene_view.orbit(Vector2(6.0, 1.5))
		await process_frame
		s_orbit.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("orbit", s_orbit, editor.scene_view.total_chunk_rebuilds - r0)

	# 4. Fly (20 frames)
	var s_fly := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.set_fly(true)
	for _i in 20:
		var t0 := Time.get_ticks_usec()
		editor.scene_view.fly_step(1.0, 0.2, 0.0, 0.016)
		await process_frame
		s_fly.append((Time.get_ticks_usec() - t0) / 1000.0)
	editor.scene_view.set_fly(false)
	_log_metric("fly", s_fly, editor.scene_view.total_chunk_rebuilds - r0)

	# 5. Brush hover (20 frames)
	var s_hover := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	var dims: Vector2i = editor.document.package.terrain.dimensions
	for i in 20:
		var t0 := Time.get_ticks_usec()
		editor.scene_view.show_cursor(Vector2(dims.x * 0.5 + i * 2, dims.y * 0.5))
		await process_frame
		s_hover.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("brush_hover", s_hover, editor.scene_view.total_chunk_rebuilds - r0)

	# 6. Brush stroke (20 frames)
	var s_stroke := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.document.begin_stroke()
	for i in 20:
		var t0 := Time.get_ticks_usec()
		var pt := Vector2(dims.x * 0.5 + i * 3, dims.y * 0.5 + (i % 4) * 2)
		editor.scene_view.show_cursor(pt)
		editor.document.dab(pt, 32.0, 4.0)
		editor._process(0.016)
		await process_frame
		s_stroke.append((Time.get_ticks_usec() - t0) / 1000.0)
	editor.document.end_stroke()
	_log_metric("brush_stroke", s_stroke, editor.scene_view.total_chunk_rebuilds - r0)

	# 7. Terrain LOD switching (teleport + drain)
	var s_lod := PackedFloat32Array()
	r0 = editor.scene_view.total_chunk_rebuilds
	editor.scene_view.center = editor.scene_view.point_world(Vector2(128, 128))
	editor.scene_view.distance = 160.0
	editor.scene_view.update_camera()
	for _i in 20:
		var t0 := Time.get_ticks_usec()
		await process_frame
		s_lod.append((Time.get_ticks_usec() - t0) / 1000.0)
		if editor.scene_view.lod_pending_count == 0 and s_lod.size() >= 6:
			break
	_log_metric("lod_switch", s_lod, editor.scene_view.total_chunk_rebuilds - r0)

	# 8. Water preview toggle
	if editor.document.package.water != null:
		var t_wat := Time.get_ticks_usec()
		editor.water_button.button_pressed = true
		editor.toggle_water()
		await process_frame
		var wat_ms := (Time.get_ticks_usec() - t_wat) / 1000.0
		_log_metric("water_preview", PackedFloat32Array([wat_ms]), 0)
		editor.water_button.button_pressed = false
		editor.toggle_water()

	# 9. Dense object placement (200 native objects placed on Stock 1192 map)
	var dense_dir := scratch.path_join("perf-dense-stock")
	var writer := Snapshots.new()
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

	# 10. Object Browser search (10 searches; verify catalog_revision unchanged -> ZERO asset rescans!)
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

	# 11. Mod profile switch (stock -> vrv -> stock)
	var s_prof := PackedFloat32Array()
	for tgt_m in ["vrv", "stock", "vrv", "stock"]:
		var t0 := Time.get_ticks_usec()
		editor.document.set_target_profile(tgt_m, "strategy")
		await process_frame
		s_prof.append((Time.get_ticks_usec() - t0) / 1000.0)
	_log_metric("profile_switch", s_prof, 0)

	# 12. Native export latency (with 203 objects!)
	var t_exp := Time.get_ticks_usec()
	check(writer.export_native(editor.document, scratch.path_join("perf-dense-export")), "PERF native export with 203 objects: " + writer.error)
	var exp_ms := (Time.get_ticks_usec() - t_exp) / 1000.0
	_log_metric("native_export_203", PackedFloat32Array([exp_ms]), 0)

	# =========================================================================
	# 13. Multi-Resolution UI Acceptance (1120x690, 1280x720, 1920x1080, 2560x1440)
	#     + Golden Default & alternate themes + all dialogs
	# =========================================================================
	var resolutions := [Vector2i(1120, 690), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
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

	# Verify dialogs open compactly without overflowing 1280x720 and other themes don't break layout
	root.size = Vector2i(1280, 720)
	editor.size = Vector2(1280, 720)
	await process_frame
	for slug: String in Wintage.theme_slugs():
		editor.set_wintage_theme(slug, false, false)
		await process_frame
		check(editor.scene_view.size.x >= 320.0 and editor.scene_view.size.y >= 260.0,
			"UI theme '%s' preserves healthy 3D viewport layout" % slug)
	editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
	await process_frame

	# Open & close each dialog cleanly at 1280x720
	var dialog_openers := [
		["new_map_wizard", func(): editor.open_new_map_wizard(); return editor.new_map_wizard],
		["target_profile_dialog", func(): editor.open_target_profile(0); return editor.target_profile_dialog],
		["object_browser", func(): editor.open_object_browser(); return editor.object_browser],
		["mission_studio", func(): editor.open_mission_studio(); return editor.mission_studio],
		["slope_studio", func(): editor.open_slope_studio(); return editor.slope_studio],
		["environment_studio", func(): editor.open_environment_studio(); return editor.environment_studio],
		["node_studio", func(): editor.open_studio(); return editor.studio],
	]
	for item in dialog_openers:
		var dname: String = item[0]
		var dlg: Window = item[1].call()
		await process_frame
		check(dlg.visible and dlg.size.x <= 1280 and dlg.size.y <= 720 and dlg.size.x >= 320 and dlg.size.y >= 180,
			"UI dialog '%s' fits cleanly inside 1280x720 (%dx%d)" % [dname, dlg.size.x, dlg.size.y])
		if DisplayServer.get_name() != "headless" and dname in ["object_browser", "environment_studio"]:
			var img := root.get_texture().get_image()
			if img != null:
				img.save_png(scratch.path_join("ui-%s-1280x720.png" % dname))
		dlg.hide()
		await process_frame

	if DisplayServer.get_name() != "headless":
		var main_img := root.get_texture().get_image()
		if main_img != null:
			main_img.save_png(scratch.path_join("ui-main-golden-1280x720.png"))

	editor.free()
	print("Wave 8 Product Performance Battery & Multi-Resolution UI Acceptance complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
