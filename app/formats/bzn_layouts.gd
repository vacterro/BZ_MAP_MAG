extends RefCounted
## Verified BZN save layouts and their editing capabilities.
##
## The BZN version number alone does not describe a save layout. This registry
## is the single source of truth the codecs and the Playtest launcher consult:
## every capability below is tied to recorded evidence, and anything outside
## these profiles stays unrecognized. Header agreement never grants write
## capabilities on its own.

const READ := "READ"
const INSPECT_PATHS := "INSPECT_PATHS"
const EDIT_PATH_POINTS := "EDIT_PATH_POINTS"
const EDIT_PATH_STRUCTURE := "EDIT_PATH_STRUCTURE"
const INSPECT_OBJECTS := "INSPECT_OBJECTS"
const EDIT_OBJECT_TRANSFORM := "EDIT_OBJECT_TRANSFORM"
const EDIT_OBJECT_COUNT := "EDIT_OBJECT_COUNT"
const ENGINE_PLAYTEST := "ENGINE_PLAYTEST"
const CONVERT_TO_185 := "CONVERT_TO_185"
const ALL_CAPABILITIES := [READ, INSPECT_PATHS, EDIT_PATH_POINTS, EDIT_PATH_STRUCTURE,
	INSPECT_OBJECTS, EDIT_OBJECT_TRANSFORM, EDIT_OBJECT_COUNT, ENGINE_PLAYTEST, CONVERT_TO_185]

