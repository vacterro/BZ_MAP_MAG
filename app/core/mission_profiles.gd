extends RefCounted
## Mission profile rules database, decoupled from ModProfile.
##
## Rules are keyed by (mission_mode, mod_profile) and backed by verified PE/map
## inspection of Stock BZCC 2.0.185, VSR (Workshop 1325933293), and VRV
## (Workshop 3820486276). Unknown custom DLLs stay explicitly marked UNKNOWN.

const Terrain := preload("res://formats/terrain_v5.gd")
const PathCodec := preload("res://formats/bzn_paths.gd")

const MISSION_MODES := ["blank", "strategy", "instant", "mpi", "duel", "lua", "custom-dll"]
# Legacy alias retained for callers expecting PROFILE_ORDER; maps cleanly via normalize_pair().
const PROFILE_ORDER := ["blank", "strategy", "instant", "mpi", "duel", "lua", "custom-dll"]

const MODE_LABELS := {
	"blank": "Blank / Sandbox",
	"strategy": "Strategy (Strategy02)",
	"instant": "Instant Action (Instant)",
	"mpi": "MPI (mpinstant)",
	"duel": "Duel / Deathmatch",
	"lua": "Lua Mission (LuaMission)",
	"custom-dll": "Custom Mission DLL",
}

## Evidence-backed rules contracts keyed by "<mission>.<mod>".
## Every non-stock or mod-specific path rule is scoped strictly to the mod whose
## DLL was actually inspected — never copied from VRV to Stock.
const RULE_CONTRACTS := {
	"blank.stock": {
		"label": "Stock BZCC · Blank",
		"dll": "",
		"dll_note": "No fixed mission DLL path requirements (Stock BZCC).",
		"evidence": "Stock blank / sandbox maps (verified 1192 native).",
		"semantics": "GENERIC",
		"required": [],
		"recommended": ["edge_path"],
		"default_team": 1,
	},
	"strategy.stock": {
		"label": "Stock BZCC · Strategy (Strategy02.dll)",
		"dll": "Strategy02.dll",
		"dll_note": "Stock Strategy02.dll (27 KB, SHA-256 415ad6ca…): uses map spawn points & Recyclers; real Stock st_dunes.bzn carries only edge_path (no AI patrol paths required).",
		"evidence": "BZ2R/Missions/Strategy02.dll + BZ2R/maps/Missions/Multiplayer/ST/STDunes/st_dunes.bzn.",
		"semantics": "VERIFIED_STATIC",
		"required": ["edge_path"],
		"recommended": [],
		"default_team": 1,
	},
	"instant.stock": {
		"label": "Stock BZCC · Instant Action (Instant.dll)",
		"dll": "Instant.dll",
		"dll_note": "Stock Instant.dll (29 KB, SHA-256 c3dc76d3…): spawns player Recycler at 'Recycler' and CPU base at 'RecyclerEnemy' with gtow2–gtow5 and AIP staging/hold points.",
		"evidence": "BZ2R/Missions/Instant.dll + BZ2R/maps/Missions/Instant/DUNESI/dunesi.bzn.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Recycler", "RecyclerEnemy", "edge_path"],
		"recommended": ["gtow1", "gtow2", "gtow3", "gtow4", "gtow5", "hold1", "hold2", "stage1", "turretEnemy1", "turretEnemy2"],
		"default_team": 1,
	},
	"mpi.stock": {
		"label": "Stock BZCC · MPI (mpinstant.dll)",
		"dll": "mpinstant.dll",
		"dll_note": "Stock mpinstant.dll (34 KB, SHA-256 62f29605…): Multiplayer Instant Action with Recycler/RecyclerEnemy, gtow2–gtow5, turretEnemy1–2 and AIP hold/stage paths.",
		"evidence": "BZ2R/Missions/mpinstant.dll + BZ2R/maps/Missions/Multiplayer/MPI/MPIDunes/mpidunes.bzn.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Recycler", "RecyclerEnemy", "edge_path"],
		"recommended": ["gtow1", "gtow2", "gtow3", "gtow4", "gtow5", "turretEnemy1", "turretEnemy2", "hold1", "stage1"],
		"default_team": 1,
	},
	"duel.stock": {
		"label": "Stock BZCC · Deathmatch / Duel (deathmatch01.dll)",
		"dll": "deathmatch01.dll",
		"dll_note": "Stock deathmatch01.dll (37 KB, SHA-256 20344ce7…): requires edge_path; player spawns may use spawn buoys or Player_1/Player_2 paths depending on map layout.",
		"evidence": "BZ2R/Missions/deathmatch01.dll + BZ2R/maps/Missions/Multiplayer/DM/DMRing/dmring.bzn.",
		"semantics": "VERIFIED_STATIC",
		"required": ["edge_path"],
		"recommended": ["Player_1", "Player_2"],
		"default_team": 1,
	},
	"lua.stock": {
		"label": "Stock BZCC · Lua Mission (LuaMission.dll)",
		"dll": "LuaMission.dll",
		"dll_note": "Stock LuaMission.dll (230 KB, SHA-256 b197f15b…): path requirements are defined entirely by the map's companion .lua script (UNKNOWN statically).",
		"evidence": "BZ2R/Missions/LuaMission.dll + BZ2R/maps/Missions/Instant/PLGR/plgr.bzn (1192, 0 paths).",
		"semantics": "UNKNOWN",
		"required": [],
		"recommended": ["edge_path"],
		"default_team": 1,
	},
	"strategy.vsr": {
		"label": "VSR · Strategy (VSR Strategy02.dll)",
		"dll": "Strategy02.dll",
		"dll_note": "VSR 1325933293 Strategy02.dll (465 KB, SHA-256 a4b3ce22…): supports Player_%d / Enemy_%d spawn paths, edge_path, %dgtow%d and optional AIP attack/stage/hold paths.",
		"evidence": "Workshop 1325933293 VSR/Missions/Strategy02.dll static inspection.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Player_1", "edge_path"],
		"recommended": ["Player_2", "Enemy_11", "attack1", "hold1", "Stage1", "Capturegoal1"],
		"default_team": 11,
	},
	"instant.vsr": {
		"label": "VSR · Instant Action (VSR Instant.dll)",
		"dll": "Instant.dll",
		"dll_note": "VSR 1325933293 Instant.dll (445 KB, SHA-256 c17c7d1c…): uses Recycler / RecyclerEnemy / Player_1 / Enemy_%d, edge_path and gtow2–gtow5.",
		"evidence": "Workshop 1325933293 VSR/Missions/Instant.dll static inspection.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Recycler", "RecyclerEnemy", "edge_path"],
		"recommended": ["Player_1", "Enemy_11", "gtow2", "gtow3", "gtow4", "gtow5", "hold1", "Stage1"],
		"default_team": 11,
	},
	"duel.vsr": {
		"label": "VSR · Duel / Multiplayer",
		"dll": "deathmatch01.dll",
		"dll_note": "VSR 1325933293 deathmatch01.dll (449 KB, SHA-256 b982c416…): edge_path + multiplayer spawns (Player_1/Player_2).",
		"evidence": "Workshop 1325933293 VSR/Missions/deathmatch01.dll.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Player_1", "Player_2", "edge_path"],
		"recommended": [],
		"default_team": 2,
	},
	"strategy.vrv": {
		"label": "VRV · Strategy (VRV Strategy02.dll)",
		"dll": "Strategy02.dll",
		"dll_note": "VRV 3820486276 Strategy02.dll (5.3 MB, SHA-256 3c1c1c94…): Player_1, Enemy_11, edge_path, 11Patrol1..8, 11MLay1..8, attack1, hold1; requires VRV+VSR dependencies.",
		"evidence": "Workshop 3820486276 VRV/Missions/Strategy02.dll + Brave 1196 fixture.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Player_1", "Enemy_11", "edge_path", "11Patrol1", "attack1", "hold1", "11MLay1"],
		"recommended": ["Stage1", "Capturegoal1", "11Patrol2"],
		"default_team": 11,
	},
	"instant.vrv": {
		"label": "VRV · Instant Action (VRV Instant.dll)",
		"dll": "Instant.dll",
		"dll_note": "VRV 3820486276 Instant.dll (5.2 MB): supports Recycler/RecyclerEnemy/Player_1 + VRV patrol/minelay paths.",
		"evidence": "Workshop 3820486276 VRV/Missions/Instant.dll static inspection.",
		"semantics": "VERIFIED_STATIC",
		"required": ["Recycler", "RecyclerEnemy", "edge_path"],
		"recommended": ["Player_1", "11Patrol1", "11MLay1", "attack1", "hold1", "gtow2", "gtow3", "gtow4", "gtow5"],
		"default_team": 11,
	},
	"custom-dll.generic": {
		"label": "Custom Mission DLL",
		"dll": "",
		"dll_note": "Unknown/custom mission DLL: semantics are UNKNOWN. Only generic path geometry, uniqueness and bounds checks apply.",
		"evidence": "No hardcoded requirements for uninspected custom DLLs.",
		"semantics": "UNKNOWN",
		"required": [],
		"recommended": ["edge_path"],
		"default_team": 1,
	},
}

