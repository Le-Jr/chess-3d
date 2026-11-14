class_name Board3D
extends Node3D
## The 3D board: 64 tiles, a beveled frame with a-h / 1-8 labels, and the
## square highlights (selection, legal moves, last move, check).
##
## Local coordinates: one square = 1 unit, the board is centered on the
## origin with its playing surface at y = 0. Files run along +X (a -> h) and
## ranks along -Z (rank 1 is at +Z, nearest to White's camera).

const HALF := 4.0
const FRAME_WIDTH := 0.6
const FRAME_BEVEL := 0.06
const FRAME_DROP := 0.32

const COLOR_SELECTED := Color(0.95, 0.85, 0.25)
const COLOR_MOVE := Color(0.30, 0.85, 0.45)
const COLOR_LAST_MOVE := Color(0.95, 0.70, 0.20)
const COLOR_CHECK := Color(1.0, 0.18, 0.12)

var _tiles: MeshInstance3D
var _frame: MeshInstance3D
var _labels: Array[Label3D] = []

var _selected_quad: MeshInstance3D
var _last_from_quad: MeshInstance3D
var _last_to_quad: MeshInstance3D
var _check_quad: MeshInstance3D
var _dots: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _dot_mesh: Mesh
var _ring_mesh: Mesh
var _move_material: StandardMaterial3D


func _init() -> void:
	_build_tiles()
	_build_frame()
	_build_labels()
	_build_highlights()
	apply_preset(MaterialPresets.Preset.CLASSIC_WOOD)


# ------------------------------------------------------------ coordinates ---

## Center of a square (0x88 index) in board-local space.
static func square_to_local(square: int) -> Vector3:
	return Vector3((square & 7) - 3.5, 0.0, 3.5 - (square >> 4))


## Square under a board-local point, or -1 if the point is off the board.
static func local_to_square(point: Vector3) -> int:
	var file := floori(point.x + HALF)
	var rank := floori(HALF - point.z)
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 16 + file


# ---------------------------------------------------------------- picking ---

## Square under the mouse, or -1. Raycasts from the camera against the
## pieces on `board` first (so clicking a tall piece selects that piece and
## not the square behind it), then against the board plane.
func pick_square(camera: Camera3D, screen_pos: Vector2, board: Board = null) -> int:
	var inv := global_transform.affine_inverse()
	var origin := inv * camera.project_ray_origin(screen_pos)
	var dir := (inv.basis * camera.project_ray_normal(screen_pos)).normalized()
	return pick_square_ray(origin, dir, board)


## Same as pick_square, with the ray given in board-local space.
func pick_square_ray(origin: Vector3, dir: Vector3, board: Board = null) -> int:
	if board != null:
		var best_t := INF
		var best_sq := -1
		for rank in 8:
			for file in 8:
				var s := rank * 16 + file
				var p := board.squares[s]
				if p == 0:
					continue
				var type := p & 7
				var t := _ray_cylinder(origin, dir, square_to_local(s),
						PieceProfiles.base_radius(type) * 0.75, PieceProfiles.height(type))
				if t < best_t:
					best_t = t
					best_sq = s
		if best_sq != -1:
			return best_sq
	if dir.y >= -1e-6 or origin.y <= 0.0:
		return -1
	return local_to_square(origin + dir * (-origin.y / dir.y))


# Distance along the ray to an upright cylinder standing on y = 0, or INF.
static func _ray_cylinder(o: Vector3, d: Vector3, center: Vector3, radius: float, height: float) -> float:
	var ox := o.x - center.x
	var oz := o.z - center.z
	var a := d.x * d.x + d.z * d.z
	if a > 1e-9:
		var b := 2.0 * (ox * d.x + oz * d.z)
		var c := ox * ox + oz * oz - radius * radius
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return INF
		var t := (-b - sqrt(disc)) / (2.0 * a)
		if t > 0.0:
			var y := o.y + d.y * t
			if y >= 0.0 and y <= height:
				return t
	# Through the top cap.
	if d.y < -1e-9 and o.y > height:
		var t_top := (height - o.y) / d.y
		var px := ox + d.x * t_top
		var pz := oz + d.z * t_top
		if px * px + pz * pz <= radius * radius:
			return t_top
	return INF


