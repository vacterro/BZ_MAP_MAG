extends SceneTree

## Failure-injection acceptance for the transactional autosave store. The
## acceptance rule: after any simulated failure the newest confirmed good
## recovery copy survives, prunes never endanger it, and the source map folder
## plus its package files stay byte-identical.

const Document := preload("res://core/map_document.gd")
const Store := preload("res://core/autosave_store.gd")

var failures := 0
var brave_path := ""
var scratch := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("Pass the Brave BZN fixture and a scratch directory.")
		quit(2)
		return
	brave_path = args[0]
	scratch = args[1]
	var original := FileAccess.get_file_as_bytes(brave_path)
	if original.is_empty():
		printerr("Could not read the Brave fixture.")
		quit(2)
		return
	var family := copy_package(brave_path, scratch.path_join("proj-a"))
	var family_b := copy_package(brave_path, scratch.path_join("proj-b"))
	var snapshot := record_members(family)
	var document := Document.new()
	if not check(document.open(family.path_join(brave_path.get_file())), "open the autosave fixture copy"):
		finish()
		return
	document.begin_stroke()
	document.dab(Vector2(512.0, 512.0), 48, 24)
	document.end_stroke()
	var root := scratch.path_join("autosaves")
	var project := Store.project_dir(root, document.package.source_path)
	var store := Store.new()

	# 1. Normal publish: a verified slot appears with its manifest.
	var first: String = store.publish(document, root, 3)
	check(not first.is_empty() and FileAccess.file_exists(first), "a normal publish writes one verified slot")
	check(FileAccess.file_exists(Store.manifest_path(project)), "the recovery manifest is published")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Store.manifest_path(project))) as Dictionary
	check(int(manifest.get("schema", 0)) == 2 and String(manifest.get("source", "")) == document.package.source_path,
		"the manifest names the project identity and schema")

	# 2. Repeated publishes roll forward and prune to the keep count.
	for i in 5:
		document.begin_stroke()
		document.dab(Vector2(400.0 + i * 16.0, 512.0), 24, 20)
		document.end_stroke()
		var slot: String = store.publish(document, root, 3)
		check(not slot.is_empty(), "publish %d succeeds with more edits" % (i + 2))
	check(Store.slots(project).size() == 3, "exactly three slots survive the rolling keep count")
	var expected_edits: int = document.edits.size()
	var recovery := Document.new()
	check(recovery.open(Store.latest(project)) and recovery.edits.size() == expected_edits,
		"the newest slot reopens with every current edit")
	var keep_latest := Store.latest(project)

	# 3. Failure matrix: each injected failure must leave the last good slot intact.
	var before_slots := Store.slots(project)
	test_failure(store, document, root, "write", keep_latest, expected_edits, before_slots)
	test_failure(store, document, root, "corrupt", keep_latest, expected_edits, before_slots)
	test_failure(store, document, root, "verify", keep_latest, expected_edits, before_slots)
	test_failure(store, document, root, "publish", keep_latest, expected_edits, before_slots)
	test_failure(store, document, root, "crash", keep_latest, expected_edits, before_slots)

	# 4. A crash leaves an unpublished verified stage; the next publish sweeps it.
	var stale := 0
	for name in DirAccess.get_files_at(project):
		if name.begins_with("stage-"):
			stale += 1
	check(stale == 1, "the injected crash leaves exactly one abandoned stage file")
	var after_crash: String = store.publish(document, root, 3)
	check(not after_crash.is_empty(), "publishing after a crash succeeds")
	stale = 0
	for name in DirAccess.get_files_at(project):
		if name.begins_with("stage-"):
			stale += 1
	check(stale == 0, "the next publish sweeps the abandoned stage files")

	# 5. Prune failures never block a publish and never endanger the newest slot.
	store.failure = "prune"
	document.begin_stroke()
	document.dab(Vector2(300.0, 400.0), 24, 12)
	document.end_stroke()
	var pruned_failure: String = store.publish(document, root, 3)
	check(not pruned_failure.is_empty() and not store.error.is_empty(), "a prune failure still publishes the new slot and records the warning")
	check(Store.latest(project) == pruned_failure, "the newest slot is the new publish even when pruning old slots failed")
	store.failure = ""

	# 6..destination folder that cannot be created fails cleanly.
	var blocked := scratch.path_join("blocker")
	var blocker := FileAccess.open(blocked, FileAccess.WRITE)
	blocker.store_string("occupied")
	blocker.close()
	var blocked_publish: String = store.publish(document, blocked, 3)
	check(blocked_publish.is_empty() and store.error.contains("Could not create the autosave folder"),
		"an unusable autosave root fails with a clear reason")

	# 7. Source revision changes refuse an autosave instead of mixing revisions.
	var trn_path := family.path_join(brave_path.get_file().get_basename() + ".trn")
	var trn_original := FileAccess.get_file_as_bytes(trn_path)
	var handle := FileAccess.open(trn_path, FileAccess.WRITE)
	handle.store_buffer(trn_original)
	handle.store_8(0)
	handle.close()
	var mismatched: String = store.publish(document, root, 3)
	check(mismatched.is_empty() and store.error.contains("Source changed"),
		"a changed source refuses the autosave with a revision reason: " + store.error)
	var restored := FileAccess.open(trn_path, FileAccess.WRITE)
	restored.store_buffer(trn_original)
	restored.close()
	var resumed: String = store.publish(document, root, 3)
	check(not resumed.is_empty(), "restoring the source revision resumes autosaves")

	# 8. Read-only sources still autosave: the store never writes the map folder.
	var windows := OS.get_name() == "Windows"
	var set_read := 0
	if windows:
		set_read = OS.execute("attrib", ["+r", ProjectSettings.globalize_path(trn_path).replace("/", "\\")], [])
	check(not windows or set_read == 0, "the read-only attribute was applied")
	document.begin_stroke()
	document.dab(Vector2(200.0, 480.0), 24, 14)
	document.end_stroke()
	var readonly_publish: String = store.publish(document, root, 3)
	check(not readonly_publish.is_empty(), "read-only source files do not block autosaving")
	if windows:
		OS.execute("attrib", ["-r", ProjectSettings.globalize_path(trn_path).replace("/", "\\")], [])

	# 9. Same-stem maps in different directories keep separate identities.
	var other := Document.new()
	check(other.open(family_b.path_join(brave_path.get_file())), "open the second same-stem package")
	other.begin_stroke()
	other.dab(Vector2(200.0, 300.0), 30, 22)
	other.end_stroke()
	var other_project := Store.project_dir(root, other.package.source_path)
	check(other_project != project, "a different source directory yields a different project identity")
	var other_slot: String = store.publish(other, root, 2)
	check(not other_slot.is_empty() and other_slot.begins_with(other_project), "the second package publishes into its own identity folder")
	var second_recovery := Document.new()
	check(second_recovery.open(Store.latest(other_project)) and second_recovery.edits.size() == other.edits.size(),
		"the second identity recovers its own edits")

	# 10. Files that merely look like autosaves are never managed.
	var stray_path := project.path_join(brave_path.get_file().get_basename() + "-autosave-1.bzmag")
	var stray := FileAccess.open(stray_path, FileAccess.WRITE)
	stray.store_string("user data that must never be touched")
	stray.close()
	var stray_bytes := FileAccess.get_file_as_bytes(stray_path)
	var joker := FileAccess.open(project.path_join("slot-0000000000-not-a-real-slot.bzmag"), FileAccess.WRITE)
	joker.store_string("misnamed file")
	joker.close()
	var managed := Store.slots(project)
	check(not managed.has(stray_path), "an old-style autosave name is not managed")
	document.begin_stroke()
	document.dab(Vector2(500.0, 400.0), 24, 10)
	document.end_stroke()
	var final_publish: String = store.publish(document, root, 3)
	check(not final_publish.is_empty(), "the final publish succeeds with stray files present")
	check(FileAccess.get_file_as_bytes(stray_path) == stray_bytes, "stray autosave-looking files are byte-identical after publishing")

	# 11. Recovery after a restart through a fresh store instance.
	var restart := Store.new()
	var restart_slot := restart.latest(project)
	var fresh := Document.new()
	check(not restart_slot.is_empty() and fresh.open(restart_slot) and fresh.edits.size() == document.edits.size(),
		"a fresh store after a restart recovers the newest confirmed slot")

	# 12. The source package files stay byte-identical (the revision probe was
	# restored and the read-only attribute does not alter bytes).
	var final_members := record_members(family)
	for name in snapshot:
		check(final_members.get(name, PackedByteArray()) == snapshot[name],
			"package member " + name + " stayed byte-identical through every autosave")
	finish()