const PRESET_ORDER := [
	"edge_path",
	"Recycler", "RecyclerEnemy",
	"Player_1", "Player_2", "Enemy_11",
	"gtow1", "gtow2", "gtow3", "gtow4", "gtow5",
	"turretEnemy1", "turretEnemy2",
	"attack1", "attack2", "attack3",
	"11Patrol1", "11Patrol2",
	"11MLay1", "hold1", "hold2", "Stage1", "Capturegoal1",
]

const PRESETS := {
	"edge_path": {"category": "Boundary", "type": 2, "min_points": 2, "description": "Playable arena perimeter boundary (2-pt box or Loop polygon)."},
	"Recycler": {"category": "Stock Spawn", "type": 0, "min_points": 1, "description": "Stock Instant/MPI friendly Recycler spawn (One-Way, 1+ pt)."},
	"RecyclerEnemy": {"category": "Stock Spawn", "type": 0, "min_points": 1, "description": "Stock Instant/MPI CPU Recycler spawn (One-Way, 1+ pt)."},
	"Player_1": {"category": "Spawn", "type": 0, "min_points": 1, "description": "Team 1 player spawn (One-Way, 1+ pt)."},
	"Player_2": {"category": "Spawn", "type": 0, "min_points": 1, "description": "Player 2 spawn for Duel / Multiplayer (One-Way, 1+ pt)."},
	"Enemy_11": {"category": "Spawn", "type": 0, "min_points": 1, "description": "Team 11 AI Commander base spawn (VSR/VRV, One-Way, 1+ pt)."},
	"gtow1": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI Gun Tower site 1 (One-Way, 1+ pt)."},
	"gtow2": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI Gun Tower site 2 (One-Way, 1+ pt)."},
	"gtow3": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI Gun Tower site 3 (One-Way, 1+ pt)."},
	"gtow4": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI Gun Tower site 4 (One-Way, 1+ pt)."},
	"gtow5": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI Gun Tower site 5 (One-Way, 1+ pt)."},
	"turretEnemy1": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI CPU turret defense point 1 (One-Way, 1+ pt)."},
	"turretEnemy2": {"category": "Defense", "type": 0, "min_points": 1, "description": "Stock Instant/MPI CPU turret defense point 2 (One-Way, 1+ pt)."},
	"attack1": {"category": "Attack", "type": 0, "min_points": 2, "description": "Primary AI attack corridor (One-Way, 2+ pts)."},
	"attack2": {"category": "Attack", "type": 0, "min_points": 2, "description": "Left flank AI attack corridor (One-Way, 2+ pts)."},
	"attack3": {"category": "Attack", "type": 0, "min_points": 2, "description": "Right flank AI attack corridor (One-Way, 2+ pts)."},
	"11Patrol1": {"category": "Patrol", "type": 2, "min_points": 3, "description": "VRV Team 11 primary scout patrol circuit (Loop, 3+ pts)."},
	"11Patrol2": {"category": "Patrol", "type": 2, "min_points": 3, "description": "VRV Team 11 secondary resource patrol circuit (Loop, 3+ pts)."},
	"11MLay1": {"category": "Minelay", "type": 0, "min_points": 2, "description": "VRV Team 11 minelayer chokepoint route (One-Way, 2+ pts)."},
	"hold1": {"category": "Defense", "type": 0, "min_points": 1, "description": "Defensive hold point 1 (One-Way, 1+ pt)."},
	"hold2": {"category": "Defense", "type": 0, "min_points": 1, "description": "Defensive hold point 2 (One-Way, 1+ pt)."},
	"Stage1": {"category": "Staging", "type": 0, "min_points": 1, "description": "AI assault wave rally point (One-Way, 1+ pt)."},
	"Capturegoal1": {"category": "Objective", "type": 0, "min_points": 1, "description": "Strategic capture / scrap priority site (One-Way, 1+ pt)."},
}


