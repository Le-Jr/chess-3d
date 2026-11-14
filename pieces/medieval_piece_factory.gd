class_name MedievalPieceFactory
extends RefCounted
## The "Medieval" built-in set: sculpted figures on carved pedestals - a king
## leaning on his sword, a crowned queen, a bishop with mitre and crosier, a
## horse bust, a brick tower and a foot soldier with spear and shield.
##
## Everything is built from MeshBuilder primitives (lathes, ellipsoids, cones,
## lofts), so there are no model files to ship. Meshes follow the same rules
## as ProceduralPieceFactory: standing on y = 0, centered on the Y axis, with
## the "body" / "felt" / "accent" surfaces. The figures are modelled facing
## +Z and then turned around, so on the board they look at the enemy.

const SEGMENTS := 28

static var _cache := {}


## Mesh for a piece type (Piece.PAWN .. Piece.KING). Cached; treat as read-only.
static func build_mesh(type: int) -> ArrayMesh:
	if _cache.has(type):
		return _cache[type]
	var body := MeshBuilder.new()
	var accent := MeshBuilder.new()
	var felt := MeshBuilder.new()
	felt.add_lathe(PieceProfiles.felt(type), SEGMENTS)

	match type:
		Piece.PAWN: _build_pawn(body, accent)
		Piece.KNIGHT: _build_knight(body, accent)
		Piece.BISHOP: _build_bishop(body, accent)
		Piece.ROOK: _build_rook(body, accent)
		Piece.QUEEN: _build_queen(body, accent)
		Piece.KING: _build_king(body, accent)

	# Face the enemy: the owner sits on the +Z side.
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	body.transform(turn)
	accent.transform(turn)

	var mesh := ArrayMesh.new()
	mesh.resource_name = "Medieval" + ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"][type]
	body.commit(mesh, ProceduralPieceFactory.SURFACE_BODY)
	felt.commit(mesh, ProceduralPieceFactory.SURFACE_FELT)
	accent.commit(mesh, ProceduralPieceFactory.SURFACE_ACCENT)
	_cache[type] = mesh
	return mesh


static func clear_cache() -> void:
	_cache.clear()


# --------------------------------------------------------------- pedestal ---

# Carved round pedestal: a plinth, a bulging drum ringed with gadroons, and a
# beaded collar. `r` is the base radius, `top` the height of its flat top.
static func _add_pedestal(body: MeshBuilder, r: float, top: float, gadroons: int = 12) -> void:
	var h := top - 0.02
	body.add_lathe(_pts([
		r, 0.02,
		r, 0.02 + h * 0.16,
		r * 0.95, 0.02 + h * 0.24,
		r * 0.80, 0.02 + h * 0.30,   # scotia
		r * 0.76, 0.02 + h * 0.36,
		r * 0.80, 0.02 + h * 0.46,   # drum
		r * 0.82, 0.02 + h * 0.58,
		r * 0.78, 0.02 + h * 0.70,
		r * 0.72, 0.02 + h * 0.76,
		r * 0.80, 0.02 + h * 0.82,   # collar
		r * 0.82, 0.02 + h * 0.90,
		r * 0.76, 0.02 + h * 0.97,
		r * 0.66, top,
		0.0, top,
	]), SEGMENTS)
	for i in gadroons:
		var a := TAU * (i + 0.5) / gadroons
		var dir := Vector3(cos(a), 0.0, sin(a))
		body.add_ellipsoid(dir * (r * 0.80) + Vector3.UP * (0.02 + h * 0.54),
				Vector3(r * 0.105, h * 0.17, r * 0.15), 8, 4, Basis(Vector3.UP, -a + PI / 2.0))
	# Small studs on the plinth, between the gadroons.
	for i in gadroons:
		var a := TAU * float(i) / gadroons
		body.add_ball(Vector3(cos(a) * r * 0.985, 0.02 + h * 0.09, sin(a) * r * 0.985), r * 0.045, 6, 3)


