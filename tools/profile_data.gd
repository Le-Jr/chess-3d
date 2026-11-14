extends RefCounted
## Serializes everything in PieceProfiles to JSON, for the Blender script.
##
## pieces/piece_profiles.gd is the single source of truth for the piece
## shapes. tools/blender_export_pieces.py carries a generated copy of the
## same numbers between two marker comments; tools/sync_blender_profiles.gd
## rewrites that block, and a unit test fails if the two ever drift apart.

const BLENDER_SCRIPT := "res://tools/blender_export_pieces.py"
const BEGIN_MARK := "# --- PROFILE DATA BEGIN"
const END_MARK := "# --- PROFILE DATA END"


static func build() -> Dictionary:
	var pieces := {}
	var names := {
		Piece.PAWN: "pawn", Piece.KNIGHT: "knight", Piece.BISHOP: "bishop",
		Piece.ROOK: "rook", Piece.QUEEN: "queen", Piece.KING: "king",
	}
	for type: int in names:
		pieces[names[type]] = {
			"base_radius": _r(PieceProfiles.base_radius(type)),
			"height": _r(PieceProfiles.height(type)),
			"profile": _points(PieceProfiles.body(type)),
			"felt": _points(PieceProfiles.felt(type)),
		}
	return {
		"segments": 32,
		"pieces": pieces,
		"rook_merlons": {
			"count": PieceProfiles.ROOK_MERLON_COUNT,
			"inner": _r(PieceProfiles.ROOK_MERLON_INNER),
			"outer": _r(PieceProfiles.ROOK_MERLON_OUTER),
			"bottom": _r(PieceProfiles.ROOK_MERLON_BOTTOM),
			"top": _r(PieceProfiles.ROOK_MERLON_TOP),
			"fill": _r(PieceProfiles.ROOK_MERLON_FILL),
		},
		"bishop_slit": {
			"angle_deg": _r(PieceProfiles.BISHOP_SLIT_ANGLE_DEG),
			"width": _r(PieceProfiles.BISHOP_SLIT_WIDTH),
			"origin": _vec(PieceProfiles.BISHOP_SLIT_ORIGIN),
		},
		"queen_pearls": {
			"count": PieceProfiles.QUEEN_PEARL_COUNT,
			"radius": _r(PieceProfiles.QUEEN_PEARL_RADIUS),
			"ring_radius": _r(PieceProfiles.QUEEN_PEARL_RING_RADIUS),
			"height": _r(PieceProfiles.QUEEN_PEARL_HEIGHT),
			"top_radius": _r(PieceProfiles.QUEEN_TOP_PEARL_RADIUS),
			"top_height": _r(PieceProfiles.QUEEN_TOP_PEARL_HEIGHT),
		},
		"king_cross": {
			"upright": _vec(PieceProfiles.KING_CROSS_UPRIGHT),
			"upright_y": _r(PieceProfiles.KING_CROSS_UPRIGHT_Y),
			"bar": _vec(PieceProfiles.KING_CROSS_BAR),
			"bar_y": _r(PieceProfiles.KING_CROSS_BAR_Y),
		},
		"knight_head": {
			"outline": _points(PieceProfiles.knight_outline()),
			"depth": _r(PieceProfiles.base_radius(Piece.KNIGHT) * 2.0 * PieceProfiles.KNIGHT_DEPTH_RATIO),
			"bevel": _r(PieceProfiles.KNIGHT_BEVEL),
		},
	}


## The data as JSON, one top-level entry (and one piece property) per line.
static func to_json() -> String:
	return _emit(build(), 0, 3)


## The generated JSON currently embedded in the Blender script ("" if the
## markers are missing).
static func embedded_json() -> String:
	var text := FileAccess.get_file_as_string(BLENDER_SCRIPT)
	var begin := text.find(BEGIN_MARK)
	var end := text.find(END_MARK)
	if begin == -1 or end == -1:
		return ""
	var open := text.find("r'''", begin)
	var close := text.find("'''", open + 4)
	if open == -1 or close == -1 or close > end:
		return ""
	return text.substr(open + 4, close - open - 4).strip_edges()


## Rewrites the generated block in the Blender script. Returns true on success.
static func write_into_blender_script() -> bool:
	var text := FileAccess.get_file_as_string(BLENDER_SCRIPT)
	var begin := text.find(BEGIN_MARK)
	var end := text.find(END_MARK)
	if begin == -1 or end == -1:
		return false
	var open := text.find("r'''", begin)
	var close := text.find("'''", open + 4)
	if open == -1 or close == -1 or close > end:
		return false
	var updated := text.substr(0, open + 4) + "\n" + to_json() + "\n" + text.substr(close)
	var f := FileAccess.open(BLENDER_SCRIPT, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(updated)
	f.close()
	return true


static func _r(v: float) -> float:
	return snappedf(v, 0.0001)


static func _vec(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _points(points: PackedVector2Array) -> Array:
	var out := []
	for p in points:
		out.append([_r(p.x), _r(p.y)])
	return out


# Dictionaries are expanded over several lines down to `expand_depth`;
# everything deeper is written compactly on one line.
static func _emit(value: Variant, depth: int, expand_depth: int) -> String:
	if value is Dictionary and depth < expand_depth:
		var pad := "  ".repeat(depth + 1)
		var lines := PackedStringArray()
		for key: String in value:
			lines.append('%s"%s": %s' % [pad, key, _emit(value[key], depth + 1, expand_depth)])
		return "{\n" + ",\n".join(lines) + "\n" + "  ".repeat(depth) + "}"
	return JSON.stringify(value)
