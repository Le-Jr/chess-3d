extends Node3D
## The game scene: owns the GameState (rules) and keeps the 3D presentation
## and the HUD in sync with it. Everything visual is built in code so the
## scene file stays trivial.

signal move_played(move: int)

const MAIN_MENU_SCENE := "res://ui/main_menu.tscn"

var state: GameState
var board_view: Board3D
var camera_rig: CameraRig
var hud: Hud
var piece_set: PieceSet
var sfx: Sfx

var _pieces := {}  # square (0x88) -> Piece3D
var _selected := -1
var _busy := false  # a move animation is playing
var _pending_promotion := Vector2i(-1, -1)  # (from, to) while the picker is open
var _ai := AiPlayer.new()
var _cinematic: Tween  # the checkmate sequence, while it plays
var _slow_token := 0
var _hover_shape := Input.CURSOR_ARROW


func _ready() -> void:
	state = GameState.new()
	Stage.build(self)

	board_view = Board3D.new()
	board_view.name = "Board3D"
	add_child(board_view)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.screen_shift_px = Hud.PANEL_WIDTH + Hud.PANEL_MARGIN
	camera_rig.pitch_deg = GameSettings.camera_pitch
	add_child(camera_rig)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)

	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	hud.undo_requested.connect(undo_move)
	hud.new_game_requested.connect(new_game)
	hud.flip_requested.connect(func() -> void: camera_rig.flip())
	hud.menu_requested.connect(_go_to_menu)
	hud.auto_rotate_toggled.connect(_on_auto_rotate_toggled)
	hud.promotion_chosen.connect(_on_promotion_chosen)
	hud.camera_pitch_changed.connect(_on_camera_pitch_changed)
	hud.camera_pitch_committed.connect(GameSettings.save)
	hud.set_camera_pitch(GameSettings.camera_pitch)
	UiStyle.set_sword_cursor(true)
	hud.set_menu_available(ResourceLoader.exists(MAIN_MENU_SCENE))
	_ai.move_ready.connect(_on_ai_move_ready)

	piece_set = GameSettings.make_piece_set()
	board_view.apply_preset(GameSettings.material_preset)
	new_game()


# ------------------------------------------------------------------ input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			click_square(board_view.pick_square(camera_rig.camera, mb.position, state.board))
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_U, KEY_BACKSPACE:
				undo_move()
			KEY_F:
				camera_rig.flip()
			KEY_ESCAPE:
				_select(-1)


# The sword glows over anything a click would act on: one of your pieces, or
# a square the selected piece can move to.
func _update_hover(screen_pos: Vector2) -> void:
	var shape := Input.CURSOR_ARROW
	if not (_busy or state.is_game_over() or not _is_human_turn() or hud.is_asking_promotion()):
		var square := board_view.pick_square(camera_rig.camera, screen_pos, state.board)
		if square != -1:
			var p := state.board.piece_at(square)
			if p != Piece.NONE and Piece.color_of(p) == state.side_to_move():
				shape = Input.CURSOR_POINTING_HAND
			elif _selected != -1 and (state.find_move(_selected, square) != Move.NONE
					or state.needs_promotion(_selected, square)):
				shape = Input.CURSOR_POINTING_HAND
	if shape != _hover_shape:
		_hover_shape = shape
		Input.set_default_cursor_shape(shape)


func _on_camera_pitch_changed(degrees: float) -> void:
	GameSettings.camera_pitch = degrees
	camera_rig.set_pitch(degrees)


## Handles a click on a square (-1 = off the board): select a piece, or move
## the selected piece there.
func click_square(square: int) -> void:
	if _busy or state.is_game_over() or not _is_human_turn() or hud.is_asking_promotion():
		return
	if square == -1:
		_select(-1)
		return
	if _selected != -1 and square != _selected:
		if state.needs_promotion(_selected, square):
			_pending_promotion = Vector2i(_selected, square)
			hud.ask_promotion(state.side_to_move())
			return
		var m := state.find_move(_selected, square)
		if m != Move.NONE:
			play_move(m)
			return
	var p := state.board.piece_at(square)
	if p != Piece.NONE and Piece.color_of(p) == state.side_to_move() and square != _selected:
		_select(square)
	else:
		_select(-1)


func _on_promotion_chosen(type: int) -> void:
	var from := _pending_promotion.x
	var to := _pending_promotion.y
	_pending_promotion = Vector2i(-1, -1)
	if type == 0 or from == -1:
		_select(-1)
		return
	play_move(state.find_move(from, to, type))