# ---------------------------------------------------------- figure pieces ---

# Head with nose, dark eyes and brow ridge, looking toward +Z.
static func _add_head(body: MeshBuilder, accent: MeshBuilder, center: Vector3, size: float) -> void:
	body.add_ellipsoid(center, Vector3(0.84, 1.0, 0.90) * size, 16, 8)
	# Jaw.
	body.add_ellipsoid(center + Vector3(0.0, -0.42, 0.18) * size, Vector3(0.60, 0.55, 0.62) * size, 12, 6)
	# Nose and brow.
	body.add_ellipsoid(center + Vector3(0.0, -0.02, 0.88) * size, Vector3(0.17, 0.30, 0.22) * size, 8, 4)
	body.add_ellipsoid(center + Vector3(0.0, 0.26, 0.76) * size, Vector3(0.62, 0.11, 0.20) * size, 10, 4)
	for side: float in [-1.0, 1.0]:
		accent.add_ellipsoid(center + Vector3(0.34 * side, 0.13, 0.775) * size,
				Vector3(0.14, 0.085, 0.08) * size, 8, 4)
		# Ears.
		body.add_ellipsoid(center + Vector3(0.82 * side, -0.02, 0.0) * size, Vector3(0.10, 0.22, 0.14) * size, 6, 4)


# Arm as a two-segment tube with a hand on the end.
static func _add_arm(body: MeshBuilder, shoulder: Vector3, elbow: Vector3, hand: Vector3,
		thickness: float) -> void:
	body.add_loft(
		PackedVector3Array([shoulder, shoulder.lerp(elbow, 0.55), elbow, elbow.lerp(hand, 0.5), hand]),
		PackedVector2Array([
			Vector2(thickness, thickness) * 1.15, Vector2(thickness, thickness) * 1.05,
			Vector2(thickness, thickness), Vector2(thickness, thickness) * 0.88,
			Vector2(thickness, thickness) * 0.78]),
		10, Vector3(0.0, 0.3, 1.0).normalized())
	body.add_ball(shoulder, thickness * 1.25, 10, 5)
	body.add_ball(hand, thickness * 0.95, 10, 5)


# Crown: flared band, `points` spikes tipped with pearls.
static func _add_crown(body: MeshBuilder, y: float, r: float, height: float, points: int) -> void:
	body.add_lathe(_pts([
		r * 0.92, y,
		r * 1.02, y + height * 0.06,
		r * 1.04, y + height * 0.22,
		r * 0.98, y + height * 0.26,
		r * 1.12, y + height * 0.52,
		r * 0.96, y + height * 0.52,
		r * 0.86, y + height * 0.30,
		r * 0.55, y + height * 0.50,   # cap inside the crown
		0.0, y + height * 0.58,
	]), 20)
	for i in points:
		var a := TAU * float(i) / points + PI / 2.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var foot := dir * (r * 1.04) + Vector3.UP * (y + height * 0.50)
		var tip := dir * (r * 1.16) + Vector3.UP * (y + height * 0.94)
		body.add_cone(foot, tip, r * 0.20, r * 0.05, 6)
		body.add_ball(tip, r * 0.13, 8, 4)
		# Jewel on the band under each point.
		body.add_ball(dir * (r * 1.05) + Vector3.UP * (y + height * 0.14), r * 0.09, 6, 3)