static func normalize_pair(mission_id: String, mod_id: String = "stock") -> Dictionary:
	var m := mission_id.strip_edges().to_lower()
	var mod := mod_id.strip_edges().to_lower()
	if mod.is_empty():
		mod = "stock"
	# Backward-compatibility bridge for legacy combined profile IDs.
	if m == "vrv_vsr":
		m = "strategy"
		mod = "vrv"
	elif m == "custom":
		m = "custom-dll"
	if not (m in MISSION_MODES):
		m = "custom-dll"
	return {"mission": m, "mod": mod}


static func contract_for(mission_id: String, mod_id: String = "stock") -> Dictionary:
	var pair := normalize_pair(mission_id, mod_id)
	var m: String = pair["mission"]
	var mod: String = pair["mod"]
	var key := "%s.%s" % [m, mod]
	if RULE_CONTRACTS.has(key):
		return RULE_CONTRACTS[key]
	if m == "blank":
		var base: Dictionary = RULE_CONTRACTS["blank.stock"].duplicate(true)
		base["label"] = "%s · Blank" % mod.to_upper()
		return base
	if m == "lua":
		var base: Dictionary = RULE_CONTRACTS["lua.stock"].duplicate(true)
		base["label"] = "%s · Lua Mission" % mod.to_upper()
		return base
	if mod.begins_with("custom:") or not (mod in ["stock", "vsr", "vrv"]):
		var generic: Dictionary = RULE_CONTRACTS["custom-dll.generic"].duplicate(true)
		generic["label"] = "%s · %s" % [mod, MODE_LABELS.get(m, m)]
		return generic
	var stock_key := "%s.stock" % m
	if RULE_CONTRACTS.has(stock_key):
		return RULE_CONTRACTS[stock_key]
	return RULE_CONTRACTS["custom-dll.generic"]


