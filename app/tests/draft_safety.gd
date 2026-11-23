extends SceneTree

## Focused acceptance for SAIHANDOFF-17: UID-aware draft identity, deletion-aware
## three-way merge, draft-aware autosave payload and the first sculpt layer.

const Document := preload("res://core/map_document.gd")
const Studio := preload("res://nodes/node_studio.gd")
const Graph := preload("res://nodes/height_graph.gd")
const Store := preload("res://core/autosave_store.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Sculpt := preload("res://core/sculpt_layers.gd")
const ColorLayers := preload("res://core/color_layers.gd")
const Package := preload("res://formats/map_package.gd")
const Terrain := preload("res://formats/terrain_v5.gd")
const LayersPanel := preload("res://ui/layers_panel.gd")
const BrushPanel := preload("res://tools/brush_panel.gd")

var failures := 0
var scratch := ""
var material_refresh_count := 0
var material_refresh_layer := -1
var material_refresh_region := Rect2i()


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func _sculpt_snapshot_for_test(doc: Document) -> Array:
	var state: Array = []
	for layer in doc.sculpt_layers:
		state.append((layer as Dictionary).duplicate(true))
	return state


func delta_at(doc: Document, index: int) -> float:
	for layer_v in doc.sculpt_layers:
		var layer: Dictionary = layer_v
		if (layer["deltas"] as Dictionary).has(index):
			return float((layer["deltas"] as Dictionary)[index])
	return 0.0


func watch_material_refresh(doc: Document) -> void:
	material_refresh_count = 0
	material_refresh_layer = -1
	material_refresh_region = Rect2i()
	if not doc.materials_changed.is_connected(_on_test_materials_changed):
		doc.materials_changed.connect(_on_test_materials_changed)


func unwatch_material_refresh(doc: Document) -> void:
	if doc.materials_changed.is_connected(_on_test_materials_changed):
		doc.materials_changed.disconnect(_on_test_materials_changed)


func _on_test_materials_changed(region: Rect2i, layer: int) -> void:
	material_refresh_count += 1
	material_refresh_layer = layer
	material_refresh_region = region


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


func fresh_document(fixture: String, name: String) -> Document:
	var path := copy_package(fixture, scratch.path_join(name))
	var doc := Document.new()
	check(doc.open(path), "open fresh document " + name)
	return doc


func fresh_studio(doc: Document) -> Studio:
	var studio := Studio.new()
	root.add_child(studio)
	studio.begin(doc, Vector2i.ZERO)
	return studio


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Pass the Brave BZN fixture and a scratch directory.")
		quit(2)
		return
	scratch = args[1]
	test_draft_identity(args[0])
	test_deletion_merge(args[0])
	test_conflict_resolution(args[0])
	test_autosave_draft(args[0])
	test_sculpt(args[0])
	test_sculpt_over_committed_edit(args[0])
	test_sculpt_stroke_transaction(args[0])
	test_native_export_composes_unbaked_sculpt(args[0])
	test_sculpt_bake_preview_ownership(args[0])
	test_recovery_pair_integrity(args[0])
	test_active_edit_transaction_guard(args[0])
	test_sculpt_hold_painting(args[0])
	test_strict_sculpt_payload_validation(args[0])
	test_sculpt_opacity_gestures(args[0])
	test_live_sculpt_stroke_composition(args[0])
	test_sculpt_selection_is_navigation(args[0])
	test_sculpt_visibility_and_reorder_recompose(args[0])
	test_sculpt_opacity_cancel_restores_preview(args[0])
	test_active_sculpt_uid_serialization(args[0])
	test_color_layer_composition(args[0])
	test_color_layer_stroke_and_history(args[0])
	test_color_layer_persistence(args[0])
	test_color_layer_native_export(args[0])
	test_color_layer_raw_validation(args[0])
	test_color_empty_override_keeps_native_source(args[0])
	test_color_live_stroke_keeps_other_layers(args[0])
	test_color_opacity_gesture_lifecycle(args[0])
	test_color_opacity_foreign_preview_refusal(args[0])
	test_color_opacity_zero_movement_ui(args[0])
	test_color_empty_preview_repaints(args[0])
	test_color_empty_state_on_off_on(args[0])
	test_color_opacity_zero_to_positive_recovery(args[0])
	test_color_preview_central_admission(args[0])
	test_color_coverage_contract(args[0])
	test_color_mask_vertical_slice(args[0])
	test_color_mask_undo_integrity(args[0])
	test_color_stroke_coverage_strength(args[0])
	test_mask_brush_panel_integration(args[0])
	test_mask_stroke_transaction_admission(args[0])
	test_sculpt_mask_vertical_slice(args[0])
	test_sculpt_mask_stroke_admission(args[0])
	test_sculpt_mask_live_composition(args[0])
	test_sculpt_mask_empty_state_and_atomicity(args[0])
	test_sculpt_mask_brush_dispatch_and_owner(args[0])
	test_sculpt_mask_history_keeps_composition(args[0])
	test_sculpt_mask_two_region_continuity(args[0])
	test_sculpt_mask_pressure_oracles(args[0])
	test_sculpt_mask_strict_dab_validation(args[0])
	test_empty_foreign_preview_admission(args[0])
	test_sculpt_stroke_reentrancy(args[0])
	test_empty_sculpt_color_preview_refusal(args[0])
	test_empty_color_sculpt_opacity_refusal(args[0])
	test_empty_sculpt_color_opacity_refusal(args[0])
	test_color_mask_flow_oracles(args[0])
	test_mask_operations(args[0])
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func test_draft_identity(fixture: String) -> void:
	var doc := fresh_document(fixture, "identity")
	check(doc.add_procedural_layer(Graph.layer()) >= 0, "add second identical layer")
	var studio := fresh_studio(doc)
	studio.sync_from_document()
	check(not studio.has_uncommitted_draft(), "identical committed layers are not a draft")
	var first_uid := studio.working_uids[0]
	studio.selected = 0
	studio.move_layer(1)
	check(studio.working_uids[1] == first_uid and studio.has_uncommitted_draft(),
		"reordering identical layers arms draft through UID identity")
	var order := studio.working_uids.duplicate()
	studio.begin(doc, Vector2i.ZERO, 0)
	check(studio.working_uids == order and studio.has_uncommitted_draft(),
		"tab switch preserves reordered UID identity")
	check(studio.keep_layers(), "keep reordered draft")
	check(doc.layer_uids == order, "commit writes reordered UIDs into MapDocument")
	var path := scratch.path_join("identity.bzmag")
	var writer := Snapshots.new()
	check(writer.save_project(doc, path), "save BZMAG with persistent layer identities")
	var reopened := Document.new()
	check(reopened.open(path) and reopened.layer_uids == order,
		"save/reopen preserves layer identity metadata")
	check(reopened.layers == doc.layers, "save/reopen preserves layer contents")
	studio.discard_draft()
	studio.selected = 0
	studio.move_layer(1)
	studio.selected = 1
	studio.move_layer(-1)
	check(not studio.has_uncommitted_draft(), "reversing a UID-only reorder clears false dirty state")
	studio.queue_free()


func test_deletion_merge(fixture: String) -> void:
	var doc := fresh_document(fixture, "deletion")
	check(doc.add_procedural_layer(Graph.layer()) >= 0, "add layer B")
	var studio := fresh_studio(doc)
	studio.sync_from_document()
	var uid_b := studio.working_uids[1]
	studio.selected = 1
	studio.remove_layer()
	check(studio.has_uncommitted_draft() and studio.working_uids.size() == 1,
		"draft deletes layer B without touching committed stack")
	var addition := Graph.layer()
	addition["seed"] = 1234.0
	check(doc.add_procedural_layer(addition) >= 0, "externally add layer C")
	var retained_from_doc := doc.layer_uids.duplicate()
	var result := studio.sync_from_document()
	check(String(result.get("status", "")) == "merged", "merge succeeds after draft deletion plus external addition")
	check(studio.working_uids.find(uid_b) < 0, "draft deletion is not silently resurrected")
	check(studio.working_uids.size() == 2 and not studio.working.is_empty(), "merged stack has A and C")
	prints("MERGE_UIDS", studio.working_uids, "B", uid_b, "RETAINED", retained_from_doc)

	var seed_c := 0.0
	for i in studio.working_uids.size():
		if studio.working[i]["seed"] == 1234.0:
			seed_c = 1234.0
	check(is_equal_approx(seed_c, 1234.0), "independent external addition survives the merge")
	check(not studio.conflict_pending, "draft deletion plus unrelated addition is not a conflict")

	var doc2 := fresh_document(fixture, "deletion-edit")
	check(doc2.add_procedural_layer(Graph.layer()) >= 0, "add layer B in second fixture")
	var studio2 := fresh_studio(doc2)
	studio2.sync_from_document()
	studio2.selected = 1
	studio2.remove_layer()
	check(doc2.set_procedural_layer_opacity(0, 0.5), "external opacity edit on an unrelated layer")
	check(String(studio2.sync_from_document().get("status", "")) == "merged", "merge with unrelated opacity edit")
	check(is_equal_approx(float(studio2.working[0]["opacity"]), 0.5), "independent opacity edit survives draft deletion")

	var doc3 := fresh_document(fixture, "deletion-conflict")
	check(doc3.add_procedural_layer(Graph.layer()) >= 0, "add layer B in conflict fixture")
	var studio3 := fresh_studio(doc3)
	studio3.sync_from_document()
	studio3.selected = 1
	studio3.remove_layer()
	check(doc3.set_procedural_layer_opacity(1, 0.25), "external edit of the draft-deleted layer")
	check(String(studio3.sync_from_document().get("status", "")) == "conflict",
		"draft deletion plus external edit of the same layer raises conflict")
	check(studio3.conflict_pending and not studio3.build_conflict_diff().is_empty(),
		"conflict exposes a docked diff")
	studio.queue_free()
	studio2.queue_free()
	studio3.queue_free()


func test_conflict_resolution(fixture: String) -> void:
	var doc := fresh_document(fixture, "conflict-resolution")
	check(doc.add_procedural_layer(Graph.layer()) >= 0, "add layer B for resolution test")
	var studio := fresh_studio(doc)
	studio.sync_from_document()
	# Draft edits A seed and deletes B; external edits A opacity and deletes B too.
	studio.selected = 0
	studio.set_parameter("seed", 4321.0)
	var uid_a := studio.working_uids[0]
	var uid_b := studio.working_uids[1]
	studio.selected = 1
	studio.remove_layer()
	check(doc.set_procedural_layer_opacity(0, 0.3), "external independent opacity edit")
	check(doc.remove_procedural_layer(1), "external deletion of the same layer B")
	var status := String(studio.sync_from_document().get("status", ""))
	check(status == "merged", "both sides deleting B is not a conflict: " + status)
	var idx_a := studio.working_uids.find(uid_a)
	check(idx_a >= 0 and not studio.working_uids.has(uid_b), "independent deletion and edits preserved")
	check(is_equal_approx(float(studio.working[idx_a]["seed"]), 4321.0)
		and is_equal_approx(float(studio.working[idx_a]["opacity"]), 0.3),
		"draft edit and external edit coexist after merge")
	check(studio.keep_layers(), "keep merged draft commits in one step")
	studio.queue_free()


func test_autosave_draft(fixture: String) -> void:
	var doc := fresh_document(fixture, "autosave")
	var studio := fresh_studio(doc)
	studio.selected = 0
	studio.set_parameter("seed", 8080.0)
	check(studio.has_uncommitted_draft(), "autosave fixture has an uncommitted draft")
	var payload := {
		"revision": studio.draft_revision,
		"working": studio.working.duplicate(true),
		"workingUids": studio.working_uids.duplicate(),
		"baseLayers": studio.base_snapshot.duplicate(true),
		"baseUids": studio.base_uids.duplicate(),
		"baseLayerRevision": studio.base_layer_revision,
		"selected": studio.selected,
	}
	var root_dir := scratch.path_join("autosaves")
	var store := Store.new()
	var slot: String = store.publish(doc, root_dir, 3, payload)
	check(not slot.is_empty(), "publish committed slot with draft payload")
	var recovered: Dictionary = Store.read_draft(slot)
	check(not recovered.is_empty() and int(recovered.get("schema", 0)) == Store.DRAFT_SCHEMA,
		"recovery draft is a separate validated record")
	var inner: Dictionary = recovered.get("draft", {})
	var restored_work_uids: Array[int] = []
	for uid in (inner.get("workingUids", []) as Array):
		restored_work_uids.append(int(uid))
	var restored_base_uids: Array[int] = []
	for uid in (inner.get("baseUids", []) as Array):
		restored_base_uids.append(int(uid))
	check(restored_work_uids == studio.working_uids and restored_base_uids == studio.base_uids,
		"draft payload records base and draft UID identity")
	var good := slot
	store.failure = "crash"
	studio.set_parameter("seed", 9090.0)
	var payload2 := payload.duplicate(true)
	payload2["working"] = studio.working.duplicate(true)
	check(store.publish(doc, root_dir, 3, payload2).is_empty(), "injected crash stops publication")
	check(Store.latest(Store.project_dir(root_dir, doc.package.source_path)) == good,
		"crash leaves the last good committed slot intact")
	store.failure = ""
	studio.queue_free()


func test_sculpt(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt")
	var terrain := doc.package.terrain
	var original := terrain.encode(doc.edits)
	check(doc.add_sculpt_layer() == 0, "create first sculpt layer")
	check(doc.sculpt_dab(Vector2(512.0, 512.0), 32.0, 20.0), "sculpt dab records sparse delta")
	var layer: Dictionary = doc.sculpt_layers[0]
	check((layer["deltas"] as Dictionary).size() > 0, "sparse delta has records")
	check(doc.edits.is_empty() and terrain.encode(doc.edits) == original,
		"native TER stays byte-identical before Bake")
	check(doc.sculpt_preview() and doc.has_preview(), "sculpt preview composes without committing")
	var preview_index := -1
	var sculpt_deltas: Dictionary = (doc.sculpt_layers[0] as Dictionary)["deltas"]
	for index: int in sculpt_deltas:
		preview_index = index
		break
	var base_sample := doc.base_heights[preview_index]
	var expected := snappedf(base_sample + float(sculpt_deltas[preview_index]), doc.package.granularity)
	check(preview_index >= 0 and is_equal_approx(float(doc.preview_after[preview_index]), expected),
		"preview changes composed height")
	var preview_value := float(doc.preview_after[preview_index])
	doc.clear_preview()
	check(doc.set_sculpt_layer_enabled(0, false), "disable sculpt layer")
	check(not doc.sculpt_preview(), "disabled layer has no previewable result")
	check(doc.set_sculpt_layer_enabled(0, true), "enable sculpt layer")
	check(doc.set_sculpt_layer_opacity(0, 0.5), "set sculpt layer opacity")
	check(doc.sculpt_preview(), "opacity preview composes")
	var half := float(doc.preview_after[preview_index])
	check(absf(half - base_sample) <= absf(float(sculpt_deltas[preview_index]) * 0.5) + doc.package.granularity * 1.5,
		"opacity halves composed delta")
	doc.clear_preview()
	check(doc.set_sculpt_layer_opacity(0, 1.0), "restore full opacity")
	check(doc.sculpt_preview(), "armed full-opacity sculpt preview")
	var export_writer := Snapshots.new()
	check(not export_writer.export_native(doc, scratch.path_join("sculpt-preview")),
		"native export refuses an unbaked sculpt preview")
	check(doc.bake_sculpt_layers(), "bake sculpt layer")
	check(not doc.edits.is_empty() and doc.sculpt_layers.is_empty(), "bake flattens deltas into native edits")
	check(terrain.encode(doc.edits) != original, "baked TER bytes differ from source")
	doc.undo()
	check(doc.edits.is_empty() and terrain.encode(doc.edits) == original, "one undo restores original TER")
	doc.redo()
	check(not doc.edits.is_empty(), "redo restores baked TER")
	var sculpt_bzmag := scratch.path_join("sculpt.bzmag")
	var writer := Snapshots.new()
	# Save before bake to prove sparse records persist in the editor project.
	var fresh := fresh_document(fixture, "sculpt-persist")
	fresh.add_sculpt_layer()
	fresh.sculpt_dab(Vector2(400.0, 400.0), 24.0, 15.0)
	check(writer.save_project(fresh, sculpt_bzmag), "save BZMAG with sculpt layer metadata")
	var reopened := Document.new()
	check(reopened.open(sculpt_bzmag) and reopened.sculpt_layers.size() == 1,
		"reopen restores sculpt layer record")
	var restored: Dictionary = reopened.sculpt_layers[0]
	check((restored["deltas"] as Dictionary).size() > 0 and reopened.edits.is_empty(),
		"reopened sculpt deltas stay non-destructive")
	check(Sculpt.validate_stack(reopened.sculpt_layers, reopened.package.terrain.heights.size()),
		"restored sculpt deltas validate")


## A sculpt layer must compose over the committed document revision, not the
## original TER: a prior +50 m brush edit under a +delta layer survives preview
## and Bake.
func test_sculpt_over_committed_edit(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-committed")
	check(doc.add_sculpt_layer() == 0, "create sculpt layer over committed edit")
	check(doc.sculpt_dab(Vector2(256.0, 256.0), 16.0, 20.0), "sculpt dab for committed-base test")
	var deltas: Dictionary = (doc.sculpt_layers[0] as Dictionary)["deltas"]
	var index := -1
	for key: int in deltas:
		index = key
		break
	check(index >= 0, "committed-base test found a sculpt delta")
	var delta := float(deltas[index])
	var committed := doc.base_heights[index] + 50.0
	doc.set_height(index, committed)
	check(doc.sculpt_preview(), "preview composes over committed edit")
	var composed := float(doc.preview_after.get(index, -1.0))
	check(absf(composed - (committed + delta)) <= doc.package.granularity,
		"preview preserves committed height under sculpt delta")
	check(doc.bake_sculpt_layers(), "bake sculpt over committed edit")
	check(absf(doc.package.terrain.heights[index] - (committed + delta)) <= doc.package.granularity,
		"bake preserves committed height under sculpt delta")
	doc.undo()
	check(is_equal_approx(doc.package.terrain.heights[index], committed),
		"undo restores committed height")
	doc.redo()
	check(absf(doc.package.terrain.heights[index] - (committed + delta)) <= doc.package.granularity,
		"redo restores composed height")


## One continuous sculpt stroke is one Undo entry, however many dabs and
## mirrored passes it contains. Cancelling a stroke records nothing.
func test_sculpt_stroke_transaction(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-stroke")
	check(doc.add_sculpt_layer() == 0, "stroke test creates sculpt layer")
	var start := doc.undo_stack.size()
	check(doc.sculpt_dab(Vector2(200.0, 200.0), 12.0, 20.0), "single dab commits")
	check(doc.undo_stack.size() == start + 1, "one dab creates one Undo entry")
	doc.undo()
	check(doc.undo_stack.size() == start, "single dab undo")
	doc.redo()
	check(doc.undo_stack.size() == start + 1, "single dab redo")

	var many := fresh_document(fixture, "sculpt-stroke-many")
	check(many.add_sculpt_layer() == 0, "many-dab stroke creates sculpt layer")
	start = many.undo_stack.size()
	check(many.begin_sculpt_stroke(), "begin stroke")
	for i in range(50):
		check(many.sculpt_dab(Vector2(120.0 + i * 2.0, 120.0), 8.0, 20.0), "stroke dab")
	check(many.end_sculpt_stroke(), "commit stroke")
	check(many.undo_stack.size() == start + 1, "50 dabs create one Undo entry")
	many.undo()
	check((many.sculpt_layers[0] as Dictionary)["deltas"].is_empty(), "stroke undo clears all deltas")
	many.redo()
	check(not (many.sculpt_layers[0] as Dictionary)["deltas"].is_empty(), "stroke redo restores all deltas")

	var cancelled := fresh_document(fixture, "sculpt-stroke-cancel")
	check(cancelled.add_sculpt_layer() == 0, "cancel stroke creates sculpt layer")
	start = cancelled.undo_stack.size()
	check(cancelled.begin_sculpt_stroke(), "begin cancelled stroke")
	for i in range(10):
		check(cancelled.sculpt_dab(Vector2(140.0 + i * 2.0, 140.0), 8.0, 20.0), "cancel stroke dab")
	cancelled.cancel_sculpt_stroke()
	check(cancelled.undo_stack.size() == start, "cancelled stroke records no Undo entry")
	check((cancelled.sculpt_layers[0] as Dictionary)["deltas"].is_empty(), "cancelled stroke restores prior deltas")
	check(not cancelled.sculpt_stroke_active, "cancelled stroke clears active flag")

	var noop := fresh_document(fixture, "sculpt-stroke-noop")
	check(noop.add_sculpt_layer() == 0, "no-op stroke creates sculpt layer")
	start = noop.undo_stack.size()
	check(noop.begin_sculpt_stroke(), "begin no-op stroke")
	check(noop.sculpt_dab(Vector2(120.0, 120.0), 8.0, 0.0), "zero-amount dab is no-op")
	check(noop.end_sculpt_stroke(), "commit no-op stroke")
	check(noop.undo_stack.size() == start, "no-op stroke records no Undo entry")


## Native export composes enabled sculpt deltas into staging without baking
## the document or creating an Undo entry (SAIHANDOFF-18 P0-3).
func test_native_export_composes_unbaked_sculpt(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-export")
	check(doc.add_sculpt_layer() == 0, "export test creates sculpt layer")
	check(doc.sculpt_dab(Vector2(256.0, 256.0), 16.0, 20.0), "export test records sculpt delta")
	var deltas: Dictionary = (doc.sculpt_layers[0] as Dictionary)["deltas"]
	var index := -1
	for key: int in deltas:
		index = key
		break
	check(index >= 0, "export test found sculpt delta")
	var expected := doc.base_heights[index] + float(deltas[index])
	var writer := Snapshots.new()
	var target := scratch.path_join("sculpt-composed-export")
	check(writer.export_native(doc, target), "native export composes unbaked sculpt layer")
	check(doc.sculpt_layers.size() == 1 and doc.edits.is_empty(), "export leaves document layers unchanged")
	var reimported := Package.new()
	check(reimported.open(target.path_join(doc.package.source_path.get_file())), "composed export reimports")
	var ter_path := target.path_join(doc.package.terrain_name.to_upper())
	check(FileAccess.file_exists(ter_path), "composed export has TER file")
	var ter := Terrain.new()
	check(ter.decode(FileAccess.get_file_as_bytes(ter_path)), "composed TER decodes")
	check(is_equal_approx(ter.heights[index], expected), "composed TER contains sculpt delta")


## Sculpt Bake accepts only a Sculpt-owned preview for the current document
## and stack revision. Cross-tool, stale and modified-layer previews are refused
## without consuming them or clearing sculpt layers.
func test_sculpt_bake_preview_ownership(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-owner")
	check(doc.add_sculpt_layer() == 0, "owner test creates sculpt layer")
	check(doc.sculpt_dab(Vector2(200.0, 200.0), 16.0, 20.0), "owner test records delta")
	check(doc.sculpt_preview(), "sculpt preview owns preview")
	var index := -1
	for key: int in doc.preview_after:
		index = key
		break
	check(index >= 0 and doc.preview_owner == "sculpt", "preview owner is sculpt")
	check(doc.bake_sculpt_layers(), "owned sculpt preview bakes")
	check(doc.sculpt_layers.is_empty(), "owned bake clears layers")

	var cross := fresh_document(fixture, "sculpt-owner-cross")
	check(cross.add_sculpt_layer() == 0, "cross-tool test creates sculpt layer")
	check(cross.sculpt_dab(Vector2(200.0, 200.0), 16.0, 20.0), "cross-tool test records delta")
	check(cross.preview_slope_plane(Vector2i(200, 200), 32.0, 300.0, Vector2(0.02, 0.0)), "slope preview created")
	check(cross.has_preview() and cross.preview_owner != "sculpt", "slope preview is not sculpt-owned")
	var undo_before := cross.undo_stack.size()
	check(not cross.bake_sculpt_layers(), "cross-tool bake refused")
	check(cross.sculpt_layers.size() == 1 and cross.undo_stack.size() == undo_before, "refused bake preserves layers and history")

	var stale := fresh_document(fixture, "sculpt-owner-stale")
	check(stale.add_sculpt_layer() == 0, "stale test creates sculpt layer")
	check(stale.sculpt_dab(Vector2(200.0, 200.0), 16.0, 20.0), "stale test records delta")
	check(stale.sculpt_preview(), "stale test creates sculpt preview")
	check(stale.set_sculpt_layer_opacity(0, 0.5), "sculpt layer modified after preview")
	check(stale.preview_sculpt_revision == stale.sculpt_revision,
		"layer mutation recomposes the sculpt-owned preview revision")
	check(stale.bake_sculpt_layers(), "recomposed sculpt preview bakes after layer change")


## Recovery sidecars are bound to the exact committed slot by SHA256, and a
## content fingerprint replaces the session-local revision as durable identity.
func test_recovery_pair_integrity(fixture: String) -> void:
	var doc := fresh_document(fixture, "recovery-pair")
	var studio := fresh_studio(doc)
	studio.selected = 0
	studio.set_parameter("seed", 7070.0)
	var payload := {
		"revision": studio.draft_revision,
		"working": studio.working.duplicate(true),
		"workingUids": studio.working_uids.duplicate(),
		"baseLayers": studio.base_snapshot.duplicate(true),
		"baseUids": studio.base_uids.duplicate(),
		"baseLayerRevision": studio.base_layer_revision,
		"selected": studio.selected,
	}
	var root := scratch.path_join("recovery-autosaves")
	var store := Store.new()
	var slot := store.publish(doc, root, 2, payload)
	check(not slot.is_empty(), "recovery pair publishes slot")
	var draft := Store.read_draft(slot)
	check(not draft.is_empty(), "recovery pair reads sidecar")
	check(String(draft.get("slotSha256", "")) == FileAccess.get_sha256(slot),
		"sidecar carries exact slot SHA256")
	var fingerprint := String(draft.get("baseFingerprint", ""))
	check(not fingerprint.is_empty() and fingerprint == Store.base_stack_fingerprint(doc),
		"sidecar carries content-based base fingerprint")
	# A sidecar whose binding was rewritten must not be offered for this slot.
	var path := slot + Store.DRAFT_SUFFIX
	var bytes := FileAccess.get_file_as_string(path)
	var broken := JSON.parse_string(bytes) as Dictionary
	broken["slotSha256"] = "0".repeat(64)
	var write := FileAccess.open(path, FileAccess.WRITE)
	write.store_string(JSON.stringify(broken))
	write.close()
	check(Store.read_draft(slot).is_empty(), "mismatched sidecar binding is rejected")
	studio.queue_free()


## Every operation that serializes a document must refuse while a brush or
## drag transaction is unfinished, and work normally after commit.
func test_active_edit_transaction_guard(fixture: String) -> void:
	var doc := fresh_document(fixture, "txn-guard")
	check(doc.add_sculpt_layer() == 0, "guard test creates sculpt layer")
	check(doc.begin_sculpt_stroke(), "begin stroke for guard test")
	check(doc.sculpt_dab(Vector2(240.0, 240.0), 12.0, 20.0), "staged dab for guard test")
	check(doc.has_active_edit_transaction(), "stroke is an active edit transaction")
	var writer := Snapshots.new()
	check(not writer.save_project(doc, scratch.path_join("txn-guard.bzmag")),
		"save refuses during active stroke")
	check(not writer.export_native(doc, scratch.path_join("txn-guard-export")),
		"export refuses during active stroke")
	var store := Store.new()
	check(store.publish(doc, scratch.path_join("txn-autosave"), 2).is_empty(),
		"autosave defers during active stroke")
	var undo_len := doc.undo_stack.size()
	doc.undo()
	check(doc.undo_stack.size() == undo_len, "undo refuses during active stroke")
	check(doc.end_sculpt_stroke(), "commit stroke")
	check(not doc.has_active_edit_transaction(), "transaction cleared after commit")
	check(writer.save_project(doc, scratch.path_join("txn-guard.bzmag")),
		"save succeeds after commit")
	check(writer.export_native(doc, scratch.path_join("txn-guard-export")),
		"export succeeds after commit")


## Hold painting feeds the same sculpt stroke transaction, so repeated ticks
## stay one Undo and use the hold pressure scale without touching native TER.
func test_sculpt_hold_painting(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-hold")
	check(doc.add_sculpt_layer() == 0, "hold test creates sculpt layer")
	var start := doc.undo_stack.size()
	check(doc.begin_sculpt_stroke(), "begin hold stroke")
	var original_ter := doc.package.terrain.encode(doc.edits)
	for _i in range(20):
		check(doc.sculpt_dab(Vector2(300.0, 300.0), 16.0, 40.0 * 0.15), "hold dab")
	check(doc.end_sculpt_stroke(), "commit hold stroke")
	check(doc.undo_stack.size() == start + 1, "hold ticks create one Undo entry")
	check(not doc.sculpt_layers.is_empty() and (doc.sculpt_layers[0] as Dictionary)["deltas"].size() > 0,
		"hold ticks accumulate sculpt deltas")
	check(doc.package.terrain.encode(doc.edits) == original_ter, "hold painting leaves native TER untouched")
	doc.undo()
	check((doc.sculpt_layers[0] as Dictionary)["deltas"].is_empty(), "hold undo clears deltas")


## Corrupt saved sculpt records are refused at raw validation; they must never
## be normalized into a different valid sample or layer.
func test_strict_sculpt_payload_validation(fixture: String) -> void:
	var valid := Sculpt.layer(1)
	valid["deltas"] = {12: 5.0}
	check(Sculpt.validate_raw_record(valid, 1024), "valid raw sculpt record accepted")
	for bad_key in ["oops", "-1", "1.5", "01"]:
		var rec := Sculpt.layer(1)
		rec["deltas"] = {bad_key: 5.0}
		check(not Sculpt.validate_raw_record(rec, 1024), "reject non-canonical key: " + String(bad_key))
	var out_of_range := Sculpt.layer(1)
	out_of_range["deltas"] = {2000: 5.0}
	check(not Sculpt.validate_raw_record(out_of_range, 1024), "reject out-of-range sample")
	var nan_delta := Sculpt.layer(1)
	nan_delta["deltas"] = {12: NAN}
	check(not Sculpt.validate_raw_record(nan_delta, 1024), "reject NaN delta")
	var inf_delta := Sculpt.layer(1)
	inf_delta["deltas"] = {12: INF}
	check(not Sculpt.validate_raw_record(inf_delta, 1024), "reject infinite delta")
	var huge := Sculpt.layer(1)
	huge["deltas"] = {12: Sculpt.MAX_ABS_DELTA + 1.0}
	check(not Sculpt.validate_raw_record(huge, 1024), "reject excessive delta")
	var bad_opacity := Sculpt.layer(1)
	bad_opacity["opacity"] = 2.5
	check(not Sculpt.validate_raw_record(bad_opacity, 1024), "reject out-of-range opacity")
	var string_uid := Sculpt.layer(1)
	string_uid["uid"] = "1"
	check(not Sculpt.validate_raw_record(string_uid, 1024), "reject string UID")
	var duplicate_uids := [Sculpt.layer(1), Sculpt.layer(1)]
	check(not Sculpt.validate_stack_raw(duplicate_uids, 1024), "reject duplicate layer UID")
	var integral_uid := Sculpt.layer(1)
	integral_uid["uid"] = 1.0
	check(Sculpt.validate_raw_record(integral_uid, 1024), "accept integral float UID representation")
	for bad_uid in [1.5, 0.0, -1.0, NAN, INF, -INF, 9007199254740993.0, 1e30]:
		var rec := Sculpt.layer(1)
		rec["uid"] = bad_uid
		check(not Sculpt.validate_raw_record(rec, 1024), "reject invalid UID: " + str(bad_uid))
	var canonical_duplicates := [Sculpt.layer(1), integral_uid]
	check(not Sculpt.validate_stack_raw(canonical_duplicates, 1024), "reject duplicate UID after canonicalization")


## T-46: opacity gestures stage preview and commit exactly one Undo entry.
func test_sculpt_opacity_gestures(fixture: String) -> void:
	var doc := fresh_document(fixture, "opacity-gesture")
	check(doc.add_sculpt_layer() == 0, "opacity gesture creates sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 16.0, 20.0), "opacity gesture paints a delta")
	var deltas: Dictionary = (doc.sculpt_layers[0] as Dictionary)["deltas"]
	var index := -1
	for key: int in deltas:
		index = key
		break
	check(index >= 0, "opacity gesture found composed sample")
	var uid := int((doc.sculpt_layers[0] as Dictionary)["uid"])
	var base := doc.base_heights[index]
	var start_undo := doc.undo_stack.size()
	check(doc.begin_sculpt_opacity_preview(0), "begin opacity gesture")
	for i in range(20):
		var v := 0.05 * float(i + 1)
		check(doc.preview_sculpt_layer_opacity(uid, v), "preview opacity %.2f" % v)
	check(doc.undo_stack.size() == start_undo, "opacity preview creates no Undo entries")
	check(doc.has_preview() and doc.preview_owner == "sculpt", "opacity preview owns sculpt surface")
	var previewed := float(doc.preview_after.get(index, -1.0))
	check(absf(previewed - (base + float(deltas[index]) * 0.95)) <= doc.package.granularity * 2.0,
		"opacity preview changes visible surface")
	check(is_equal_approx(float((doc.sculpt_layers[0] as Dictionary)["opacity"]), 1.0),
		"opacity preview does not mutate committed layer")
	check(doc.commit_sculpt_opacity_preview(uid, 0.35), "commit opacity gesture")
	check(doc.undo_stack.size() == start_undo + 1, "commit creates exactly one Undo entry")
	check(is_equal_approx(float((doc.sculpt_layers[0] as Dictionary)["opacity"]), 0.35), "committed opacity stored")
	doc.undo()
	check(is_equal_approx(float((doc.sculpt_layers[0] as Dictionary)["opacity"]), 1.0), "undo restores opacity")
	doc.redo()
	check(is_equal_approx(float((doc.sculpt_layers[0] as Dictionary)["opacity"]), 0.35), "redo restores opacity")

	var cancelled := fresh_document(fixture, "opacity-cancel")
	cancelled.add_sculpt_layer()
	cancelled.sculpt_dab(Vector2(220.0, 220.0), 16.0, 20.0)
	var cancel_uid := int((cancelled.sculpt_layers[0] as Dictionary)["uid"])
	var cancel_undo := cancelled.undo_stack.size()
	check(cancelled.begin_sculpt_opacity_preview(0), "begin cancelled opacity gesture")
	check(cancelled.preview_sculpt_layer_opacity(cancel_uid, 0.25), "preview cancelled opacity")
	cancelled.cancel_sculpt_opacity_preview()
	check(cancelled.undo_stack.size() == cancel_undo, "cancelled opacity creates no Undo")
	check(is_equal_approx(float((cancelled.sculpt_layers[0] as Dictionary)["opacity"]), 1.0), "cancelled opacity restores committed value")
	check(not cancelled.has_preview(), "cancelled opacity clears preview")


## T-46: dabs compose visible heights during the stroke with one Undo at end.
func test_live_sculpt_stroke_composition(fixture: String) -> void:
	var doc := fresh_document(fixture, "live-stroke")
	check(doc.add_sculpt_layer() == 0, "live stroke creates sculpt layer")
	var start_undo := doc.undo_stack.size()
	check(doc.begin_sculpt_stroke(), "begin live stroke")
	check(doc.sculpt_dab(Vector2(256.0, 256.0), 20.0, 30.0), "live stroke first dab")
	check(doc.has_preview() and doc.preview_owner == "sculpt", "first dab composes sculpt-owned preview")
	var deltas: Dictionary = (doc.sculpt_layers[0] as Dictionary)["deltas"]
	var index := -1
	for key: int in deltas:
		index = key
		break
	check(index >= 0 and absf(float(doc.preview_after.get(index, 0.0)) - (doc.base_heights[index] + float(deltas[index]))) <= doc.package.granularity,
		"first dab visible height matches export composition")
	check(doc.edits.is_empty(), "live preview leaves committed terrain untouched")
	check(doc.undo_stack.size() == start_undo, "live dabs add no Undo entries")
	check(doc.sculpt_dab(Vector2(260.0, 256.0), 20.0, 30.0), "live stroke second dab")
	check(doc.preview_after.size() > deltas.size() / 2, "second dab extends composed region")
	var last_visible := float(doc.preview_after.get(index, 0.0))
	var expected := doc.export_heights()
	check(absf(last_visible - float(expected.get(index, 0.0))) <= doc.package.granularity * 2.0,
		"live visible height matches native export composition")
	check(doc.end_sculpt_stroke(), "commit live stroke")
	check(doc.undo_stack.size() == start_undo + 1, "live stroke creates one Undo")
	check(not doc.has_preview(), "document-level commit clears live preview so export is allowed")
	check(doc.sculpt_preview() and doc.has_preview(), "editor recomposes final preview after commit")
	check(absf(float(doc.preview_after.get(index, 0.0)) - float(expected.get(index, 0.0))) <= doc.package.granularity * 2.0,
		"final composed preview matches native export")
	doc.undo()
	check(not doc.has_preview(), "undo clears stale sculpt preview")


## T-46: selecting a sculpt layer is navigation, not a terrain edit.
func test_sculpt_selection_is_navigation(fixture: String) -> void:
	var doc := fresh_document(fixture, "selection-nav")
	check(doc.add_sculpt_layer() == 0, "create layer A")
	check(doc.sculpt_dab(Vector2(180.0, 180.0), 12.0, 15.0), "paint layer A")
	check(doc.add_sculpt_layer() == 1, "create layer B")
	var before_stack := doc.undo_stack.size()
	var before_revision := doc.edit_revision
	var before_sculpt_revision := doc.sculpt_revision
	var before_layers := doc.sculpt_layers.duplicate(true)
	var uid_b := int((doc.sculpt_layers[1] as Dictionary)["uid"])
	check(doc.set_active_sculpt_layer(1), "select layer B")
	check(doc.undo_stack.size() == before_stack, "selection adds no Undo")
	check(doc.edit_revision == before_revision, "selection does not dirty document")
	check(doc.sculpt_revision == before_sculpt_revision, "selection does not bump sculpt revision")
	check(doc.sculpt_layers == before_layers, "selection leaves layer content unchanged")
	check(doc.active_sculpt_uid == uid_b, "selection updates active UID")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 12.0, 15.0), "paint targets selected layer B")
	check(not (doc.sculpt_layers[1] as Dictionary)["deltas"].is_empty(), "selected layer B receives deltas")


## T-46: any validated sculpt layer mutation must leave the viewport showing
## the same composite Native Export would produce, with the preview still
## owned by sculpt and no extra Undo entries.
func test_sculpt_visibility_and_reorder_recompose(fixture: String) -> void:
	var doc := fresh_document(fixture, "visibility-recompose")
	check(doc.add_sculpt_layer() == 0, "visibility test creates layer A")
	check(doc.sculpt_dab(Vector2(180.0, 180.0), 12.0, 25.0), "paint layer A")
	check(doc.add_sculpt_layer() == 1, "visibility test creates layer B")
	check(doc.sculpt_dab(Vector2(260.0, 260.0), 12.0, 25.0), "paint layer B")
	check(doc.sculpt_preview(), "compose both sculpt layers")
	var sample_a := -1
	var sample_b := -1
	for key: int in (doc.sculpt_layers[0] as Dictionary)["deltas"]:
		if not (doc.sculpt_layers[1] as Dictionary)["deltas"].has(key):
			sample_a = key
			break
	for key: int in (doc.sculpt_layers[1] as Dictionary)["deltas"]:
		if not (doc.sculpt_layers[0] as Dictionary)["deltas"].has(key):
			sample_b = key
			break
	check(sample_a >= 0 and sample_b >= 0 and sample_a != sample_b, "distinct dab samples found")
	var full_a := float(doc.preview_after.get(sample_a, -1.0))
	var full_b := float(doc.preview_after.get(sample_b, -1.0))
	var expected_a := float(doc.export_heights().get(sample_a, -1.0))
	var expected_b := float(doc.export_heights().get(sample_b, -1.0))
	check(absf(full_a - expected_a) <= doc.package.granularity * 2.0 and absf(full_b - expected_b) <= doc.package.granularity * 2.0,
		"initial sculpt preview matches native export")
	var undo_before := doc.undo_stack.size()
	check(doc.set_sculpt_layer_enabled(1, false), "disable layer B under preview")
	check(doc.has_preview() and doc.preview_owner == "sculpt", "visibility keeps sculpt-owned preview")
	check(doc.undo_stack.size() == undo_before + 1, "visibility creates one Undo")
	check(absf(float(doc.preview_after.get(sample_a, -1.0)) - full_a) <= doc.package.granularity * 2.0,
		"layer A stays visible after B is disabled")
	check(not doc.preview_after.has(sample_b) and absf(doc.package.terrain.heights[sample_b] - doc.base_heights[sample_b]) <= doc.package.granularity * 2.0,
		"hidden layer B is removed from the visible surface")
	var export_hidden := doc.export_heights()
	check(absf(float(doc.preview_after.get(sample_a, -1.0)) - float(export_hidden.get(sample_a, -1.0))) <= doc.package.granularity * 2.0,
		"visibility preview agrees with native export")
	check(doc.set_sculpt_layer_enabled(1, true), "re-enable layer B")
	check(absf(float(doc.preview_after.get(sample_b, -1.0)) - full_b) <= doc.package.granularity * 2.0,
		"re-enabled layer B returns to the visible surface")

	var order := fresh_document(fixture, "reorder-recompose")
	check(order.add_sculpt_layer() == 0, "reorder test creates layer A")
	check(order.sculpt_dab(Vector2(240.0, 240.0), 14.0, 25.0), "reorder paints layer A")
	check(order.add_sculpt_layer() == 1, "reorder test creates layer B")
	check(order.sculpt_dab(Vector2(244.0, 244.0), 14.0, 25.0), "reorder paints layer B")
	check(order.set_sculpt_layer_opacity(0, 0.25), "reorder sets opacity where order matters")
	check(order.sculpt_preview(), "reorder composes both layers")
	var overlap := -1
	for key: int in (order.sculpt_layers[0] as Dictionary)["deltas"]:
		if (order.sculpt_layers[1] as Dictionary)["deltas"].has(key):
			overlap = key
			break
	check(overlap >= 0, "reorder test found an overlapping sample")
	# Force a near-limit committed height so the order of clamped deltas matters.
	var limit := mini(int(order.MAX_EDITOR_ABS_HEIGHT), int(order.package.granularity * 32000.0))
	order.set_height(overlap, float(limit - 1))
	(order.sculpt_layers[0] as Dictionary)["deltas"][overlap] = 10.0
	(order.sculpt_layers[1] as Dictionary)["deltas"][overlap] = -10.0
	check(order.sculpt_preview(), "near-limit reorder preview composes")
	var before_reorder := float(order.preview_after.get(overlap, -1.0))
	var active_before := order.active_sculpt_uid
	undo_before = order.undo_stack.size()
	check(order.move_sculpt_layer(0, 1), "reorder sculpt layers")
	check(order.active_sculpt_uid == active_before, "reorder preserves active UID")
	check(order.undo_stack.size() == undo_before + 1, "reorder creates one Undo")
	check(order.has_preview() and order.preview_owner == "sculpt", "reorder keeps sculpt-owned preview")
	check(not is_equal_approx(float(order.preview_after.get(overlap, -1.0)), before_reorder),
		"near-limit overlapping heights change when order changes")
	var reordered_export := order.export_heights()
	check(absf(float(order.preview_after.get(overlap, -1.0)) - float(reordered_export.get(overlap, -1.0))) <= order.package.granularity * 2.0,
		"reordered preview matches native export")

	var foreign := fresh_document(fixture, "visibility-foreign-preview")
	check(foreign.add_sculpt_layer() == 0, "foreign preview test creates sculpt layer")
	check(foreign.sculpt_dab(Vector2(200.0, 200.0), 12.0, 20.0), "foreign preview test paints delta")
	check(foreign.preview_slope_plane(Vector2i(200, 200), 32.0, 300.0, Vector2(0.02, 0.0)), "slope owns preview")
	check(foreign.set_sculpt_layer_enabled(0, false), "visibility toggle succeeds under foreign preview")
	check(foreign.preview_owner != "sculpt", "visibility toggle does not steal foreign preview")


## T-46: cancelling an opacity gesture returns to the surface that was visible
## before the gesture, not to the committed terrain.
func test_sculpt_opacity_cancel_restores_preview(fixture: String) -> void:
	var doc := fresh_document(fixture, "opacity-cancel-restore")
	check(doc.add_sculpt_layer() == 0, "opacity cancel test creates layer A")
	check(doc.sculpt_dab(Vector2(180.0, 180.0), 12.0, 25.0), "opacity cancel paints layer A")
	check(doc.add_sculpt_layer() == 1, "opacity cancel test creates layer B")
	check(doc.sculpt_dab(Vector2(270.0, 270.0), 12.0, 25.0), "opacity cancel paints layer B")
	check(doc.sculpt_preview(), "compose prior sculpt preview")
	var sample := -1
	for key: int in (doc.sculpt_layers[1] as Dictionary)["deltas"]:
		if not (doc.sculpt_layers[0] as Dictionary)["deltas"].has(key):
			sample = key
			break
	check(sample >= 0, "opacity cancel found layer B delta")
	var prior := float(doc.preview_after.get(sample, -1.0))
	var uid_b := int((doc.sculpt_layers[1] as Dictionary)["uid"])
	var undo_before := doc.undo_stack.size()
	check(doc.begin_sculpt_opacity_preview(1), "begin opacity gesture on layer B")
	check(doc.preview_sculpt_layer_opacity(uid_b, 0.2), "stage reduced opacity")
	check(absf(float(doc.preview_after.get(sample, -1.0)) - prior) > doc.package.granularity * 0.5,
		"staged opacity changes the visible surface")
	doc.cancel_sculpt_opacity_preview(uid_b)
	check(doc.undo_stack.size() == undo_before, "opacity cancel adds no Undo")
	check(is_equal_approx(float((doc.sculpt_layers[1] as Dictionary)["opacity"]), 1.0), "opacity cancel preserves committed value")
	check(doc.has_preview() and doc.preview_owner == "sculpt", "opacity cancel restores sculpt preview")
	check(absf(float(doc.preview_after.get(sample, -1.0)) - prior) <= doc.package.granularity * 2.0,
		"opacity cancel restores the previous visible composite")

	var none := fresh_document(fixture, "opacity-cancel-none")
	check(none.add_sculpt_layer() == 0, "no prior preview test creates layer")
	check(none.sculpt_dab(Vector2(200.0, 200.0), 12.0, 20.0), "no prior preview paints delta")
	check(none.begin_sculpt_opacity_preview(0), "begin opacity without prior preview")
	check(none.preview_sculpt_layer_opacity(int((none.sculpt_layers[0] as Dictionary)["uid"]), 0.4), "stage opacity without prior preview")
	none.cancel_sculpt_opacity_preview()
	check(not none.has_preview(), "cancel without prior preview clears staged surface")


## T-46: activeSculptUid is editor selection metadata, but a serialized value
## must still be either a valid integral existing UID or an explicit sentinel.
func test_active_sculpt_uid_serialization(fixture: String) -> void:
	var doc := fresh_document(fixture, "active-uid-source")
	check(doc.add_sculpt_layer() == 0, "active UID test creates sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 12.0, 20.0), "active UID test paints delta")
	var writer := Snapshots.new()
	var source := scratch.path_join("active-uid.bzmag")
	check(writer.save_project(doc, source), "save source project for UID validation")
	var raw := JSON.parse_string(FileAccess.get_file_as_string(source)) as Dictionary
	var uid := int((doc.sculpt_layers[0] as Dictionary)["uid"])

	var cases := [
		{"label": "integral int", "value": uid, "accept": true, "expected": uid},
		{"label": "integral float", "value": float(uid), "accept": true, "expected": uid},
		{"label": "missing field", "value": "missing", "accept": true, "expected": uid},
		{"label": "null sentinel", "value": null, "accept": true, "expected": -1},
		{"label": "minus one sentinel", "value": -1, "accept": true, "expected": -1},
		{"label": "fractional", "value": 1.5, "accept": false, "expected": -1},
		{"label": "string", "value": "oops", "accept": false, "expected": -1},
		{"label": "unknown UID", "value": uid + 99, "accept": false, "expected": -1},
		{"label": "zero UID", "value": 0, "accept": false, "expected": -1},
	]
	for item: Dictionary in cases:
		var payload := raw.duplicate(true)
		var value: Variant = item["value"]
		if value is String and String(value) == "missing":
			payload.erase("activeSculptUid")
		else:
			payload["activeSculptUid"] = value
		var case_path := scratch.path_join("uid-case.bzmag")
		var out := FileAccess.open(case_path, FileAccess.WRITE)
		out.store_string(JSON.stringify(payload))
		out.close()
		var reopened := Document.new()
		var ok := reopened.open(case_path)
		check(ok == bool(item["accept"]), "activeSculptUid " + String(item["label"]))
		if ok:
			check(reopened.active_sculpt_uid == int(item["expected"]),
				"activeSculptUid expected value for " + String(item["label"]))
	var legacy := raw.duplicate(true)
	legacy.erase("sculptLayers")
	legacy.erase("activeSculptUid")
	var legacy_path := scratch.path_join("uid-legacy.bzmag")
	var legacy_out := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_out.store_string(JSON.stringify(legacy))
	legacy_out.close()
	var legacy_doc := Document.new()
	check(legacy_doc.open(legacy_path) and legacy_doc.active_sculpt_uid == -1,
		"legacy BZMAG without sculpt selection opens")


## T-47: deterministic non-destructive color composition, stroke transactions,
## persistence and native export. Native TER and committed color_edits stay
## untouched; export writes exactly what the composited preview shows.
func test_color_layer_composition(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-composition")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	var source := terrain.source_material_value(Terrain.Layer.COLOR, sample)
	terrain.color_edits[sample] = 0x204060

	var a := ColorLayers.layer(1)
	a["opacity"] = 0.5
	a["samples"] = {sample: {"rgb": 0xff0000, "coverage": 1.0}}
	var b := ColorLayers.layer(2)
	b["opacity"] = 0.5
	b["samples"] = {sample: {"rgb": 0x0000ff, "coverage": 1.0}}
	var stack := [a, b]
	var expected_ab := ColorLayers.blend_word(ColorLayers.blend_word(0x204060, 0xff0000, 0.5), 0x0000ff, 0.5)
	check(ColorLayers.compose_word(source, terrain.color_edits, stack, sample) == expected_ab,
		"two overlapping layers blend in stack order")
	b["enabled"] = false
	check(ColorLayers.compose_word(source, terrain.color_edits, stack, sample) == ColorLayers.blend_word(0x204060, 0xff0000, 0.5),
		"disabled layer falls back to committed RGB plus earlier layers")
	a["enabled"] = false
	b["enabled"] = true
	check(ColorLayers.compose_word(source, terrain.color_edits, stack, sample) == ColorLayers.blend_word(0x204060, 0x0000ff, 0.5),
		"reorder changes overlap result")
	a["enabled"] = true
	b["enabled"] = true
	stack = [b, a]
	var expected_ba := ColorLayers.blend_word(ColorLayers.blend_word(0x204060, 0x0000ff, 0.5), 0xff0000, 0.5)
	check(ColorLayers.compose_word(source, terrain.color_edits, stack, sample) == expected_ba,
		"reordered layers produce the documented order")
	check(expected_ba != expected_ab, "overlapping red and blue are order sensitive")
	a["opacity"] = 0.0
	check(ColorLayers.compose_word(source, terrain.color_edits, [a], sample) == 0x204060,
		"zero opacity shows committed RGB, not original source RGB")
	a["opacity"] = 1.0
	a["samples"][sample]["coverage"] = 0.5
	check(ColorLayers.compose_word(source, terrain.color_edits, [a], sample) == ColorLayers.blend_word(0x204060, 0xff0000, 0.5),
		"partial coverage blends with committed RGB")
	var again := ColorLayers.compose_word(source, terrain.color_edits, [a], sample)
	check(again == ColorLayers.compose_word(source, terrain.color_edits, [a], sample),
		"same composition input gives byte-identical output")
	var opaque := ColorLayers.layer(3)
	opaque["samples"] = {sample: {"rgb": 0xffffff, "coverage": 1.0}}
	check(ColorLayers.compose_word(source, {}, [opaque], sample) == 0xffffff,
		"opaque white layer yields exact 24-bit RGB word")


func test_color_layer_stroke_and_history(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-stroke")
	check(doc.color_layers.is_empty(), "new document has no color layers")
	var committed_before: Dictionary = doc.package.terrain.color_edits.duplicate(true)
	check(doc.add_color_layer() == 0, "add first color layer")
	var uid := int((doc.color_layers[0] as Dictionary)["uid"])
	check(doc.active_color_uid == uid, "new color layer becomes active")
	var undo_before := doc.undo_stack.size()
	check(doc.begin_color_stroke(), "begin color stroke")
	for i in range(3):
		check(doc.color_dab(Vector2(200.0 + i, 200.0), 6.0, 0xff8800, Document.BrushShape.CIRCLE, 1.0),
			"color dab %d" % i)
	check(doc.color_stroke_active, "color stroke stays active across dabs")
	check(doc.undo_stack.size() == undo_before, "no Undo during color stroke")
	check(doc.end_color_stroke(), "commit color stroke")
	check(doc.undo_stack.size() == undo_before + 1, "one continuous stroke equals one Undo")
	check((doc.color_layers[0] as Dictionary)["samples"].size() > 0, "stroke stores sparse RGB samples")
	check(doc.package.terrain.color_edits == committed_before, "color stroke never mutates committed native RGB")
	check(doc.has_preview() and doc.preview_owner == "color", "color stroke leaves composed preview active")
	doc.undo()
	check((doc.color_layers[0] as Dictionary)["samples"].is_empty(), "Undo removes the color stroke")
	doc.redo()
	check(not (doc.color_layers[0] as Dictionary)["samples"].is_empty(), "Redo restores the color stroke")
	var undo_after_redo := doc.undo_stack.size()
	var before_cancel: Dictionary = (doc.color_layers[0] as Dictionary)["samples"].duplicate(true)
	check(doc.begin_color_stroke(), "begin cancel probe")
	doc.color_dab(Vector2(240.0, 240.0), 6.0, 0x00ff00)
	check((doc.color_layers[0] as Dictionary)["samples"] != before_cancel, "cancel probe changed samples")
	doc.cancel_color_stroke()
	check((doc.color_layers[0] as Dictionary)["samples"] == before_cancel,
		"cancel restores exact sparse samples")
	check(doc.undo_stack.size() == undo_after_redo, "cancel creates no Undo")
	check(doc.package.terrain.color_edits == committed_before, "cancel never touches committed native RGB")
	var added := doc.add_color_layer()
	check(added == 1, "add second color layer")
	check(doc.move_color_layer(1, 0), "reorder color layers")
	check(doc.set_color_layer_enabled(0, false), "toggle color layer visibility")
	check(doc.set_color_layer_opacity(0, 0.35), "change color layer opacity")
	check(doc.rename_color_layer(1, "Wash"), "rename color layer")
	check(doc.color_layers.size() == 2, "color layer stack preserved")


func test_color_layer_persistence(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-persist")
	doc.add_color_layer()
	doc.color_dab(Vector2(300.0, 300.0), 10.0, 0x33aaff)
	doc.set_color_layer_opacity(0, 0.6)
	doc.rename_color_layer(0, "Blue Wash")
	var writer := Snapshots.new()
	var target := scratch.path_join("color-layer.bzmag")
	check(writer.save_project(doc, target), "save BZMAG with color layers")
	var reopened := Document.new()
	check(reopened.open(target), "reopen BZMAG with color layers")
	check(reopened.color_layers.size() == 1, "color layer count survives save/reopen")
	var restored: Dictionary = reopened.color_layers[0]
	check(String(restored["name"]) == "Blue Wash", "color layer name survives save/reopen")
	check(is_equal_approx(float(restored["opacity"]), 0.6), "color layer opacity survives save/reopen")
	check((restored["samples"] as Dictionary).size() > 0, "color layer sparse samples survive save/reopen")
	check(reopened.active_color_uid == doc.active_color_uid, "active color UID survives save/reopen")
	check(reopened.export_colors() == doc.export_colors(), "composed RGB survives BZMAG reopen")
	var legacy := JSON.parse_string(FileAccess.get_file_as_string(target)) as Dictionary
	legacy.erase("colorLayers")
	legacy.erase("activeColorUid")
	var legacy_path := scratch.path_join("color-legacy.bzmag")
	var legacy_out := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_out.store_string(JSON.stringify(legacy))
	legacy_out.close()
	var legacy_doc := Document.new()
	check(legacy_doc.open(legacy_path) and legacy_doc.color_layers.is_empty(), "legacy BZMAG opens with empty color stack")


func test_color_layer_native_export(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-export")
	var terrain: Terrain = doc.package.terrain
	var sample := 210 * terrain.dimensions.x + 210
	terrain.color_edits[sample] = 0x204060
	doc.add_color_layer()
	var layer_data: Dictionary = doc.color_layers[0]
	layer_data["samples"] = {sample: {"rgb": 0xff0000, "coverage": 1.0}}
	layer_data["opacity"] = 0.5
	var expected := ColorLayers.blend_word(0x204060, 0xff0000, 0.5)
	var export_colors := doc.export_colors()
	check(export_colors.get(sample, -1) == expected, "export_colors contains composed RGB")
	check(terrain.color_edits[sample] == 0x204060, "export composition never mutates committed color edits")
	var writer := Snapshots.new()
	var target := scratch.path_join("color-native")
	check(writer.export_native(doc, target), "native export succeeds with unbaked color layer")
	var reimport := Package.new()
	check(reimport.open(target.path_join(doc.package.source_path.get_file())), "color export reimports")
	check(reimport.terrain.material_value(Terrain.Layer.COLOR, sample) == expected,
		"exported native TER contains composed RGB without Bake")
	check(expected != terrain.color_edits[sample],
		"negative check: exported TER differs from committed color while layer is active")
	check(terrain.source_material_value(Terrain.Layer.COLOR, sample) != expected,
		"negative check: exported TER differs from original source color")


func test_color_layer_raw_validation(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-validation")
	var terrain: Terrain = doc.package.terrain
	var valid := ColorLayers.layer(1)
	valid["samples"] = {12: {"rgb": 0x112233, "coverage": 1.0}}
	check(ColorLayers.validate_raw_record(valid, terrain.heights.size()), "valid color record accepted")
	var cases := [
		{"label": "fractional uid", "value": 1.5, "field": "uid"},
		{"label": "zero uid", "value": 0, "field": "uid"},
		{"label": "negative uid", "value": -1, "field": "uid"},
		{"label": "non-finite opacity", "value": NAN, "field": "opacity"},
		{"label": "oversized opacity", "value": 1.5, "field": "opacity"},
	]
	for item: Dictionary in cases:
		var bad := valid.duplicate(true)
		bad[String(item["field"])] = item["value"]
		check(not ColorLayers.validate_raw_record(bad, terrain.heights.size()),
			"raw validation rejects " + String(item["label"]))
	var bad_key := valid.duplicate(true)
	bad_key["samples"] = {"oops": {"rgb": 0x112233, "coverage": 1.0}}
	check(not ColorLayers.validate_raw_record(bad_key, terrain.heights.size()), "raw validation rejects non-canonical sample key")
	var bad_rgb := valid.duplicate(true)
	bad_rgb["samples"] = {12: {"rgb": 0x1000000, "coverage": 1.0}}
	check(not ColorLayers.validate_raw_record(bad_rgb, terrain.heights.size()), "raw validation rejects RGB beyond 24-bit")
	var bad_coverage := valid.duplicate(true)
	bad_coverage["samples"] = {12: {"rgb": 0x112233, "coverage": 0.0}}
	check(not ColorLayers.validate_raw_record(bad_coverage, terrain.heights.size()), "raw validation rejects zero coverage")
	var duplicate := ColorLayers.layer(2)
	check(not ColorLayers.validate_stack_raw([valid, duplicate, duplicate], terrain.heights.size()),
		"duplicate color UIDs rejected")


## P0 regression: empty composed override is not "no override". A Color Layer
## that cancels a committed native edit must export native source RGB while the
## committed edit and BZMAG layer remain intact.
func test_color_empty_override_keeps_native_source(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-empty-override")
	var terrain: Terrain = doc.package.terrain
	var sample := 210 * terrain.dimensions.x + 210
	var source := terrain.source_material_value(Terrain.Layer.COLOR, sample)
	var committed := source ^ 0xffffff
	if committed == source:
		committed = (source + 1) & 0xffffff
	terrain.color_edits[sample] = committed
	check(doc.add_color_layer() == 0, "add layer for empty-override probe")
	var layer_data: Dictionary = doc.color_layers[0]
	layer_data["samples"] = {sample: {"rgb": source, "coverage": 1.0}}
	layer_data["opacity"] = 1.0
	check(doc.export_colors().is_empty(), "composed override is empty when layer returns sample to source")
	check(terrain.color_edits[sample] == committed, "committed native RGB stays unchanged before export")
	var writer := Snapshots.new()
	var target := scratch.path_join("color-empty-override-export")
	check(writer.export_native(doc, target), "native export succeeds with empty composed override: " + writer.error)
	var reimport := Package.new()
	check(reimport.open(target.path_join(doc.package.source_path.get_file())), "empty-override export reimports")
	check(reimport.terrain.material_value(Terrain.Layer.COLOR, sample) == source,
		"empty composed override exports source RGB, not committed edit")
	check(terrain.color_edits[sample] == committed, "export does not mutate committed native RGB")
	check(doc.color_layers.size() == 1 and (doc.color_layers[0] as Dictionary)["samples"].has(sample),
		"BZMAG color layer survives empty-override export")
	var undo_before := doc.undo_stack.size()
	doc.undo()
	doc.redo()
	check(doc.undo_stack.size() == undo_before, "export does not add Undo history")
	unwatch_material_refresh(doc)


## P0 regression: a new dab must merge into the existing composed preview, not
## replace it with only the current stroke's touched samples.
func test_color_live_stroke_keeps_other_layers(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-live-cumulative")
	var terrain: Terrain = doc.package.terrain
	var a := 200 * terrain.dimensions.x + 200
	var b := 260 * terrain.dimensions.x + 260
	var c := 320 * terrain.dimensions.x + 320
	check(doc.add_color_layer() == 0, "add layer for first committed stroke")
	check(doc.color_dab(Vector2(200.0, 200.0), 3.0, 0xff0000, Document.BrushShape.CIRCLE, 1.0),
		"commit first colored region")
	check(doc.add_color_layer() == 1, "add layer for second committed stroke")
	check(doc.color_dab(Vector2(260.0, 260.0), 3.0, 0x0000ff, Document.BrushShape.CIRCLE, 1.0),
		"commit second colored region")
	var preview: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(preview.has(a) and preview.has(b), "both committed regions are in the composed preview")
	check(doc.begin_color_stroke(), "begin third color stroke")
	check(doc.color_dab(Vector2(320.0, 320.0), 3.0, 0x00ff00, Document.BrushShape.CIRCLE, 1.0),
		"dab third region while stroke active")
	var live: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(live.has(a) and live.has(b) and live.has(c),
		"live dab preserves previously composed samples A and B while adding C")
	check(doc.end_color_stroke(), "end third stroke")
	check(not doc.color_stroke_active and not doc._color_live_preview, "stroke cleanup clears live preview flag")
	unwatch_material_refresh(doc)


## P0 regression: every Color Opacity gesture closes its document preview. The
## zero-movement terminal case is simulated by cancel_color_opacity_preview,
## which is what the SliderField gesture_ended handler now calls.
func test_color_opacity_gesture_lifecycle(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-opacity-gesture")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	check(doc.add_color_layer() == 0, "add layer for opacity gesture")
	var uid := int((doc.color_layers[0] as Dictionary)["uid"])
	(doc.color_layers[0] as Dictionary)["samples"] = {sample: {"rgb": 0xff8800, "coverage": 1.0}}
	check(doc.color_preview(), "color preview active before opacity gesture")
	var undo_before := doc.undo_stack.size()
	check(doc.begin_color_opacity_preview(0), "begin color opacity gesture")
	check(doc.preview_color_layer_opacity(uid, 0.4), "preview lower opacity")
	check(doc._color_opacity_preview_uid == uid, "gesture tracked in document")
	doc.cancel_color_opacity_preview(uid)
	check(doc._color_opacity_preview_uid == -1, "zero-movement cancel clears gesture UID")
	check(doc.undo_stack.size() == undo_before, "cancel adds no Undo")
	check(terrain.material_previews.has(Terrain.Layer.COLOR), "cancel restores composed color preview")
	check(doc.begin_color_opacity_preview(0), "begin committed opacity gesture")
	check(doc.preview_color_layer_opacity(uid, 0.25), "preview new opacity")
	check(doc.commit_color_opacity_preview(uid, 0.25), "commit opacity")
	check(doc._color_opacity_preview_uid == -1, "commit clears gesture UID")
	check(doc.undo_stack.size() == undo_before + 1, "one opacity commit equals one Undo")
	check(is_equal_approx(float((doc.color_layers[0] as Dictionary)["opacity"]), 0.25),
		"committed opacity value applied")
	var before_noop := doc.undo_stack.size()
	check(doc.begin_color_opacity_preview(0), "begin no-op opacity gesture")
	check(doc.commit_color_opacity_preview(uid, 0.25), "no-op commit succeeds")
	check(doc.undo_stack.size() == before_noop, "no-op opacity adds no Undo")
	check(doc._color_opacity_preview_uid == -1, "no-op gesture still clears UID")
	unwatch_material_refresh(doc)


## P0 regression: Color Opacity must not adopt a foreign preview owner.
func test_color_opacity_foreign_preview_refusal(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-opacity-ownership")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	check(doc.add_color_layer() == 0, "add layer for foreign-preview probe")
	var uid := int((doc.color_layers[0] as Dictionary)["uid"])
	var stage_heights := {sample: terrain.heights[sample] + 0.5}
	check(doc.show_preview(stage_heights, {}, "slope"), "foreign slope preview active")
	var before_owner := doc.preview_owner
	var before_preview: Dictionary = terrain.material_previews.duplicate(true)
	check(not doc.begin_color_opacity_preview(0), "foreign preview refuses color opacity gesture")
	check(doc._color_opacity_preview_uid == -1, "refused gesture leaves no UID armed")
	check(doc.preview_owner == before_owner, "refused gesture keeps foreign preview owner")
	check(terrain.material_previews == before_preview, "refused gesture leaves foreign preview data unchanged")
	check(not doc.preview_color_layer_opacity(uid, 0.5), "previewing without a gesture is refused")
	check(doc.preview_owner == before_owner and terrain.material_previews == before_preview,
		"refused preview change leaves foreign data untouched")
	doc.clear_preview()
	check(doc.preview_owner.is_empty(), "foreign preview cleanup succeeds")
	check(doc.begin_color_opacity_preview(0), "color opacity gesture allowed after foreign preview cleared")
	doc.cancel_color_opacity_preview(uid)
	check(doc._color_opacity_preview_uid == -1, "gesture cleanup after refusal")
	unwatch_material_refresh(doc)


## P0 regression: zero-movement Color Opacity gesture on the real panel closes
## the document preview via gesture_ended, not only via commit/cancel callbacks.
func test_color_opacity_zero_movement_ui(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-opacity-zero-ui")
	var sample := 200 * doc.package.terrain.dimensions.x + 200
	check(doc.add_color_layer() == 0, "add layer for zero-movement gesture")
	var uid := int((doc.color_layers[0] as Dictionary)["uid"])
	;(doc.color_layers[0] as Dictionary)["samples"] = {sample: {"rgb": 0xff8800, "coverage": 1.0}}
	check(doc.color_preview(), "color preview active before zero-movement gesture")
	var panel := LayersPanel.new()
	root.add_child(panel)
	panel.bind_document(doc)
	var slider = panel.get("color_opacity")
	slider.gesture_started.emit(float((doc.color_layers[0] as Dictionary)["opacity"]))
	check(doc._color_opacity_preview_uid == uid, "UI gesture arms document preview")
	slider.gesture_ended.emit(true)
	check(doc._color_opacity_preview_uid == -1, "zero-movement UI gesture clears document UID")
	check(not bool(panel.get("_color_opacity_gesture_active")), "zero-movement UI gesture clears panel flag")
	panel.queue_free()
	unwatch_material_refresh(doc)


## P0 regression: clearing the last color preview entry must still repaint the
## renderer region instead of changing the Dictionary only.
func test_color_empty_preview_repaints(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-empty-preview-repaint")
	var terrain: Terrain = doc.package.terrain
	var sample := 210 * terrain.dimensions.x + 210
	var source := terrain.source_material_value(Terrain.Layer.COLOR, sample)
	check(doc.add_color_layer() == 0, "add layer for empty-preview probe")
	var layer_data: Dictionary = doc.color_layers[0]
	layer_data["samples"] = {sample: {"rgb": source ^ 0xffffff, "coverage": 1.0}}
	check(doc.color_preview(), "non-empty color preview established")
	check(terrain.material_previews.has(Terrain.Layer.COLOR), "color preview entry present")
	watch_material_refresh(doc)
	layer_data["samples"] = {sample: {"rgb": source, "coverage": 1.0}}
	check(doc.color_preview(), "empty composed color preview is a valid state")
	check(terrain.material_previews.get(Terrain.Layer.COLOR, {}).is_empty(),
		"empty color preview removes material preview entry")
	check(material_refresh_count > 0 and material_refresh_layer == Terrain.Layer.COLOR,
		"empty color preview emits a COLOR material refresh")
	check(material_refresh_region.has_point(terrain.sample_at(sample)),
		"empty color preview repaints the previously tinted sample")
	unwatch_material_refresh(doc)


## T-48 P0: an empty composition is still an active Color compositing context.
func test_color_empty_state_on_off_on(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-empty-on-off-on")
	var terrain: Terrain = doc.package.terrain
	var sample := 210 * terrain.dimensions.x + 210
	var source := terrain.source_material_value(Terrain.Layer.COLOR, sample)
	check(doc.add_color_layer() == 0, "add layer for ON/OFF/ON")
	var layer_data: Dictionary = doc.color_layers[0]
	layer_data["samples"] = {sample: {"rgb": source ^ 0xffffff, "coverage": 1.0}}
	check(doc.color_preview(), "initial color preview visible")
	var preview: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(preview.has(sample), "initial composed RGB visible")
	check(doc.set_color_layer_enabled(0, false), "disable only color layer")
	check(terrain.material_previews.get(Terrain.Layer.COLOR, {}).is_empty(), "empty composition is valid")
	check(doc.set_color_layer_enabled(0, true), "re-enable color layer")
	preview = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(preview.has(sample) and preview[sample] == (source ^ 0xffffff),
		"ON/OFF/ON restores exact composed RGB without manual preview")
	doc.clear_preview()
	var writer := Snapshots.new()
	var target := scratch.path_join("color-on-off-on-export")
	check(writer.export_native(doc, target), "native export after ON/OFF/ON: " + writer.error)
	var reimport := Package.new()
	var reimport_ok := reimport.open(target.path_join(doc.package.source_path.get_file()))
	check(reimport_ok, "ON/OFF/ON export reimports")
	if reimport_ok:
		check(reimport.terrain.material_value(Terrain.Layer.COLOR, sample) == (source ^ 0xffffff),
			"native export matches restored viewport RGB")
	check(doc.color_preview(), "restored color preview after export")
	var undo_before := doc.undo_stack.size()
	doc.undo()
	doc.redo()
	check(doc.undo_stack.size() == undo_before, "ON/OFF/ON adds no extra Undo")


## T-48 P1: opacity recovery from an empty composition.
func test_color_opacity_zero_to_positive_recovery(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-opacity-zero-recovery")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	var source := terrain.source_material_value(Terrain.Layer.COLOR, sample)
	check(doc.add_color_layer() == 0, "add layer for opacity recovery")
	var uid := int((doc.color_layers[0] as Dictionary)["uid"])
	(doc.color_layers[0] as Dictionary)["samples"] = {sample: {"rgb": source ^ 0xffffff, "coverage": 1.0}}
	check(doc.set_color_layer_opacity(0, 0.0), "set opacity to zero")
	check(doc.color_preview(), "empty zero-opacity preview is valid")
	check(terrain.material_previews.get(Terrain.Layer.COLOR, {}).is_empty(), "zero opacity has no material entries")
	check(doc.begin_color_opacity_preview(0), "begin opacity recovery gesture")
	check(doc.preview_color_layer_opacity(uid, 0.75), "live preview at 75%")
	var live: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(live.has(sample), "live drag restores composed RGB")
	check(doc.commit_color_opacity_preview(uid, 0.75), "commit opacity recovery")
	check(is_equal_approx(float((doc.color_layers[0] as Dictionary)["opacity"]), 0.75),
		"75% opacity committed")
	var preview: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(preview.has(sample), "commit keeps composed RGB visible")
	var export_colors := doc.export_colors()
	check(export_colors.get(sample, -1) == preview[sample], "export matches restored preview")
	doc.undo()
	check(is_equal_approx(float((doc.color_layers[0] as Dictionary)["opacity"]), 0.0),
		"undo restores zero opacity")
	check(terrain.material_previews.get(Terrain.Layer.COLOR, {}).is_empty(),
		"undo restores empty composition")
	doc.redo()
	check(is_equal_approx(float((doc.color_layers[0] as Dictionary)["opacity"]), 0.75),
		"redo restores 75% opacity")
	check((terrain.material_previews.get(Terrain.Layer.COLOR, {}) as Dictionary).has(sample),
		"redo restores visible RGB")


## T-48 P1: centralized Color preview admission must refuse a foreign owner.
func test_color_preview_central_admission(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-preview-admission")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	check(doc.add_color_layer() == 0, "add layer for admission probe")
	(doc.color_layers[0] as Dictionary)["samples"] = {sample: {"rgb": 0xff8800, "coverage": 1.0}}
	var foreign_heights := {sample: terrain.heights[sample] + 0.5}
	check(doc.show_preview(foreign_heights, {}, "slope"), "foreign slope preview active")
	var owner_before := doc.preview_owner
	var preview_before: Dictionary = terrain.material_previews.duplicate(true)
	check(not doc.color_preview(), "color_preview refuses foreign owner")
	check(not doc.show_color_preview({sample: 0xff0000}), "direct show_color_preview refuses foreign owner")
	check(doc.preview_owner == owner_before, "foreign owner unchanged")
	check(terrain.material_previews == preview_before, "foreign preview bytes unchanged")
	check(doc.preview_before.has(sample) and doc.preview_after.has(sample), "foreign height preview unchanged")
	doc.clear_preview()
	check(doc.color_preview(), "color preview allowed after foreign cleanup")
	unwatch_material_refresh(doc)


## T-48 P1: in-stroke coverage keeps the strongest dab while RGB comes from the
## latest dab; a new stroke replaces coverage.
func test_color_coverage_contract(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-coverage-contract")
	check(doc.add_color_layer() == 0, "add layer for coverage probe")
	check(doc.begin_color_stroke(), "begin first coverage stroke")
	check(doc.color_dab(Vector2(200.0, 200.0), 6.0, 0xff0000, Document.BrushShape.CIRCLE, 1.0),
		"strong red dab")
	check(doc.color_dab(Vector2(200.0, 200.0), 1.0, 0x0000ff, Document.BrushShape.CIRCLE, 1.0),
		"weak blue dab")
	var sample := 200 * doc.package.terrain.dimensions.x + 200
	var samples: Dictionary = (doc.color_layers[0] as Dictionary)["samples"]
	check(samples.has(sample), "coverage probe sample painted")
	check(int((samples[sample] as Dictionary)["rgb"]) == 0x0000ff, "latest RGB wins in stroke")
	var strong_coverage := float((samples[sample] as Dictionary)["coverage"])
	check(strong_coverage > 0.0, "coverage stored")
	check(doc.end_color_stroke(), "commit first coverage stroke")
	check(doc.begin_color_stroke(), "begin second coverage stroke")
	check(doc.color_dab(Vector2(200.0, 200.0), 1.0, 0x00ff00, Document.BrushShape.CIRCLE, 0.3),
		"weak green dab in new stroke")
	samples = (doc.color_layers[0] as Dictionary)["samples"]
	check(int((samples[sample] as Dictionary)["rgb"]) == 0x00ff00, "new stroke replaces RGB")
	check(float((samples[sample] as Dictionary)["coverage"]) < strong_coverage,
		"new stroke replaces coverage instead of inheriting old maximum")
	check(doc.end_color_stroke(), "commit second coverage stroke")


## T-48 first Color Mask vertical slice: sparse strength, preview, export,
## BZMAG persistence and one Undo per mask stroke.
func test_color_mask_vertical_slice(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-mask-slice")
	var terrain: Terrain = doc.package.terrain
	var sample := 230 * terrain.dimensions.x + 230
	var source := terrain.source_material_value(Terrain.Layer.COLOR, sample)
	var painted := source ^ 0xffffff
	check(doc.add_color_layer() == 0, "add masked color layer")
	var layer_data: Dictionary = doc.color_layers[0]
	layer_data["samples"] = {sample: {"rgb": painted, "coverage": 1.0}}
	check(doc.color_preview(), "color visible before mask")
	check((terrain.material_previews.get(Terrain.Layer.COLOR, {}) as Dictionary).get(sample, -1) == painted,
		"unmasked color visible")
	var undo_before := doc.undo_stack.size()
	check(doc.add_color_mask(0, 0.0), "add default-zero mask")
	check((terrain.material_previews.get(Terrain.Layer.COLOR, {}) as Dictionary).is_empty(),
		"zero mask hides color")
	check(doc.undo_stack.size() == undo_before + 1, "add mask creates one Undo")
	check(doc.begin_color_mask_stroke(), "begin mask paint stroke")
	check(doc.color_mask_dab(Vector2(230.0, 230.0), 4.0, 1.0, Document.BrushShape.CIRCLE), "paint white into mask")
	check(doc.end_color_mask_stroke(), "commit mask paint")
	check(doc.undo_stack.size() == undo_before + 2, "mask stroke creates one Undo")
	var preview: Dictionary = terrain.material_previews.get(Terrain.Layer.COLOR, {})
	check(preview.get(sample, -1) == painted, "mask white restores color")
	check(doc.set_color_mask_enabled(0, false), "disable mask")
	check((terrain.material_previews.get(Terrain.Layer.COLOR, {}) as Dictionary).get(sample, -1) == painted,
		"disabled mask shows full layer")
	check(doc.set_color_mask_enabled(0, true), "re-enable mask")
	check((terrain.material_previews.get(Terrain.Layer.COLOR, {}) as Dictionary).get(sample, -1) == painted,
		"re-enabled mask restores masked result")
	var writer := Snapshots.new()
	var target := scratch.path_join("color-mask-slice.bzmag")
	check(writer.save_project(doc, target), "save BZMAG with color mask")
	var reopened := Document.new()
	check(reopened.open(target), "reopen BZMAG with color mask")
	var restored: Dictionary = reopened.color_layers[0]
	var restored_mask: Dictionary = restored["mask"]
	check(bool(restored_mask["enabled"]), "mask enabled state survives save/reopen")
	check((restored_mask["samples"] as Dictionary).has(sample), "sparse mask samples survive save/reopen")
	check(reopened.export_colors().get(sample, -1) == painted, "masked export composes after reopen")
	doc.clear_preview()
	var export_target := scratch.path_join("color-mask-slice-export")
	check(writer.export_native(doc, export_target), "native export with color mask: " + writer.error)
	var reimport := Package.new()
	var ok := reimport.open(export_target.path_join(doc.package.source_path.get_file()))
	check(ok, "masked native export reimports")
	if ok:
		check(reimport.terrain.material_value(Terrain.Layer.COLOR, sample) == painted,
			"native TER contains masked composed RGB")


## Undo after a committed Mask stroke must restore the exact pre-stroke stack.
## Regression for end_color_mask_stroke() recording before=[] and deleting
## every Color Layer on Undo.
func test_color_mask_undo_integrity(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-mask-undo-integrity")
	var terrain: Terrain = doc.package.terrain
	var sample := 210 * terrain.dimensions.x + 210
	check(doc.add_color_layer() == 0, "undo integrity: add layer A")
	check(doc.begin_color_stroke(), "undo integrity: begin RGB stroke")
	check(doc.color_dab(Vector2(210.0, 210.0), 4.0, 0xff0000, Document.BrushShape.CIRCLE, 1.0),
		"undo integrity: paint RGB")
	check(doc.end_color_stroke(), "undo integrity: end RGB stroke")
	var rgb_before: Dictionary = (doc.color_layers[0] as Dictionary)["samples"].duplicate(true)
	check(doc.add_color_mask(0, 0.0), "undo integrity: add mask")
	var mask_before: Variant = (doc.color_layers[0] as Dictionary)["mask"].duplicate(true)
	var undo_before := doc.undo_stack.size()
	check(doc.begin_color_mask_stroke(), "undo integrity: begin mask stroke")
	check(doc.color_mask_dab(Vector2(210.0, 210.0), 4.0, 1.0, Document.BrushShape.CIRCLE),
		"undo integrity: paint white")
	check(doc.end_color_mask_stroke(), "undo integrity: end mask stroke")
	check(doc.undo_stack.size() == undo_before + 1, "undo integrity: one history entry")
	doc.undo()
	check(doc.color_layers.size() == 1, "undo integrity: Undo keeps Color Layer stack")
	if doc.color_layers.size() == 1:
		var restored: Dictionary = doc.color_layers[0]
		check(restored["samples"] == rgb_before, "undo integrity: RGB samples preserved")
		check(restored["mask"] == mask_before, "undo integrity: exact mask state restored")
	doc.redo()
	check(doc.color_layers.size() == 1, "undo integrity: Redo keeps Color Layer stack")
	if doc.color_layers.size() == 1:
		var redone: Dictionary = doc.color_layers[0]
		check(((redone["mask"] as Dictionary)["samples"] as Dictionary).has(sample),
			"undo integrity: Redo restores painted mask sample")
	doc.undo()
	check(doc.color_layers.size() == 1, "undo integrity: second Undo keeps stack")


## Within one stroke the strongest coverage wins even when a weaker, later dab
## changes the RGB. Two CONE dabs at different offsets exercise real falloff.
func test_color_stroke_coverage_strength(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-stroke-coverage-strength")
	check(doc.add_color_layer() == 0, "coverage strength: add layer")
	var sample := 200 * doc.package.terrain.dimensions.x + 200
	check(doc.begin_color_stroke(), "coverage strength: begin stroke")
	check(doc.color_dab(Vector2(200.0, 200.0), 6.0, 0xff0000, Document.BrushShape.CONE, 1.0),
		"coverage strength: strong red dab")
	var samples: Dictionary = (doc.color_layers[0] as Dictionary)["samples"]
	var strong := float((samples[sample] as Dictionary)["coverage"])
	check(doc.color_dab(Vector2(201.4, 200.0), 6.0, 0x0000ff, Document.BrushShape.CONE, 1.0),
		"coverage strength: weaker blue dab")
	samples = (doc.color_layers[0] as Dictionary)["samples"]
	var after_weak := float((samples[sample] as Dictionary)["coverage"])
	check(is_equal_approx(after_weak, strong), "coverage strength: weaker dab keeps strongest coverage")
	check(int((samples[sample] as Dictionary)["rgb"]) == 0x0000ff, "coverage strength: latest RGB wins")
	check(doc.color_dab(Vector2(200.0, 200.0), 6.0, 0x00ff00, Document.BrushShape.CONE, 1.0),
		"coverage strength: another strong green dab")
	samples = (doc.color_layers[0] as Dictionary)["samples"]
	check(is_equal_approx(float((samples[sample] as Dictionary)["coverage"]), strong),
		"coverage strength: remaining strong dab preserves maximum")
	check(doc.end_color_stroke(), "coverage strength: end stroke")
	check(doc.begin_color_stroke(), "coverage strength: begin new stroke")
	check(doc.color_dab(Vector2(200.0, 200.0), 6.0, 0xffff00, Document.BrushShape.CONE, 0.2),
		"coverage strength: weak dab in new stroke")
	samples = (doc.color_layers[0] as Dictionary)["samples"]
	check(float((samples[sample] as Dictionary)["coverage"]) < strong,
		"coverage strength: new stroke replaces previous maximum")
	doc.cancel_color_stroke()


## BrushPanel Mask target routes dab_at() to color_mask_dab without changing
## RGB. Mirrors produce dabs in the same transaction; reveal/hide set strength.
func test_mask_brush_panel_integration(fixture: String) -> void:
	var doc := fresh_document(fixture, "mask-brush-panel")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	check(doc.add_color_layer() == 0, "mask brush: add layer")
	var layer_data: Dictionary = doc.color_layers[0]
	layer_data["samples"] = {sample: {"rgb": 0xff0000, "coverage": 1.0}}
	check(doc.color_preview(), "mask brush: preview before mask")
	check(doc.add_color_mask(0, 0.0), "mask brush: add zero mask")
	var brush := BrushPanel.new()
	root.add_child(brush)
	brush.set_brush_size(8)
	brush.set_pressure(100)
	brush.set_shape(Document.BrushShape.CIRCLE)
	brush.surface.select(Terrain.Layer.COLOR)
	brush.mask_target.set_pressed_no_signal(true)
	brush.mask_reveal.set_pressed_no_signal(true)
	check(brush.paint_layer() == Terrain.Layer.COLOR, "mask brush: color surface selected")
	check(doc.begin_color_mask_stroke(), "mask brush: begin stroke")
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	check(doc.end_color_mask_stroke(), "mask brush: end stroke")
	var mask_samples: Dictionary = ((doc.color_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(mask_samples.has(sample), "mask brush: white dab stored")
	check(float(mask_samples[sample]) == 1.0, "mask brush: reveal strength is 1")
	var rgb_samples: Dictionary = (doc.color_layers[0] as Dictionary)["samples"]
	check(int((rgb_samples[sample] as Dictionary)["rgb"]) == 0xff0000, "mask brush: RGB preserved")
	var undo_before := doc.undo_stack.size()
	check(doc.begin_color_mask_stroke(), "mask brush: begin hide stroke")
	brush.mask_reveal.set_pressed_no_signal(false)
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	check(doc.end_color_mask_stroke(), "mask brush: end hide stroke")
	check(doc.undo_stack.size() == undo_before + 1, "mask brush: one Undo per stroke")
	mask_samples = ((doc.color_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(not mask_samples.has(sample) or is_equal_approx(float(mask_samples[sample]), 0.0), "mask brush: hide strength is 0")
	brush.queue_free()


## Conflicting operations must refuse at the model layer while a mask stroke
## owns the document. No partial mutation, history or preview drift.
func test_mask_stroke_transaction_admission(fixture: String) -> void:
	var doc := fresh_document(fixture, "mask-stroke-admission")
	check(doc.add_color_layer() == 0, "admission: add layer")
	check(doc.add_color_mask(0, 0.0), "admission: add mask")
	check(doc.begin_color_mask_stroke(), "admission: begin mask stroke")
	var before := doc.color_layers.duplicate(true)
	var history_before := doc.undo_stack.size()
	var rev_before := doc.color_revision
	check(doc.add_color_layer() == -1, "admission: add layer refused")
	check(not doc.remove_color_layer(0), "admission: remove layer refused")
	check(not doc.set_color_layer_enabled(0, false), "admission: toggle layer refused")
	check(not doc.rename_color_layer(0, "renamed"), "admission: rename refused")
	check(not doc.remove_color_mask(0), "admission: remove mask refused")
	check(not doc.set_color_mask_enabled(0, false), "admission: mask enable refused")
	check(not doc.set_color_mask_default(0, 1.0), "admission: mask default refused")
	check(not doc.begin_color_stroke(), "admission: color stroke refused")
	check(doc.color_layers == before, "admission: color layers unchanged")
	check(doc.undo_stack.size() == history_before, "admission: history unchanged")
	check(doc.color_revision == rev_before, "admission: revision unchanged")
	var writer := Snapshots.new()
	check(not writer.save_project(doc, scratch.path_join("admission-refused.bzmag")),
		"admission: save refused")
	check(not writer.export_native(doc, scratch.path_join("admission-refused-export")),
		"admission: export refused")
	doc.undo()
	check(doc.color_layers == before, "admission: undo refused during stroke")
	check(doc.color_mask_stroke_active, "admission: stroke still active")
	doc.cancel_color_mask_stroke()
	check(not doc.color_mask_stroke_active, "admission: cancel ends stroke")


## T-52 Sculpt Mask vertical slice: sparse strength, composition, one Undo per
## stroke, exact Undo/Redo, save/reopen and native export.
func test_sculpt_mask_vertical_slice(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-slice")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	var base := float(doc.base_heights[sample])
	check(doc.add_sculpt_layer() == 0, "add masked sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"paint sculpt delta")
	var layer: Dictionary = doc.sculpt_layers[0]
	check((layer["deltas"] as Dictionary).has(sample), "sculpt delta recorded at sample")
	var full_delta := float((layer["deltas"] as Dictionary)[sample])
	check(doc.sculpt_preview() and doc.has_preview(), "unmasked sculpt preview composes")
	var full_height := float(doc.preview_after[sample])
	doc.clear_preview()

	# Default-zero mask hides the whole layer; composition falls back to native.
	check(doc.add_sculpt_mask(0, 0.0), "add default-zero sculpt mask")
	var masked := doc.export_heights()
	check(is_equal_approx(float(masked.get(sample, base)), base),
		"zero default mask hides sculpt delta")

	# Paint white into the mask: the sample's delta returns at full strength.
	var undo_before := doc.undo_stack.size()
	check(doc.begin_sculpt_mask_stroke(), "begin sculpt mask stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 1.0, Document.BrushShape.CIRCLE),
		"paint white into sculpt mask")
	check(doc.end_sculpt_mask_stroke(), "end sculpt mask stroke")
	check(doc.undo_stack.size() == undo_before + 1, "one Undo per sculpt mask stroke")
	var revealed := doc.export_heights()
	var expected := base + full_delta
	check(is_equal_approx(float(revealed.get(sample, -1.0)), expected),
		"white mask reveals full sculpt delta")

	# Undo returns the exact pre-stroke stack; Redo restores it.
	doc.undo()
	check(doc.sculpt_layers.size() == 1, "Undo keeps sculpt layer stack")
	var undone: Dictionary = doc.sculpt_layers[0]
	check(not ((undone["mask"] as Dictionary)["samples"] as Dictionary).has(sample),
		"Undo removes painted mask sample")
	check(doc.export_heights().get(sample, base) == base, "Undo restores masked result")
	doc.redo()
	var redone: Dictionary = doc.sculpt_layers[0]
	check(((redone["mask"] as Dictionary)["samples"] as Dictionary).has(sample),
		"Redo restores painted mask sample")

	# Partial strength gives a proportional delta on a fresh mask (no sparse override).
	check(doc.remove_sculpt_mask(0), "remove painted mask")
	check(doc.add_sculpt_mask(0, 0.5), "add partial default mask")
	var partial := doc.export_heights()
	var half := base + full_delta * 0.5
	check(is_equal_approx(float(partial.get(sample, -1.0)), half),
		"partial mask strength scales sculpt delta")

	# Disable reveals full layer regardless of sparse overrides.
	check(doc.set_sculpt_mask_enabled(0, false), "disable sculpt mask")
	check(is_equal_approx(float(doc.export_heights().get(sample, -1.0)), expected),
		"disabled mask reveals full sculpt layer")
	check(doc.set_sculpt_mask_enabled(0, true), "re-enable sculpt mask")

	# BZMAG persistence and independent native export.
	var writer := Snapshots.new()
	var target := scratch.path_join("sculpt-mask-slice.bzmag")
	check(writer.save_project(doc, target), "save BZMAG with sculpt mask")
	var reopened := Document.new()
	check(reopened.open(target), "reopen BZMAG with sculpt mask")
	check(reopened.sculpt_layers.size() == 1, "sculpt layer survives save/reopen")
	var restored: Dictionary = reopened.sculpt_layers[0]
	check(not ((restored["mask"] as Dictionary)["samples"] as Dictionary).has(sample)
		and is_equal_approx(float((restored["mask"] as Dictionary)["default"]), 0.5),
		"sculpt mask default strength survives save/reopen")
	check(is_equal_approx(float(reopened.export_heights().get(sample, -1.0)), half),
		"reopened mask composes identically")
	doc.clear_preview()
	var export_target := scratch.path_join("sculpt-mask-slice-export")
	check(writer.export_native(doc, export_target), "native export with sculpt mask: " + writer.error)
	var reimport := Package.new()
	var ok := reimport.open(export_target.path_join(doc.package.source_path.get_file()))
	check(ok, "masked sculpt native export reimports")
	if ok:
		var expected_export := float(doc.export_heights().get(sample, -1.0))
		check(is_equal_approx(reimport.terrain.heights[sample], expected_export),
			"native TER carries the masked composed height")


## A mask stroke owns the layer stack until END. Nested sculpt mutations must
## be refused so the stroke records exactly one Undo and CANCEL can restore it.
func test_sculpt_mask_stroke_admission(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-admission")
	check(doc.add_sculpt_layer() == 0, "admission: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"admission: paint sculpt delta")
	check(doc.add_sculpt_mask(0, 0.0), "admission: add sculpt mask")
	check(doc.begin_sculpt_mask_stroke(), "admission: begin sculpt mask stroke")
	var before: Array = doc.sculpt_layers.duplicate(true)
	var history_before := doc.undo_stack.size()
	var revision_before := doc.sculpt_revision
	check(not doc.set_sculpt_layer_enabled(0, false), "admission: toggle sculpt layer refused")
	check(not doc.set_sculpt_layer_opacity(0, 0.5), "admission: sculpt opacity refused")
	check(not doc.rename_sculpt_layer(0, "renamed"), "admission: sculpt rename refused")
	check(not doc.add_sculpt_mask(0, 1.0), "admission: second sculpt mask refused")
	check(not doc.remove_sculpt_mask(0), "admission: remove sculpt mask refused")
	check(not doc.set_sculpt_mask_enabled(0, false), "admission: mask enable refused")
	check(not doc.set_sculpt_mask_default(0, 1.0), "admission: mask default refused")
	check(not doc.begin_sculpt_stroke(), "admission: sculpt stroke refused")
	check(not doc.sculpt_dab(Vector2(230.0, 230.0), 4.0, 20.0, Document.BrushShape.CIRCLE),
		"admission: sculpt dab refused")
	check(not doc.sculpt_preview(), "admission: sculpt preview refused")
	check(doc.sculpt_layers == before, "admission: sculpt layers unchanged")
	check(doc.undo_stack.size() == history_before, "admission: history unchanged")
	check(doc.sculpt_revision == revision_before, "admission: revision unchanged")
	var writer := Snapshots.new()
	check(not writer.save_project(doc, scratch.path_join("sculpt-admission-refused.bzmag")),
		"admission: save refused")
	check(not writer.export_native(doc, scratch.path_join("sculpt-admission-refused-export")),
		"admission: export refused")
	doc.undo()
	check(doc.sculpt_layers == before, "admission: undo refused during mask stroke")
	check(doc.sculpt_mask_stroke_active, "admission: stroke still active")
	doc.cancel_sculpt_mask_stroke()
	check(not doc.sculpt_mask_stroke_active, "admission: cancel ends stroke")
	check(doc.undo_stack.size() == history_before and doc.sculpt_layers == before,
		"admission: cancel leaves no history and no layer change")


## T-53 P0: mask painting must change the VISIBLE surface during the stroke.
## Oracle: base 100 m, sculpt delta +20 m, mask default 0. White -> 120 m,
## black -> 100 m, gray 0.5 -> 110 m; export must agree with the viewport.
func test_sculpt_mask_live_composition(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-live")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	var base := float(doc.base_heights[sample])
	check(doc.add_sculpt_layer() == 0, "live: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"live: paint sculpt delta")
	var delta := float(((doc.sculpt_layers[0] as Dictionary)["deltas"] as Dictionary)[sample])
	doc.clear_preview()
	var full := base + delta
	check(doc.add_sculpt_mask(0, 0.0), "live: add default-zero mask")

	# Mask 0 equals the baseline. The composition may be empty yet still owned.
	check(absf(float(doc.export_heights().get(sample, -1.0)) - base) < 0.01,
		"live: export starts at base")
	var history_before := doc.undo_stack.size()
	check(doc.begin_sculpt_mask_stroke(), "live: begin mask stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 1.0, Document.BrushShape.CIRCLE),
		"live: reveal dab")
	# P0 oracle: the dab itself must refresh terrain.heights, not only save data.
	check(absf(terrain.heights[sample] - full) < 0.01,
		"live: white dab shows 120 m during stroke (got %.3f)" % terrain.heights[sample])
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.5, Document.BrushShape.CIRCLE),
		"live: gray dab")
	check(absf(terrain.heights[sample] - (base + delta * 0.5)) < 0.01,
		"live: gray dab shows 110 m during stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.0, Document.BrushShape.CIRCLE),
		"live: hide dab")
	check(absf(terrain.heights[sample] - base) < 0.01,
		"live: black dab returns to 100 m during stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 1.0, Document.BrushShape.CIRCLE),
		"live: final reveal dab")
	check(doc.end_sculpt_mask_stroke(), "live: end stroke")
	check(doc.undo_stack.size() == history_before + 1, "live: one Undo for the whole stroke")
	check(absf(terrain.heights[sample] - full) < 0.01, "live: final surface stays revealed")
	check(absf(float(doc.export_heights().get(sample, -1.0)) - terrain.heights[sample]) < 0.01,
		"live: viewport matches native export")
	var expected_final: Dictionary = (doc.sculpt_layers[0] as Dictionary).duplicate(true)
	doc.undo()
	check(doc.undo_stack.size() == history_before, "live: undo removes stroke history")
	check(doc.sculpt_layers[0] == {
		"uid": expected_final["uid"], "name": expected_final["name"],
		"enabled": expected_final["enabled"], "opacity": expected_final["opacity"],
		"deltas": expected_final["deltas"],
		"mask": {"enabled": true, "default": 0.0, "samples": {}},
	}, "live: undo restores exact pre-stroke mask")
	check(absf(terrain.heights[sample] - base) < 0.01, "live: undo restores visible base")
	doc.redo()
	check(doc.sculpt_layers[0] == expected_final, "live: redo restores exact mask")
	check(absf(terrain.heights[sample] - full) < 0.01, "live: redo restores visible surface")

	# CANCEL must restore samples AND the visible surface without history.
	history_before = doc.undo_stack.size()
	check(doc.begin_sculpt_mask_stroke(), "live: begin cancel stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.0, Document.BrushShape.CIRCLE),
		"live: paint black for cancel")
	check(absf(terrain.heights[sample] - base) < 0.01, "live: cancel setup changed surface")
	doc.cancel_sculpt_mask_stroke()
	check(absf(terrain.heights[sample] - full) < 0.01, "live: cancel restores visible surface")
	check(doc.undo_stack.size() == history_before, "live: cancel adds no history")
	check(doc.sculpt_layers[0] == expected_final, "live: cancel restores exact mask data")


## T-53 P1: empty composition, mask ON/OFF/ON, opacity zero transitions, soft
## pressure falloff, mirrored dabs and invalid-dab atomicity.
func test_sculpt_mask_empty_state_and_atomicity(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-empty")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	var mirrored := 220 * terrain.dimensions.x + (terrain.dimensions.x - 1 - 220)
	var base := float(doc.base_heights[sample])
	check(doc.add_sculpt_layer() == 0, "empty: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"empty: paint sculpt delta")
	var delta := float(((doc.sculpt_layers[0] as Dictionary)["deltas"] as Dictionary)[sample])
	doc.clear_preview()
	var full := base + delta
	check(doc.add_sculpt_mask(0, 0.0), "empty: add default-zero mask")
	check(doc.sculpt_preview() and not doc.has_preview(),
		"empty: zero mask is a valid empty sculpt composition")
	check(doc.begin_sculpt_mask_stroke(), "empty: begin preview stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 1.0, Document.BrushShape.CIRCLE),
		"empty: reveal while empty composition")
	check(absf(terrain.heights[sample] - full) < 0.01, "empty: reveal restores delta")
	doc.cancel_sculpt_mask_stroke()

	# ON -> OFF -> ON of a zero mask must expose and then hide the delta again.
	check(doc.set_sculpt_mask_enabled(0, false), "empty: disable zero mask")
	check(absf(float(doc.export_heights().get(sample, -1.0)) - full) < 0.01,
		"empty: disabled mask reveals full delta")
	check(doc.set_sculpt_mask_enabled(0, true), "empty: re-enable zero mask")
	check(absf(float(doc.export_heights().get(sample, -1.0)) - base) < 0.01,
		"empty: re-enabled zero mask hides delta")

	# A soft dab applies weight*pressure; strength is a TARGET blended by weight.
	var brush := BrushPanel.new()
	root.add_child(brush)
	brush.set_brush_size(32)
	brush.set_shape(Document.BrushShape.BELL)
	brush.set_pressure(100)
	brush.sculpt_mask_target.set_pressed_no_signal(true)
	brush.sculpt_mask_reveal.set_pressed_no_signal(true)
	var soft_point := Vector2(220.0, 220.0)
	var soft_index := 220 * terrain.dimensions.x + 222
	check(doc.begin_sculpt_mask_stroke(), "empty: begin soft dab stroke")
	brush.apply_dab(doc, soft_point)
	check(doc.end_sculpt_mask_stroke(), "empty: end soft dab stroke")
	var soft_samples: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(soft_samples.has(soft_index), "empty: soft dab stored a sparse sample")
	var soft_value := float(soft_samples.get(soft_index, -1.0))
	check(soft_value > 0.0 and soft_value < 1.0,
		"empty: soft dab strength is partial (%.3f)" % soft_value)
	var soft_export := float(doc.export_heights().get(soft_index, -1.0))
	var soft_base := float(doc.base_heights[soft_index])
	check(absf(soft_export - (soft_base + delta_at(doc, soft_index) * soft_value)) < 0.01,
		"empty: soft dab export matches strength")
	brush.queue_free()

	# Invalid stroke input must leave the stack, preview and history untouched.
	var layer_before: Dictionary = (doc.sculpt_layers[0] as Dictionary).duplicate(true)
	var history_before := doc.undo_stack.size()
	check(doc.begin_sculpt_mask_stroke(), "empty: begin invalid dab stroke")
	check(not doc.sculpt_mask_dab(soft_point, 4.0, NAN, Document.BrushShape.CIRCLE),
		"empty: NaN dab rejected")
	check(not doc.sculpt_mask_dab(soft_point, 0.0, 1.0, Document.BrushShape.CIRCLE),
		"empty: bad radius dab rejected")
	check(doc.sculpt_mask_dab(soft_point, 4.0, 1.0, Document.BrushShape.CIRCLE),
		"empty: valid dab after failure still works")
	check(doc.sculpt_layers[0] != layer_before, "empty: valid dab changed the layer")
	check(doc.undo_stack.size() == history_before, "empty: no Undo before end")
	doc.cancel_sculpt_mask_stroke()
	check(doc.sculpt_layers[0] == layer_before, "empty: cancel restores after failed dab")
	check(doc.undo_stack.size() == history_before, "empty: no Undo after cancel")


## T-53: Sculpt Mask target is explicit; any brush mode routes to mask data,
## and conflicting transactions/previews are refused without data loss.
func test_sculpt_mask_brush_dispatch_and_owner(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-dispatch")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	check(doc.add_sculpt_layer() == 0, "dispatch: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"dispatch: paint sculpt delta")
	doc.clear_preview()
	check(doc.add_sculpt_mask(0, 0.0), "dispatch: add mask")
	var brush := BrushPanel.new()
	root.add_child(brush)
	brush.set_brush_size(8)
	brush.set_pressure(100)
	brush.set_shape(Document.BrushShape.CIRCLE)
	brush.sculpt_mask_target.set_pressed_no_signal(true)
	brush.sculpt_mask_reveal.set_pressed_no_signal(true)
	brush.update_buttons()
	check(brush.sculpt_mask_active(), "dispatch: sculpt mask target active")
	check(brush.sculpt_mask_reveal.visible, "dispatch: reveal/hide control visible in height target")
	var deltas_before: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["deltas"] as Dictionary).duplicate(true)
	var strengths := [0.25, 0.4, 0.6, 0.8]
	var brush_modes := [BrushPanel.Mode.RAISE, BrushPanel.Mode.BLEND, BrushPanel.Mode.PAINT, BrushPanel.Mode.SPRAY]
	for i in brush_modes.size():
		var brush_mode: int = brush_modes[i]
		brush.set_mode(brush_mode)
		brush.sculpt_mask_strength.set_value_no_signal(strengths[i])
		var undo_before := doc.undo_stack.size()
		check(doc.begin_sculpt_mask_stroke(), "dispatch: begin %d stroke" % brush_mode)
		brush.apply_dab(doc, Vector2(220.0, 220.0))
		check(doc.end_sculpt_mask_stroke(), "dispatch: end %d stroke" % brush_mode)
		check(doc.undo_stack.size() == undo_before + 1, "dispatch: mode %d records one Undo" % brush_mode)
		var mask_samples: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
		check(mask_samples.has(sample), "dispatch: mode %d wrote mask" % brush_mode)
		var deltas: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["deltas"] as Dictionary)
		check(deltas == deltas_before, "dispatch: mode %d did not touch native sculpt deltas" % brush_mode)
		check(doc.edits.is_empty(), "dispatch: mode %d did not touch committed terrain" % brush_mode)

	# Reveal/Hide target in the height context.
	check(doc.begin_sculpt_mask_stroke(), "dispatch: begin hide stroke")
	brush.sculpt_mask_reveal.set_pressed_no_signal(false)
	brush.sculpt_mask_strength.set_value_no_signal(1.0)
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	check(doc.end_sculpt_mask_stroke(), "dispatch: end hide stroke")
	var hidden: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(not hidden.has(sample) or absf(float(hidden[sample])) < 0.01,
		"dispatch: hide paints black (sparse default removes the override)")

	# Foreign preview admission: mask stroke refuses if a foreign preview owns
	# the surface, and the foreign buffer is left intact.
	var foreign_doc := fresh_document(fixture, "sculpt-mask-foreign")
	check(foreign_doc.add_sculpt_layer() == 0, "owner: add sculpt layer")
	check(foreign_doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"owner: sculpt delta")
	foreign_doc.clear_preview()
	check(foreign_doc.add_sculpt_mask(0, 0.0), "owner: add mask")
	check(foreign_doc.show_preview({sample: float(foreign_doc.base_heights[sample]) + 5.0}, {}, "slope"),
		"owner: create foreign preview")
	var foreign_before: Dictionary = foreign_doc.preview_after.duplicate(true)
	var foreign_owner := foreign_doc.preview_owner
	check(not foreign_doc.begin_sculpt_mask_stroke(), "owner: foreign preview refuses mask stroke")
	check(foreign_doc.preview_owner == foreign_owner and foreign_doc.preview_after == foreign_before,
		"owner: foreign preview buffer untouched")
	check(not foreign_doc.has_active_edit_transaction(), "owner: refusal leaves no transaction")
	foreign_doc.clear_preview()

	# Native terrain and Color Layer strokes must be refused mid-mask-stroke.
	check(doc.begin_sculpt_mask_stroke(), "owner: begin stroke for conflict checks")
	var layers_before: Array = doc.sculpt_layers.duplicate(true)
	var edits_before := doc.edits.duplicate(true)
	var history_before := doc.undo_stack.size()
	check(not doc.begin_stroke(Terrain.Layer.HEIGHT), "owner: native stroke refused")
	check(not doc.begin_water_stroke(), "owner: water stroke refused")
	check(not doc.begin_color_stroke(), "owner: color stroke refused")
	check(not doc.begin_color_mask_stroke(), "owner: color mask stroke refused")
	check(not doc.show_preview({sample: 42.0}, {}, "slope"), "owner: foreign preview refused")
	check(doc.sculpt_layers == layers_before and doc.edits == edits_before
		and doc.undo_stack.size() == history_before, "owner: refusals leave data intact")
	doc.cancel_sculpt_mask_stroke()
	brush.queue_free()


## T-53: a Sculpt Mask stroke recorded while a Sculpt composition was visible
## must restore that composition on Undo and Redo, not lose the surface.
func test_sculpt_mask_history_keeps_composition(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-history-preview")
	check(doc.add_sculpt_layer() == 0, "history: add layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"history: sculpt delta")
	check(doc.sculpt_preview(), "history: compose sculpt preview")
	var sample := 220 * doc.package.terrain.dimensions.x + 220
	var full := float(doc.preview_after[sample])
	check(doc.add_sculpt_mask(0, 0.0), "history: add mask")
	check(doc.begin_sculpt_mask_stroke(), "history: begin mask stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 1.0, Document.BrushShape.CIRCLE),
		"history: reveal dab")
	check(doc.end_sculpt_mask_stroke(), "history: end mask stroke")
	check(doc.has_preview() and doc.preview_owner == "sculpt", "history: preview survives stroke end")
	check(absf(float(doc.preview_after.get(sample, -1.0)) - full) < 0.01,
		"history: preview matches revealed surface")
	doc.undo()
	# Mask 0 composes to baseline: an owned EMPTY sculpt composition, not a
	# foreign or missing compositor. preview_after is empty by definition.
	check(doc.preview_owner == "sculpt", "history: undo keeps owned empty sculpt composition")
	check(absf(doc.package.terrain.heights[sample] - float(doc.base_heights[sample])) < 0.01,
		"history: undo visible surface shows baseline")
	doc.redo()
	check(doc.has_preview() and doc.preview_owner == "sculpt", "history: redo keeps sculpt preview")
	check(absf(float(doc.preview_after.get(sample, -1.0)) - full) < 0.01,
		"history: redo preview shows revealed surface")


## T-54 P0: Pressure is FLOW (how far one dab moves toward the target), not a
## scaled target. Reveal and Hide are symmetric: 20% flow moves a 0 sample to
## 0.2 and an exposed 1 sample to 0.8 at the brush centre; 100% reaches the
## target in one dab; repeated dabs converge without overshooting.
func test_sculpt_mask_pressure_oracles(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-pressure")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	check(doc.add_sculpt_layer() == 0, "flow: add sculpt layer")
	check(doc.add_sculpt_mask(0, 0.0), "flow: add default-zero mask")
	check(doc.begin_sculpt_mask_stroke(), "flow: begin reveal stroke")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 8.0, 1.0, Document.BrushShape.CIRCLE, 0.2),
		"flow: reveal dab at flow 0.2")
	var samples: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(absf(float(samples.get(sample, -1.0)) - 0.2) < 0.005,
		"flow: reveal 20%% moves 0 -> 0.2 (got %.4f)" % float(samples[sample]))
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 8.0, 1.0, Document.BrushShape.CIRCLE, 0.5),
		"flow: reveal dab at flow 0.5")
	check(absf(float(samples[sample]) - 0.6) < 0.005,
		"flow: reveal 50%% moves 0.2 -> 0.6 (got %.4f)" % float(samples[sample]))
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 8.0, 1.0, Document.BrushShape.CIRCLE, 1.0),
		"flow: reveal dab at flow 1.0")
	check(absf(float(samples[sample]) - 1.0) < 0.005, "flow: reveal 100% reaches target")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 8.0, 0.0, Document.BrushShape.CIRCLE, 0.2),
		"flow: hide dab at flow 0.2")
	check(absf(float(samples[sample]) - 0.8) < 0.005,
		"flow: hide 20%% moves 1 -> 0.8, never straight to 0 (got %.4f)" % float(samples[sample]))
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 8.0, 0.0, Document.BrushShape.CIRCLE, 0.2),
		"flow: second hide dab at flow 0.2")
	check(absf(float(samples[sample]) - 0.64) < 0.005,
		"flow: hide 20%% again moves 0.8 -> 0.64 (got %.4f)" % float(samples[sample]))
	doc.cancel_sculpt_mask_stroke()

	# BrushPanel: pressure and hold scale FLOW, the Strength slider sets the
	# target. 20% pressure moves the sample by 0.2 in EITHER direction.
	var brush := BrushPanel.new()
	root.add_child(brush)
	brush.set_brush_size(8)
	brush.set_shape(Document.BrushShape.CIRCLE)
	brush.sculpt_mask_target.set_pressed_no_signal(true)
	brush.sculpt_mask_reveal.set_pressed_no_signal(true)
	brush.sculpt_mask_strength.set_value_no_signal(1.0)
	check(doc.begin_sculpt_mask_stroke(), "flow: begin brush reveal stroke")
	# stroke state was rebuilt at BEGIN: re-read the live samples dictionary.
	samples = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	brush.set_pressure(20)
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	check(absf(float(samples.get(sample, -1.0)) - 0.2) < 0.005,
		"flow: brush reveal 20%% writes 0.2 (got %.4f)" % float(samples.get(sample, -1.0)))
	brush.sculpt_mask_reveal.set_pressed_no_signal(false)
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	check(absf(float(samples.get(sample, -1.0)) - 0.16) < 0.005,
		"flow: brush hide 20%% from 0.2 removes only 0.04 (got %.4f)" % float(samples.get(sample, -1.0)))
	var contact := float(samples[sample])
	brush.set_pressure(100)
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	check(doc.end_sculpt_mask_stroke(), "flow: end brush stroke")
	check(not samples.has(sample),
		"flow: brush hide 100%% reaches black from %.4f" % contact)
	brush.queue_free()


## T-54 P1: the public model API must reject, not coerce, invalid sculpt mask
## input, and a failure must never leave a partial mutation behind.
func test_sculpt_mask_strict_dab_validation(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-strict")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	check(doc.add_sculpt_layer() == 0, "strict: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"strict: paint sculpt delta")
	doc.clear_preview()
	check(doc.add_sculpt_mask(0, 0.0), "strict: add default-zero mask")
	check(doc.begin_sculpt_mask_stroke(), "strict: begin stroke")
	var history_strict := doc.undo_stack.size()
	var samples_before: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"].duplicate(true)
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, -0.1, Document.BrushShape.CIRCLE),
		"strict: strength -0.1 rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 1.1, Document.BrushShape.CIRCLE),
		"strict: strength 1.1 rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, NAN, Document.BrushShape.CIRCLE, 0.5),
		"strict: NaN target rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.5, Document.BrushShape.CIRCLE, NAN),
		"strict: NaN flow rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.5, Document.BrushShape.CIRCLE, 1.5),
		"strict: flow 1.5 rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.5, Document.BrushShape.CIRCLE, -0.2),
		"strict: negative flow rejected")
	check(not doc.sculpt_mask_dab(Vector2(NAN, 220.0), 4.0, 0.5, Document.BrushShape.CIRCLE),
		"strict: NaN point rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), -4.0, 0.5, Document.BrushShape.CIRCLE),
		"strict: negative radius rejected")
	check(not doc.sculpt_mask_dab(Vector2(220.0, 220.0), 300.0, 0.5, Document.BrushShape.CIRCLE),
		"strict: oversized radius rejected")
	var samples_now: Dictionary = ((doc.sculpt_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(samples_now == samples_before, "strict: no partial mutation after rejected dabs")
	check(doc.sculpt_mask_dab(Vector2(220.0, 220.0), 4.0, 0.5, Document.BrushShape.CIRCLE, 1.0),
		"strict: valid dab after rejections still works")
	check(doc.sculpt_layers.size() == 1, "strict: no layer side effects")
	doc.cancel_sculpt_mask_stroke()
	check(doc.undo_stack.size() == history_strict, "strict: rejected dabs never reached history")
## T-54 P1: begin_sculpt_stroke must refuse while a sculpt stroke is already
## active. The before-snapshot of the user gesture can never be replaced, so
## the whole gesture stays exactly one Undo step.
func test_sculpt_stroke_reentrancy(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-stroke-reentrancy")
	check(doc.add_sculpt_layer() == 0, "reentry: add sculpt layer")
	var history0 := doc.undo_stack.size()
	check(doc.begin_sculpt_stroke(), "reentry: first begin accepted")
	check(not doc.begin_sculpt_stroke(), "reentry: second begin refused")
	check(doc.sculpt_stroke_active, "reentry: first stroke still owns the document")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"reentry: dab A lands in the first stroke")
	check(not doc.begin_sculpt_stroke(), "reentry: begin after dab refused")
	check(doc.sculpt_dab(Vector2(221.0, 221.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"reentry: dab B lands in the same stroke")
	check(doc.end_sculpt_stroke(), "reentry: first stroke ends")
	check(doc.undo_stack.size() == history0 + 1, "reentry: exactly one Undo for the whole gesture")
	var edits_after_first: Dictionary = doc.edits.duplicate()
	check(doc.sculpt_dab(Vector2(222.0, 222.0), 6.0, 20.0, Document.BrushShape.CIRCLE),
		"reentry: one-call fresh stroke works")
	check(doc.undo_stack.size() == history0 + 2, "reentry: one-call stroke adds exactly one more Undo")
	doc.undo()
	check(doc.undo_stack.size() == history0 + 1, "reentry: undo steps back one gesture")
	check(doc.edits == edits_after_first, "reentry: undo restores the exact prior sculpt state")

	# The same one-gesture rule holds for sculpt mask strokes; the layer
	# first needs a mask for the masked gate to be reachable.
	check(doc.add_sculpt_mask(0, 0.0), "reentry: add sculpt mask")
	check(doc.begin_sculpt_mask_stroke(), "reentry: masked stroke begins")
	check(not doc.begin_sculpt_mask_stroke(), "reentry: masked begin refused")
	check(doc.sculpt_mask_stroke_active, "reentry: masked stroke still owns the document")
	doc.cancel_sculpt_mask_stroke()
	check(not doc.sculpt_mask_stroke_active, "reentry: masked cancel clean")


## T-54 P0: an empty preview is still an ACTIVE foreign context. Mask strokes
## must refuse it instead of silently capturing ownership, in both directions,
## while a cleared state admits the stroke and preserves the composition.
func test_empty_foreign_preview_admission(fixture: String) -> void:
	var doc := fresh_document(fixture, "empty-foreign-admission")
	check(doc.add_color_layer() == 0, "foreign: add color layer")
	check(doc.color_preview(), "foreign: compose empty color layer")
	check(not doc.has_preview(), "foreign: empty color composition has no pixel buffer")
	check(doc.preview_owner == "color" and doc.has_active_preview_context(),
		"foreign: empty color composition is an active context")
	check(doc.add_sculpt_layer() == 0, "foreign: add sculpt layer")
	check(doc.add_sculpt_mask(0, 0.0), "foreign: add sculpt mask")
	check(not doc.begin_sculpt_mask_stroke(), "foreign: empty color composition refuses mask stroke")
	check(doc._color_composition_active and doc.preview_owner == "color",
		"foreign: empty color composition survives mask admission")

	# Mirror direction: an active empty SCULPT composition refuses color masks.
	var sculpt_doc := fresh_document(fixture, "sculpt-vs-color-mask")
	check(sculpt_doc.add_sculpt_layer() == 0, "foreign: sculpt side layer")
	check(sculpt_doc.sculpt_dab(Vector2(220.0, 220.0), 8.0, 20.0, Document.BrushShape.CIRCLE),
		"foreign: sculpt delta")
	check(sculpt_doc.add_sculpt_mask(0, 0.0), "foreign: add zero mask")
	check(sculpt_doc.sculpt_preview() and not sculpt_doc.has_preview(),
		"foreign: empty sculpt composition owns the document")

	# Non-empty foreign previews still refuse exactly as before.
	check(doc.show_preview({0: float(doc.base_heights[0]) + 3.0}, {}, "slope"),
		"foreign: non-empty foreign preview posted")
	check(not doc.begin_sculpt_mask_stroke(), "foreign: non-empty foreign preview refused")
	check(doc.preview_owner == "slope", "foreign: refusals keep the foreign owner")

	# A safe transition still works: after the foreign preview is cleared the
	# mask stroke is admitted again and the composition is unchanged.
	doc.clear_preview()
	check(doc.begin_sculpt_mask_stroke(), "foreign: cleared state admits mask stroke")
	check(doc.sculpt_mask_stroke_active, "foreign: transition stroke active")
	doc.cancel_sculpt_mask_stroke()
	check(not doc.sculpt_mask_stroke_active, "foreign: transition stroke cancelled")


## T-54 P0: with two sculpt layers over two separate regions and the composed
## surface visible, painting the Sculpt Mask on region B must never hide
## region A - during the stroke, on cancel and on commit - and the native
## export must agree with the visible surface at every step.
func test_sculpt_mask_two_region_continuity(fixture: String) -> void:
	var doc := fresh_document(fixture, "sculpt-mask-two-region")
	var terrain: Terrain = doc.package.terrain
	var dims := terrain.dimensions
	var point_a := Vector2(dims.x * 0.25, dims.y * 0.25)
	var point_b := Vector2(dims.x * 0.75, dims.y * 0.75)
	var sample_a := int(point_a.y) * dims.x + int(point_a.x)
	var sample_b := int(point_b.y) * dims.x + int(point_b.x)
	var base_a := float(doc.base_heights[sample_a])
	var base_b := float(doc.base_heights[sample_b])
	check(doc.add_sculpt_layer() == 0, "dual: add sculpt layer A")
	check(doc.sculpt_dab(point_a, 8.0, 20.0, Document.BrushShape.CIRCLE), "dual: sculpt region A")
	check(doc.add_sculpt_layer() == 1, "dual: add sculpt layer B")
	check(doc.sculpt_dab(point_b, 8.0, -15.0, Document.BrushShape.CIRCLE), "dual: sculpt region B")
	var delta_a := float(((doc.sculpt_layers[0] as Dictionary)["deltas"] as Dictionary)[sample_a])
	var delta_b := float(((doc.sculpt_layers[1] as Dictionary)["deltas"] as Dictionary)[sample_b])
	var expected_a := base_a + delta_a
	var expected_b := base_b + delta_b
	check(doc.add_sculpt_mask(1, 0.0), "dual: add mask on layer B")
	check(doc.sculpt_preview(), "dual: full sculpt composition visible")
	check(doc.preview_after.has(sample_a), "dual: region A is in the composed preview")
	# B's own zero mask hides its delta: region B shows the BASE until the
	# mask stroke reveals it; unmasked region A stays composed all the time.
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01,
		"dual: region A visible before mask (%.3f)" % terrain.heights[sample_a])
	check(absf(terrain.heights[sample_b] - base_b) < 0.01,
		"dual: masked-out region B shows the base before the stroke")

	# Mask stroke on region B: region A must not flicker, drop or jump.
	check(doc.begin_sculpt_mask_stroke(), "dual: begin mask stroke on B")
	check(doc.sculpt_mask_dab(point_b, 8.0, 1.0, Document.BrushShape.CIRCLE, 1.0),
		"dual: reveal dab on B")
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01,
		"dual: region A still at %.3f during stroke (got %.3f)" % [expected_a, terrain.heights[sample_a]])
	check(doc.preview_after.has(sample_a), "dual: region A preview entry survives mask stroke")
	check(absf(terrain.heights[sample_b] - expected_b) < 0.01, "dual: region B revealed during stroke")
	check(doc.sculpt_mask_dab(point_b, 8.0, 0.0, Document.BrushShape.CIRCLE, 1.0),
		"dual: hide dab on B")
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01, "dual: region A still visible after hide dab")
	check(absf(terrain.heights[sample_b] - base_b) < 0.01, "dual: hide dab returns region B to base")
	check(doc.sculpt_mask_dab(point_b, 8.0, 1.0, Document.BrushShape.CIRCLE, 1.0),
		"dual: final reveal dab on B")
	check(doc.end_sculpt_mask_stroke(), "dual: end mask stroke")
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01, "dual: region A visible after commit")
	check(absf(terrain.heights[sample_b] - expected_b) < 0.01, "dual: region B visible after commit")
	check(doc.preview_after.has(sample_a) and doc.preview_after.has(sample_b),
		"dual: full composition stays on screen after commit")
	check(absf(float(doc.export_heights().get(sample_a, -1.0)) - expected_a) < 0.01,
		"dual: native export agrees on region A")
	check(absf(float(doc.export_heights().get(sample_b, -1.0)) - expected_b) < 0.01,
		"dual: native export agrees on region B")

	# Cancel restores the exact pre-stroke composition of BOTH regions.
	check(doc.begin_sculpt_mask_stroke(), "dual: begin stroke for cancel")
	check(doc.sculpt_mask_dab(point_b, 8.0, 1.0, Document.BrushShape.CIRCLE, 1.0),
		"dual: dab before cancel")
	doc.cancel_sculpt_mask_stroke()
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01, "dual: region A intact after cancel")
	check(absf(terrain.heights[sample_b] - expected_b) < 0.01, "dual: region B intact after cancel")
	check(doc.preview_after.has(sample_a) and doc.preview_after.has(sample_b),
		"dual: composed preview of both regions restored after cancel")

	# Undo/Redo of the committed mask stroke keeps the composition exact: the
	# undo target is the pre-stroke mask (empty), so region B falls back to its
	# masked-out base and redo re-reveals it.
	doc.undo()
	check(absf(terrain.heights[sample_b] - base_b) < 0.01, "dual: undo restores masked-out region B")
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01, "dual: region A survives undo")
	doc.redo()
	check(absf(terrain.heights[sample_b] - expected_b) < 0.01, "dual: redo restores region B")
	check(absf(terrain.heights[sample_a] - expected_a) < 0.01, "dual: region A survives redo")


## T-56 P0: an empty but active Sculpt composition owns the preview. Color
## Preview must not read has_preview() as permission to take that owner; refusal
## must leave every bit of state alone, and an explicit clear is the safe path.
func test_empty_sculpt_color_preview_refusal(fixture: String) -> void:
	var doc := fresh_document(fixture, "empty-sculpt-color-preview")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	check(doc.add_sculpt_layer() == 0, "empty-sculpt: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 8.0, 20.0, Document.BrushShape.CIRCLE),
		"empty-sculpt: keep a real sculpt delta elsewhere")
	check(doc.add_sculpt_mask(0, 0.0), "empty-sculpt: default-zero mask hides the delta")
	check(doc.sculpt_preview(), "empty-sculpt: compose masked sculpt preview")
	check(doc.has_active_preview_context() and not doc.has_preview(),
		"empty-sculpt: active composition has no pixel buffer")
	check(doc.preview_owner == "sculpt", "empty-sculpt: sculpt owns the empty context")
	check(doc.add_color_layer() == 0, "empty-sculpt: add color layer")
	(doc.color_layers[0] as Dictionary)["samples"] = {sample: {"rgb": 0xff8080, "coverage": 1.0}}
	var history_before := doc.undo_stack.size()
	var revision_before := doc.edit_revision
	var terrain_before := terrain.encode(doc.edits)
	var before_preview: Dictionary = terrain.material_previews.duplicate(true)
	check(not doc.color_preview(), "empty-sculpt: color preview refuses the empty foreign sculpt context")
	check(doc.preview_owner == "sculpt" and doc._sculpt_composition_active,
		"empty-sculpt: refusal keeps sculpt owner and active composition")
	check(terrain.material_previews == before_preview, "empty-sculpt: refusal adds no color buffer")
	check(doc.undo_stack.size() == history_before and doc.edit_revision == revision_before,
		"empty-sculpt: refusal adds no history or edit revision")
	check(terrain.encode(doc.edits) == terrain_before, "empty-sculpt: native terrain untouched")
	check(not doc.show_color_preview({sample: 0xff0000}), "empty-sculpt: direct show also refuses")
	check(doc.preview_owner == "sculpt", "empty-sculpt: direct refusal keeps owner")
	doc.clear_preview()
	check(doc.color_preview(), "empty-sculpt: explicit transition admits color preview")
	check(doc.preview_owner == "color" and terrain.material_previews.has(Terrain.Layer.COLOR),
		"empty-sculpt: transition publishes the color sample")
	unwatch_material_refresh(doc)


## T-56 P0: the mirror gap. An empty active Color composition must not be
## silently consumed when a Sculpt Opacity gesture arms and stages a preview.
## Refusal must leave the owner, layer, preview, gesture UID and history intact.
func test_empty_color_sculpt_opacity_refusal(fixture: String) -> void:
	var doc := fresh_document(fixture, "empty-color-sculpt-opacity")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	check(doc.add_sculpt_layer() == 0, "empty-color: add sculpt layer")
	var sample_sculpt := 220 * terrain.dimensions.x + 220
	var sculpt_state := _sculpt_snapshot_for_test(doc)
	(sculpt_state[0] as Dictionary)["deltas"] = {sample_sculpt: 20.0}
	check(doc._commit_sculpt_layers(sculpt_state, doc.active_sculpt_uid), "empty-color: stage sculpt delta")
	var uid := int((doc.sculpt_layers[0] as Dictionary)["uid"])
	check(doc.add_color_layer() == 0, "empty-color: add color layer")
	check(doc.color_preview(), "empty-color: compose empty color layer")
	# Stage the sculpt delta through the layer API: a real sculpt_dab would
	# leave its own nonempty preview and mask the ownership defect under test.
	check(doc.has_active_preview_context() and not doc.has_preview(),
		"empty-color: active color composition has no pixel buffer")
	check(doc.preview_owner == "color" and doc._color_composition_active,
		"empty-color: color owns the empty context")
	var history_before := doc.undo_stack.size()
	var revision_before := doc.edit_revision
	var terrain_before := terrain.encode(doc.edits)
	var opacity_before := float((doc.sculpt_layers[0] as Dictionary)["opacity"])
	check(not doc.begin_sculpt_opacity_preview(0), "empty-color: opacity gesture refuses the foreign empty context")
	check(doc._sculpt_opacity_preview_uid == -1, "empty-color: refusal leaves no armed gesture UID")
	check(doc.preview_owner == "color" and doc._color_composition_active,
		"empty-color: refusal preserves color owner and composition")
	check(not doc.preview_sculpt_layer_opacity(uid, 0.4),
		"empty-color: staging without a gesture is refused")
	check(doc.undo_stack.size() == history_before and doc.edit_revision == revision_before,
		"empty-color: refusal adds no history or edit revision")
	check(terrain.encode(doc.edits) == terrain_before, "empty-color: native terrain untouched")
	check(is_equal_approx(float((doc.sculpt_layers[0] as Dictionary)["opacity"]), opacity_before),
		"empty-color: committed layer opacity untouched")
	doc.cancel_sculpt_opacity_preview()
	check(doc.preview_owner == "color", "empty-color: cancel on a refused gesture changes nothing")
	doc.clear_preview()
	check(doc.begin_sculpt_opacity_preview(0), "empty-color: explicit transition arms the gesture")
	check(doc.preview_sculpt_layer_opacity(uid, 0.4), "empty-color: staging after transition works")
	check(doc.preview_owner == "sculpt" and doc.has_preview(), "empty-color: transition owns sculpt preview")
	check(doc.commit_sculpt_opacity_preview(uid, 0.4), "empty-color: gesture commits")
	check(is_equal_approx(float((doc.sculpt_layers[0] as Dictionary)["opacity"]), 0.4),
		"empty-color: committed opacity applied")
	check(doc.undo_stack.size() == history_before + 1, "empty-color: commit is one Undo")
	unwatch_material_refresh(doc)


## T-55: the last empty-composition ownership gap. An empty but active Sculpt
## composition must not let a Color Opacity gesture arm or stage; refusal leaves
## the gesture UID, owner, history and native state untouched until the context
## is explicitly cleared.
func test_empty_sculpt_color_opacity_refusal(fixture: String) -> void:
	var doc := fresh_document(fixture, "empty-sculpt-color-opacity")
	var terrain: Terrain = doc.package.terrain
	var sample := 200 * terrain.dimensions.x + 200
	check(doc.add_sculpt_layer() == 0, "empty-sculpt-op: add sculpt layer")
	check(doc.sculpt_dab(Vector2(220.0, 220.0), 8.0, 20.0, Document.BrushShape.CIRCLE),
		"empty-sculpt-op: keep a real sculpt delta elsewhere")
	check(doc.add_sculpt_mask(0, 0.0), "empty-sculpt-op: default-zero mask hides the delta")
	check(doc.sculpt_preview(), "empty-sculpt-op: compose masked sculpt preview")
	check(doc.has_active_preview_context() and not doc.has_preview(),
		"empty-sculpt-op: active sculpt composition has no pixel buffer")
	check(doc.add_color_layer() == 0, "empty-sculpt-op: add color layer")
	var uid := int((doc.color_layers[0] as Dictionary)["uid"])
	var history_before := doc.undo_stack.size()
	var revision_before := doc.edit_revision
	var terrain_before := terrain.encode(doc.edits)
	var mats_before: Dictionary = terrain.material_previews.duplicate(true)
	check(not doc.begin_color_opacity_preview(0),
		"empty-sculpt-op: begin refuses the foreign empty sculpt context")
	check(doc._color_opacity_preview_uid == -1, "empty-sculpt-op: refusal leaves no armed gesture UID")
	check(doc.preview_owner == "sculpt" and doc._sculpt_composition_active,
		"empty-sculpt-op: refusal preserves sculpt owner and composition")
	check(not doc.preview_color_layer_opacity(uid, 0.4), "empty-sculpt-op: staging without a gesture is refused")
	check(doc.preview_owner == "sculpt" and terrain.material_previews == mats_before,
		"empty-sculpt-op: refusal adds no color buffer")
	check(doc.undo_stack.size() == history_before and doc.edit_revision == revision_before,
		"empty-sculpt-op: refusal adds no history or edit revision")
	check(terrain.encode(doc.edits) == terrain_before, "empty-sculpt-op: native terrain untouched")
	doc.cancel_color_opacity_preview()
	check(doc.preview_owner == "sculpt", "empty-sculpt-op: cancel on a refused gesture changes nothing")
	doc.clear_preview()
	check(doc.begin_color_opacity_preview(0), "empty-sculpt-op: explicit transition arms the gesture")
	check(doc.preview_color_layer_opacity(uid, 0.4), "empty-sculpt-op: staging after transition works")
	check(doc.commit_color_opacity_preview(uid, 0.4), "empty-sculpt-op: gesture commits")
	check(is_equal_approx(float((doc.color_layers[0] as Dictionary)["opacity"]), 0.4),
		"empty-sculpt-op: committed opacity applied")
	check(doc.undo_stack.size() == history_before + 1, "empty-sculpt-op: commit is one Undo")
	unwatch_material_refresh(doc)


## T-58 RED: Color Mask must share Sculpt Mask flow physics. Brush pressure is
## the alpha of lerp(previous, target), not the target itself; BELL falloff must
## yield graded strengths; invalid args must refuse without partial mutation.
func test_color_mask_flow_oracles(fixture: String) -> void:
	var doc := fresh_document(fixture, "color-mask-flow")
	var terrain: Terrain = doc.package.terrain
	var sample := 220 * terrain.dimensions.x + 220
	check(doc.add_color_layer() == 0, "flow: add color layer")
	check(doc.add_color_mask(0, 0.0), "flow: add default-zero mask")
	var brush := BrushPanel.new()
	root.add_child(brush)
	brush.set_brush_size(8)
	brush.set_shape(Document.BrushShape.CIRCLE)
	brush.surface.select(Terrain.Layer.COLOR)
	brush.mask_target.set_pressed_no_signal(true)
	brush.mask_reveal.set_pressed_no_signal(true)
	brush.set_pressure(20)
	var undo_before := doc.undo_stack.size()
	check(doc.begin_color_mask_stroke(), "flow: begin color reveal stroke")
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	var samples: Dictionary = ((doc.color_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(absf(float(samples.get(sample, -1.0)) - 0.2) < 0.005,
		"flow: brush reveal 20%% writes 0.2 (got %.4f)" % float(samples.get(sample, -1.0)))
	brush.mask_reveal.set_pressed_no_signal(false)
	brush.apply_dab(doc, Vector2(220.0, 220.0))
	samples = ((doc.color_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(absf(float(samples.get(sample, -1.0)) - 0.16) < 0.005,
		"flow: brush hide 20%% from 0.2 removes only 0.04 (got %.4f)" % float(samples.get(sample, -1.0)))
	check(doc.end_color_mask_stroke(), "flow: end color stroke")
	check(doc.undo_stack.size() == undo_before + 1, "flow: color stroke is one Undo")
	brush.queue_free()
	unwatch_material_refresh(doc)


## T-59 RED: mask utilities operate on the canonical sparse representation and
## use the existing one-Undo layer commit lifecycle. No active stroke admitted.
func test_mask_operations(fixture: String) -> void:
	var doc := fresh_document(fixture, "mask-operations")
	var terrain: Terrain = doc.package.terrain
	var a := 200 * terrain.dimensions.x + 200
	var b := 201 * terrain.dimensions.x + 201
	check(doc.add_color_layer() == 0, "ops: add color layer")
	check(doc.add_color_mask(0, 0.2), "ops: add color mask default 0.2")
	var mask_data: Dictionary = (doc.color_layers[0] as Dictionary)["mask"]
	var samples_set: Dictionary = mask_data["samples"]
	samples_set[a] = 0.8
	samples_set[b] = 0.0
	var before := doc.undo_stack.size()
	check(doc.invert_color_mask(0), "ops: invert color mask")
	var mask: Dictionary = (doc.color_layers[0] as Dictionary)["mask"]
	check(is_equal_approx(float(mask["default"]), 0.8), "ops: inverted default 0.8")
	var samples: Dictionary = mask["samples"]
	check(is_equal_approx(float(samples[a]), 0.2), "ops: inverted A 0.2")
	check(is_equal_approx(float(samples[b]), 1.0), "ops: inverted B 1.0")
	check(doc.undo_stack.size() == before + 1, "ops: invert is one Undo")
	doc.undo()
	mask = (doc.color_layers[0] as Dictionary)["mask"]
	check(is_equal_approx(float(mask["default"]), 0.2), "ops: undo restores default")
	doc.redo()
	check(doc.clear_color_mask_overrides(0), "ops: clear color overrides")
	samples = ((doc.color_layers[0] as Dictionary)["mask"] as Dictionary)["samples"]
	check(samples.is_empty(), "ops: clear removes all sparse overrides")
	check(doc.fill_color_mask(0, 1.0), "ops: fill white")
	mask = (doc.color_layers[0] as Dictionary)["mask"]
	check(is_equal_approx(float(mask["default"]), 1.0), "ops: fill sets default 1")
	check((mask["samples"] as Dictionary).is_empty(), "ops: fill clears overrides")
	check(doc.fill_color_mask(0, 0.0), "ops: fill black")
	check(not doc.fill_color_mask(0, 2.0), "ops: invalid strength refused")
	check(doc.add_sculpt_layer() == 0, "ops: add sculpt layer")
	check(doc.add_sculpt_mask(0, 0.25), "ops: add sculpt mask")
	check(doc.invert_sculpt_mask(0), "ops: invert sculpt mask")
	var smask: Dictionary = (doc.sculpt_layers[0] as Dictionary)["mask"]
	check(is_equal_approx(float(smask["default"]), 0.75), "ops: sculpt inverted default")
	check(doc.clear_sculpt_mask_overrides(0), "ops: clear sculpt overrides")
	check(doc.fill_sculpt_mask(0, 1.0), "ops: sculpt fill white")
	check(doc.invert_color_mask(0) and doc.invert_color_mask(0), "ops: double invert color")
	mask = (doc.color_layers[0] as Dictionary)["mask"]
	check(is_equal_approx(float(mask["default"]), 0.0), "ops: double invert restores default")
	check(doc.invert_sculpt_mask(0) and doc.invert_sculpt_mask(0), "ops: double invert sculpt")
	smask = (doc.sculpt_layers[0] as Dictionary)["mask"]
	check(is_equal_approx(float(smask["default"]), 1.0), "ops: double invert restores sculpt default")
	unwatch_material_refresh(doc)
