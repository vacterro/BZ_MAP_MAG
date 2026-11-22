extends RefCounted
## Native BZCC binary .SKY (SKY_ / 1YKS / EMOD / ...) decoder & safe surgical
## 1YKS writer, plus .TRN environment inspector.
##
## Format verified directly against BZCC 2.0.185 plgr.SKY (7068 B),
## braveliltoaster.SKY (7068 B), and duel_map_27_autosave_01.SKY (7068 B):
##   - Root chunk: "_YKS" (4-byte u32 version = 65536 / 0x00010000)
##   - Followed by sequential little-endian (4-byte FourCC, u32 payload_size) chunks:
##     "1YKS" (212 B), "EMOD" (1808 B), "NIAR" (116 B), "TLPS" (360 B), " GOF" (488 B),
##     "RRIM" (8 B), "RATS" (64 B), "TRPS" (3596 B), "RTAW" (36 B), "TLOB" (224 B),
##     "_VNE" (32 B), "CVNE" (16 B).
##   - Writing modifies ONLY verified fixed-offset float fields inside "1YKS"
##     without shifting any byte offset or altering any other chunk.

const SKY_MAGIC := "_YKS"
const SKY_VERSION := 65536
const CHUNK_SKY1 := "1YKS"
const SKY1_SIZE := 212
const MAX_SKY_BYTES := 2 * 1024 * 1024

const CHUNK_LABELS := {
	"_YKS": "SKY_ Header",
	"1YKS": "SKY1 Core Lighting & Fog",
	"EMOD": "DOME Sky Dome Mesh",
	"NIAR": "RAIN Precipitation",
	"TLPS": "SPLT Rain Splat",
	" GOF": "FOG  Multi-Layer Fog",
	"RRIM": "MIRR Reflection/Mirror",
	"RATS": "STAR Starfield",
	"TRPS": "SPRT Sky Sprites",
	"RTAW": "WATR Water Environment",
	"TLOB": "BOLT Lightning Bolts",
	"_VNE": "ENV_ Environment Params",
	"CVNE": "ENVC Environment Color",
}

const WRITABLE_KEYS := [
	"fogColor", "fogStart", "fogEnd", "visibilityRange",
	"sunPeriod", "sunAngle", "sunColor", "ambientColor",
]


static func _read_cstr(data: PackedByteArray, offset: int, max_len: int) -> String:
	if offset < 0 or offset + max_len > data.size():
		return ""
	var slice := data.slice(offset, offset + max_len)
	var nul := slice.find(0)
	if nul >= 0:
		slice = slice.slice(0, nul)
	var out := ""
	for b in slice:
		if b >= 32 and b <= 126:
			out += char(b)
		else:
			break
	return out.strip_edges()