static func _build_king(body: MeshBuilder, accent: MeshBuilder) -> void:
	_add_pedestal(body, 0.35, 0.30)
	# Robe.
	body.add_squashed_lathe(_smooth([
		0.235, 0.29,
		0.230, 0.36,
		0.205, 0.50,
		0.195, 0.62,
		0.215, 0.74,
		0.232, 0.82,   # shoulders
		0.205, 0.875,
		0.130, 0.915,
		0.078, 0.945,  # neck
		0.072, 0.990,
	]), SEGMENTS, 0.76)
	# Fur mantle over the shoulders, and its hem down the back.
	body.add_torus(0.872, 0.186, 0.044, SEGMENTS, 8, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.80)), Vector3.ZERO))
	body.add_ellipsoid(Vector3(0.0, 0.60, -0.10), Vector3(0.215, 0.30, 0.10), 16, 8)
	# Belt.
	body.add_torus(0.585, 0.193, 0.018, SEGMENTS, 6, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.77)), Vector3.ZERO))

	var head := Vector3(0.0, 1.060, 0.0)
	_add_head(body, accent, head, 0.118)
	# Hair to the collar, and a full beard.
	body.add_ellipsoid(Vector3(0.0, 1.02, -0.045), Vector3(0.118, 0.135, 0.105), 14, 7)
	body.add_ellipsoid(Vector3(0.0, 0.972, 0.048), Vector3(0.090, 0.080, 0.056), 12, 6)
	body.add_cone(Vector3(0.0, 0.960, 0.066), Vector3(0.0, 0.835, 0.118), 0.066, 0.012, 10)
	body.add_ellipsoid(Vector3(0.0, 1.008, 0.100), Vector3(0.058, 0.014, 0.016), 8, 4)  # moustache

	_add_crown(body, 1.130, 0.108, 0.150, 8)
	# Orb and cross on top.
	body.add_ball(Vector3(0.0, 1.235, 0.0), 0.040, 12, 6)
	body.add_box(Vector3(0.0, 1.335, 0.0), Vector3(0.036, 0.165, 0.030))
	body.add_box(Vector3(0.0, 1.352, 0.0), Vector3(0.112, 0.036, 0.030))

	# Both hands rest on a great sword planted in front of him.
	var sword_z := 0.212
	body.add_box(Vector3(0.0, 0.565, sword_z), Vector3(0.040, 0.400, 0.014))
	body.add_cone(Vector3(0.0, 0.365, sword_z), Vector3(0.0, 0.312, sword_z), 0.020, 0.002, 4)
	body.add_box(Vector3(0.0, 0.775, sword_z), Vector3(0.165, 0.030, 0.030))
	body.add_cone(Vector3(0.0, 0.775, sword_z), Vector3(0.0, 0.860, sword_z), 0.016, 0.016, 8)
	body.add_ball(Vector3(0.0, 0.878, sword_z), 0.030, 10, 5)
	for side: float in [-1.0, 1.0]:
		_add_arm(body, Vector3(0.205 * side, 0.835, 0.01), Vector3(0.225 * side, 0.700, 0.105),
				Vector3(0.030 * side, 0.812, sword_z - 0.012), 0.047)


static func _build_queen(body: MeshBuilder, accent: MeshBuilder) -> void:
	_add_pedestal(body, 0.34, 0.30)
	# Gown: wide skirt, narrow waist.
	body.add_squashed_lathe(_smooth([
		0.238, 0.29,
		0.228, 0.37,
		0.185, 0.50,
		0.135, 0.625,
		0.122, 0.675,  # waist
		0.148, 0.755,
		0.176, 0.825,  # shoulders
		0.150, 0.872,
		0.086, 0.905,
		0.060, 0.932,  # neck
		0.056, 0.980,
	]), SEGMENTS, 0.80)
	# Girdle and a high collar.
	body.add_torus(0.668, 0.124, 0.016, SEGMENTS, 6, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.80)), Vector3.ZERO))
	body.add_torus(0.880, 0.128, 0.026, SEGMENTS, 6, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.82)), Vector3.ZERO))
	# Folds of the skirt.
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0
		body.add_ellipsoid(Vector3(cos(a) * 0.196, 0.40, sin(a) * 0.196 * 0.80),
				Vector3(0.046, 0.115, 0.030), 8, 4, Basis(Vector3.UP, -a + PI / 2.0))

	var head := Vector3(0.0, 1.040, 0.0)
	_add_head(body, accent, head, 0.106)
	# Long hair down the back and over the shoulders.
	body.add_ellipsoid(Vector3(0.0, 0.955, -0.062), Vector3(0.112, 0.205, 0.082), 14, 8)
	for side: float in [-1.0, 1.0]:
		body.add_ellipsoid(Vector3(0.088 * side, 0.955, 0.005), Vector3(0.036, 0.150, 0.056), 10, 6)

	_add_crown(body, 1.100, 0.096, 0.150, 6)
	body.add_ball(Vector3(0.0, 1.205, 0.0), 0.034, 12, 6)
	body.add_ball(Vector3(0.0, 1.255, 0.0), 0.022, 10, 5)

	# Hands folded at the waist, holding an orb.
	for side: float in [-1.0, 1.0]:
		_add_arm(body, Vector3(0.158 * side, 0.812, 0.0), Vector3(0.178 * side, 0.672, 0.075),
				Vector3(0.034 * side, 0.690, 0.150), 0.038)
	body.add_ball(Vector3(0.0, 0.712, 0.172), 0.040, 12, 6)