static func expected_dll(mission_id: String, mod_id: String = "stock") -> String:
	return String(contract_for(mission_id, mod_id).get("dll", ""))


static func presets_for(mission_id: String, mod_id: String = "stock") -> Array[String]:
	var contract := contract_for(mission_id, mod_id)
	var out: Array[String] = []
	for name_v in contract.get("required", []):
		var n := String(name_v)
		if PRESETS.has(n) and not (n in out):
			out.append(n)
	for name_v in contract.get("recommended", []):
		var n := String(name_v)
		if PRESETS.has(n) and not (n in out):
			out.append(n)
	# Include remaining presets only for the matching mod family so Stock never
	# pushes VRV-only 11Patrol1/11MLay1 paths as primary suggestions.
	var pair := normalize_pair(mission_id, mod_id)
	var mod: String = pair["mod"]
	for n: String in PRESET_ORDER:
		if n in out:
			continue
		if mod == "stock" and (n.begins_with("11") or n == "Enemy_11"):
			continue
		if mod == "vsr" and n.begins_with("11"):
			continue
		out.append(n)
	return out


static func terrain_world_rect(terrain: Terrain) -> Rect2:
	var min_pt := Vector2(terrain.origin) * Terrain.SPACING
	var span := Vector2((terrain.dimensions - Vector2i.ONE).maxi(1)) * Terrain.SPACING
	return Rect2(min_pt, span)


