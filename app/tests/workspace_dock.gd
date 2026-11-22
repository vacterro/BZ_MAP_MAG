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
const Graph := preload("res://nodes/height_graph.gd")
const NodeStudio := preload("res://nodes/node_studio.gd")
const CollapsibleSection := preload("res://ui/collapsible_section.gd")
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

	# 4. Real Procedural Layers Transactions, Undo/Redo, Opacity Gesture & Node Draft Safety (Waves B & C)
	var orig_ter_before_layers: PackedByteArray = editor.document.package.terrain.encode(editor.document.edits)
	var rev_before_layers: int = editor.document.edit_revision
	var lrev_before_layers: int = editor.document.layer_stack_revision
	var undo_before_layers: int = editor.document.undo_stack.size()
	var layers_before: int = editor.document.layers.size()
	editor.layers_panel.add_btn.pressed.emit()
	check(editor.document.layers.size() == layers_before + 1, "LayersPanel +Add adds real procedural layer via MapDocument transaction")
	check(editor.document.undo_stack.size() == undo_before_layers + 1 and editor.document.edit_revision > rev_before_layers and editor.document.layer_stack_revision > lrev_before_layers,
		"Layer Add pushes 1 undo step and bumps edit_revision & layer_stack_revision")
	# Undo -> Redo Add
	editor.document.undo()
	check(editor.document.layers.size() == layers_before, "Undo reverses procedural Layer Add")
	editor.document.redo()
	check(editor.document.layers.size() == layers_before + 1, "Redo re-applies procedural Layer Add")

	# Reorder -> Undo -> Redo (and verify stable layer UID moves with the layer!)
	var uid0_before: int = editor.document.layer_uid(0)
	var uid1_before: int = editor.document.layer_uid(1)
	editor.layers_panel.up_btn.pressed.emit()
	check(editor.document.layer_uid(0) == uid1_before and editor.document.layer_uid(1) == uid0_before,
		"Layer Move Up reorders layer and preserves stable layer UIDs")
	editor.document.undo()
	check(editor.document.layer_uid(0) == uid0_before and editor.document.layer_uid(1) == uid1_before,
		"Undo reverses procedural Layer reorder and restores exact UID order")
	editor.document.redo()
	check(editor.document.layer_uid(0) == uid1_before and editor.document.layer_uid(1) == uid0_before,
		"Redo re-applies procedural Layer reorder")

	# Enable/Disable -> Undo -> Redo
	editor.layers_panel.enabled_check.button_pressed = false
	check(not bool(editor.document.layers[editor.layers_panel.selected_index]["enabled"]),
		"LayersPanel Enabled toggle disables layer transactionally")
	editor.document.undo()
	check(bool(editor.document.layers[editor.layers_panel.selected_index]["enabled"]),
		"Undo restores Layer enabled state")

	# Opacity Value Ladder gesture: live preview -> 0 history entries during drag -> Cancel restores -> Commit = 1 Undo!
	var op_undo_base: int = editor.document.undo_stack.size()
	var op_rev_base: int = editor.document.edit_revision
	var op_initial: float = float(editor.document.layers[editor.layers_panel.selected_index]["opacity"])
	editor.layers_panel.opacity_field.begin_ladder(Vector2(100, 100))
	editor.layers_panel.opacity_field.step_ladder_by(-3, -1)
	editor.layers_panel.opacity_field.step_ladder_by(-2, -1)
	check(editor.document.undo_stack.size() == op_undo_base and editor.document.edit_revision == op_rev_base,
		"Opacity Value Ladder drag previews live with 0 intermediate history entries")
	editor.layers_panel.opacity_field.end_ladder(false) # Cancel
	check(is_equal_approx(float(editor.document.layers[editor.layers_panel.selected_index]["opacity"]), op_initial)
		and editor.document.undo_stack.size() == op_undo_base,
		"Cancelling opacity gesture restores exact initial opacity with 0 undo entries")
	editor.layers_panel.opacity_field.begin_ladder(Vector2(100, 100))
	editor.layers_panel.opacity_field.step_ladder_by(-4, -1)
	editor.layers_panel.opacity_field.step_ladder_by(-2, -1)
	editor.layers_panel.opacity_field.end_ladder(true) # Commit
	var op_committed: float = float(editor.document.layers[editor.layers_panel.selected_index]["opacity"])
	check(not is_equal_approx(op_committed, op_initial) and editor.document.undo_stack.size() == op_undo_base + 1,
		"Committing opacity Value Ladder creates exactly 1 Undo step (%.2f -> %.2f)" % [op_initial, op_committed])
	editor.document.undo()
	check(is_equal_approx(float(editor.document.layers[editor.layers_panel.selected_index]["opacity"]), op_initial),
		"Undo reverses opacity gesture in 1 step")
	editor.document.redo()
	check(is_equal_approx(float(editor.document.layers[editor.layers_panel.selected_index]["opacity"]), op_committed),
		"Redo restores committed opacity")

	# Direct programmatic opacity assignment & no-op check
	editor.layers_panel.opacity_field.value = 0.65
	check(is_equal_approx(float(editor.document.layers[editor.layers_panel.selected_index]["opacity"]), 0.65),
		"LayersPanel opacity commits cleanly to MapDocument.layers")
	var undo_after_direct: int = editor.document.undo_stack.size()
	check(editor.document.set_procedural_layer_opacity(editor.layers_panel.selected_index, 0.65)
		and editor.document.undo_stack.size() == undo_after_direct,
		"No-op opacity transaction creates 0 history entries")

	# Remove layer -> Undo -> Redo
	var count_before_rm: int = editor.document.layers.size()
	editor.layers_panel.remove_btn.pressed.emit()
	check(editor.document.layers.size() == count_before_rm - 1, "LayersPanel Remove deletes layer transactionally")
	editor.document.undo()
	check(editor.document.layers.size() == count_before_rm, "Undo restores removed procedural layer")

	# Validation & boundary checks (invalid index, max layers, bad graph)
	var undo_before_err: int = editor.document.undo_stack.size()
	check(not editor.document.remove_procedural_layer(-1) and not editor.document.remove_procedural_layer(99),
		"Invalid layer index rejected cleanly")
	check(not editor.document.set_procedural_layer_opacity(0, 1.5) and not editor.document.set_procedural_layer_opacity(0, NAN),
		"Out-of-range / NaN layer opacity rejected cleanly")
	var bad_layer := Graph.layer()
	bad_layer["low"] = 500.0
	bad_layer["high"] = -100.0
	check(not editor.document.replace_procedural_layers([bad_layer]), "Invalid graph validation (low > high) rejected atomically")
	check(editor.document.undo_stack.size() == undo_before_err, "Failed layer transactions never pollute undo stack")
	# Max layer count cap
	var added_to_cap := 0
	while editor.document.layers.size() < Graph.MAX_LAYERS:
		if editor.document.add_procedural_layer() >= 0:
			added_to_cap += 1
		else:
			break
	check(editor.document.layers.size() == Graph.MAX_LAYERS and editor.document.add_procedural_layer() == -1,
		"Maximum procedural layer count (%d) enforced cleanly" % Graph.MAX_LAYERS)
	for _u in added_to_cap:
		editor.document.undo()
	check(editor.document.layers.size() == count_before_rm, "Undoing cap additions returns exact layer stack")

	# Autosave detects layer changes, BZMAG save/reopen persists layers, native TER stays untouched before Bake
	check(editor.has_unsaved_changes(), "Editor detects unsaved procedural layer changes")
	var autosave_dir := scratch_dir.path_join("layer-autosave")
	check(editor.autosave_now(autosave_dir), "Autosave detects procedural layer stack change")
	var layers_bzmag := scratch_dir.path_join("layers-tx.bzmag")
	check(writer.save_project(editor.document, layers_bzmag), "Save BZMAG with procedural layer stack")
	var reopened_layers := Document.new()
	check(reopened_layers.open(layers_bzmag) and reopened_layers.layers == editor.document.layers,
		"Reopen BZMAG preserves exact transactional procedural layer stack")
	check(editor.document.package.terrain.encode(editor.document.edits) == orig_ter_before_layers,
		"Native terrain bytes remain completely unchanged by procedural layer edits until Bake")

	# 4b. Central Node Graph Workspace & Uncommitted Draft Safety (Wave C)
	editor.layers_panel.edit_graph_btn.pressed.emit()
	for _i in 3:
		await process_frame
	check(editor.workspace_state.center_mode == WorkspaceState.CenterMode.NODES and editor.studio.is_visible_in_tree(),
		"Edit Graph opens central NodeStudio GraphEdit workspace (no Window)")
	check(_visible_tool_windows(editor).is_empty(), "Node Graph workspace opens ZERO popup Windows")
	check(editor.studio.working.size() == editor.document.layers.size() and editor.studio.attributes_panel.is_visible_in_tree(),
		"Central NodeStudio & Right Inspector Node Attributes stay synchronized with LayersPanel")

	# Edit node parameter (uncommitted draft) -> switch Scene -> switch Layers -> return: MUST preserve draft!
	var draft_seed := 7777.0
	var edited_layer_uid: int = editor.studio.working_uids[editor.studio.selected]
	editor.studio.parameters["seed"].value = draft_seed
	check(editor.studio.has_uncommitted_draft() and editor.studio.draft_state == NodeStudio.DraftState.DRAFT,
		"Editing NodeStudio parameter enters DRAFT state without mutating committed document.layers")
	check(not is_equal_approx(float(editor.document.layers[editor.studio.selected]["seed"]), draft_seed),
		"Uncommitted NodeStudio draft stays isolated from committed document.layers")
	editor.workspace_state.set_left_tab(WorkspaceState.LeftTab.SCENE, true)
	editor.set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	editor.workspace_state.set_left_tab(WorkspaceState.LeftTab.LAYERS, true)
	editor.open_studio()
	check(editor.studio.has_uncommitted_draft() and is_equal_approx(float(editor.studio.working[editor.studio.selected]["seed"]), draft_seed),
		"Switching Scene/Layers/Viewport/Nodes preserves uncommitted NodeStudio draft")

	# Non-conflicting LayersPanel Add / Reorder / Opacity merges safely without losing draft seed!
	var pre_merge_count: int = editor.document.layers.size()
	editor.layers_panel.add_btn.pressed.emit()
	var merged_idx_after_add: int = editor.studio.working_uids.find(edited_layer_uid)
	check(merged_idx_after_add >= 0 and is_equal_approx(float(editor.studio.working[merged_idx_after_add]["seed"]), draft_seed)
		and editor.studio.working.size() == pre_merge_count + 1 and not editor.studio.conflict_pending,
		"Adding a layer in LayersPanel preserves uncommitted NodeStudio draft via controlled merge")
	# Reorder in LayersPanel -> draft seed follows its stable UID!
	editor.layers_panel.refresh(merged_idx_after_add)
	if merged_idx_after_add > 0:
		editor.layers_panel.up_btn.pressed.emit()
	else:
		editor.layers_panel.down_btn.pressed.emit()
	var merged_idx_after_move: int = editor.studio.working_uids.find(edited_layer_uid)
	check(merged_idx_after_move >= 0 and is_equal_approx(float(editor.studio.working[merged_idx_after_move]["seed"]), draft_seed)
		and not editor.studio.conflict_pending,
		"Reordering layers in LayersPanel keeps uncommitted NodeStudio draft attached to its layer")
	# Non-conflicting opacity edit in LayersPanel -> 3-way merges opacity while preserving draft seed!
	editor.layers_panel.refresh(merged_idx_after_move)
	editor.layers_panel.opacity_field.value = 0.45
	check(is_equal_approx(float(editor.studio.working[merged_idx_after_move]["seed"]), draft_seed)
		and is_equal_approx(float(editor.studio.working[merged_idx_after_move]["opacity"]), 0.45)
		and not editor.studio.conflict_pending,
		"Non-conflicting LayersPanel opacity edit 3-way merges while preserving uncommitted draft seed")

	# True conflict: edit SAME field (opacity) in both NodeStudio draft and LayersPanel -> conflict_pending, NO silent loss!
	editor.studio.load_layer(merged_idx_after_move)
	editor.studio.parameters["opacity"].value = 0.85
	editor.layers_panel.opacity_field.value = 0.25
	check(editor.studio.conflict_pending and is_equal_approx(float(editor.studio.working[merged_idx_after_move]["opacity"]), 0.85)
		and is_equal_approx(float(editor.studio.working[merged_idx_after_move]["seed"]), draft_seed),
		"Conflicting opacity edit triggers explicit conflict banner without silently overwriting NodeStudio draft")
	# Save Project while uncommitted draft exists reports clear notice and never bakes preview
	var draft_save_path := scratch_dir.path_join("with-draft-warning.bzmag")
	editor.save_project(draft_save_path)
	check(editor.status.text.contains("uncommitted Node Graph draft"),
		"Save Project informs user about uncommitted Node Graph draft")
	# Keep Draft commits via transactional MapDocument API -> Undo/Redo works!
	var undo_before_keep: int = editor.document.undo_stack.size()
	check(editor.studio.resolve_conflict("keep_draft") and not editor.studio.conflict_pending and not editor.studio.has_uncommitted_draft(),
		"Resolving conflict with Keep Draft commits draft cleanly")
	check(editor.document.undo_stack.size() == undo_before_keep + 1
		and is_equal_approx(float(editor.document.layers[merged_idx_after_move]["seed"]), draft_seed),
		"Keep Layers commits graph draft as 1 undoable transaction")
	editor.document.undo()
	check(not is_equal_approx(float(editor.document.layers[merged_idx_after_move]["seed"]), draft_seed),
		"Undo reverses Keep Layers graph commit")
	editor.document.redo()
	check(is_equal_approx(float(editor.document.layers[merged_idx_after_move]["seed"]), draft_seed),
		"Redo restores Keep Layers graph commit")

	# Discard Draft restores committed layers
	editor.studio.load_layer(merged_idx_after_move)
	editor.studio.parameters["seed"].value = 9999.0
	check(editor.studio.has_uncommitted_draft(), "Draft arms before Discard Draft test")
	# Edit node -> change mod profile preserves draft cleanly!
	var prev_prof: String = editor.document.mod_profile
	var alt_prof := "vrv" if prev_prof == "stock" else "stock"
	check(editor.document.set_target_profile(alt_prof, editor.document.mission_profile), "Switch target profile with active NodeStudio draft")
	check(editor.studio.has_uncommitted_draft() and is_equal_approx(float(editor.studio.working[merged_idx_after_move]["seed"]), 9999.0),
		"Changing mod profile preserves uncommitted NodeStudio draft")
	editor.document.undo()
	# Delete conflict: delete a layer in LayersPanel that has uncommitted draft edits in NodeStudio!
	editor.layers_panel.refresh(merged_idx_after_move)
	editor.layers_panel.remove_btn.pressed.emit()
	check(editor.studio.conflict_pending and editor.studio.has_uncommitted_draft(),
		"Deleting externally a layer with uncommitted NodeStudio draft triggers conflict instead of silent loss")
	check(not editor.studio.resolve_conflict("cancel") and editor.studio.conflict_pending,
		"Resolving conflict with Cancel keeps draft and conflict pending")
	editor.document.undo() # restore deleted layer
	editor.studio.discard_draft()
	check(not editor.studio.has_uncommitted_draft() and not editor.studio.conflict_pending
		and is_equal_approx(float(editor.studio.working[merged_idx_after_move]["seed"]), draft_seed),
		"Discard Draft restores committed layers cleanly")

	# Worker invalidation after layer mutation (stale async result MUST be rejected!)
	editor.studio.preview()
	editor.document.set_procedural_layer_opacity(0, 0.55)
	var worker_deadline := Time.get_ticks_msec() + 10000
	while editor.studio.worker.is_started() and Time.get_ticks_msec() < worker_deadline:
		await process_frame
	for _i in 2:
		await process_frame
	check(not editor.document.has_preview(),
		"Async NodeStudio worker result is rejected after external layer mutation")

	# Node Preview -> Object Selection: preview clears safely on Object Move without losing draft!
	editor.studio.load_layer(0)
	editor.studio.parameters["seed"].value = 5432.0
	editor.studio.preview()
	var prev_dl := Time.get_ticks_msec() + 10000
	while editor.studio.worker.is_started() and Time.get_ticks_msec() < prev_dl:
		await process_frame
	for _i in 2:
		await process_frame
	check(editor.document.has_preview() and editor.workspace_state.active_preview_owner == "node",
		"Node preview arms with explicit active_preview_owner='node'")
	editor._toggle_move_objects(true)
	check(not editor.document.has_preview() and editor.workspace_state.active_preview_owner.is_empty(),
		"Switching Node Preview -> Move Object clears incompatible preview safely")
	check(editor.studio.has_uncommitted_draft() and is_equal_approx(float(editor.studio.working[0]["seed"]), 5432.0),
		"Clearing Node preview on tool switch NEVER destroys uncommitted NodeStudio draft")
	editor._toggle_move_objects(false)
	editor.studio.discard_draft()

	# 4c. Scene Tree Stability: Expansion, Selection, Stable Identity, Delete, Filter Restore (Wave D)
	editor.set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)
	editor.workspace_state.set_left_tab(WorkspaceState.LeftTab.SCENE, true)
	editor.scene_tree.rebuild()
	editor.scene_tree.set_branch_expanded("objects_group", true)
	var first_team_id: int = editor.document.object_team(0)
	var team_branch_key := "objects_team:%d" % first_team_id
	editor.scene_tree.set_branch_expanded(team_branch_key, true)
	var tracked_view := 1 if editor.document.object_count() > 1 else 0
	var tracked_key: String = editor.document.object_stable_key(tracked_view)
	editor.scene_tree.select_entry("object", tracked_view)
	# Move object -> rebuild -> expansion & selection MUST remain!
	var orig_obj_pos: Vector3 = editor.document.object_position(tracked_view)
	check(editor.document.move_object(tracked_view, orig_obj_pos + Vector3(2.0, 0.0, 2.0)), "Move tracked object")
	editor.scene_tree.rebuild()
	check(editor.scene_tree.is_branch_expanded("objects_group") and editor.scene_tree.is_branch_expanded(team_branch_key),
		"Scene Tree preserves expanded Objects & Team branches across move/rebuild")
	check(editor.scene_tree.selected_stable_key() == tracked_key,
		"Scene Tree preserves selected object across move/rebuild")
	# Rename object -> rebuild -> selection remains!
	check(editor.document.set_object_label(tracked_view, "tracked_bldg"), "Rename tracked object")
	editor.scene_tree.rebuild()
	check(editor.scene_tree.selected_stable_key() == tracked_key,
		"Scene Tree preserves selected object across rename/rebuild")
	# Insert & remove another object before tracked_view -> stable key follows tracked object even if view index shifts!
	if tracked_view > 0:
		var removed_prior: bool = editor.document.remove_object(0)
		check(removed_prior, "Remove earlier object #0 to test view-index shift stability")
		editor.scene_tree.rebuild()
		var shifted_view: int = editor.document.view_for_object_stable_key(tracked_key)
		check(shifted_view == tracked_view - 1 and editor.scene_tree.selected_stable_key() == tracked_key,
			"Scene Tree stable identity preserves selection after earlier object removal shifts indices")
		editor.document.undo()
		editor.scene_tree.rebuild()
		check(editor.scene_tree.selected_stable_key() == tracked_key,
			"Scene Tree preserves selection after Undo restores earlier object")
	# Filter -> Clear filter restores exact pre-filter expansion state!
	editor.scene_tree.set_branch_expanded("terrain", false)
	editor.scene_tree.set_branch_expanded(team_branch_key, true)
	editor.scene_tree.filter_box.text = "tracked_bldg"
	editor.scene_tree.rebuild()
	editor.scene_tree.filter_box.text = ""
	editor.scene_tree.rebuild()
	check(editor.scene_tree.is_branch_expanded(team_branch_key) and not editor.scene_tree.is_branch_expanded("terrain"),
		"Clearing Scene Tree filter restores exact pre-filter branch expansion state")
	# Reorder procedural layer -> Scene Tree follows stable layer UID!
	editor.scene_tree.set_branch_expanded("layers", true)
	var tracked_layer_uid: int = editor.document.layer_uid(0)
	editor.scene_tree.select_entry("layer", 0)
	if editor.document.layers.size() >= 2:
		check(editor.document.move_procedural_layer(0, 1), "Move layer 0 -> 1 for Scene Tree stable UID test")
		editor.scene_tree.rebuild()
		check(editor.scene_tree.selected_stable_key() == ("layer:%d" % tracked_layer_uid),
			"Scene Tree selection follows reordered procedural layer by stable UID")
		editor.document.undo()
	# Edit path & switch mod profile -> Scene Tree preserves expansion!
	editor.scene_tree.set_branch_expanded("paths", true)
	editor.scene_tree.set_branch_expanded(team_branch_key, true)
	if not editor.document.path_indices().is_empty():
		var pidx: int = editor.document.path_indices()[0]
		var pdata: Dictionary = editor.document.path_at(pidx)
		var ppts: PackedVector2Array = (pdata["points"] as PackedVector2Array).duplicate()
		if not ppts.is_empty():
			ppts[0] += Vector2(2.0, 2.0)
			check(editor.document.edit_path(pidx, String(pdata["name"]), ppts, int(pdata["type"])), "Edit path for Scene Tree rebuild check")
			editor.scene_tree.rebuild()
			check(editor.scene_tree.is_branch_expanded("paths") and editor.scene_tree.is_branch_expanded(team_branch_key),
				"Scene Tree preserves branch expansion across path edit/rebuild")
			editor.document.undo()
	var sc_prof_before: String = editor.document.mod_profile
	check(editor.document.set_target_profile("vrv" if sc_prof_before == "stock" else "stock", editor.document.mission_profile),
		"Switch mod profile for Scene Tree preservation check")
	editor.scene_tree.rebuild()
	check(editor.scene_tree.is_branch_expanded(team_branch_key),
		"Scene Tree preserves branch expansion across mod profile switch")
	editor.document.undo()
	# Scroll restoration across rebuild
	editor.scene_tree._restore_scroll(Vector2(0.0, 48.0))
	await process_frame
	var scroll_before_rb: Vector2 = editor.scene_tree._capture_scroll()
	editor.scene_tree.rebuild()
	await process_frame
	var scroll_after_rb: Vector2 = editor.scene_tree._capture_scroll()
	check(absf(scroll_after_rb.y - scroll_before_rb.y) <= 2.0,
		"Scene Tree preserves vertical scroll position across rebuild (%.1f -> %.1f)" % [scroll_before_rb.y, scroll_after_rb.y])
	# Delete selected object -> clears selection safely (no dangling selection!)
	var dup_for_del: int = editor.document.duplicate_object(tracked_view, orig_obj_pos + Vector3(8.0, 0.0, 0.0))
	check(dup_for_del >= 0, "Duplicate object for delete-selection test")
	editor.scene_tree.rebuild()
	editor.scene_tree.select_entry("object", dup_for_del)
	check(editor.document.remove_object(dup_for_del), "Delete currently selected object")
	editor.scene_tree.rebuild()
	check(editor.scene_tree.selected_stable_key().is_empty(),
		"Deleting selected object clears Scene Tree selection safely (no dangling selection)")
	editor.document.undo() # restore deleted dup
	editor.document.undo() # undo dup
	editor.document.undo() # undo rename
	editor.document.undo() # undo move

	# 4d. Multi-Object Selection Vertical Slice: Select group -> Move group -> 1 Undo -> Native Export/Reimport (Wave G)
	if editor.document.object_count() >= 2:
		var multi_views: Array[int] = [0, 1]
		var pos0_orig: Vector3 = editor.document.object_position(0)
		var pos1_orig: Vector3 = editor.document.object_position(1)
		editor.select_object_views(multi_views)
		check(editor.workspace_state.selected_object_views == multi_views
			and editor.object_attributes.selected_views == multi_views
			and editor.object_tool.selected_views == multi_views,
			"Multi-object selection syncs WorkspaceState, ObjectAttributes and MoveObject")
		var multi_undo_before: int = editor.document.undo_stack.size()
		editor.object_attributes.pos_x.set_value_no_signal(editor.object_attributes.pos_x.value + 6.0)
		editor.object_attributes.pos_z.set_value_no_signal(editor.object_attributes.pos_z.value + 4.0)
		editor.object_attributes.apply_transform()
		check(editor.document.undo_stack.size() == multi_undo_before + 1,
			"Group move of multi-selected objects creates exactly 1 Undo step")
		check(editor.document.object_position(0).distance_to(pos0_orig + Vector3(6.0, 0.0, 4.0)) < 0.05
			and editor.document.object_position(1).distance_to(pos1_orig + Vector3(6.0, 0.0, 4.0)) < 0.05,
			"Group move shifts every selected object by exact delta")
		var multi_export_dir := scratch_dir.path_join("multi-select-export")
		check(writer.export_native(editor.document, multi_export_dir),
			"Native export & reimport succeeds after multi-object group transform")
		editor.document.undo()
		check(editor.document.object_position(0).distance_to(pos0_orig) < 0.01
			and editor.document.object_position(1).distance_to(pos1_orig) < 0.01,
			"1 Undo restores ALL objects in multi-selection group to exact original positions")
		editor.document.redo()
		check(editor.document.object_position(0).distance_to(pos0_orig + Vector3(6.0, 0.0, 4.0)) < 0.05
			and editor.document.object_position(1).distance_to(pos1_orig + Vector3(6.0, 0.0, 4.0)) < 0.05,
			"1 Redo re-applies multi-selection group move")
		editor.document.undo()

	# 4e. CollapsibleSection Persistence, Theme Invariance & Reset Layout (Wave E)
	editor.open_slope_studio()
	var slope_masks_sec: CollapsibleSection = null
	var slope_geo_sec: CollapsibleSection = null
	for ch in editor.slope_studio.get_children():
		if ch is CollapsibleSection:
			var cs := ch as CollapsibleSection
			if cs.section_id == "slope_masks":
				slope_masks_sec = cs
			elif cs.section_id == "slope_geo":
				slope_geo_sec = cs
	check(slope_masks_sec != null and slope_geo_sec != null, "Locate bound Slope Studio CollapsibleSections")
	if slope_masks_sec != null and slope_geo_sec != null:
		check(slope_masks_sec.collapsed == true and slope_geo_sec.collapsed == false,
			"Default collapsed states applied on fresh workspace (slope_masks=true, slope_geo=false)")
		slope_masks_sec.header_button.pressed.emit()
		slope_geo_sec.header_button.pressed.emit()
		check(slope_masks_sec.collapsed == false and slope_geo_sec.collapsed == true,
			"Toggling CollapsibleSection updates local state")
		check(editor.workspace_state.is_section_collapsed("slope_masks", true) == false
			and editor.workspace_state.is_section_collapsed("slope_geo", false) == true,
			"CollapsibleSection toggles propagate to WorkspaceState")
		# Tool switch + theme switch preserve collapsed state
		editor.activate_terrain_brush()
		editor.set_wintage_theme("vintagedark", false, false)
		editor.open_slope_studio()
		check(slope_masks_sec.collapsed == false and slope_geo_sec.collapsed == true,
			"Collapsed sections survive tool switch and Wintage theme change")
		editor.set_wintage_theme(Wintage.DEFAULT_THEME, false, false)
		# Reload config into fresh WorkspaceState + section simulates app restart
		var sec_cfg := ConfigFile.new()
		check(sec_cfg.load(cfg_path) == OK, "Reload editor.cfg for collapsed section persistence check")
		var ws_sec_reload := WorkspaceState.new()
		ws_sec_reload.load_from_config(sec_cfg, Vector2(1280, 720))
		var probe_masks := CollapsibleSection.new("Masks", "slope_masks", true)
		var probe_geo := CollapsibleSection.new("Geo", "slope_geo", false)
		probe_masks.bind_workspace_state(ws_sec_reload)
		probe_geo.bind_workspace_state(ws_sec_reload)
		check(probe_masks.collapsed == false and probe_geo.collapsed == true,
			"Restart restores persisted CollapsibleSection states from editor.cfg")
		probe_masks.free()
		probe_geo.free()
		# Reset Workspace Layout restores defaults!
		editor.reset_workspace_layout()
		check(slope_masks_sec.collapsed == true and slope_geo_sec.collapsed == false
			and editor.workspace_state.collapsed_sections.is_empty(),
			"Reset Workspace Layout restores default CollapsibleSection states and clears overrides")

	# 4f. Responsive Stacked 2D Layout Toggle & Lifecycle Transitions (Waves F & G)
	editor.toggle_views_vertical()
	check(editor.views.vertical == true and editor.workspace_state.stack_2d_below == true,
		"Toggle 2D Stacked Below 3D switches SplitContainer vertical mode")
	editor.toggle_views_vertical()
	check(editor.views.vertical == false and editor.workspace_state.stack_2d_below == false,
		"Toggle back restores side-by-side 3D + 2D split")

	# Slope Preview -> Nodes & Slope Preview -> New Map clear active Slope preview cleanly!
	editor.open_slope_studio()
	check(editor.slope_studio.preview_shape() and editor.document.has_preview(), "Arm Slope preview before Nodes switch")
	editor.open_studio()
	check(not editor.document.has_preview() and editor.workspace_state.active_preview_owner.is_empty(),
		"Switching Slope Preview -> Nodes cleanly clears active Slope preview")
	editor.open_slope_studio()
	check(editor.slope_studio.preview_shape() and editor.document.has_preview(), "Arm Slope preview before New Map switch")
	editor.open_new_map_wizard()
	check(not editor.document.has_preview() and editor.workspace_state.active_preview_owner.is_empty(),
		"Switching Slope Preview -> New Map cleanly clears active preview and ownership")
	editor.set_center_mode(WorkspaceState.CenterMode.SPLIT_3D_2D)

	# Pinned Inspector -> Switch Tool keeps Inspector pinned while updating active tool & selection!
	editor.open_slope_studio()
	editor.workspace_state.set_pinned(true)
	editor.activate_terrain_brush()
	check(editor.workspace_state.active_tool == WorkspaceState.Tool.TERRAIN_BRUSH
		and editor.workspace_state.active_inspector_context == WorkspaceState.InspectorContext.SLOPE,
		"Pinned Inspector keeps SLOPE panel visible while switching active tool to TERRAIN_BRUSH")
	editor.workspace_state.set_pinned(false)

	# Object Placement -> Path Editing cancels pending object placement
	editor.start_place_object("morock03", 0, -1, true)
	check(not editor.pending_place_spec.is_empty(), "Arm Object Placement mode")
	editor._toggle_move_paths(true)
	check(editor.pending_place_spec.is_empty() and editor.workspace_state.active_tool == WorkspaceState.Tool.PATH_MOVE,
		"Switching Object Placement -> Path Editing cancels pending placement cleanly")
	editor._toggle_move_paths(false)

	# Profile Switch while Assets tab hidden invalidates ObjectBrowser for next open
	editor.workspace_state.set_left_tab(WorkspaceState.LeftTab.SCENE, true)
	editor.open_object_browser()
	var bro_mod_before: String = editor.object_browser.catalog_mod_profile
	editor.workspace_state.set_left_tab(WorkspaceState.LeftTab.SCENE, true)
	var next_mod := "vrv" if bro_mod_before == "stock" else "stock"
	check(editor.document.set_target_profile(next_mod, editor.document.mission_profile), "Switch target mod profile while Assets tab hidden")
	editor.open_object_browser()
	check(editor.object_browser.catalog_mod_profile == next_mod,
		"Opening Assets tab after hidden Profile Switch refreshes ObjectBrowser for new profile")
	editor.document.undo()

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