static func decode_sky(data: PackedByteArray) -> Dictionary:
	var out := {
		"ok": false,
		"error": "",
		"version": 0,
		"sizeBytes": data.size(),
		"sky1Offset": -1,
		"chunks": [] as Array[Dictionary],
		"fields": {},
		"readOnly": {},
	}
	if data.size() < 12 or data.size() > MAX_SKY_BYTES:
		out["error"] = "SKY file size out of bounded range (%d bytes)." % data.size()
		return out
	var magic := data.slice(0, 4).get_string_from_ascii()
	if magic != SKY_MAGIC:
		out["error"] = "Invalid SKY magic '%s' (expected '_YKS')." % magic
		return out
	var hdr_sz := data.decode_u32(4)
	if hdr_sz != 4:
		out["error"] = "Unexpected SKY header payload size %d." % hdr_sz
		return out
	var ver := data.decode_u32(8)
	out["version"] = ver
	if ver != SKY_VERSION:
		out["error"] = "Unsupported SKY version %d (expected %d)." % [ver, SKY_VERSION]
		return out

	var chunks: Array[Dictionary] = [{"tag": SKY_MAGIC, "label": String(CHUNK_LABELS[SKY_MAGIC]), "offset": 0, "size": 4}]
	var off := 12
	var sky1_body := -1
	var dome_mesh := ""
	var chunk_count := 0
	while off + 8 <= data.size() and chunk_count < 64:
		var tag := data.slice(off, off + 4).get_string_from_ascii()
		var sz := data.decode_u32(off + 4)
		var body_off := off + 8
		if body_off + sz > data.size():
			out["error"] = "SKY chunk '%s' at %d exceeds file size (%d > %d)." % [tag, off, body_off + sz, data.size()]
			return out
		chunks.append({
			"tag": tag,
			"label": String(CHUNK_LABELS.get(tag, tag)),
			"offset": off,
			"size": sz,
		})
		if tag == CHUNK_SKY1 and sz == SKY1_SIZE and sky1_body < 0:
			sky1_body = body_off
		elif tag == "EMOD" and sz >= 64 and dome_mesh.is_empty():
			dome_mesh = _read_cstr(data, body_off + 16, 48)
		off = body_off + sz
		chunk_count += 1

	if off != data.size():
		out["error"] = "SKY file contains trailing unparsed bytes (%d of %d)." % [data.size() - off, data.size()]
		return out
	if sky1_body < 0:
		out["error"] = "SKY file is missing the verified 212-byte 1YKS chunk."
		return out

	var fog_col := [
		data.decode_float(sky1_body + 0),
		data.decode_float(sky1_body + 4),
		data.decode_float(sky1_body + 8),
		data.decode_float(sky1_body + 12),
	]
	var fog_start := data.decode_float(sky1_body + 16)
	var fog_end := data.decode_float(sky1_body + 20)
	var vis_range := data.decode_float(sky1_body + 24)
	var sun_period := data.decode_float(sky1_body + 28)
	var sun_angle := data.decode_float(sky1_body + 32)
	var sun_dir_rad := data.decode_float(sky1_body + 36)
	var sun_col := [
		data.decode_float(sky1_body + 44),
		data.decode_float(sky1_body + 48),
		data.decode_float(sky1_body + 52),
		data.decode_float(sky1_body + 56),
	]
	var amb_col := [
		data.decode_float(sky1_body + 60),
		data.decode_float(sky1_body + 64),
		data.decode_float(sky1_body + 68),
		data.decode_float(sky1_body + 72),
	]
	var sky_height := data.decode_float(sky1_body + 80)
	var sky_tex := _read_cstr(data, sky1_body + 84, 32)
	var sky_col_u32 := data.decode_u32(sky1_body + 116)
	var sun_tex := _read_cstr(data, sky1_body + 124, 32)

	for val: float in [fog_start, fog_end, vis_range, sun_period, sun_angle, sun_dir_rad, sky_height]:
		if not is_finite(val):
			out["error"] = "SKY 1YKS chunk contains non-finite float values."
			return out
	for arr: Array in [fog_col, sun_col, amb_col]:
		for c_v in arr:
			if not is_finite(float(c_v)):
				out["error"] = "SKY 1YKS color contains non-finite values."
				return out

	out["ok"] = true
	out["sky1Offset"] = sky1_body
	out["chunks"] = chunks
	out["fields"] = {
		"fogColor": fog_col,
		"fogStart": fog_start,
		"fogEnd": fog_end,
		"visibilityRange": vis_range,
		"sunPeriod": sun_period,
		"sunAngle": sun_angle,
		"sunColor": sun_col,
		"ambientColor": amb_col,
	}
	out["readOnly"] = {
		"sunDirectionRad": sun_dir_rad,
		"skyHeight": sky_height,
		"skyTexture": sky_tex,
		"skyColorHex": "0x%08x" % sky_col_u32,
		"sunTexture": sun_tex,
		"domeMesh": dome_mesh,
		"chunkCount": chunks.size(),
	}
	return out


static func valid_color_array(val: Variant) -> bool:
	if not (val is Array):
		return false
	var arr: Array = val
	if arr.size() != 4:
		return false
	for item in arr:
		if not (item is float or item is int):
			return false
		var f := float(item)
		if not is_finite(f) or f < 0.0 or f > 1.0:
			return false
	return true