static func clamp_to_terrain(point: Vector2, terrain: Terrain) -> Vector2:
	var rect := terrain_world_rect(terrain)
	return Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))


static func snap_point(point: Vector2, terrain: Terrain) -> Vector2:
	var snapped := Vector2(snappedf(point.x, Terrain.SPACING), snappedf(point.y, Terrain.SPACING))
	return clamp_to_terrain(snapped, terrain)


static func propose_edge_path(terrain: Terrain, margin_m := 64.0) -> PackedVector2Array:
	var rect := terrain_world_rect(terrain)
	var max_margin := minf(rect.size.x, rect.size.y) * 0.25
	var inset := clampf(margin_m, Terrain.SPACING, maxf(Terrain.SPACING, max_margin))
	var lo := rect.position + Vector2(inset, inset)
	var hi := rect.end - Vector2(inset, inset)
	return PackedVector2Array([
		Vector2(lo.x, lo.y),
		Vector2(hi.x, lo.y),
		Vector2(hi.x, hi.y),
		Vector2(lo.x, hi.y),
	])


static func preset_type(preset_name: String) -> int:
	if PRESETS.has(preset_name):
		return int(PRESETS[preset_name]["type"])
	return 0


static func preset_points(preset_name: String, terrain: Terrain, anchor: Vector2) -> PackedVector2Array:
	var rect := terrain_world_rect(terrain)
	var center := rect.position + rect.size * 0.5
	var span := minf(rect.size.x, rect.size.y) * 0.28
	var p1 := clamp_to_terrain(center + Vector2(-span, -span * 0.6), terrain)
	var e11 := clamp_to_terrain(center + Vector2(span, span * 0.6), terrain)
	var use_anchor := clamp_to_terrain(anchor, terrain) if anchor.is_finite() else center
	match preset_name:
		"edge_path":
			return propose_edge_path(terrain)
		"Recycler", "Player_1":
			return PackedVector2Array([p1])
		"RecyclerEnemy", "Player_2", "Enemy_11":
			return PackedVector2Array([e11])
		"gtow1":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.20), terrain)])
		"gtow2":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.25) + Vector2(-48.0, 0.0), terrain)])
		"gtow3":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.25) + Vector2(48.0, 0.0), terrain)])
		"gtow4":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.30) + Vector2(0.0, -48.0), terrain)])
		"gtow5":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.30) + Vector2(0.0, 48.0), terrain)])
		"turretEnemy1":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.38) + Vector2(-32.0, 24.0), terrain)])
		"turretEnemy2":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.38) + Vector2(32.0, -24.0), terrain)])
		"attack1":
			return PackedVector2Array([e11.lerp(p1, 0.2), center, e11.lerp(p1, 0.8)])
		"attack2":
			return PackedVector2Array([e11.lerp(p1, 0.2), center + Vector2(-span * 0.5, span * 0.5), e11.lerp(p1, 0.8)])
		"attack3":
			return PackedVector2Array([e11.lerp(p1, 0.2), center + Vector2(span * 0.5, -span * 0.5), e11.lerp(p1, 0.8)])
		"11Patrol1":
			var r := maxf(48.0, span * 0.35)
			return PackedVector2Array([
				clamp_to_terrain(center + Vector2(-r, -r), terrain),
				clamp_to_terrain(center + Vector2(r, -r), terrain),
				clamp_to_terrain(center + Vector2(r, r), terrain),
				clamp_to_terrain(center + Vector2(-r, r), terrain),
			])
		"11Patrol2":
			var r2 := maxf(48.0, span * 0.3)
			var c2 := clamp_to_terrain(center + Vector2(span * 0.4, -span * 0.4), terrain)
			return PackedVector2Array([
				clamp_to_terrain(c2 + Vector2(-r2, 0.0), terrain),
				clamp_to_terrain(c2 + Vector2(0.0, -r2), terrain),
				clamp_to_terrain(c2 + Vector2(r2, 0.0), terrain),
			])
		"11MLay1":
			return PackedVector2Array([
				clamp_to_terrain(center + Vector2(-span * 0.25, span * 0.25), terrain),
				clamp_to_terrain(center + Vector2(span * 0.25, -span * 0.25), terrain),
			])
		"hold1":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.35), terrain)])
		"hold2":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.35) + Vector2(0.0, -span * 0.4), terrain)])
		"Stage1":
			return PackedVector2Array([clamp_to_terrain(e11.lerp(center, 0.45), terrain)])
		"Capturegoal1":
			return PackedVector2Array([clamp_to_terrain(center, terrain)])
	return PackedVector2Array([use_anchor])


