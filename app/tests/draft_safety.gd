extends SceneTree

## Focused acceptance for SAIHANDOFF-17: UID-aware draft identity, deletion-aware
## three-way merge, draft-aware autosave payload and the first sculpt layer.

const Document := preload("res://core/map_document.gd")
const Studio := preload("res://nodes/node_studio.gd")
const Graph := preload("res://nodes/height_graph.gd")
const Store := preload("res://core/autosave_store.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Sculpt := preload("res://core/sculpt_layers.gd")
const Package := preload("res://formats/map_package.gd")
const Terrain := preload("res://formats/terrain_v5.gd")

var failures := 0
var scratch := ""


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
