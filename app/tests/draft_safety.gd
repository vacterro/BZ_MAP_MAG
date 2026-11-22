extends SceneTree

## Focused acceptance for SAIHANDOFF-17: UID-aware draft identity, deletion-aware
## three-way merge, draft-aware autosave payload and the first sculpt layer.

const Document := preload("res://core/map_document.gd")
const Studio := preload("res://nodes/node_studio.gd")
const Graph := preload("res://nodes/height_graph.gd")
const Store := preload("res://core/autosave_store.gd")
const Snapshots := preload("res://bridge/snapshots.gd")
const Sculpt := preload("res://core/sculpt_layers.gd")

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
