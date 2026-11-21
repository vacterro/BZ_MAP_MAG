extends RefCounted
## Mission profile definitions, preset path templates, deterministic path
## transforms (translate/rotate/mirror/resample/snap), and advisory mission
## readiness validation on top of native AiPath records.

const Terrain := preload("res://formats/terrain_v5.gd")
const PathCodec := preload("res://formats/bzn_paths.gd")

const PROFILE_ORDER := ["blank", "strategy", "instant", "duel", "vrv_vsr", "custom"]

const PROFILES := {
	"blank": {
		"label": "Blank mission",
		"dll_note": "No fixed script path requirements.",
		"required": [],
		"recommended": ["edge_path"],
		"default_team": 1,
	},
	"strategy": {
		"label": "Strategy (Strategy02)",
		"dll_note": "Verified Strategy02.dll 1v1 Strategy conventions; custom DLLs may differ.",
		"required": ["Player_1", "Enemy_11", "edge_path"],
		"recommended": ["attack1", "11Patrol1", "11MLay1", "hold1", "Stage1", "Capturegoal1"],
		"default_team": 11,
	},
	"instant": {
		"label": "Instant Action (Instant.dll)",
		"dll_note": "Verified Instant.dll skirmish conventions; custom instant scripts may differ.",
		"required": ["Player_1", "Enemy_11", "edge_path"],
		"recommended": ["11Patrol1", "attack1", "hold1"],
		"default_team": 11,
	},
	"duel": {
		"label": "Duel / Multiplayer",
		"dll_note": "Standard DM / Duel multiplayer spawn conventions.",
		"required": ["Player_1", "Player_2", "edge_path"],
		"recommended": [],
		"default_team": 2,
	},
	"vrv_vsr": {
		"label": "VRV / VSR Strategy",
		"dll_note": "VRV/VSR Strategy02.dll conventions; requires VSR mod asset dependencies.",
		"required": ["Player_1", "Enemy_11", "edge_path", "11Patrol1", "attack1", "hold1", "11MLay1"],
		"recommended": ["Stage1", "Capturegoal1"],
		"default_team": 11,
	},
	"custom": {
		"label": "Custom mission",
		"dll_note": "Checks duplicates, bounds, spawns and team consistency without fixed DLL rules.",
		"required": [],
		"recommended": ["Player_1", "edge_path"],
		"default_team": 1,
	},
}

const PRESET_ORDER := [
	"Player_1", "Player_2", "Enemy_11", "edge_path",
	"attack1", "attack2", "attack3",
	"11Patrol1", "11Patrol2",
	"11MLay1", "hold1", "hold2", "Stage1", "Capturegoal1",
]

const PRESETS := {
	"Player_1": {"category": "Spawn", "type": 0, "min_points": 1, "description": "Team 1 Recycler / player spawn (One-Way, 1+ pt)."},
	"Player_2": {"category": "Spawn", "type": 0, "min_points": 1, "description": "Player 2 spawn for Duel / Multiplayer (One-Way, 1+ pt)."},
	"Enemy_11": {"category": "Spawn", "type": 0, "min_points": 1, "description": "Team 11 AI Commander base spawn (One-Way, 1+ pt)."},
	"edge_path": {"category": "Boundary", "type": 2, "min_points": 3, "description": "Playable arena perimeter loop (Loop, 3+ pts)."},
	"attack1": {"category": "Attack", "type": 0, "min_points": 2, "description": "Primary AI attack corridor toward Player_1 (One-Way, 2+ pts)."},
	"attack2": {"category": "Attack", "type": 0, "min_points": 2, "description": "Left flank AI attack corridor (One-Way, 2+ pts)."},
	"attack3": {"category": "Attack", "type": 0, "min_points": 2, "description": "Right flank AI attack corridor (One-Way, 2+ pts)."},
	"11Patrol1": {"category": "Patrol", "type": 2, "min_points": 3, "description": "Team 11 primary scout patrol circuit (Loop, 3+ pts)."},
	"11Patrol2": {"category": "Patrol", "type": 2, "min_points": 3, "description": "Team 11 secondary resource patrol circuit (Loop, 3+ pts)."},
	"11MLay1": {"category": "Minelay", "type": 0, "min_points": 2, "description": "Team 11 minelayer chokepoint route (One-Way, 2+ pts)."},
	"hold1": {"category": "Defense", "type": 0, "min_points": 1, "description": "Team 11 defensive hold point 1 (One-Way, 1+ pt)."},
	"hold2": {"category": "Defense", "type": 0, "min_points": 1, "description": "Team 11 defensive hold point 2 (One-Way, 1+ pt)."},
	"Stage1": {"category": "Staging", "type": 0, "min_points": 1, "description": "AI assault wave rally point (One-Way, 1+ pt)."},
	"Capturegoal1": {"category": "Objective", "type": 0, "min_points": 1, "description": "Strategic capture / scrap priority site (One-Way, 1+ pt)."},
}


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
		"Player_1":
			return PackedVector2Array([p1])
		"Player_2":
			return PackedVector2Array([e11])
		"Enemy_11":
			return PackedVector2Array([e11])
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


static func validate(document: Object, profile_id: String) -> Dictionary:
	var profile: Dictionary = PROFILES.get(profile_id, PROFILES["custom"])
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

	var req_list: Array = profile.get("required", [])
	for req: String in req_list:
		var key := req.to_lower()
		if not by_lower.has(key):
			missing_req.append(req)
			errors.append("Missing required path for %s: %s" % [profile["label"], req])
			continue
		var found: Dictionary = by_lower[key]
		var pts: PackedVector2Array = found["points"]
		var min_pts: int = int(PRESETS.get(req, {}).get("min_points", 1))
		if pts.size() < min_pts:
			errors.append("Path %s needs at least %d points (has %d)." % [req, min_pts, pts.size()])
		if key == "edge_path" and int(found["type"]) != 2:
			errors.append("edge_path should use Loop (type 2) to close the arena boundary.")

	var rec_list: Array = profile.get("recommended", [])
	for rec: String in rec_list:
		if not by_lower.has(rec.to_lower()):
			missing_rec.append(rec)
			warnings.append("Recommended path absent for %s: %s" % [profile["label"], rec])

	# Missing spawn warnings (even in custom/blank if none exist at all)
	if profile_id in ["custom", "blank"] and not by_lower.has("player_1"):
		warnings.append("No Player_1 spawn path present.")

	# Team consistency checks against placed map objects
	var teams := {}
	for view in document.object_count():
		teams[document.object_team(view)] = true
	if teams.has(1) and not by_lower.has("player_1"):
		warnings.append("Team 1 objects exist without a Player_1 spawn path.")
	if teams.has(11) and not by_lower.has("enemy_11"):
		warnings.append("Team 11 objects exist without an Enemy_11 spawn path.")

	return {
		"ok": errors.is_empty(),
		"profile": profile_id,
		"label": String(profile["label"]),
		"dll_note": String(profile["dll_note"]),
		"errors": errors,
		"warnings": warnings,
		"missing_required": missing_req,
		"missing_recommended": missing_rec,
	}