static func centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for pt in points:
		sum += pt
	return sum / float(points.size())


static func transform_points(points: PackedVector2Array, delta: Vector2, rotate_deg: float, pivot: Vector2,
		mirror_x: bool, mirror_z: bool, symmetry_origin: Vector2, snap_grid: bool = false, terrain: Terrain = null) -> PackedVector2Array:
	if points.is_empty() or not delta.is_finite() or not is_finite(rotate_deg) or not pivot.is_finite() or not symmetry_origin.is_finite():
		return PackedVector2Array()
	var rad := deg_to_rad(rotate_deg)
	var c := cos(rad)
	var s := sin(rad)
	var result := PackedVector2Array()
	for pt in points:
		if not pt.is_finite():
			return PackedVector2Array()
		var rel := pt - pivot
		var rotated := pivot + Vector2(rel.x * c - rel.y * s, rel.x * s + rel.y * c) + delta
		if mirror_x:
			rotated.x = 2.0 * symmetry_origin.x - rotated.x
		if mirror_z:
			rotated.y = 2.0 * symmetry_origin.y - rotated.y
		if snap_grid:
			rotated = Vector2(snappedf(rotated.x, Terrain.SPACING), snappedf(rotated.y, Terrain.SPACING))
		if terrain != null:
			rotated = clamp_to_terrain(rotated, terrain)
		if not rotated.is_finite():
			return PackedVector2Array()
		result.append(rotated)
	return result


static func resample_points(points: PackedVector2Array, spacing_m: float, closed: bool, snap_grid: bool = false, terrain: Terrain = null) -> PackedVector2Array:
	if points.size() <= 1 or not is_finite(spacing_m) or spacing_m < Terrain.SPACING:
		return points.duplicate()
	var result := PackedVector2Array()
	var seg_count := points.size() if closed else points.size() - 1
	for i in seg_count:
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		if not a.is_finite() or not b.is_finite():
			return PackedVector2Array()
		var dist := a.distance_to(b)
		var steps := maxi(1, int(round(dist / spacing_m)))
		for s in steps:
			if result.size() >= PathCodec.MAX_POINTS:
				break
			var pt := a.lerp(b, float(s) / float(steps))
			if snap_grid:
				pt = Vector2(snappedf(pt.x, Terrain.SPACING), snappedf(pt.y, Terrain.SPACING))
			if terrain != null:
				pt = clamp_to_terrain(pt, terrain)
			result.append(pt)
	if not closed and result.size() < PathCodec.MAX_POINTS:
		var last := points[points.size() - 1]
		if snap_grid:
			last = Vector2(snappedf(last.x, Terrain.SPACING), snappedf(last.y, Terrain.SPACING))
		if terrain != null:
			last = clamp_to_terrain(last, terrain)
		result.append(last)
	return result