func _is_human_turn() -> bool:
	if GameSettings.mode == GameSettings.Mode.VS_AI:
		return state.side_to_move() == GameSettings.human_color
	return true


func _select(square: int) -> void:
	if square != _selected:
		# The selected piece rises off its square.
		var animate := GameSettings.animations
		var old: Piece3D = _pieces.get(_selected)
		if old != null:
			old.set_lifted(false, animate)
		var picked: Piece3D = _pieces.get(square)
		if picked != null:
			picked.set_lifted(true, animate)
			sfx.play(Sfx.Sound.SELECT)
	_selected = square
	if square == -1:
		board_view.clear_selection()
	else:
		board_view.show_selection(square)
		board_view.show_targets(state.legal_moves_from(square))


# ------------------------------------------------------------------ moves ---

## Plays a legal move on the state and animates it. Returns false if the
## move was rejected.
func play_move(m: int) -> bool:
	var mover := state.side_to_move()
	if not state.make_move(m):
		return false
	_select(-1)
	_refresh_view()
	move_played.emit(m)
	_run_move(m, mover)
	return true


# Animates the move, then hands the turn over (game over / camera / AI).
func _run_move(m: int, mover: int) -> void:
	var duration := _animate_move(m, mover)
	if duration > 0.0:
		_busy = true
		await get_tree().create_timer(duration).timeout
		_busy = false
	if Move.is_promotion(m):
		var node: Piece3D = _pieces.get(Move.to_sq(m))
		if node != null and node.piece != (mover | Move.promotion(m)):
			node.setup(mover | Move.promotion(m), piece_set)
			if GameSettings.animations:
				Effects.flash(board_view, node.position)
				sfx.play(Sfx.Sound.PROMOTE)
	if not Move.is_capture(m) or duration <= 0.0:
		sfx.play(Sfx.Sound.CAPTURE if Move.is_capture(m) else Sfx.Sound.MOVE)
	_after_move()


func _after_move() -> void:
	var animate := GameSettings.animations
	var king: Piece3D = null
	if state.is_check():
		king = _pieces.get(state.board.king_square[Piece.color_index(state.side_to_move())])
	if state.is_game_over():
		if state.status == GameState.Status.CHECKMATE and king != null and animate:
			_play_checkmate(king)
		else:
			sfx.play(Sfx.Sound.CHECKMATE if state.status == GameState.Status.CHECKMATE
					else Sfx.Sound.GAME_OVER)
			hud.show_game_over(state)
		return
	if king != null and animate:
		king.shudder()
	if state.is_check():
		sfx.play(Sfx.Sound.CHECK)
	_point_camera_at_turn(true)
	_start_ai_if_needed()


# Moves the piece nodes for a move already played on the state. Returns how
# long the animation takes.
func _animate_move(m: int, mover: int) -> float:
	var animate := GameSettings.animations
	var from := Move.from_sq(m)
	var to := Move.to_sq(m)
	var node: Piece3D = _pieces.get(from)
	if node == null:
		_rebuild_pieces()
		return 0.0

	var start := node.position
	var duration := node.move_to(Board3D.square_to_local(to), animate, Move.is_capture(m))

	if Move.is_capture(m):
		var cap_sq := to
		if Move.is_en_passant(m):
			cap_sq = to - 16 if mover == Piece.WHITE else to + 16
		var victim: Piece3D = _pieces.get(cap_sq)
		if victim != null:
			_pieces.erase(cap_sq)
			# A knight lands on its victim; everything else knocks it flying.
			var style := Piece3D.CaptureStyle.CRUSH if Piece.type_of(node.piece) == Piece.KNIGHT \
					else Piece3D.CaptureStyle.KNOCK
			victim.struck.connect(_on_piece_struck.bind(Board3D.square_to_local(cap_sq), victim.piece))
			victim.capture_out(animate, duration * node.impact_fraction(),
					Board3D.square_to_local(cap_sq) - start, style)

	_pieces.erase(from)
	_pieces[to] = node

	if Move.is_castle(m):
		var rook_from := to + 1 if Move.is_castle_kingside(m) else to - 2
		var rook_to := to - 1 if Move.is_castle_kingside(m) else to + 1
		var rook: Piece3D = _pieces.get(rook_from)
		if rook != null:
			_pieces.erase(rook_from)
			_pieces[rook_to] = rook
			rook.move_to(Board3D.square_to_local(rook_to), animate)
	return duration