func record_members(folder: String) -> Dictionary:
	var bytes := {}
	for name in DirAccess.get_files_at(folder):
		bytes[name] = FileAccess.get_file_as_bytes(folder.path_join(name))
	return bytes


func test_failure(store, document: Document, root: String, mode: String, keep_latest: String, expected_edits: int, before_slots: PackedStringArray) -> void:
	store.failure = mode
	var outcome: String = store.publish(document, root, 3)
	check(outcome.is_empty() and not store.error.is_empty(), "injected " + mode + " failure refuses the publish with a reason")
	var slots_after := Store.slots(Store.project_dir(root, document.package.source_path))
	check(slots_after.size() == before_slots.size(), "the " + mode + " failure does not add or destroy slots")
	var recovery := Document.new()
	check(recovery.open(Store.latest(Store.project_dir(root, document.package.source_path)))
		and recovery.edits.size() == expected_edits, "after the " + mode + " failure the last confirmed copy still opens with every edit")
	check(Store.latest(Store.project_dir(root, document.package.source_path)) == keep_latest,
		"the " + mode + " failure leaves the newest previous good slot in place")
	store.failure = ""


func copy_package(source: String, target: String) -> String:
	DirAccess.make_dir_recursive_absolute(target)
	var stem := source.get_file().get_basename().to_lower()
	for name in DirAccess.get_files_at(source.get_base_dir()):
		if name.to_lower().get_basename() != stem and name.to_lower() != stem + "_load.dds":
			continue
		var copied := FileAccess.open(target.path_join(name), FileAccess.WRITE)
		copied.store_buffer(FileAccess.get_file_as_bytes(source.get_base_dir().path_join(name)))
		copied.close()
	return target


func finish() -> void:
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, description: String) -> bool:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	return condition
