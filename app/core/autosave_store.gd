extends RefCounted
## Project autosaves, transactionally published outside the source map folder.
##
## The store keeps immutable slot files (slot-<sequence>-<UTC>-<nonce>.bzmag)
## inside a per-project identity folder under the autosave root. Slots are never
## renamed over each other: a new autosave is written to a stage file, verified
## by a full project re-open, atomically renamed to its own unique slot name,
## and only then are older slots pruned. At any interruption point the newest
## previous good recovery copy survives, and the source map folder is never
## touched. The manifest is advisory; slots are self-describing.

const Snapshots := preload("res://bridge/snapshots.gd")
const Document := preload("res://core/map_document.gd")

const DEFAULT_ROOT := "user://autosaves"
const MANIFEST := "manifest.json"
const MANIFEST_STAGE := "manifest.json.stage"
const SLOT_PREFIX := "slot-"
const STAGE_PREFIX := "stage-"
const DRAFT_SUFFIX := ".draft.json"
const SAVE_STAGE_DIR := ".bzmag-"
const SCHEMA := 2
const DRAFT_SCHEMA := 1

const SLOT_PATTERN := "^slot-([0-9]{10})-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}\\.bzmag$"

var error := ""
## Failure injection for tests only. One of "", "write", "corrupt", "verify",
## "publish", "crash", "prune": each one aborts at a real checkpoint of the
## protocol instead of fabricating results.
var failure := ""


## Stable project identity: the map stem plus a digest of the normalized
## source path, so maps sharing a basename never collide.
static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	var finish: PackedByteArray = context.finish()
	return String(finish.hex_encode())


static func project_key(source_path: String) -> String:
	var normalized := source_path.simplify_path()
	return digest(normalized.to_utf8_buffer()).substr(0, 16)


static func project_dir(root: String, source_path: String) -> String:
	var stem := source_path.get_file().get_basename()
	return root.path_join("%s-%s" % [stem, project_key(source_path)])


static func timestamp_name() -> String:
	var utc: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02dT%02d%02d%02dZ" % [utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second]


## Sorted slot paths, oldest first. Only files matching the verified slot
## naming rule are managed; anything else in the folder is left untouched.
static func slots(directory: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var handle := DirAccess.open(directory)
	if handle == null:
		return found
	var pattern := RegEx.new()
	pattern.compile(SLOT_PATTERN)
	for name in handle.get_files():
		if pattern.search(name):
			found.push_back(name)
	found.sort()
	for index in found.size():
		found.set(index, directory.path_join(found[index]))
	return found


static func latest(directory: String) -> String:
	var found := slots(directory)
	return "" if found.is_empty() else found[found.size() - 1]


static func manifest_path(directory: String) -> String:
	return directory.path_join(MANIFEST)


## The highest stored sequence number, so ordering survives same-second writes.
static func next_sequence(directory: String) -> int:
	var highest := 0
	var handle := DirAccess.open(directory)
	if handle == null:
		return 1
	var pattern := RegEx.new()
	pattern.compile(SLOT_PATTERN)
	for name in handle.get_files():
		var match := pattern.search(name)
		if match:
			highest = maxi(highest, int(match.get_string(1)))
	return highest + 1


## Publishes one autosave. Returns the published slot path, or "" with a
## reason in error. The previous newest good slot is never removed before the
## new one is fully written, verified and renamed into place.
func publish(document: Document, base_root: String, keep: int, draft: Dictionary = {}) -> String:
	error = ""
	if document == null:
		error = "No open document."
		return ""
	if document.has_active_edit_transaction():
		# Defer: autosave must never serialize a half-finished stroke. The
		# caller keeps its timer so the next tick retries after commit.
		error = "An edit transaction is active; autosave deferred."
		return ""
	if keep < 1:
		error = "The autosave slot count must be at least one."
		return ""
	var directory := project_dir(base_root, document.package.source_path)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "Could not create the autosave folder " + directory
		return ""
	sweep_abandoned_stages(directory)
	var writer := Snapshots.new()
	if failure == "write":
		error = "Injected write failure: the project record could not be written."
		return ""
	var stage := directory.path_join("%s%s.bzmag" % [STAGE_PREFIX, writer.nonce()])
	if not writer.save_project(document, stage):
		error = "The autosave record could not be written. " + writer.error
		return ""
	if failure == "corrupt":
		# A partial record on disk: the verification below must catch it.
		var partial := FileAccess.open(stage, FileAccess.WRITE)
		partial.store_string("{\"schema\": 1, \"source\": \"")
		partial.close()
	if failure == "verify":
		DirAccess.remove_absolute(stage)
		error = "The staged autosave did not re-open as a valid project."
		return ""
	var probe := Document.new()
	if not probe.open(stage):
		DirAccess.remove_absolute(stage)
		error = "The staged autosave did not re-open as a valid project. " + probe.error
		return ""
	if failure == "crash":
		# Simulated termination between verification and publication: the
		# verified stage stays, the previous newest slot is untouched.
		error = "Injected crash before publication."
		return ""
	var target := directory.path_join("%s%010d-%s-%s.bzmag" % [SLOT_PREFIX, next_sequence(directory), timestamp_name(), writer.nonce()])
	var draft_target := target + DRAFT_SUFFIX
	if not draft.is_empty():
		# The staged slot has the exact bytes that will be renamed into place;
		# bind the draft to that SHA256 so a sidecar can never be offered as
		# recovery for a different committed slot.
		var slot_sha := FileAccess.get_sha256(stage)
		if not publish_draft(draft, document, draft_target, slot_sha):
			DirAccess.remove_absolute(stage)
			DirAccess.remove_absolute(draft_target)
			return ""
	if failure == "publish" or DirAccess.rename_absolute(stage, target) != OK:
		DirAccess.remove_absolute(draft_target)
		error = "The autosave could not be published to " + target
		return ""
	write_manifest(document, directory, keep)
	prune(directory, keep)
	return target


## Advisory recovery manifest. A manifest failure is recorded but never
## invalidates the published slot.
## Draft payload is written beside its committed slot and cross-links the base
## stack by UID and revision. A mismatch or corrupt payload is never applied.
func publish_draft(draft: Dictionary, document: Document, target: String, slot_sha: String = "") -> bool:
	document.ensure_layer_uids()
	var payload := {
		"schema": DRAFT_SCHEMA,
		"source": document.package.source_path,
		"sourceRevision": digest(JSON.stringify(document.package.files).to_utf8_buffer()),
		"documentId": document.document_id,
		"slotSha256": slot_sha,
		"baseFingerprint": base_stack_fingerprint(document),
		"baseLayerRevision": studio_base_revision(draft),
		"baseUids": studio_base_uids(draft),
		"draft": draft,
		"savedUtc": timestamp_name(),
	}
	# JSON round-trips integers as floats; the editor casts UIDs on restore.

	var stage := target + ".stage"
	var handle := FileAccess.open(stage, FileAccess.WRITE)
	if handle == null:
		error = "The recovery draft could not be staged."
		return false
	var bytes := JSON.stringify(payload, "", true, true).to_utf8_buffer()
	handle.store_buffer(bytes)
	handle.close()
	var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(stage))
	if not probe is Dictionary or (probe as Dictionary).get("schema") != DRAFT_SCHEMA:
		DirAccess.remove_absolute(stage)
		error = "The recovery draft failed verification."
		return false
	if DirAccess.rename_absolute(stage, target) != OK:
		DirAccess.remove_absolute(stage)
		error = "The recovery draft could not be published."
		return false
	return true