# A captured piece was just hit: the camera lunges at the square, the picture
# flashes and time stalls for an instant. The bigger the piece, the harder.
func _on_piece_struck(at: Vector3, victim: int) -> void:
	var weight: float = [0.0, 0.35, 0.6, 0.6, 0.75, 1.0, 1.0][Piece.type_of(victim)]
	camera_rig.shake(0.05 + 0.05 * weight)
	camera_rig.punch_in(at + Vector3.UP * 0.4, 0.16 + 0.14 * weight, 0.55 + 0.25 * weight)
	hud.impact_flash(0.10 + 0.14 * weight)
	sfx.play(Sfx.Sound.CAPTURE)
	_slow_motion(0.22, 0.07 + 0.08 * weight)


# Runs the game at `scale` speed for `real_seconds`, then back to normal.
func _slow_motion(scale: float, real_seconds: float) -> void:
	_slow_token += 1
	var token := _slow_token
	Engine.time_scale = scale
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	if token == _slow_token and not _is_cinematic_playing():
		Engine.time_scale = 1.0


# ---------------------------------------------------------------- checkmate ---

# The end of the king, in slow motion: the camera drops to a close, low,
# slowly circling shot while he falls, the bars of a film frame slide in,
# "Checkmate" slams onto the screen to drums, bell and horn - and then the
# result dialog unrolls and the view is handed back.
func _play_checkmate(king: Piece3D) -> void:
	_stop_cinematic()
	# He falls away from the piece that delivered mate.
	var from: Vector3 = Board3D.square_to_local(Move.to_sq(state.last_move()))
	var away := king.position - from
	king.topple(away)

	_slow_token += 1
	Engine.time_scale = 0.28
	sfx.play(Sfx.Sound.CHECKMATE)
	camera_rig.shake(0.09)
	hud.impact_flash(0.30, Color(1.0, 0.72, 0.45))
	hud.set_letterbox(true)
	hud.announce("Checkmate", "%s is victorious" % Piece.color_name(state.winner))
	# Look at where the king will lie, from the side he falls toward.
	var fall := Vector3(away.x, 0.0, away.z).normalized() * 0.45
	var side := 30.0 if fall.x >= 0.0 else -30.0
	camera_rig.cinematic(king.position + fall + Vector3.UP * 0.35, 17.0, 5.4, side, 9.0, 1.5)

	_cinematic = create_tween()
	if _cinematic.has_method("set_ignore_time_scale"):
		_cinematic.call("set_ignore_time_scale", true)
	_cinematic.tween_interval(1.5)
	_cinematic.tween_method(func(v: float) -> void: Engine.time_scale = v, 0.28, 1.0, 0.5)
	_cinematic.tween_interval(1.4)
	_cinematic.tween_callback(_finish_checkmate)


func _finish_checkmate() -> void:
	_cinematic = null
	Engine.time_scale = 1.0
	hud.set_letterbox(false)
	hud.hide_announcement()
	camera_rig.release(1.6)
	hud.show_game_over(state)


func _is_cinematic_playing() -> bool:
	return _cinematic != null and _cinematic.is_valid()


# Cuts the checkmate sequence short (undo, new game, leaving the scene).
func _stop_cinematic() -> void:
	if _is_cinematic_playing():
		_cinematic.kill()
	_cinematic = null
	_slow_token += 1
	Engine.time_scale = 1.0
	hud.set_letterbox(false, false)
	hud.hide_announcement(false)
	camera_rig.release(0.0)


## Takes back the last move (in a game against the computer: your last move
## and the computer's reply).
func undo_move() -> void:
	if _busy or state.ply_count() == 0:
		return
	_cancel_ai()
	var plies := 1
	if GameSettings.mode == GameSettings.Mode.VS_AI and _is_human_turn() and state.ply_count() >= 2:
		plies = 2
	for i in plies:
		state.undo()
	_reset_view()
	_start_ai_if_needed()


## Starts over from the standard position (or from a FEN).
func new_game(fen: String = Board.START_FEN) -> void:
	_cancel_ai()
	state.reset(fen)
	_reset_view(true)
	if GameSettings.animations:
		sfx.play(Sfx.Sound.START)
	_start_ai_if_needed()


