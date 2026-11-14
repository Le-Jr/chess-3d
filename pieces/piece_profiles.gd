class_name PieceProfiles
extends RefCounted
## The shape data for the procedural chess set - tweak the numbers here.
##
## Every lathe profile is a list of (radius, height) pairs running from the
## bottom of the piece to the top, in board units (one square = 1.0).
## The lathe smooths gentle bends and keeps corners sharper than ~40 degrees
## crisp, so a sharp edge is simply two segments meeting at a steep angle.
##
## tools/blender_export_pieces.py mirrors these numbers; if you change a
## profile here, change it there too (or just export from Blender and load
## the .glb as a PieceSet).

## Height of the felt bevel under every piece.
const FELT_HEIGHT := 0.02


## Radius of the piece's base.
static func base_radius(type: int) -> float:
	match type:
		Piece.PAWN: return 0.27
		Piece.KNIGHT: return 0.31
		Piece.BISHOP: return 0.31
		Piece.ROOK: return 0.31
		Piece.QUEEN: return 0.34
		Piece.KING: return 0.35
	return 0.3


## Total height of the finished piece (used for click picking and animation).
static func height(type: int) -> float:
	match type:
		Piece.PAWN: return 0.74
		Piece.KNIGHT: return 0.97
		Piece.BISHOP: return 1.09
		Piece.ROOK: return 0.82
		Piece.QUEEN: return 1.22
		Piece.KING: return 1.41
	return 1.0


## Lathe profile of the main body for a piece type.
static func body(type: int) -> PackedVector2Array:
	match type:
		Piece.PAWN: return pawn()
		Piece.KNIGHT: return knight_base()
		Piece.BISHOP: return bishop()
		Piece.ROOK: return rook()
		Piece.QUEEN: return queen()
		Piece.KING: return king()
	return PackedVector2Array()


## The felt pad: a flat underside with a small bevel up to the base rim.
static func felt(type: int) -> PackedVector2Array:
	var r := base_radius(type)
	return _pts([
		0.0, 0.0,
		r - FELT_HEIGHT, 0.0,
		r, FELT_HEIGHT,
	])


# ------------------------------------------------------------------- pawn ---

static func pawn() -> PackedVector2Array:
	var p := _pts([
		0.270, 0.020,  # top of the felt
		0.270, 0.065,  # base rim
		0.245, 0.095,
		0.200, 0.115,  # base collar
		0.200, 0.135,
		0.165, 0.160,
		0.125, 0.215,
		0.098, 0.300,  # stem
		0.085, 0.400,
		0.082, 0.440,
		0.150, 0.458,  # neck collar
		0.160, 0.475,
		0.150, 0.492,
		0.085, 0.505,
		0.075, 0.520,
	])
	p.append_array(arc(0.615, 0.125, -50.0, 90.0, 9))  # ball head
	return p


# ------------------------------------------------------------------- rook ---

static func rook() -> PackedVector2Array:
	return _pts([
		0.310, 0.020,
		0.310, 0.070,  # base rim
		0.285, 0.105,
		0.235, 0.125,  # base collar
		0.235, 0.150,
		0.200, 0.180,
		0.185, 0.250,  # tower
		0.175, 0.400,
		0.170, 0.540,
		0.215, 0.575,  # flare under the battlements
		0.245, 0.600,
		0.245, 0.700,  # outer wall, up to the walkway
		0.170, 0.700,  # walkway rim (the merlons stand on this ring)
		0.170, 0.650,  # sunken floor
		0.000, 0.650,
	])


## Battlements: blocks standing on the rook's rim.
const ROOK_MERLON_COUNT := 6
const ROOK_MERLON_INNER := 0.170
const ROOK_MERLON_OUTER := 0.245
const ROOK_MERLON_BOTTOM := 0.700
const ROOK_MERLON_TOP := 0.820
## Fraction of each 60-degree slot filled by the merlon (the rest is the gap).
const ROOK_MERLON_FILL := 0.62


# ----------------------------------------------------------------- bishop ---

static func bishop() -> PackedVector2Array:
	var p := _pts([
		0.310, 0.020,
		0.310, 0.070,  # base rim
		0.285, 0.105,
		0.235, 0.125,  # base collar
		0.235, 0.150,
		0.195, 0.180,
		0.140, 0.260,  # stem
		0.105, 0.400,
		0.088, 0.560,
		0.085, 0.610,
		0.165, 0.628,  # neck collar
		0.175, 0.645,
		0.165, 0.662,
		0.090, 0.675,
		0.082, 0.700,  # BISHOP_HEAD_START: everything above is the mitre
		0.115, 0.735,
		0.145, 0.790,
		0.150, 0.830,
		0.135, 0.890,
		0.100, 0.950,
		0.060, 0.990,
		0.030, 1.005,
	])
	p.append_array(arc(1.045, 0.042, -60.0, 90.0, 6))  # finial
	return p