# -------------------------------------------------------------- materials ---

func apply_preset(preset: int) -> void:
	apply_materials(MaterialPresets.board_light(preset), MaterialPresets.board_dark(preset),
			MaterialPresets.board_frame(preset), MaterialPresets.label_color(preset))


func apply_materials(light: Material, dark: Material, frame: Material, label_color: Color) -> void:
	_tiles.set_surface_override_material(0, light)
	_tiles.set_surface_override_material(1, dark)
	_frame.set_surface_override_material(0, frame)
	for label in _labels:
		label.modulate = label_color


# ------------------------------------------------------------- highlights ---

func show_selection(square: int) -> void:
	_place(_selected_quad, square)


## Marks the destinations of `moves`: a dot on empty squares, a ring around
## pieces that can be captured.
func show_targets(moves: PackedInt32Array) -> void:
	var dot_i := 0
	var ring_i := 0
	var seen := {}
	for m in moves:
		var to := Move.to_sq(m)
		if seen.has(to):
			continue  # the four promotion moves share one target square
		seen[to] = true
		var marker: MeshInstance3D
		if Move.is_capture(m) and not Move.is_en_passant(m):
			if ring_i == _rings.size():
				_rings.append(_make_marker(_ring_mesh, 0.008))
			marker = _rings[ring_i]
			ring_i += 1
		else:
			if dot_i == _dots.size():
				_dots.append(_make_marker(_dot_mesh, 0.006))
			marker = _dots[dot_i]
			dot_i += 1
		var pos := square_to_local(to)
		marker.position = Vector3(pos.x, marker.position.y, pos.z)
		marker.visible = true
	for i in range(dot_i, _dots.size()):
		_dots[i].visible = false
	for i in range(ring_i, _rings.size()):
		_rings[i].visible = false


func clear_selection() -> void:
	_selected_quad.visible = false
	for d in _dots:
		d.visible = false
	for r in _rings:
		r.visible = false


## Pass -1 / -1 to hide.
func show_last_move(from: int, to: int) -> void:
	_place(_last_from_quad, from)
	_place(_last_to_quad, to)


## Highlights the square of a king in check; -1 hides it.
func show_check(square: int) -> void:
	_place(_check_quad, square)


func clear_highlights() -> void:
	clear_selection()
	show_last_move(-1, -1)
	show_check(-1)


## What is currently highlighted, for tests: {"selected", "check", "last_from",
## "last_to"} hold a square or -1; "dots" / "rings" hold the marked squares.
func highlight_state() -> Dictionary:
	var dots: Array[int] = []
	for d in _dots:
		if d.visible:
			dots.append(local_to_square(d.position))
	var rings: Array[int] = []
	for r in _rings:
		if r.visible:
			rings.append(local_to_square(r.position))
	dots.sort()
	rings.sort()
	return {
		"selected": local_to_square(_selected_quad.position) if _selected_quad.visible else -1,
		"check": local_to_square(_check_quad.position) if _check_quad.visible else -1,
		"last_from": local_to_square(_last_from_quad.position) if _last_from_quad.visible else -1,
		"last_to": local_to_square(_last_to_quad.position) if _last_to_quad.visible else -1,
		"dots": dots,
		"rings": rings,
	}


func _place(quad: MeshInstance3D, square: int) -> void:
	quad.visible = square >= 0
	if square >= 0:
		var pos := square_to_local(square)
		quad.position = Vector3(pos.x, quad.position.y, pos.z)


# --------------------------------------------------------------- building ---

func _build_tiles() -> void:
	var light := MeshBuilder.new()
	var dark := MeshBuilder.new()
	for rank in 8:
		for file in 8:
			var c := square_to_local(rank * 16 + file)
			var target := dark if (rank + file) % 2 == 0 else light  # a1 is dark
			target.add_flat_quad(
				c + Vector3(-0.5, 0.0, -0.5), c + Vector3(0.5, 0.0, -0.5),
				c + Vector3(0.5, 0.0, 0.5), c + Vector3(-0.5, 0.0, 0.5), Vector3.UP)
	var mesh := ArrayMesh.new()
	light.commit(mesh, "light")
	dark.commit(mesh, "dark")
	_tiles = MeshInstance3D.new()
	_tiles.name = "Tiles"
	_tiles.mesh = mesh
	_tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tiles)