static func validate_edits(edits: Variant) -> String:
	if not (edits is Dictionary):
		return "Environment edits must be a dictionary."
	var d: Dictionary = edits
	for k_v in d:
		var k := String(k_v)
		if not (k in WRITABLE_KEYS):
			return "Unsupported or read-only environment property '%s'." % k
		var v: Variant = d[k]
		match k:
			"fogColor", "sunColor", "ambientColor":
				if not valid_color_array(v):
					return "Color property '%s' must be an RGBA array of 4 floats in [0, 1]." % k
			"fogStart", "fogEnd":
				if not (v is float or v is int) or not is_finite(float(v)) or float(v) < 0.0 or float(v) > 20000.0:
					return "'%s' must be a finite distance in [0, 20000] m." % k
			"visibilityRange":
				if not (v is float or v is int) or not is_finite(float(v)) or float(v) < 10.0 or float(v) > 30000.0:
					return "'visibilityRange' must be a finite distance in [10, 30000] m."
			"sunPeriod":
				if not (v is float or v is int) or not is_finite(float(v)) or float(v) < 0.1 or float(v) > 1000.0:
					return "'sunPeriod' must be a finite value in [0.1, 1000]."
			"sunAngle":
				if not (v is float or v is int) or not is_finite(float(v)) or float(v) < 0.0 or float(v) > 24.0:
					return "'sunAngle' must be a finite value in [0, 24]."
	return ""


## Encodes validated 1YKS edits into a copy of source_bytes without modifying
## any byte outside the exact verified float slots of 1YKS.
static func encode_sky(source_bytes: PackedByteArray, edits: Dictionary) -> PackedByteArray:
	if not validate_edits(edits).is_empty():
		return PackedByteArray()
	var decoded := decode_sky(source_bytes)
	if not bool(decoded["ok"]):
		return PackedByteArray()
	var sky1_off := int(decoded["sky1Offset"])
	var out := source_bytes.duplicate()
	if edits.has("fogColor"):
		var fc: Array = edits["fogColor"]
		for i in 4:
			out.encode_float(sky1_off + i * 4, clampf(float(fc[i]), 0.0, 1.0))
	if edits.has("fogStart"):
		out.encode_float(sky1_off + 16, float(edits["fogStart"]))
	if edits.has("fogEnd"):
		out.encode_float(sky1_off + 20, float(edits["fogEnd"]))
	if edits.has("visibilityRange"):
		out.encode_float(sky1_off + 24, float(edits["visibilityRange"]))
	if edits.has("sunPeriod"):
		out.encode_float(sky1_off + 28, float(edits["sunPeriod"]))
	if edits.has("sunAngle"):
		out.encode_float(sky1_off + 32, float(edits["sunAngle"]))
	if edits.has("sunColor"):
		var sc: Array = edits["sunColor"]
		for i in 4:
			out.encode_float(sky1_off + 44 + i * 4, clampf(float(sc[i]), 0.0, 1.0))
	if edits.has("ambientColor"):
		var ac: Array = edits["ambientColor"]
		for i in 4:
			out.encode_float(sky1_off + 60 + i * 4, clampf(float(ac[i]), 0.0, 1.0))
	var verify := decode_sky(out)
	if not bool(verify["ok"]) or out.size() != source_bytes.size():
		return PackedByteArray()
	return out


static func inspect_trn_environment(trn_meta: Dictionary) -> Dictionary:
	var nv: Dictionary = trn_meta.get("normalview", {})
	var lt: Dictionary = trn_meta.get("light", {})
	var sk: Dictionary = trn_meta.get("sky", {})
	var wd: Dictionary = trn_meta.get("world", {})
	return {
		"normalView": nv.duplicate(),
		"light": lt.duplicate(),
		"sky": sk.duplicate(),
		"world": wd.duplicate(),
	}