static func _build_bishop(body: MeshBuilder, accent: MeshBuilder) -> void:
	_add_pedestal(body, 0.31, 0.30)
	# Vestments.
	body.add_squashed_lathe(_smooth([
		0.214, 0.29,
		0.208, 0.37,
		0.178, 0.50,
		0.166, 0.62,
		0.184, 0.72,
		0.198, 0.785,  # shoulders
		0.170, 0.835,
		0.092, 0.868,
		0.062, 0.890,  # neck
		0.058, 0.935,
	]), SEGMENTS, 0.80)
	# Stole: a band round the neck with two tails down the front.
	body.add_torus(0.842, 0.118, 0.026, SEGMENTS, 6, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.82)), Vector3.ZERO))
	for side: float in [-1.0, 1.0]:
		body.add_box(Vector3(0.050 * side, 0.600, 0.136), Vector3(0.042, 0.400, 0.018),
				Basis(Vector3.RIGHT, deg_to_rad(4.0)))
		body.add_box(Vector3(0.050 * side, 0.415, 0.156), Vector3(0.058, 0.034, 0.020))

	var head := Vector3(0.0, 0.990, 0.0)
	_add_head(body, accent, head, 0.102)
	body.add_ellipsoid(Vector3(0.0, 0.918, 0.046), Vector3(0.068, 0.062, 0.044), 12, 6)  # beard
	body.add_cone(Vector3(0.0, 0.905, 0.060), Vector3(0.0, 0.825, 0.100), 0.050, 0.010, 8)
	body.add_ellipsoid(Vector3(0.0, 0.965, -0.040), Vector3(0.100, 0.105, 0.088), 12, 6)  # hair

	# Mitre: a pointed hat, wide from the front and narrow from the side.
	body.add_squashed_lathe(_smooth([
		0.098, 1.040,
		0.110, 1.048,
		0.112, 1.078,  # band
		0.104, 1.084,
		0.122, 1.135,
		0.112, 1.180,
		0.070, 1.232,
		0.022, 1.268,
		0.0, 1.276,
	]), 20, 0.70)
	# Cross on the front of the mitre.
	body.add_box(Vector3(0.0, 1.158, 0.080), Vector3(0.022, 0.104, 0.016))
	body.add_box(Vector3(0.0, 1.172, 0.080), Vector3(0.072, 0.022, 0.016))
	# Lappets hanging down the back.
	for side: float in [-1.0, 1.0]:
		body.add_box(Vector3(0.034 * side, 0.955, -0.098), Vector3(0.034, 0.200, 0.012))

	# Crosier in the right hand.
	var staff_x := 0.232
	var staff_z := 0.062
	body.add_cone(Vector3(staff_x, 0.292, staff_z), Vector3(staff_x, 1.030, staff_z), 0.017, 0.015, 8)
	body.add_ball(Vector3(staff_x, 1.035, staff_z), 0.026, 8, 4)
	var crook := PackedVector3Array()
	var crook_r := PackedVector2Array()
	for i in 15:
		var t := float(i) / 14.0
		# Spiral curling up and inward, toward the bishop.
		var ang := lerpf(-0.35, PI * 1.5, t)
		var radius := lerpf(0.060, 0.020, t)
		crook.append(Vector3(staff_x - 0.056 + cos(ang) * radius, 1.100 + sin(ang) * radius, staff_z))
		crook_r.append(Vector2.ONE * lerpf(0.015, 0.008, t))
	crook[0] = Vector3(staff_x, 1.035, staff_z)
	body.add_loft(crook, crook_r, 8, Vector3.BACK)
	_add_arm(body, Vector3(0.176, 0.770, 0.0), Vector3(0.214, 0.640, 0.045),
			Vector3(staff_x - 0.008, 0.700, staff_z + 0.006), 0.040)
	# Left hand raised in blessing.
	_add_arm(body, Vector3(-0.176, 0.770, 0.0), Vector3(-0.205, 0.640, 0.075),
			Vector3(-0.130, 0.745, 0.150), 0.040)