## Height where the bishop's head (mitre) begins.
const BISHOP_HEAD_START := 0.700
## The mitre slit: a slab cut into the head, running up and toward the front
## (+Z) at this angle from the horizontal.
const BISHOP_SLIT_ANGLE_DEG := 50.0
const BISHOP_SLIT_WIDTH := 0.032
## A point on the slit's center plane where the cut starts (x, y, z).
const BISHOP_SLIT_ORIGIN := Vector3(0.0, 0.870, 0.020)
## How far below the surface the dark bottom of the slit sits (as a radius scale).
const BISHOP_SLIT_CORE_SCALE := 0.80


# ------------------------------------------------------------------ queen ---

static func queen() -> PackedVector2Array:
	return _pts([
		0.340, 0.020,
		0.340, 0.075,  # base rim
		0.315, 0.110,
		0.260, 0.130,  # base collar
		0.260, 0.158,
		0.215, 0.190,
		0.155, 0.280,  # stem
		0.118, 0.450,
		0.098, 0.650,
		0.092, 0.770,
		0.180, 0.790,  # neck collar
		0.192, 0.808,
		0.180, 0.826,
		0.100, 0.840,
		0.090, 0.870,
		0.105, 0.920,  # crown flare
		0.140, 0.990,
		0.200, 1.060,
		0.200, 1.075,  # crown rim
		0.160, 1.075,
		0.110, 1.100,  # dome inside the crown
		0.050, 1.118,
		0.000, 1.122,
	])


## The ring of pearls on the queen's crown, and the big one on top.
const QUEEN_PEARL_COUNT := 8
const QUEEN_PEARL_RADIUS := 0.036
const QUEEN_PEARL_RING_RADIUS := 0.180
const QUEEN_PEARL_HEIGHT := 1.095
const QUEEN_TOP_PEARL_RADIUS := 0.052
const QUEEN_TOP_PEARL_HEIGHT := 1.165


# ------------------------------------------------------------------- king ---

static func king() -> PackedVector2Array:
	return _pts([
		0.350, 0.020,
		0.350, 0.075,  # base rim
		0.325, 0.110,
		0.268, 0.130,  # base collar
		0.268, 0.158,
		0.222, 0.190,
		0.160, 0.285,  # stem
		0.122, 0.460,
		0.102, 0.680,
		0.097, 0.810,
		0.188, 0.830,  # neck collar
		0.200, 0.848,
		0.188, 0.866,
		0.105, 0.880,
		0.095, 0.910,
		0.110, 0.960,  # crown flare
		0.150, 1.040,
		0.195, 1.100,
		0.195, 1.118,  # crown rim
		0.150, 1.125,
		0.090, 1.150,  # dome
		0.045, 1.160,
		0.000, 1.162,
	])


## The king's cross: two bars (width, height, depth) and their center heights.
const KING_CROSS_UPRIGHT := Vector3(0.055, 0.260, 0.050)
const KING_CROSS_UPRIGHT_Y := 1.280
const KING_CROSS_BAR := Vector3(0.170, 0.055, 0.050)
const KING_CROSS_BAR_Y := 1.310


# ----------------------------------------------------------------- knight ---

## The knight's round pedestal; the horse head is mounted on top of it.
static func knight_base() -> PackedVector2Array:
	return _pts([
		0.310, 0.020,
		0.310, 0.070,  # base rim
		0.285, 0.105,
		0.235, 0.125,  # base collar
		0.235, 0.150,
		0.245, 0.195,  # pedestal
		0.230, 0.220,
		0.000, 0.220,
	])


## Horse-head silhouette as (x, y) points: x is left/right, y is up. The horse
## faces -X (to the left for the player who owns it), like a diagram knight.
static func knight_outline() -> PackedVector2Array:
	return _pts([
		 0.190, 0.200,  # back of the neck, at the pedestal
		 0.215, 0.360,
		 0.205, 0.520,  # mane
		 0.165, 0.680,
		 0.095, 0.820,
		 0.035, 0.900,  # behind the ear
		 0.030, 0.970,  # ear tip
		-0.035, 0.905,  # front of the ear
		-0.100, 0.860,  # forehead
		-0.190, 0.760,
		-0.265, 0.645,  # bridge of the nose
		-0.300, 0.570,  # nose tip
		-0.280, 0.510,  # mouth
		-0.220, 0.498,  # chin
		-0.140, 0.535,  # jaw
		-0.080, 0.555,  # throat
		-0.105, 0.440,  # front of the neck
		-0.160, 0.320,  # chest
		-0.190, 0.200,  # front of the neck, at the pedestal
	])


## Thickness of the knight's head as a fraction of the base diameter.
const KNIGHT_DEPTH_RATIO := 0.35
const KNIGHT_BEVEL := 0.028


# ---------------------------------------------------------------- helpers ---

## Points along a circle centered on the axis at `center_y`: angles run from
## -90 (bottom) through 0 (widest) to 90 (top). Handy for balls and finials.
static func arc(center_y: float, radius: float, from_deg: float, to_deg: float,
		steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		var t := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		out.append(Vector2(maxf(0.0, cos(t) * radius), center_y + sin(t) * radius))
	# Land exactly on the axis when the arc ends at the pole.
	if is_equal_approx(to_deg, 90.0):
		out[out.size() - 1] = Vector2(0.0, out[out.size() - 1].y)
	return out


static func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out
