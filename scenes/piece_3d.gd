class_name Piece3D
extends Node3D
## One piece on the board. Owns its visual (from a PieceSet) and animates
## moves (lift, arc, set down), attacks (a lunge, or a knight's stomp) and
## being captured (knocked flying, or crushed), plus the small touches: the
## selected piece lifting, a king shaking in check or toppling when mated,
## and the pieces dropping onto the board at the start of a game.
##
## The node's own position is always the piece's place on the board; the
## flourishes that should not disturb it (lift, drop-in, squash) are played on
## the visual child.

## Emitted when a captured piece is struck (the moment for sound and shake).
signal struck

## How a captured piece goes out.
enum CaptureStyle { KNOCK, CRUSH }

const SELECT_LIFT := 0.14

var piece: int = Piece.NONE

var _visual: Node3D
var _visual_scale := Vector3.ONE
var _tween: Tween         # moves the node itself
var _visual_tween: Tween  # flourishes on the visual
var _facing := 0.0
var _impact := 0.6  # when an attacking move connects, as a fraction of it


## (Re)builds the visual for `new_piece`; also used when a pawn promotes.
func setup(new_piece: int, piece_set: PieceSet) -> void:
	piece = new_piece
	_kill(_visual_tween)
	if _visual != null:
		remove_child(_visual)
		_visual.queue_free()
	_visual = piece_set.instantiate(new_piece)
	_visual_scale = _visual.scale
	add_child(_visual)
	move_child(_visual, 0)
	# Models face +Z (toward White's seat); turn Black's pieces around.
	_facing = PI if Piece.color_of(new_piece) == Piece.BLACK else 0.0
	_set_tilt(Vector3.RIGHT, 0.0)


## Moves to `target` (board-local). `attack` adds the strike of a capturing
## move. Returns the animation length in seconds (0 when not animated).
func move_to(target: Vector3, animate: bool = true, attack: bool = false) -> float:
	_kill(_tween)
	_set_tilt(Vector3.RIGHT, 0.0)
	if not animate or not is_inside_tree():
		position = target
		return 0.0
	var start := position
	var distance := start.distance_to(target)
	var duration := clampf(0.24 + distance * 0.055, 0.28, 0.62)
	var knight := Piece.type_of(piece) == Piece.KNIGHT
	# Knights hop over other pieces; everything else just clears the board.
	var lift := 0.95 if knight else 0.22 + distance * 0.03
	var lean_axis := Vector3.ZERO
	if attack:
		duration = clampf(duration * 1.3, 0.42, 0.72)
		if knight:
			# Comes down on top of its victim.
			lift = 1.25
			_impact = 0.86
		else:
			lean_axis = Vector3.UP.cross((target - start).normalized())
			# The blow lands when the two pieces touch, about half a square
			# short of the target.
			_impact = _time_of_travel(clampf(1.0 - 0.5 / maxf(distance, 0.01), 0.3, 0.9))
	_tween = create_tween()
	_tween.tween_method(_arc_step.bind(start, target, lift, lean_axis), 0.0, 1.0, duration)
	_tween.tween_callback(_land)
	return duration


## When, as a fraction of the attacking move just started with move_to, the
## mover reaches its victim.
func impact_fraction() -> float:
	return _impact


# How far along the path the piece is at time t (both 0..1).
static func _travel(t: float) -> float:
	return smoothstep(0.08, 0.92, t)