static func _build_pawn(body: MeshBuilder, accent: MeshBuilder) -> void:
	_add_pedestal(body, 0.27, 0.235, 10)
	# Tunic and mail.
	body.add_squashed_lathe(_smooth([
		0.168, 0.225,
		0.164, 0.280,
		0.138, 0.365,
		0.136, 0.420,
		0.152, 0.475,
		0.160, 0.505,  # shoulders
		0.136, 0.540,
		0.074, 0.562,
		0.052, 0.575,  # neck
		0.050, 0.600,
	]), 24, 0.80)
	body.add_torus(0.395, 0.139, 0.015, 24, 6, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.80)), Vector3.ZERO))

	_add_head(body, accent, Vector3(0.0, 0.632, 0.0), 0.082)
	# Kettle helmet with a brim.
	body.add_lathe(_pts([
		0.074, 0.662,
		0.120, 0.668,
		0.122, 0.680,
		0.086, 0.690,
		0.078, 0.722,
		0.052, 0.752,
		0.018, 0.768,
		0.0, 0.770,
	]), 18)
	# Mail coif under the helmet.
	body.add_ellipsoid(Vector3(0.0, 0.612, -0.022), Vector3(0.088, 0.075, 0.078), 12, 6)

	# Spear in the right hand.
	var spear := Vector3(0.158, 0.0, 0.070)
	body.add_cone(spear + Vector3.UP * 0.225, spear + Vector3.UP * 0.745, 0.012, 0.011, 6)
	body.add_cone(spear + Vector3.UP * 0.735, spear + Vector3.UP * 0.830, 0.026, 0.002, 4)
	_add_arm(body, Vector3(0.140, 0.495, 0.0), Vector3(0.168, 0.405, 0.035),
			spear + Vector3(-0.004, 0.455, 0.004), 0.032)

	# Round shield on the left arm, with a boss and a rim.
	var shield := MeshBuilder.new()
	shield.add_lathe(_pts([
		0.0, -0.012,
		0.112, -0.012,
		0.118, 0.000,
		0.112, 0.014,
		0.096, 0.012,
		0.090, 0.020,
		0.042, 0.030,
		0.036, 0.046,
		0.016, 0.060,
		0.0, 0.062,
	]), 20)
	for i in 8:
		var a := TAU * float(i) / 8.0
		shield.add_ball(Vector3(cos(a) * 0.104, 0.014, sin(a) * 0.104), 0.010, 6, 3)
	shield.transform(Transform3D(
			Basis(Vector3.UP, deg_to_rad(-22.0)) * Basis(Vector3.RIGHT, deg_to_rad(82.0)),
			Vector3(-0.092, 0.425, 0.128)))
	body.append(shield)
	_add_arm(body, Vector3(-0.140, 0.495, 0.0), Vector3(-0.172, 0.410, 0.040),
			Vector3(-0.110, 0.425, 0.105), 0.032)