# Resyncs everything visual with the state after a non-animated change.
func _reset_view(intro: bool = false) -> void:
	_stop_cinematic()
	_busy = false
	_pending_promotion = Vector2i(-1, -1)
	hud.hide_game_over()
	_select(-1)
	_rebuild_pieces(intro and GameSettings.animations)
	_refresh_view()
	_point_camera_at_turn(false)
	if state.is_game_over():
		hud.show_game_over(state)


func _point_camera_at_turn(after_move: bool) -> void:
	if GameSettings.mode == GameSettings.Mode.VS_AI:
		if not after_move:
			camera_rig.face_side(GameSettings.human_color)
	elif GameSettings.auto_rotate_camera:
		camera_rig.face_side(state.side_to_move())
	elif not after_move and state.ply_count() == 0:
		camera_rig.face_side(Piece.WHITE)


func _on_auto_rotate_toggled(enabled: bool) -> void:
	GameSettings.auto_rotate_camera = enabled
	if enabled:
		camera_rig.face_side(state.side_to_move())


func _go_to_menu() -> void:
	_cancel_ai()
	_stop_cinematic()
	if ResourceLoader.exists(MAIN_MENU_SCENE):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# --------------------------------------------------------------------- AI ---

## True while the computer is searching for its move.
func is_ai_thinking() -> bool:
	return _ai.is_thinking()


# Starts the engine (on its own thread) when it is the computer's turn.
func _start_ai_if_needed() -> void:
	if GameSettings.mode != GameSettings.Mode.VS_AI or state.is_game_over() or _is_human_turn():
		return
	_ai.think(state, GameSettings.ai_level)
	hud.set_thinking(true, state)


func _cancel_ai() -> void:
	if _ai.is_thinking():
		_ai.cancel()
		hud.set_thinking(false, state)


func _on_ai_move_ready(m: int, _info: Dictionary) -> void:
	hud.set_thinking(false, state)
	if m != Move.NONE and not state.is_game_over() and not _is_human_turn():
		play_move(m)


func _exit_tree() -> void:
	_ai.cancel()
	if _is_cinematic_playing():
		_cinematic.kill()
	Engine.time_scale = 1.0
	UiStyle.set_sword_cursor(false)


# ------------------------------------------------------------------- view ---

## Throws away all piece nodes and recreates them from the current position.
## With `intro`, the pieces drop onto the board in a wave from the center out.
func _rebuild_pieces(intro: bool = false) -> void:
	for node: Piece3D in _pieces.values():
		node.queue_free()
	_pieces.clear()
	for rank in 8:
		for file in 8:
			var square := rank * 16 + file
			var p := state.board.piece_at(square)
			if p == Piece.NONE:
				continue
			var node := Piece3D.new()
			node.setup(p, piece_set)
			node.position = Board3D.square_to_local(square)
			board_view.add_child(node)
			_pieces[square] = node
			if intro:
				var home_rank := rank if Piece.color_of(p) == Piece.WHITE else 7 - rank
				node.drop_in(0.05 + absf(file - 3.5) * 0.035 + home_rank * 0.05)


# Highlights and HUD.
func _refresh_view() -> void:
	var last := state.last_move()
	if last == Move.NONE:
		board_view.show_last_move(-1, -1)
	else:
		board_view.show_last_move(Move.from_sq(last), Move.to_sq(last))
	if state.is_check():
		board_view.show_check(state.board.king_square[Piece.color_index(state.side_to_move())])
	else:
		board_view.show_check(-1)
	hud.set_auto_rotate(GameSettings.auto_rotate_camera, GameSettings.mode == GameSettings.Mode.HOTSEAT)
	hud.refresh(state)


## Number of piece nodes on the board (for tests).
func piece_node_count() -> int:
	return _pieces.size()


## Plays a comma-separated list of UCI moves instantly (screenshots, tests).
func debug_play_moves(ucis: String) -> void:
	var was := GameSettings.animations
	GameSettings.animations = false
	for uci in ucis.split(",", false):
		var m := state.find_uci(uci.strip_edges())
		if m == Move.NONE or not play_move(m):
			push_warning("debug_play_moves: illegal move %s" % uci)
			break
	GameSettings.animations = was


## Selects a square as if clicked (screenshots).
func debug_select(square_name: String) -> void:
	_select(Board.sq_from_name(square_name))


## Opens the promotion picker (screenshots).
func debug_show_promotion() -> void:
	hud.ask_promotion(state.side_to_move())