func _build_frame() -> void:
	var mb := MeshBuilder.new()
	var outer := HALF + FRAME_WIDTH
	_square_ring(mb, HALF, 0.0, outer, 0.0)
	_square_ring(mb, outer, 0.0, outer + FRAME_BEVEL, -FRAME_BEVEL)
	_square_ring(mb, outer + FRAME_BEVEL, -FRAME_BEVEL, outer + FRAME_BEVEL, -FRAME_DROP)
	var mesh := ArrayMesh.new()
	mb.commit(mesh, "frame")
	_frame = MeshInstance3D.new()
	_frame.name = "Frame"
	_frame.mesh = mesh
	add_child(_frame)


# Four quads joining a square of half-size h0 at height y0 to one of
# half-size h1 at height y1 (a "square lathe" segment).
static func _square_ring(mb: MeshBuilder, h0: float, y0: float, h1: float, y1: float) -> void:
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var c0: Vector2 = corners[k]
		var c1: Vector2 = corners[(k + 1) % 4]
		var mid := (c0 + c1) * 0.5
		var hint := Vector3(mid.x, 0.0, mid.y)
		if is_equal_approx(y0, y1):
			hint = Vector3.UP
		mb.add_flat_quad(
			Vector3(c0.x * h0, y0, c0.y * h0), Vector3(c1.x * h0, y0, c1.y * h0),
			Vector3(c1.x * h1, y1, c1.y * h1), Vector3(c0.x * h1, y1, c0.y * h1), hint)


func _build_labels() -> void:
	var edge := HALF + FRAME_WIDTH * 0.5
	for i in 8:
		var along := i - 3.5
		var file_text := "abcdefgh"[i]
		var rank_text := str(i + 1)
		# Near edge and left side read correctly from White's seat, the far
		# edge and right side from Black's.
		_add_label(file_text, Vector3(along, 0.0, edge), 0.0)
		_add_label(file_text, Vector3(along, 0.0, -edge), 180.0)
		_add_label(rank_text, Vector3(-edge, 0.0, -along), 0.0)
		_add_label(rank_text, Vector3(edge, 0.0, -along), 180.0)


func _add_label(text: String, pos: Vector3, yaw_deg: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0042
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos + Vector3(0.0, 0.004, 0.0)
	label.rotation_degrees = Vector3(-90.0, yaw_deg, 0.0)
	add_child(label)
	_labels.append(label)


func _build_highlights() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.98, 0.98)
	_last_from_quad = _make_quad(quad, COLOR_LAST_MOVE, 0.32, 0.25, 0.002)
	_last_to_quad = _make_quad(quad, COLOR_LAST_MOVE, 0.42, 0.35, 0.002)
	_selected_quad = _make_quad(quad, COLOR_SELECTED, 0.50, 0.6, 0.003)
	_check_quad = _make_quad(quad, COLOR_CHECK, 0.62, 1.6, 0.004)

	var dot := CylinderMesh.new()
	dot.top_radius = 0.15
	dot.bottom_radius = 0.15
	dot.height = 0.01
	dot.radial_segments = 24
	dot.rings = 1
	_dot_mesh = dot
	var ring := TorusMesh.new()
	ring.inner_radius = 0.40
	ring.outer_radius = 0.47
	ring.rings = 32
	ring.ring_segments = 6
	_ring_mesh = ring
	_move_material = _highlight_material(COLOR_MOVE, 0.75, 1.1)


func _make_quad(mesh: Mesh, color: Color, alpha: float, glow: float, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _highlight_material(color, alpha, glow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = y
	mi.visible = false
	add_child(mi)
	return mi


func _make_marker(mesh: Mesh, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _move_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = y
	if mesh == _ring_mesh:
		mi.scale = Vector3(1.0, 0.25, 1.0)
	add_child(mi)
	return mi


static func _highlight_material(color: Color, alpha: float, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = glow
	return m