static func _build_rook(body: MeshBuilder, accent: MeshBuilder) -> void:
	# Stone plinth and the tower core (the mortar between the bricks).
	body.add_lathe(_pts([
		0.310, 0.020,
		0.310, 0.070,
		0.292, 0.092,
		0.262, 0.100,
		0.248, 0.118,
		0.206, 0.122,
		0.200, 0.650,
		0.232, 0.690,   # flare under the parapet
		0.262, 0.708,
		0.262, 0.790,   # parapet wall
		0.196, 0.790,
		0.196, 0.745,   # walkway
		0.0, 0.745,
	]), SEGMENTS)

	# Brick courses, each offset by half a brick.
	var courses := 7
	var bricks := 9
	var course_h := (0.650 - 0.124) / courses
	for c in courses:
		var y0 := 0.124 + course_h * c + 0.005
		var y1 := 0.124 + course_h * (c + 1) - 0.005
		var slot := TAU / bricks
		for b in bricks:
			var a0 := slot * (b + (0.5 if c % 2 == 1 else 0.0)) + slot * 0.055
			body.add_arc_block(0.190, 0.218, y0, y1, a0, a0 + slot * 0.89, 2)

	# Corbels carrying the parapet.
	for i in 12:
		var a := TAU * float(i) / 12.0
		body.add_arc_block(0.205, 0.256, 0.648, 0.700, a - 0.085, a + 0.085, 1)

	# Battlements.
	var merlons := 6
	var slot_m := TAU / merlons
	for i in merlons:
		var mid := slot_m * (i + 0.5)
		body.add_arc_block(0.196, 0.262, 0.790, 0.905, mid - slot_m * 0.30, mid + slot_m * 0.30, 3)
	# String course under the merlons.
	body.add_torus(0.712, 0.262, 0.012, SEGMENTS, 6)

	# Gate with a round arch, and arrow slits.
	accent.add_box(Vector3(0.0, 0.205, 0.214), Vector3(0.092, 0.150, 0.024))
	accent.add_ellipsoid(Vector3(0.0, 0.280, 0.214), Vector3(0.046, 0.050, 0.012), 12, 6)
	for side: float in [-1.0, 1.0]:
		body.add_box(Vector3(0.056 * side, 0.212, 0.220), Vector3(0.020, 0.172, 0.024))
	body.add_box(Vector3(0.0, 0.338, 0.220), Vector3(0.132, 0.022, 0.024))
	for i in 3:
		var a := PI / 2.0 + TAU * float(i + 1) / 4.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		accent.add_box(dir * 0.212 + Vector3.UP * 0.470, Vector3(0.024, 0.105, 0.020),
				Basis(Vector3.UP, -a + PI / 2.0))
	accent.add_box(Vector3(0.0, 0.530, 0.212), Vector3(0.024, 0.105, 0.020))