## Durable identity of the committed layer stack by content and UID, not by a
## session-local revision counter that restarts when the project reopens.
static func base_stack_fingerprint(document: Document) -> String:
	var canonical := []
	for i in document.layers.size():
		var layer: Dictionary = document.layers[i]
		var uid := document.layer_uids[i] if i < document.layer_uids.size() else -1
		canonical.append({"uid": uid, "layer": layer})
	return digest(JSON.stringify(canonical, "", true, true).to_utf8_buffer())


func studio_base_revision(draft: Dictionary) -> int:
	return int(draft.get("baseLayerRevision", -1))


func studio_base_uids(draft: Dictionary) -> Array:
	var raw: Variant = draft.get("baseUids", [])
	return raw if raw is Array else []


static func read_draft(slot: String) -> Dictionary:
	var path := slot + DRAFT_SUFFIX
	if not FileAccess.file_exists(path):
		return {}
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null or handle.get_length() > 64 * 1024 * 1024:
		return {}
	var parsed: Variant = JSON.parse_string(handle.get_as_text())
	if not parsed is Dictionary:
		return {}
	var payload := parsed as Dictionary
	# A sidecar belongs to exactly one slot. Refuse a stale or tampered sidecar
	# rather than offering a draft for a different committed recovery pair.
	if not payload.has("slotSha256"):
		return {}
	var expected := String(payload["slotSha256"])
	if expected.is_empty() or expected != FileAccess.get_sha256(slot):
		return {}
	return payload


func write_manifest(document: Document, directory: String, keep: int) -> void:
	var source_revision := digest(JSON.stringify(document.package.files).to_utf8_buffer())
	var record := {
		"schema": SCHEMA,
		"source": document.package.source_path,
		"key": project_key(document.package.source_path),
		"source_revision": source_revision,
		"saved_utc": timestamp_name(),
		"keep": keep,
	}
	var stage := directory.path_join(MANIFEST_STAGE)
	var handle := FileAccess.open(stage, FileAccess.WRITE)
	if handle == null:
		error = "The recovery manifest could not be staged."
		return
	handle.store_string(JSON.stringify(record, "\t", false, true))
	handle.close()
	var probe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(stage)) as Dictionary
	if probe.is_empty():
		DirAccess.remove_absolute(stage)
		error = "The recovery manifest could not be verified."
		return
	if DirAccess.rename_absolute(stage, manifest_path(directory)) != OK:
		DirAccess.remove_absolute(stage)
		error = "The recovery manifest could not be published."
		return


## Removes slots beyond the newest keep-count. Deletion failures are recorded
## but never endanger the newest slot.
func prune(directory: String, keep: int) -> void:
	var found := slots(directory)
	var excess := found.size() - keep
	for index in excess:
		if failure == "prune" and index == 0:
			error = "Injected prune failure: an old slot could not be removed."
			continue
		# Remove the committed slot FIRST. A failed removal then leaves a
		# complete recovery pair (slot + sidecar) rather than an orphan slot.
		if DirAccess.remove_absolute(found[index]) != OK:
			error = "An old autosave slot could not be removed: " + found[index]
			continue
		DirAccess.remove_absolute(found[index] + DRAFT_SUFFIX)


## Removes abandoned stage files and interrupted save staging folders so a
## crashed publication cannot pollute the next one. Runs before the new write.
func sweep_abandoned_stages(directory: String) -> void:
	var handle := DirAccess.open(directory)
	if handle == null:
		return
	for name in handle.get_files():
		if name.begins_with(STAGE_PREFIX) or name == MANIFEST_STAGE or name.ends_with(DRAFT_SUFFIX + ".stage"):
			handle.remove(name)
	for name in handle.get_directories():
		if name.begins_with(SAVE_STAGE_DIR):
			handle.remove(name)