## Status vocabulary (matches docs/COMPATIBILITY_MATRIX.md):
## NATIVE - proven through public BZCC. BAKED - materialised into the supported
## native format. EDITOR_ONLY - BZMAG state only. EXPERIMENTAL - proof incomplete.
## UNSUPPORTED - unavailable in this profile.
const PROFILES := {
	"binary-1192": {
		"version": 1192,
		"encoding": "binary",
		"header": "version 1192, saveType 0, binarySave true framed records",
		"framing": "tag byte + little-endian u16 length records",
		"boundaries": "path table and object block are located by structural discovery, not fixed offsets",
		"invariants": "declared path and object counts must match discovery, unique object IDs, 8031-byte map trailer",
		"engines": ["BZCC 2.0.185"],
		"adapter": "native 185 layout; VRV bzn_compat rejects version 1192",
		"fixtures": ["map_references/blank_map1/duel_map_27_autosave_01.bzn"],
		"capabilities": {READ: "NATIVE", INSPECT_PATHS: "NATIVE", EDIT_PATH_POINTS: "BAKED",
			EDIT_PATH_STRUCTURE: "BAKED", INSPECT_OBJECTS: "NATIVE", EDIT_OBJECT_TRANSFORM: "BAKED",
			EDIT_OBJECT_COUNT: "BAKED", ENGINE_PLAYTEST: "NATIVE", CONVERT_TO_185: "UNSUPPORTED"},
		"evidence": "docs/COMPATIBILITY_MATRIX.md BZN 1192 row; blank snapshot and duplicated-object 1192 export reached MISSION/RUN under /startedit /noscript",
	},
	"binary-1196": {
		"version": 1196,
		"encoding": "binary",
		"header": "version 1196, saveType 0, binarySave true framed records",
		"framing": "tag byte + little-endian u16 length records, later Craft ejection records present",
		"boundaries": "path table and object block are located by structural discovery, not fixed offsets",
		"invariants": "declared path and object counts must match discovery, unique object IDs, 8031-byte map trailer",
		"engines": ["BZCC 2.0.185 through the VRV bzn_compat adapter"],
		"adapter": "VRV tools/bzn_compat.py converts the verified late-1196 layout to 185",
		"fixtures": ["map_references/Brave Lil Toaster/braveliltoaster.bzn"],
		"capabilities": {READ: "NATIVE", INSPECT_PATHS: "NATIVE", EDIT_PATH_POINTS: "NATIVE",
			EDIT_PATH_STRUCTURE: "BAKED", INSPECT_OBJECTS: "NATIVE", EDIT_OBJECT_TRANSFORM: "NATIVE",
			EDIT_OBJECT_COUNT: "NATIVE", ENGINE_PLAYTEST: "UNSUPPORTED", CONVERT_TO_185: "NATIVE"},
		"evidence": "docs/COMPATIBILITY_MATRIX.md BZN 1196 rows; Brave path edits, object transforms, template-cloned object insertions and unreferenced removals reached MISSION/RUN on 2.0.185",
	},
	"binary-1197": {
		"version": 1197,
		"encoding": "binary",
		"header": "version 1197, saveType 0, binarySave true framed records",
		"framing": "tag byte + little-endian u16 length records",
		"boundaries": "path table and object block are located by structural discovery, not fixed offsets",
		"invariants": "declared path count must match discovery, unique object IDs, 8031-byte map trailer",
		"engines": [],
		"adapter": "no verified converter; engine compatibility is experimental",
		"fixtures": ["map_references/vsr_1197/vsrterrace2.bzn", "map_references/vsr_1197/admemvolcvsr.bzn"],
		"capabilities": {READ: "NATIVE", INSPECT_PATHS: "NATIVE", EDIT_PATH_POINTS: "BAKED",
			EDIT_PATH_STRUCTURE: "BAKED", INSPECT_OBJECTS: "UNSUPPORTED", EDIT_OBJECT_TRANSFORM: "UNSUPPORTED",
			EDIT_OBJECT_COUNT: "UNSUPPORTED", ENGINE_PLAYTEST: "UNSUPPORTED", CONVERT_TO_185: "UNSUPPORTED"},
		"evidence": "docs/COMPATIBILITY_MATRIX.md BZN 1197 row; VSR path tables match the independent BZNTools read and a Terrace 2 path rename round-trips byte-preserved",
	},
	"text-1200": {
		"version": 1200,
		"encoding": "text",
		"header": "version 1200, saveType 0, binarySave false text stream",
		"framing": "newline-separated text keys and [GameObject] sections",
		"boundaries": "not decoded by the binary editors",
		"invariants": "none verified",
		"engines": [],
		"adapter": "no verified converter",
		"fixtures": ["map_references/stbolt_1200_text/STBolt.bzn"],
		"capabilities": {READ: "EXPERIMENTAL", INSPECT_PATHS: "UNSUPPORTED", EDIT_PATH_POINTS: "UNSUPPORTED",
			EDIT_PATH_STRUCTURE: "UNSUPPORTED", INSPECT_OBJECTS: "UNSUPPORTED", EDIT_OBJECT_TRANSFORM: "UNSUPPORTED",
			EDIT_OBJECT_COUNT: "UNSUPPORTED", ENGINE_PLAYTEST: "UNSUPPORTED", CONVERT_TO_185: "UNSUPPORTED"},
		"evidence": "docs/COMPATIBILITY_MATRIX.md BZN 1200 row; text paths remain opaque to the binary editor",
	},
}

## Launch policy for the verified 2.0.185 adapter. Direct-native layouts launch
## unchanged; conversion sources must go through the VRV converter. Everything
## else must abort instead of launching an unverified layout.
const DIRECT_PLAYTEST_VERSIONS := [1192]
const CONVERTIBLE_PLAYTEST_SOURCES := [1196]
const HEADER_PREFIX := "version [1] ="
const MAX_HEADER_BYTES := 128


