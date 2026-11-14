class_name ProceduralPieceFactory
extends RefCounted
## Builds the default chess set as ArrayMeshes, from the data in PieceProfiles.
##
## Every mesh sits on y = 0 centered on the Y axis, with its "front" toward +Z
## (the side its owner sees). Surfaces are named so PieceSet can assign
## materials:
##   "body"   - the piece itself (white / black material)
##   "felt"   - the pad underneath
##   "accent" - dark detail (the bottom of the bishop's slit)

const DEFAULT_SEGMENTS := 28

const SURFACE_BODY := "body"
const SURFACE_FELT := "felt"
const SURFACE_ACCENT := "accent"

static var _cache := {}


## Mesh for a piece type (Piece.PAWN .. Piece.KING). Meshes are cached and
## shared, so treat them as read-only.
static func build_mesh(type: int, segments: int = DEFAULT_SEGMENTS) -> ArrayMesh:
	var key := type * 1000 + segments
	if _cache.has(key):
		return _cache[key]

	var body := MeshBuilder.new()
	var felt := MeshBuilder.new()
	var accent := MeshBuilder.new()

	felt.add_lathe(PieceProfiles.felt(type), segments)
	match type:
		Piece.ROOK:
			_build_rook(body, segments)
		Piece.BISHOP:
			_build_bishop(body, accent, segments)
		Piece.QUEEN:
			_build_queen(body, segments)
		Piece.KING:
			_build_king(body, segments)
		Piece.KNIGHT:
			_build_knight(body, segments)
		_:
			body.add_lathe(PieceProfiles.body(type), segments)

	var mesh := ArrayMesh.new()
	mesh.resource_name = "Procedural" + ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"][type]
	body.commit(mesh, SURFACE_BODY)
	felt.commit(mesh, SURFACE_FELT)
	accent.commit(mesh, SURFACE_ACCENT)
	_cache[key] = mesh
	return mesh


static func clear_cache() -> void:
	_cache.clear()


# Rook: lathe tower plus crenellations as extra geometry on the rim.
static func _build_rook(body: MeshBuilder, segments: int) -> void:
	body.add_lathe(PieceProfiles.rook(), segments)
	var count := PieceProfiles.ROOK_MERLON_COUNT
	var slot := TAU / count
	var width := slot * PieceProfiles.ROOK_MERLON_FILL
	for i in count:
		var mid := slot * (i + 0.5)
		body.add_arc_block(
			PieceProfiles.ROOK_MERLON_INNER, PieceProfiles.ROOK_MERLON_OUTER,
			PieceProfiles.ROOK_MERLON_BOTTOM, PieceProfiles.ROOK_MERLON_TOP,
			mid - width * 0.5, mid + width * 0.5, 3)


# Bishop: the head is cut open along a slanted slab (a real cut in the
# geometry), with a slightly smaller dark copy of the head showing through.
static func _build_bishop(body: MeshBuilder, accent: MeshBuilder, segments: int) -> void:
	body.add_lathe(PieceProfiles.bishop(), segments)

	var angle := deg_to_rad(PieceProfiles.BISHOP_SLIT_ANGLE_DEG)
	var along := Vector3(0.0, sin(angle), cos(angle))    # direction the slit runs (up, toward the front)
	var across := Vector3(0.0, cos(angle), -sin(angle))  # normal of the slit's slab
	var origin := PieceProfiles.BISHOP_SLIT_ORIGIN
	var half_w := PieceProfiles.BISHOP_SLIT_WIDTH * 0.5
	var planes: Array[Plane] = [
		Plane(across, across.dot(origin) + half_w),
		Plane(-across, -across.dot(origin) + half_w),
		Plane(-along, -along.dot(origin)),
	]
	body.cut_convex(planes)

	var core := PackedVector2Array()
	for p in PieceProfiles.bishop():
		if p.y >= PieceProfiles.BISHOP_HEAD_START:
			core.append(Vector2(p.x * PieceProfiles.BISHOP_SLIT_CORE_SCALE, p.y))
	accent.add_lathe(core, segments)


# Queen: a ring of pearls on the crown rim and a larger one on top.
static func _build_queen(body: MeshBuilder, segments: int) -> void:
	body.add_lathe(PieceProfiles.queen(), segments)
	var count := PieceProfiles.QUEEN_PEARL_COUNT
	for i in count:
		var a := TAU * i / count
		body.add_ball(
			Vector3(cos(a) * PieceProfiles.QUEEN_PEARL_RING_RADIUS, PieceProfiles.QUEEN_PEARL_HEIGHT,
					sin(a) * PieceProfiles.QUEEN_PEARL_RING_RADIUS),
			PieceProfiles.QUEEN_PEARL_RADIUS, 10, 5)
	body.add_ball(Vector3(0.0, PieceProfiles.QUEEN_TOP_PEARL_HEIGHT, 0.0),
			PieceProfiles.QUEEN_TOP_PEARL_RADIUS, 12, 6)


# King: a cross on top, facing the front.
static func _build_king(body: MeshBuilder, segments: int) -> void:
	body.add_lathe(PieceProfiles.king(), segments)
	body.add_box(Vector3(0.0, PieceProfiles.KING_CROSS_UPRIGHT_Y, 0.0), PieceProfiles.KING_CROSS_UPRIGHT)
	body.add_box(Vector3(0.0, PieceProfiles.KING_CROSS_BAR_Y, 0.0), PieceProfiles.KING_CROSS_BAR)


# Knight: extruded, beveled horse-head silhouette on a lathe pedestal.
static func _build_knight(body: MeshBuilder, segments: int) -> void:
	body.add_lathe(PieceProfiles.knight_base(), segments)
	var depth := PieceProfiles.base_radius(Piece.KNIGHT) * 2.0 * PieceProfiles.KNIGHT_DEPTH_RATIO
	body.add_beveled_extrusion(PieceProfiles.knight_outline(), depth, PieceProfiles.KNIGHT_BEVEL)
