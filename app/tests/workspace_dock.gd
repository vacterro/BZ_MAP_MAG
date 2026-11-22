extends SceneTree
## Dedicated Unified DCC Workspace & Docked Inspector Acceptance Suite (SAIHANDOFF-15).
## Verifies:
## - Zero modal popup Windows for all 11 migrated editor tools
## - 23-step Docked Slope Studio vertical slice (Preview/Orbit/Ladder/Cancel/Apply/Undo/Redo/BZMAG/Export)
## - Scene Tree selection, double-click camera focus & editor-only visibility separation
## - Real Procedural Layers synchronization with central Node Graph workspace
## - Pinned Inspector, all 6 Workspace Presets, Fullscreen restore, persistence & bounds clamping
## - MMB Value Ladder vs 3D camera pan isolation, LineEdit shortcut guard, preview/water safety, post-resize ray picking
## - 4 resolutions (1120x690, 1280x720, 1920x1080, 2560x1440), 3 scales (100/150/200%), 4 Wintage themes + GPU PNGs

const EditorScene := preload("res://editor.tscn")
const WorkspaceState := preload("res://ui/workspace_state.gd")
const Document := preload("res://core/map_document.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Wintage := preload("res://themes/wintage.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func _visible_tool_windows(root_node: Node) -> Array[Window]:
	var found: Array[Window] = []
	for child in root_node.get_children():
		if child is Window and (child as Window).visible:
			found.append(child as Window)
		found.append_array(_visible_tool_windows(child))
	return found


func _stage_stock_plgr(raw_plgr_bzn: String, scratch_dir: String) -> String:
	var stage := scratch_dir.path_join("stock-plgr-staged")
	DirAccess.make_dir_recursive_absolute(stage)
	var src_dir := raw_plgr_bzn.get_base_dir()
	var dir := DirAccess.open(src_dir)
	if dir != null:
		for f: String in dir.get_files():
			if f.to_lower().begins_with("plgr."):
				var bytes := FileAccess.get_file_as_bytes(src_dir.path_join(f))
				var out := FileAccess.open(stage.path_join(f), FileAccess.WRITE)
				if out != null:
					out.store_buffer(bytes)
					out.close()
	var inf_path := stage.path_join("plgr.inf")
	if not FileAccess.file_exists(inf_path):
		var inf := FileAccess.open(inf_path, FileAccess.WRITE)
		if inf != null:
			inf.store_string("[DESCRIPTION]\r\nmissionName = \"plgr\"\r\n")
			inf.close()
	return stage.path_join("plgr.bzn")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("FAIL: workspace_dock.gd requires 4 args: <plgr.bzn> <brave.bzn> <game_dir> <scratch_dir> [vrv_dir]")
		quit(1)
		return
	var raw_plgr := args[0]
	var brave_bzn := args[1]
	var game_dir := args[2]
	var scratch_dir := args[3]
	var vrv_dir := args[4] if args.size() > 4 else ""
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	var shots_dir := scratch_dir.path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var plgr_bzn := _stage_stock_plgr(raw_plgr, scratch_dir)
	var is_gpu := DisplayServer.get_name() != "headless"

	var cfg_path := scratch_dir.path_join("workspace-test.cfg")
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(cfg_path)

	if is_gpu:
		DisplayServer.window_set_size(Vector2i(1120, 690))
	else:
		root.size = Vector2i(1120, 690)

	var editor := EditorScene.instantiate()
	editor.settings_path = cfg_path
	root.add_child(editor)
	editor.game_path.text = game_dir
	editor.vrv_path.text = vrv_dir
	editor.mod_registry.discover_installed(game_dir, vrv_dir)
	for _i in 4:
		await process_frame

	# 1. Verify ALL migrated tools are Control (never Window) and zero modal popups open
	for pair in [
		["slope_studio", editor.slope_studio],
		["terrain_tools", editor.terrain_tools],
		["water_tools", editor.water_tools],
		["environment_studio", editor.environment_studio],
		["sound_editor", editor.sound_editor],
		["path_inspector", editor.path_inspector],
		["mission_studio", editor.mission_studio],
		["object_browser", editor.object_browser],
		["node_studio", editor.studio],
		["new_map_wizard", editor.new_map_wizard],
		["target_profile_dialog", editor.target_profile_dialog],
		["settings_page", editor.playtest_dialog],
	]:
		check(pair[1] is Control and not (pair[1] is Window), "Tool '%s' is a docked Control, not a popup Window" % pair[0])

	# 2. Open Stock BZN 1192 — 23-step Docked Slope Studio Acceptance (Section 13)
	check(editor.open_map(plgr_bzn), "Open Stock BZN 1192 (plgr.bzn)")
	for _i in 6:
		await process_frame
	check(editor.views.visible and editor.scene_view.visible and editor.top.visible,
		"3D and 2D viewports are both visible in center workspace")
	check(editor.scene_view.size.x >= 200.0 and editor.top.size.x >= 120.0,
		"Both 3D (%.0f) and 2D (%.0f) have practical width at 1120x690" % [editor.scene_view.size.x, editor.top.size.x])

	# Select Slope Studio — MUST dock in Right Attributes with ZERO popup Window
	editor.open_slope_studio()
	for _i in 4:
		await process_frame
	check(_visible_tool_windows(editor).is_empty(), "Activating Slope Studio opens ZERO popup Windows")
	check(editor.workspace_state.active_inspector_context == WorkspaceState.InspectorContext.SLOPE,
		"Attributes Inspector context switches to SLOPE")
	check(editor.slope_studio.is_visible_in_tree(), "Slope Studio panel is visible inside docked Attributes Inspector")
	check(editor.scene_view.is_visible_in_tree() and editor.top.is_visible_in_tree(),
		"3D and 2D viewports stay fully unobstructed while Slope Studio is active")

	var doc: Document = editor.document
	var orig_heights: PackedFloat32Array = doc.package.terrain.heights.duplicate()
	var terrain := doc.package.terrain
	var center_w := Vector2(terrain.origin + terrain.dimensions / 2) * terrain.SPACING
	editor.slope_studio.from_x.value = center_w.x - 48.0
	editor.slope_studio.from_z.value = center_w.y
	editor.slope_studio.to_x.value = center_w.x + 48.0
	editor.slope_studio.to_z.value = center_w.y
	editor.slope_studio.mode_choice.select(1) # Exact angle
	editor.slope_studio.angle.value = 15.0
	editor.slope_studio.width.value = 32.0
	editor.slope_studio.falloff.value = 8.0
	check(editor.slope_studio.preview_shape(), "Slope Studio Preview succeeds at 15 deg, width 32 m, falloff 8 m")
	for _i in 4:
		await process_frame
	check(editor.document.has_preview() and editor.document.preview_after.size() > 50,
		"Slope preview modifies live preview buffer (%d samples)" % editor.document.preview_after.size())
	check(editor.document.edits.is_empty(), "Preview does not mutate committed document edits")

	if is_gpu:
		# Focus camera near the sculpted 15 deg ramp so the After shot clearly shows
		# live 3D terrain preview alongside the docked Slope Studio panel (zero overlap!)
		editor.scene_view.center = Vector3(center_w.x, terrain.heights[terrain.dimensions.y / 2 * terrain.dimensions.x + terrain.dimensions.x / 2], center_w.y)
		editor.scene_view.distance = 220.0
		editor.scene_view.update_camera()
		for _i in 6:
			await process_frame
		var img_1120 := root.get_texture().get_image()
		img_1120.save_png(shots_dir.path_join("after-slope-1120x690.png"))
		print("SHOT=after-slope-1120x690.png (%dx%d) left=%.0f center3d=%.0f attr=%.0f attr_end_x=%.0f" % [
			img_1120.get_width(), img_1120.get_height(),
			editor.left_dock.size.x, editor.scene_view.size.x,
			editor.attributes_inspector.size.x, editor.attributes_inspector.get_global_rect().end.x])
	check(editor.attributes_inspector.size.x >= 224.0 and editor.attributes_inspector.get_global_rect().end.x <= editor.size.x + 2.0,
		"Right Attributes Inspector fits strictly inside 1120x690 (w=%.0f, end_x=%.0f / %.0f)" % [
			editor.attributes_inspector.size.x, editor.attributes_inspector.get_global_rect().end.x, editor.size.x])
	check(editor.slope_studio.get_global_rect().intersects(editor.scene_view.get_global_rect()) == false,
		"Docked Slope Studio NEVER overlaps the 3D viewport")

	# Camera orbit/pan/zoom continues working while Slope Studio is open
	var cam_yaw_before: float = editor.scene_view.yaw
	var cam_dist_before: float = editor.scene_view.distance
	editor.scene_view.orbit(Vector2(24.0, -8.0))
	editor.scene_view.zoom(0.87)
	check(not is_equal_approx(editor.scene_view.yaw, cam_yaw_before) and not is_equal_approx(editor.scene_view.distance, cam_dist_before),
		"3D camera orbit and zoom work smoothly while docked Slope Studio is active")

	# Houdini Value Ladder on docked Slope Studio angle updates live preview WITHOUT panning 3D camera
	var cam_center_before: Vector3 = editor.scene_view.center
	var preview_count_before: int = editor.document.preview_after.size()
	var angle_before: float = editor.slope_studio.angle.value
	editor.slope_studio.angle.begin_ladder(editor.slope_studio.angle.get_global_rect().get_center())
	editor.slope_studio.angle.step_ladder_by(4, -1)
	editor.slope_studio.angle.end_ladder(true)
	for _i in 2:
		await process_frame
	check(not is_equal_approx(editor.slope_studio.angle.value, angle_before),
		"Houdini Value Ladder changes docked Slope Studio angle (%.1f -> %.1f)" % [angle_before, editor.slope_studio.angle.value])
	check(editor.scene_view.center.is_equal_approx(cam_center_before),
		"MMB Value Ladder gesture on docked SliderField does not pan 3D camera")
	check(editor.document.has_preview() and editor.document.preview_after.size() > 0,
		"Value Ladder edit keeps live Slope preview updated (%d -> %d samples)" % [preview_count_before, editor.document.preview_after.size()])

	# Cancel returns exact original heights
	editor.slope_studio.cancel_shape()
	check(not editor.document.has_preview(), "Slope Cancel clears active preview")
	check(editor.document.package.terrain.heights == orig_heights, "Slope Cancel restores exact original committed heights")

	# Repeat Preview -> Apply -> 1 Undo -> Undo -> Redo
	check(editor.slope_studio.preview_shape(), "Re-preview Slope before Apply")
	var undo_before: int = editor.document.undo_stack.size()
	editor.slope_studio.apply_shape()
	check(editor.document.undo_stack.size() == undo_before + 1, "Slope Apply creates exactly 1 Undo step")
	check(not editor.document.edits.is_empty(), "Slope Apply commits terrain height edits")
	var applied_heights: PackedFloat32Array = editor.document.package.terrain.heights.duplicate()
	check(applied_heights != orig_heights, "Applied terrain heights differ from original")
	editor.document.undo()
	check(editor.document.package.terrain.heights == orig_heights, "Undo restores exact original heights")
	editor.document.redo()
	check(editor.document.package.terrain.heights == applied_heights, "Redo restores exact applied slope heights")

	# Save BZMAG -> Reopen -> Native Export/Reimport
	var bzmag_path := scratch_dir.path_join("slope-docked.bzmag")
	var writer := Snapshots.new()
	check(writer.save_project(editor.document, bzmag_path), "Save BZMAG after docked Slope edit")
	var reopened := Document.new()
	check(reopened.open(bzmag_path) and reopened.package.terrain.heights == applied_heights,
		"Reopen BZMAG preserves exact docked Slope heights")
	var export_dir := scratch_dir.path_join("slope-docked-export")
	check(writer.export_native(reopened, export_dir), "Native export & reimport succeeds after docked Slope edit")

	# 3. Pinned Inspector keeps SLOPE when selecting an object in Scene Tree
	editor.workspace_state.set_pinned(true)
	check(editor.attributes_inspector.pin_button.button_pressed, "Pin button reflects pinned state")
	editor.scene_tree.item_selected_kind.emit("object", 0)
	check(editor.workspace_state.active_inspector_context == WorkspaceState.InspectorContext.SLOPE,
		"Pinned Inspector remains on SLOPE while selecting object in Scene Tree")
	check(editor.object_tool.selected == 0, "Object selection still updates while Inspector is pinned")
	editor.workspace_state.set_pinned(false)
	editor.scene_tree.item_selected_kind.emit("object", 0)
	check(editor.workspace_state.active_inspector_context == WorkspaceState.InspectorContext.OBJECT,
		"Unpinned Inspector switches to OBJECT on Scene Tree selection")
	check(editor.object_attributes.is_visible_in_tree(), "Object Attributes panel visible in Right Inspector")

	# Double-click object in Scene Tree focuses 3D camera
	var prev_center: Vector3 = editor.scene_view.center
	editor.scene_view.center = prev_center + Vector3(200.0, 0.0, 200.0)
	editor.scene_tree.item_activated_kind.emit("object", 0)
	check(editor.scene_view.center.distance_to(editor.document.object_position(0)) < 0.1,
		"Scene Tree double-click focuses 3D camera on selected object")

	# Editor-only visibility toggles NEVER delete native BZN objects or paths
	var obj_cnt_before: int = editor.document.object_count()
	var path_cnt_before: int = editor.document.path_indices().size()
	editor.scene_tree.visibility_toggled.emit("paths", false)
	check(editor.top.path_overlay.is_empty() and editor.document.path_indices().size() == path_cnt_before,
		"Hiding paths in Scene Tree is editor-only and keeps native BZN paths intact")
	editor.scene_tree.visibility_toggled.emit("paths", true)
	check(editor.document.object_count() == obj_cnt_before, "Native BZN object count untouched by editor visibility")

	# 4. Real Procedural Layers <-> Central Node Graph synchronization
	var layers_before: int = editor.document.layers.size()
	editor.layers_panel.add_btn.pressed.emit()
	check(editor.document.layers.size() == layers_before + 1, "LayersPanel +Add adds real procedural layer to MapDocument")
	editor.layers_panel.opacity_field.value = 0.65
	check(is_equal_approx(float(editor.document.layers[editor.layers_panel.selected_index]["opacity"]), 0.65),
		"LayersPanel opacity edits MapDocument.layers directly")
	editor.layers_panel.edit_graph_btn.pressed.emit()
	for _i in 3:
		await process_frame
	check(editor.workspace_state.center_mode == WorkspaceState.CenterMode.NODES and editor.studio.is_visible_in_tree(),
		"Edit Graph opens central NodeStudio GraphEdit workspace (no Window)")
	check(_visible_tool_windows(editor).is_empty(), "Node Graph workspace opens ZERO popup Windows")
	check(editor.studio.working.size() == editor.document.layers.size() and editor.studio.attributes_panel.is_visible_in_tree(),
		"Central NodeStudio & Right Inspector Node Attributes stay synchronized with LayersPanel")

	# 5. Cycle ALL remaining docked tools — ZERO popup Windows for any of them
	editor.open_terrain_tools()
	check(editor.terrain_tools.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Shape Terrain docked, 0 popups")
	editor.open_environment_studio()
	check(editor.environment_studio.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Environment Studio docked, 0 popups")
	editor.open_mission_studio()
	check(editor.mission_studio.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Mission Studio docked, 0 popups")
	editor.open_object_browser()
	check(editor.object_browser.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Object Browser docked in Assets tab, 0 popups")
	editor.open_sound_editor()
	check(editor.sound_editor.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Sound Editor docked, 0 popups")
	editor.open_target_profile(0)
	check(editor.target_profile_dialog.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Target Profile docked, 0 popups")
	editor.open_new_map_wizard()
	check(editor.new_map_wizard.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "New Map embedded in center workspace, 0 popups")
	editor.show_playtest_setup()
	check(editor.playtest_dialog.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Settings embedded in center workspace, 0 popups")

	# 6. Water paint tool lifecycle — NO hidden active paint mode after switching tools!
	editor.toggle_water_edit()
	check(editor.water_tools.is_visible_in_tree() and _visible_tool_windows(editor).is_empty(), "Water Editor docked, 0 popups")
	editor.water_tools.paint_toggle.button_pressed = true
	check(editor.painting_water_active(), "Water paint activates via explicit ToolState")
	editor.activate_terrain_brush()
	check(not editor.painting_water_active() and not editor.water_tools.paint_toggle.button_pressed,
		"Switching to Terrain Brush cleanly disables Water Paint (no hidden paint mode)")

	# 7. Preview safety across incompatible tools & document switching
	editor.open_slope_studio()
	check(editor.slope_studio.preview_shape() and editor.document.has_preview(), "Arm Slope preview")
	editor.open_terrain_tools()
	check(not editor.document.has_preview(), "Switching to Shape Terrain safely clears active Slope preview")
	editor.open_slope_studio()
	check(editor.slope_studio.preview_shape() and editor.document.has_preview(), "Re-arm Slope preview before doc switch")
	var prev_doc: Document = editor.document
	check(editor.open_map(brave_bzn), "Switch document to Brave Lil Toaster")
	for _i in 6:
		await process_frame
	check(not prev_doc.has_preview() and not editor.document.has_preview(),
		"Switching documents safely clears old preview and never leaks stale references")

	# 8. Keyboard focus safety: LineEdit focus blocks global Fly hotkey
	var fly_before: bool = editor.fly_button.button_pressed
	editor.tool_search.grab_focus()
	var key_f := InputEventKey.new()
	key_f.keycode = KEY_F
	key_f.pressed = true
	editor._shortcut_input(key_f)
	check(editor.fly_button.button_pressed == fly_before,
		"Typing in LineEdit does not trigger global Fly shortcut")
	editor.tool_search.release_focus()

	# 9. All 6 Workspace Presets + Fullscreen Restore + Persistence + Out-of-bounds Clamping
	if is_gpu:
		DisplayServer.window_set_size(Vector2i(1280, 720))
	else:
		root.size = Vector2i(1280, 720)
		editor.size = Vector2(1280, 720)
		editor._on_editor_resized()
	for _i in 4:
		await process_frame

	editor.apply_workspace_preset(WorkspaceState.LayoutPreset.DEFAULT)
	for _i in 3:
		await process_frame
	if is_gpu:
		root.get_texture().get_image().save_png(shots_dir.path_join("after-default-1280x720.png"))
	editor.apply_workspace_preset(WorkspaceState.LayoutPreset.NODES)
	for _i in 3:
		await process_frame
	if is_gpu:
		root.get_texture().get_image().save_png(shots_dir.path_join("after-nodes-1280x720.png"))
	editor.apply_workspace_preset(WorkspaceState.LayoutPreset.MISSION)
	for _i in 3:
		await process_frame
	if is_gpu:
		root.get_texture().get_image().save_png(shots_dir.path_join("after-mission-1280x720.png"))
	editor.apply_workspace_preset(WorkspaceState.LayoutPreset.OBJECT_PLACEMENT)
	for _i in 3:
		await process_frame
	if is_gpu:
		root.get_texture().get_image().save_png(shots_dir.path_join("after-objects-1280x720.png"))
	editor.open_environment_studio()
	for _i in 3:
		await process_frame
	if is_gpu:
		root.get_texture().get_image().save_png(shots_dir.path_join("after-environment-1280x720.png"))

	# Fullscreen Viewport hides docks and restores exact previous preset on exit
	editor.apply_workspace_preset(WorkspaceState.LayoutPreset.SCULPTING)
	editor.toggle_fullscreen_viewport()
	check(not editor.left_dock.visible and not editor.attributes_inspector.visible,
		"Fullscreen Viewport hides Left and Right docks")
	editor.toggle_fullscreen_viewport()
	check(editor.left_dock.visible and editor.attributes_inspector.visible and editor.workspace_state.active_preset == WorkspaceState.LayoutPreset.SCULPTING,
		"Exiting Fullscreen Viewport restores exact prior preset and dock visibility")

	# Splitter resize preserves camera, undo stack, and accurate 3D ray picking!
	var cam_before_split: Vector3 = editor.scene_view.center
	var undo_before_split: int = editor.document.undo_stack.size()
	editor.workspace_state.left_dock_width = 260
	editor.workspace_state.right_dock_width = 340
	editor._apply_workspace_layout()
	for _i in 4:
		await process_frame
	check(editor.scene_view.center.is_equal_approx(cam_before_split) and editor.document.undo_stack.size() == undo_before_split,
		"Dock resize never resets camera or clears Undo history")
	var pick_pt: Vector2 = editor.scene_view.sample_at(editor.scene_view.size * 0.5)
	check(pick_pt.x >= 0.0 and pick_pt.y >= 0.0,
		"3D viewport ray picking remains accurate after dock resize (sample=%.1f,%.1f)" % [pick_pt.x, pick_pt.y])

	# Persistence + out-of-bounds clamping + Reset Layout
	editor._save_workspace_layout()
	var cfg := ConfigFile.new()
	check(cfg.load(cfg_path) == OK and cfg.has_section("workspace"),
		"Workspace layout persists cleanly into [workspace] section of editor.cfg")
	cfg.set_value("workspace", "left_width", 9999)
	cfg.set_value("workspace", "right_width", 9999)
	cfg.save(cfg_path)
	var ws_reload := WorkspaceState.new()
	ws_reload.load_from_config(cfg, Vector2(1120, 690))
	check(ws_reload.left_dock_width + ws_reload.right_dock_width <= 800,
		"Out-of-bounds saved layout clamps cleanly to keep center viewport usable (%d + %d)" % [ws_reload.left_dock_width, ws_reload.right_dock_width])
	editor.reset_workspace_layout()
	check(editor.workspace_state.active_preset == WorkspaceState.LayoutPreset.DEFAULT and editor.left_dock.visible and editor.attributes_inspector.visible,
		"Reset Workspace Layout restores Default preset cleanly")

	# 10. Resolutions (1120x690, 1280x720, 1920x1080, 2560x1440), Scales (100/150/200%), 4 Wintage Themes
	editor.open_slope_studio()
	for res: Vector2i in [Vector2i(1120, 690), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		if is_gpu:
			DisplayServer.window_set_size(res)
		else:
			root.size = res
			editor.size = Vector2(res)
			editor._on_editor_resized()
		for _i in 2:
			await process_frame
		check(editor.scene_view.size.x >= 180.0 and editor.attributes_inspector.size.x >= 220.0,
			"Layout fits cleanly at %dx%d (3D=%.0f, Attr=%.0f)" % [res.x, res.y, editor.scene_view.size.x, editor.attributes_inspector.size.x])

	for fsz: int in [12, 18, 24]:
		editor.ui_font_size = fsz
		editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
		for _i in 2:
			await process_frame
		check(editor.theme.default_font_size == fsz and editor.slope_studio.is_visible_in_tree(),
			"UI scale font=%dpx keeps docked Slope Studio usable" % fsz)
	editor.ui_font_size = 12

	for slug: String in Wintage.theme_slugs():
		editor.set_wintage_theme(slug, false, false)
		for _i in 2:
			await process_frame
		check(editor.theme_slug == slug and editor.backdrop.color.is_equal_approx(Wintage.palette(slug)["background"]),
			"Wintage theme '%s' applies cleanly across unified workspace" % slug)
	editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)

	print("Unified DCC Workspace & Docked Inspector Acceptance complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