static func _build_knight(body: MeshBuilder, accent: MeshBuilder) -> void:
	_add_pedestal(body, 0.31, 0.30)
	# Neck and head as one loft, arched like a charger's: (x, y, z) centers and
	# (half width, half depth) sections.
	var path := PackedVector3Array([
		Vector3(0.0, 0.270, -0.030),
		Vector3(0.0, 0.380, -0.020),
		Vector3(0.0, 0.500, -0.030),
		Vector3(0.0, 0.620, -0.045),
		Vector3(0.0, 0.730, -0.040),
		Vector3(0.0, 0.820, -0.010),
		Vector3(0.0, 0.870, 0.050),
		Vector3(0.0, 0.855, 0.125),
		Vector3(0.0, 0.800, 0.195),
		Vector3(0.0, 0.735, 0.250),
		Vector3(0.0, 0.680, 0.290),
		Vector3(0.0, 0.650, 0.312),
	])
	var sections := PackedVector2Array([
		Vector2(0.185, 0.215),
		Vector2(0.168, 0.200),
		Vector2(0.140, 0.178),
		Vector2(0.118, 0.158),
		Vector2(0.104, 0.142),
		Vector2(0.098, 0.128),
		Vector2(0.098, 0.112),
		Vector2(0.094, 0.098),
		Vector2(0.080, 0.086),
		Vector2(0.066, 0.072),
		Vector2(0.060, 0.062),
		Vector2(0.044, 0.044),
	])
	body.add_loft(path, sections, 18, Vector3.RIGHT)

	# Cheeks, muzzle and the brow over each eye.
	for side: float in [-1.0, 1.0]:
		body.add_ellipsoid(Vector3(0.062 * side, 0.790, 0.090), Vector3(0.052, 0.082, 0.082), 12, 6,
				Basis(Vector3.RIGHT, deg_to_rad(40.0)))
		body.add_ellipsoid(Vector3(0.070 * side, 0.872, 0.105), Vector3(0.030, 0.022, 0.045), 8, 4)
		accent.add_ellipsoid(Vector3(0.084 * side, 0.846, 0.118), Vector3(0.016, 0.020, 0.026), 8, 4)
		accent.add_ball(Vector3(0.030 * side, 0.664, 0.326), 0.013, 6, 3)
		body.add_ellipsoid(Vector3(0.034 * side, 0.672, 0.306), Vector3(0.028, 0.030, 0.034), 8, 4)
		# Ears.
		body.add_cone(Vector3(0.052 * side, 0.895, 0.020), Vector3(0.074 * side, 1.020, -0.012), 0.034, 0.004, 6)
	body.add_ellipsoid(Vector3(0.0, 0.655, 0.275), Vector3(0.050, 0.040, 0.060), 10, 5)  # chin

	# Mane: overlapping locks down the back of the neck, and a forelock.
	var locks := 9
	for i in locks:
		var t := float(i) / (locks - 1)
		var y := lerpf(0.330, 0.905, t)
		var back := lerpf(-0.225, -0.085, pow(t, 1.6))
		body.add_ellipsoid(Vector3(0.012 * (1.0 if i % 2 == 0 else -1.0), y, back),
				Vector3(0.050, 0.072, 0.062), 10, 5, Basis(Vector3.RIGHT, deg_to_rad(-25.0)))
	body.add_ellipsoid(Vector3(0.0, 0.905, 0.060), Vector3(0.034, 0.030, 0.062), 8, 4)

	# Bridle: noseband, browband and cheek straps.
	var nose_dir := (path[10] - path[8]).normalized()
	body.add_torus(0.0, 0.074, 0.011, 16, 6,
			Transform3D(MeshBuilder.basis_from_y(nose_dir), Vector3(0.0, 0.752, 0.236)))
	body.add_torus(0.0, 0.110, 0.011, 16, 6,
			Transform3D(MeshBuilder.basis_from_y(Vector3(0.0, 0.25, 0.97).normalized()), Vector3(0.0, 0.880, 0.040)))
	for side: float in [-1.0, 1.0]:
		body.add_cone(Vector3(0.100 * side, 0.872, 0.060), Vector3(0.074 * side, 0.760, 0.228), 0.010, 0.010, 6)
	# Breast strap with a medallion.
	body.add_torus(0.0, 0.176, 0.016, 20, 6,
			Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18.0)), Vector3(0.0, 0.405, -0.012)))
	body.add_ellipsoid(Vector3(0.0, 0.352, 0.186), Vector3(0.036, 0.036, 0.016), 10, 5)


# Like _pts, but rounded: a Catmull-Rom curve through the points, so robes
# and hats read as sculpted cloth rather than turned wood.
static func _smooth(flat: Array, steps: int = 3) -> PackedVector2Array:
	var p := _pts(flat)
	var out := PackedVector2Array()
	for i in p.size() - 1:
		var p0 := p[maxi(i - 1, 0)]
		var p3 := p[mini(i + 2, p.size() - 1)]
		for k in steps:
			var point := p[i].cubic_interpolate(p[i + 1], p0, p3, float(k) / steps)
			out.append(Vector2(maxf(point.x, 0.0), point.y))
	out.append(p[p.size() - 1])
	return out


static func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out
