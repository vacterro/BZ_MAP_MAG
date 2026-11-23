extends SceneTree

## SAIHANDOFF-28 (T-54) editor-level acceptance: two Sculpt Layer regions over
## two separate areas, the composed surface visible, then REAL viewport strokes
## through Editor.view_input. The Sculpt Mask must never hide the other region,
## Pressure must be FLOW (target/flow split), and refusals must not leak state.

const EditorScene := preload("res://editor.tscn")
const Document := preload("res://core/map_document.gd")
const BrushPanel := preload("res://tools/brush_panel.gd")
const Terrain := preload("res://formats/terrain_v5.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func copy_package(source: String, target: String) -> String:
	DirAccess.make_dir_recursive_absolute(target)
	var stem := source.get_file().get_basename().to_lower()
	for name in DirAccess.get_files_at(source.get_base_dir()):
		if name.to_lower().get_basename() != stem and name.to_lower() != stem + "_load.dds":
			continue
		var out := FileAccess.open(target.path_join(name), FileAccess.WRITE)
		out.store_buffer(FileAccess.get_file_as_bytes(source.get_base_dir().path_join(name)))
		out.close()
	return target.path_join(source.get_file())


func top_pixel(editor: Node, terrain: Terrain, sample: Vector2) -> Vector2:
	var rect: Rect2 = editor.top.view_rect()
	var dimensions := Vector2(terrain.dimensions)
	return rect.position + (sample / dimensions) * rect.size


func top_sample(editor: Node, terrain: Terrain, sample: Vector2) -> Vector2:
	# The 2D view quantises pixels back to samples; snap the stroke target onto
	# the exact sample centre the assertion reads afterwards.
	var pixel := top_pixel(editor, terrain, sample)
	var back: Vector2 = editor.top.sample_at(pixel)
	return pixel + (sample - back)


func mouse_press(editor: Node, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	editor.view_input(event, editor.top)


func mouse_drag(editor: Node, from: Vector2, to: Vector2, steps: int) -> void:
	for i in range(1, steps + 1):
		var event := InputEventMouseMotion.new()
		event.position = from.lerp(to, float(i) / float(steps))
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		editor.view_input(event, editor.top)


func mouse_release(editor: Node, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	editor.view_input(event, editor.top)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Pass the Brave BZN fixture and a scratch directory.")
		quit(2)
		return
	var scratch := args[1]
	DirAccess.make_dir_recursive_absolute(scratch)
	root.size = Vector2i(1120, 690)
	var editor := EditorScene.instantiate()
	root.add_child(editor)
	editor.settings_path = scratch.path_join("mask-continuity-editor.cfg")
	for _i in 4:
		await process_frame
	var path := copy_package(args[0], scratch.path_join("mask-continuity-map"))
	check(editor.open_map(path), "continuity: open copied map")
	for _i in 6:
		await process_frame
	var doc: Document = editor.document
	var terrain: Terrain = doc.package.terrain
	var dims := terrain.dimensions

	editor.activate_terrain_brush()
	var idx_a := 200 * dims.x + 200
	var idx_b := 240 * dims.x + 240
	var base_a := float(doc.base_heights[idx_a])
	var base_b := float(doc.base_heights[idx_b])
	check(doc.add_sculpt_layer() == 0, "continuity: add sculpt layer A")
	check(doc.sculpt_dab(Vector2(200.0, 200.0), 8.0, 20.0, Document.BrushShape.CIRCLE),
		"continuity: sculpt region A")
	check(doc.add_sculpt_layer() == 1, "continuity: add sculpt layer B")
	check(doc.sculpt_dab(Vector2(240.0, 240.0), 8.0, -15.0, Document.BrushShape.CIRCLE),
		"continuity: sculpt region B")
	var delta_a := float(((doc.sculpt_layers[0] as Dictionary)["deltas"] as Dictionary)[idx_a])
	var delta_b := float(((doc.sculpt_layers[1] as Dictionary)["deltas"] as Dictionary)[idx_b])
	var expected_a := base_a + delta_a
	var expected_b := base_b + delta_b
	check(doc.add_sculpt_mask(1, 1.0), "continuity: add fully revealing mask on layer B")
	check(doc.sculpt_preview(), "continuity: full sculpt composition visible")
	check(doc.preview_after.has(idx_a) and doc.preview_after.has(idx_b),
		"continuity: both regions are in the composed preview")
	check(absf(terrain.heights[idx_a] - expected_a) < 0.01, "continuity: region A visible before stroke")
	check(absf(terrain.heights[idx_b] - expected_b) < 0.01, "continuity: region B visible before stroke")

	# Real viewport gesture on the 2D view: mask stroke must keep region A.
	var brush: BrushPanel = editor.brush_panel
	brush.set_brush_size(8)
	brush.set_pressure(100)
	brush.set_shape(Document.BrushShape.CIRCLE)
	brush.sculpt_mask_target.set_pressed_no_signal(true)
	# Start from a fully revealed mask; hide 100% at the centre so the stroke
	# actually changes mask samples while region A stays visible throughout.
	brush.sculpt_mask_reveal.set_pressed_no_signal(false)
	brush.sculpt_mask_strength.set_value_no_signal(1.0)
	brush.update_buttons()
	check(brush.sculpt_mask_active(), "continuity: brush routes into sculpt mask")
	var press_at := top_sample(editor, terrain, Vector2(240.0, 240.0))
	var drag_to := press_at + Vector2(10.0, 4.0)
	var history_before := doc.undo_stack.size()
	mouse_press(editor, press_at)
	check(doc.sculpt_mask_stroke_active, "continuity: viewport press begins the mask stroke")
	check(absf(terrain.heights[idx_a] - expected_a) < 0.01,
		"continuity: region A still visible at stroke start (got %.3f, want %.3f)" % [terrain.heights[idx_a], expected_a])
	check(doc.preview_after.has(idx_a), "continuity: region A preview survives stroke start")
	mouse_drag(editor, press_at, drag_to, 4)
	check(absf(terrain.heights[idx_a] - expected_a) < 0.01,
		"continuity: region A still visible after drag (got %.3f)" % terrain.heights[idx_a])
	check(doc.sculpt_mask_stroke_active, "continuity: drag keeps the stroke alive")
	mouse_release(editor, drag_to)
	check(not doc.sculpt_mask_stroke_active, "continuity: release ends the stroke")
	check(doc.undo_stack.size() == history_before + 1, "continuity: one Undo for the mask gesture")
	check(absf(terrain.heights[idx_a] - expected_a) < 0.01, "continuity: region A visible after commit")
	# Hiding B was the gesture, so B leaves the visible surface by design; A
	# must remain. The full composed mask is restored by undoing the gesture.
	check(absf(terrain.heights[idx_b] - base_b) < 0.01, "continuity: hidden region B back at base")
	check(doc.preview_after.has(idx_a), "continuity: region A preview stays after commit")
	check(editor.workspace_state.active_preview_owner == "sculpt",
		"continuity: workspace mirror tracks the sculpt-owned preview")
	check(absf(float(doc.export_heights().get(idx_a, -1.0)) - expected_a) < 0.01,
		"continuity: native export agrees on region A")
	doc.undo()
	check(absf(terrain.heights[idx_b] - expected_b) < 0.01,
		"continuity: undo restores region B on screen")
	check(doc.preview_after.has(idx_a) and doc.preview_after.has(idx_b),
		"continuity: full composition restored by undo")
	check(absf(float(doc.export_heights().get(idx_b, -1.0)) - expected_b) < 0.01,
		"continuity: native export agrees on restored region B")
	doc.redo()
	check(absf(terrain.heights[idx_b] - base_b) < 0.01, "continuity: redo hides B again")

	# Cancel mid-stroke restores the exact pre-stroke composition.
	mouse_press(editor, press_at)
	check(doc.sculpt_mask_stroke_active, "continuity: second stroke begins")
	mouse_drag(editor, press_at, drag_to, 2)
	check(doc.sculpt_mask_stroke_active, "continuity: second stroke still active")
	var cancel_event := InputEventKey.new()
	cancel_event.keycode = KEY_ESCAPE
	cancel_event.pressed = true
	editor._shortcut_input(cancel_event)
	check(not doc.sculpt_mask_stroke_active, "continuity: Escape cancels the mask stroke")
	check(absf(terrain.heights[idx_a] - expected_a) < 0.01, "continuity: region A intact after cancel")
	check(absf(terrain.heights[idx_b] - base_b) < 0.01, "continuity: region B stays hidden after cancel")
	check(doc.undo_stack.size() == history_before + 1, "continuity: cancel adds no history")

	# Pressure is FLOW through the real brush panel: after undo, B is revealed
	# (mask 1). One 20% hide dab must move 1 -> 0.8, never all the way to 0.
	doc.undo()
	check(absf(terrain.heights[idx_b] - expected_b) < 0.01, "pressure: undo returns B to a revealed mask")
	brush.sculpt_mask_strength.set_value_no_signal(1.0)
	brush.set_pressure(20)
	brush.sculpt_mask_reveal.set_pressed_no_signal(false)
	mouse_press(editor, press_at)
	check(doc.sculpt_mask_stroke_active, "pressure: 20% hide stroke begins")
	mouse_release(editor, press_at)
	var mask_samples: Dictionary = ((doc.sculpt_layers[1] as Dictionary)["mask"] as Dictionary)["samples"]
	check(absf(float(mask_samples.get(idx_b, -1.0)) - 0.8) < 0.02,
		"pressure: hide 20%% moves 1 -> 0.8 at the centre (got %.4f)" % float(mask_samples.get(idx_b, -1.0)))
	check(absf(terrain.heights[idx_a] - expected_a) < 0.01,
		"pressure: region A unaffected by the 20% stroke")

	print("Mask continuity editor acceptance complete.")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