## Classifies raw BZN bytes. Returns a result dictionary:
## { "profile": id or "", "version": int, "encoding": "binary"/"text"/"",
##   "reason": human-readable classification note }. Recognition only asserts
## the header shape; structural acceptance is the codecs' job.
static func recognize(data: PackedByteArray) -> Dictionary:
	var result := {"profile": "", "version": 0, "encoding": "", "reason": ""}
	if data.is_empty():
		result["reason"] = "The BZN is empty."
		return result
	var header := data.slice(0, MAX_HEADER_BYTES).get_string_from_ascii().replace("\r", "")
	if not header.begins_with(HEADER_PREFIX):
		result["reason"] = "The BZN does not start with the version header."
		return result
	var lines := header.split("\n", false)
	# Expected shape: "version [1] =", "<digits>", "saveType [1] =", "0", "binarySave [1] =", "true"/"false".
	if lines.size() < 4 or lines[0] != HEADER_PREFIX or not lines[1].is_valid_int():
		result["reason"] = "The BZN header is malformed."
		return result
	var version := lines[1].strip_edges().to_int()
	var binary := false
	if lines.size() >= 6 and lines[4] == "binarySave [1] =":
		if lines[5] == "true":
			binary = true
		elif lines[5] == "false":
			binary = false
		else:
			result["reason"] = "The binarySave marker is neither true nor false."
			return result
	else:
		result["reason"] = "The save header is missing its binarySave marker."
		return result
	var encoding := "binary" if binary else "text"
	result["version"] = version
	result["encoding"] = encoding
	var id := profile_id_for(version, encoding)
	result["profile"] = id
	if id.is_empty():
		result["reason"] = "Version %d in a %s save has no verified layout profile." % [version, encoding]
	else:
		result["reason"] = "Recognized the verified %s layout." % id
	return result


static func profile_id_for(version: int, encoding: String) -> String:
	for id: String in PROFILES:
		var profile: Dictionary = PROFILES[id]
		if int(profile["version"]) == version and String(profile["encoding"]) == encoding:
			return id
	return ""


static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, {}) as Dictionary


static func capabilities(id: String) -> Dictionary:
	var entry := profile(id)
	if entry.is_empty():
		return {}
	return entry.get("capabilities", {}) as Dictionary


static func capability_status(id: String, capability: String) -> String:
	return String(capabilities(id).get(capability, "UNSUPPORTED"))


## Capability Model: 
## TRUE only when the profile grants the capability in any non-UNSUPPORTED
## status. Write operations must additionally refuse configurations whose
## status is limited, and callers surface the exact status to the user.
static func has_capability(id: String, capability: String) -> bool:
	var status := String(capabilities(id).get(capability, "UNSUPPORTED"))
	return not status.is_empty() and status != "UNSUPPORTED"


## Whether a BZN of this version may be written through the path table codec.
static func supports_path_table(version: int) -> bool:
	return version in path_table_versions()


static func path_table_versions() -> Array[int]:
	var versions: Array[int] = []
	for id: String in PROFILES:
		if has_capability(id, INSPECT_PATHS) and String(PROFILES[id]["encoding"]) == "binary":
			versions.append(int(PROFILES[id]["version"]))
	return versions


## Whether a BZN of this version may be read or written through the object
## table codec. 1197 stays out until its object layout is verified.
static func supports_object_table(version: int) -> bool:
	for id: String in PROFILES:
		if int(PROFILES[id]["version"]) == version and String(PROFILES[id]["encoding"]) == "binary":
			return has_capability(id, INSPECT_OBJECTS)
	return false


## Playtest eligibility for the verified 2.0.185 adapter:
## "native" - launches unchanged through the known-good launcher.
## "convert" - needs the VRV bzn_compat adapter before launch.
## "refuse" - no verified path to the game engine; the launch must abort.
static func playtest_route(version: int, encoding: String) -> String:
	if encoding == "binary" and version in DIRECT_PLAYTEST_VERSIONS:
		return "native"
	if encoding == "binary" and version in CONVERTIBLE_PLAYTEST_SOURCES:
		return "convert"
	return "refuse"


static func human_statuses(id: String) -> String:
	var lines: Array[String] = []
	for capability: String in ALL_CAPABILITIES:
		var status := capability_status(id, capability)
		if status != "UNSUPPORTED":
			lines.append("%s %s" % [capability, status])
	return "; ".join(lines)