# Inverse of _travel.
static func _time_of_travel(fraction: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 20:
		var mid := (lo + hi) * 0.5
		if _travel(mid) < fraction:
			lo = mid
		else:
			hi = mid
	return hi


func _arc_step(t: float, start: Vector3, target: Vector3, lift: float, lean_axis: Vector3) -> void:
	var rise := smoothstep(0.0, 0.32, t) * (1.0 - smoothstep(0.68, 1.0, t))
	position = start.lerp(target, _travel(t)) + Vector3.UP * (lift * rise)
	if lean_axis != Vector3.ZERO:
		# Rear back, then lunge into the blow as it lands.
		var wind_up := (t - _impact + 0.30) / 0.13
		var strike := (t - _impact) / 0.17
		_set_tilt(lean_axis, -0.15 * exp(-wind_up * wind_up) + 0.44 * exp(-strike * strike))


# Setting down: a quick squash so the piece feels heavy.
func _land() -> void:
	_set_tilt(Vector3.RIGHT, 0.0)
	if _visual == null:
		return
	_kill(_visual_tween)
	_rest_visual()
	_visual.scale = _visual_scale * Vector3(1.07, 0.90, 1.07)
	_visual_tween = create_tween()
	_visual_tween.tween_property(_visual, "scale", _visual_scale, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Removes the piece. `direction` is the way the blow travels (board-local);
## `delay` lets the capturing piece arrive first.
func capture_out(animate: bool = true, delay: float = 0.0, direction: Vector3 = Vector3.ZERO,
		style: CaptureStyle = CaptureStyle.KNOCK) -> void:
	_kill(_tween)
	_kill(_visual_tween)
	if not animate or not is_inside_tree():
		queue_free()
		return
	_rest_visual()
	var dir := Vector3(direction.x, 0.0, direction.z)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_callback(_on_struck.bind(dir))
	if style == CaptureStyle.CRUSH:
		# Flattened under the knight, then gone.
		_tween.tween_property(self, "scale", Vector3(1.30, 0.07, 1.30), 0.10) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_fade, 0.0, 1.0, 0.26)
	else:
		_tween.tween_method(_knock_step.bind(position, dir), 0.0, 1.0, 0.52)
	_tween.tween_callback(queue_free)


func _on_struck(dir: Vector3) -> void:
	struck.emit()
	var parent := get_parent()
	if parent is Node3D:
		Effects.shatter(parent as Node3D, position, dir, body_material(),
				PieceProfiles.height(Piece.type_of(piece)))


# Knocked off its square: flies back along the blow, tumbling and fading.
func _knock_step(t: float, start: Vector3, dir: Vector3) -> void:
	var fly := 1.0 - pow(1.0 - t, 2.0)
	position = start + dir * (1.35 * fly) + Vector3.UP * (1.9 * t * (1.0 - t) + 0.10 * t)
	_set_tilt(Vector3.UP.cross(dir), 3.6 * fly)
	scale = Vector3.ONE * lerpf(1.0, 0.55, t)
	_set_fade(smoothstep(0.35, 1.0, t))


## The material of the piece's body (for the debris of a capture).
func body_material() -> Material:
	return _first_material(_visual)


func _first_material(node: Node) -> Material:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			return mi.get_active_material(0)
	for child in node.get_children():
		var found := _first_material(child)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------- touches ---

## Raises the piece a little while it is selected.
func set_lifted(lifted: bool, animate: bool = true) -> void:
	if _visual == null:
		return
	_kill(_visual_tween)
	_visual.scale = _visual_scale
	_fade_node(_visual, 0.0)
	var y := SELECT_LIFT if lifted else 0.0
	if not animate or not is_inside_tree():
		_visual.position.y = y
		return
	_visual_tween = create_tween()
	_visual_tween.tween_property(_visual, "position:y", y, 0.16) \
			.set_trans(Tween.TRANS_BACK if lifted else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Start of a game: the piece drops onto its square after `delay`.
func drop_in(delay: float) -> void:
	if _visual == null or not is_inside_tree():
		return
	_kill(_visual_tween)
	_visual.position.y = 2.6
	_fade_node(_visual, 1.0)
	_visual_tween = create_tween()
	_visual_tween.tween_interval(delay)
	_visual_tween.tween_method(_fade_visual, 1.0, 0.0, 0.14)
	_visual_tween.parallel().tween_property(_visual, "position:y", 0.0, 0.34) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_visual_tween.tween_property(_visual, "scale", _visual_scale * Vector3(1.08, 0.88, 1.08), 0.05)
	_visual_tween.tween_property(_visual, "scale", _visual_scale, 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A king in check trembles.
func shudder() -> void:
	if _visual == null or not is_inside_tree():
		return
	_kill(_visual_tween)
	_rest_visual()
	_visual_tween = create_tween()
	for i in 6:
		var offset := 0.035 * (1.0 - i / 6.0) * (1.0 if i % 2 == 0 else -1.0)
		_visual_tween.tween_property(_visual, "position:x", offset, 0.045)
	_visual_tween.tween_property(_visual, "position:x", 0.0, 0.045)


## Checkmate: the king falls over, away from `toward_enemy`.
func topple(away: Vector3) -> void:
	if not is_inside_tree():
		return
	_kill(_tween)
	var dir := Vector3(away.x, 0.0, away.z)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.RIGHT
	var axis := Vector3.UP.cross(dir)
	_tween = create_tween()
	_tween.tween_interval(0.25)
	_tween.tween_method(_topple_step.bind(axis), 0.0, 1.0, 0.75)


func _topple_step(t: float, axis: Vector3) -> void:
	# Tips slowly, falls fast, and bounces once on the board.
	var fall := pow(t / 0.62, 2.4) if t < 0.62 else 1.0 - 0.10 * sin((t - 0.62) / 0.38 * PI)
	_set_tilt(axis, fall * PI * 0.5)
	position.y = sin(fall * PI * 0.5) * PieceProfiles.base_radius(Piece.type_of(piece))


# ---------------------------------------------------------------- helpers ---

# Leans the piece by `angle` around a board-space axis, keeping its facing.
func _set_tilt(axis: Vector3, angle: float) -> void:
	var facing := Basis(Vector3.UP, _facing)
	basis = (Basis(axis.normalized(), angle) * facing) if absf(angle) > 1e-5 else facing


func _rest_visual() -> void:
	if _visual == null:
		return
	_visual.position = Vector3.ZERO
	_visual.scale = _visual_scale
	_fade_node(_visual, 0.0)


func _set_fade(amount: float) -> void:
	_fade_node(_visual, amount)


func _fade_visual(amount: float) -> void:
	_fade_node(_visual, amount)


func _fade_node(node: Node, amount: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = amount
	for child in node.get_children():
		_fade_node(child, amount)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
