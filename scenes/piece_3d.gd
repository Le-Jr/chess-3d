class_name Piece3D
extends Node3D
## One piece on the board. Owns its visual (from a PieceSet) and animates
## moves (lift, arc, set down) and captures (sink and fade).

var piece: int = Piece.NONE

var _visual: Node3D
var _tween: Tween


## (Re)builds the visual for `new_piece`; also used when a pawn promotes.
func setup(new_piece: int, piece_set: PieceSet) -> void:
	piece = new_piece
	if _visual != null:
		remove_child(_visual)
		_visual.queue_free()
	_visual = piece_set.instantiate(new_piece)
	add_child(_visual)
	# Models face +Z (toward White's seat); turn Black's pieces around.
	rotation.y = PI if Piece.color_of(new_piece) == Piece.BLACK else 0.0


## Moves to `target` (board-local). Returns the animation length in seconds
## (0 when not animated).
func move_to(target: Vector3, animate: bool = true) -> float:
	_kill_tween()
	if not animate or not is_inside_tree():
		position = target
		return 0.0
	var start := position
	var distance := start.distance_to(target)
	var duration := clampf(0.24 + distance * 0.055, 0.28, 0.62)
	# Knights hop over other pieces; everything else just clears the board.
	var lift := 0.95 if Piece.type_of(piece) == Piece.KNIGHT else 0.22 + distance * 0.03
	_tween = create_tween()
	_tween.tween_method(_arc_step.bind(start, target, lift), 0.0, 1.0, duration)
	return duration


func _arc_step(t: float, start: Vector3, target: Vector3, lift: float) -> void:
	var rise := smoothstep(0.0, 0.32, t) * (1.0 - smoothstep(0.68, 1.0, t))
	var travel := smoothstep(0.08, 0.92, t)
	position = start.lerp(target, travel) + Vector3.UP * (lift * rise)


## Removes the piece: sinks into the board while fading, then frees itself.
## `delay` lets the capturing piece arrive first.
func capture_out(animate: bool = true, delay: float = 0.0) -> void:
	_kill_tween()
	if not animate or not is_inside_tree():
		queue_free()
		return
	var depth := PieceProfiles.height(Piece.type_of(piece)) + 0.1
	_tween = create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_property(self, "position:y", position.y - depth, 0.38) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_method(_set_fade, 0.0, 1.0, 0.38)
	_tween.tween_callback(queue_free)


func _set_fade(amount: float) -> void:
	_fade_node(_visual, amount)


func _fade_node(node: Node, amount: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = amount
	for child in node.get_children():
		_fade_node(child, amount)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