static func validate(document: Object, mission_id: String, mod_id: String = "") -> Dictionary:
	var effective_mod := mod_id if not mod_id.is_empty() else (String(document.mod_profile) if document != null and "mod_profile" in document else "stock")
	var pair := normalize_pair(mission_id, effective_mod)
	var m: String = pair["mission"]
	var mod: String = pair["mod"]
	var contract := contract_for(m, mod)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var missing_req: Array[String] = []
	var missing_rec: Array[String] = []
	var by_lower := {}
	var duplicates := {}
	var terrain: Terrain = document.package.terrain
	var rect := terrain_world_rect(terrain)

	for index: int in document.path_indices():
		var p: Dictionary = document.path_at(index)
		var pname: String = String(p.get("name", ""))
		var key := pname.to_lower()
		if by_lower.has(key):
			duplicates[key] = pname
		else:
			by_lower[key] = p
		var pts: PackedVector2Array = p.get("points", PackedVector2Array())
		for pt in pts:
			if not pt.is_finite():
				errors.append("Path %s contains non-finite coordinates." % pname)
				break
			if not rect.grow(0.5).has_point(pt):
				warnings.append("Path %s has points outside terrain bounds." % pname)
				break

	for dup_key: String in duplicates:
		errors.append("Duplicate path name: %s" % duplicates[dup_key])

	var req_list: Array = contract.get("required", [])
	for req: String in req_list:
		var key := req.to_lower()
		if not by_lower.has(key):
			missing_req.append(req)
			errors.append("Missing required path for %s: %s" % [contract["label"], req])
			continue
		var found: Dictionary = by_lower[key]
		var pts: PackedVector2Array = found["points"]
		var min_pts: int = int(PRESETS.get(req, {}).get("min_points", 1))
		if pts.size() < min_pts:
			errors.append("Path %s needs at least %d points (has %d)." % [req, min_pts, pts.size()])
		if key == "edge_path" and int(found["type"]) != 2:
			warnings.append("edge_path uses type %d instead of Loop (type 2); stock maps also accept One-Way boundaries." % int(found["type"]))

	var rec_list: Array = contract.get("recommended", [])
	for rec: String in rec_list:
		if not by_lower.has(rec.to_lower()):
			missing_rec.append(rec)
			warnings.append("Recommended path absent for %s: %s" % [contract["label"], rec])

	# DLL consistency advisory
	var actual_dll := String(document.package.mission_dll)
	var expected := String(contract.get("dll", ""))
	if not expected.is_empty() and not actual_dll.is_empty() and actual_dll.nocasecmp_to(expected) != 0:
		warnings.append("BZN mission DLL is '%s', while %s expects '%s'." % [actual_dll, contract["label"], expected])

	# Team consistency checks scoped to mods that use Player_1 / Enemy_11 path spawns
	if mod in ["vsr", "vrv"] and m == "strategy":
		var teams := {}
		for view in document.object_count():
			teams[document.object_team(view)] = true
		if teams.has(1) and not by_lower.has("player_1"):
			warnings.append("Team 1 objects exist without a Player_1 spawn path.")
		if teams.has(11) and not by_lower.has("enemy_11"):
			warnings.append("Team 11 objects exist without an Enemy_11 spawn path.")

	return {
		"ok": errors.is_empty(),
		"profile": m,
		"mission": m,
		"mod": mod,
		"label": String(contract["label"]),
		"dll": expected,
		"actual_dll": actual_dll,
		"dll_note": String(contract["dll_note"]),
		"evidence": String(contract.get("evidence", "")),
		"semantics": String(contract.get("semantics", "UNKNOWN")),
		"errors": errors,
		"warnings": warnings,
		"missing_required": missing_req,
		"missing_recommended": missing_rec,
	}
