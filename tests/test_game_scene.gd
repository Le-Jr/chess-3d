extends "res://tests/test_case.gd"
## Smoke tests for the game scene: it loads, builds its nodes, and
## click-to-move drives the rules correctly. Runs headless.

var _scene: Node


func _open() -> Node:
	GameSettings.mode = GameSettings.Mode.HOTSEAT
	GameSettings.animations = false
	GameSettings.auto_rotate_camera = false
	var packed: PackedScene = load("res://scenes/game.tscn")
	_scene = packed.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(_scene)
	return _scene


func _close() -> void:
	if _scene != null:
		_scene.get_parent().remove_child(_scene)
		_scene.free()
		_scene = null
	GameSettings.animations = true
	GameSettings.auto_rotate_camera = true


func _sq(name: String) -> int:
	return Board.sq_from_name(name)


func test_scene_builds() -> void:
	var game := _open()
	check(game.board_view is Board3D, "has a Board3D")
	check(game.camera_rig is CameraRig, "has a CameraRig")
	check(game.camera_rig.camera is Camera3D, "rig has a camera")
	eq(game.piece_node_count(), 32, "32 piece nodes")
	check(game.get_node_or_null("WorldEnvironment") != null, "has a WorldEnvironment")
	check(game.get_node_or_null("Sun") != null, "has a key light")
	_close()


func test_camera_tilt() -> void:
	var game := _open()
	var cam: Camera3D = game.camera_rig.camera
	var forward := -cam.global_transform.basis.z
	var tilt := rad_to_deg(asin(-forward.y))
	check(tilt >= 55.0 and tilt <= 65.0, "camera tilt %.1f deg is within 55-65" % tilt)
	check(cam.global_position.z > 0.0, "camera starts behind White")
	game.camera_rig.face_side(Piece.BLACK, false)
	check(cam.global_position.z < 0.0, "face_side(BLACK) moves behind Black")
	eq(game.camera_rig.facing_side(), Piece.BLACK)
	_close()


func test_click_to_move() -> void:
	var game := _open()
	game.click_square(_sq("e2"))
	game.click_square(_sq("e4"))
	eq(game.state.to_fen(), "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "e2-e4 played")
	# Clicking an enemy piece or an illegal target does nothing.
	game.click_square(_sq("e4"))
	game.click_square(_sq("e5"))
	eq(game.state.ply_count(), 1, "black can't move white's pawn")
	# Re-selecting another own piece switches the selection.
	game.click_square(_sq("b8"))
	game.click_square(_sq("g8"))
	game.click_square(_sq("f6"))
	eq(game.state.san_history[1], "Nf6", "selection switched to the g8 knight")
	eq(game.piece_node_count(), 32)
	_close()


func test_captures_castling_en_passant_promotion_sync() -> void:
	var game := _open()
	game.debug_play_moves("e2e4,d7d5,e4d5,d8d5,g1f3,d5e4,f1e2,c8g4,e1g1")
	eq(game.piece_node_count(), 30, "two pieces captured")
	eq(game.state.board.piece_at(_sq("f1")), Piece.WHITE | Piece.ROOK, "rook castled")
	_assert_nodes_match(game)

	game.state.reset("4k3/1P6/8/3pP3/8/8/8/4K3 w - d6 0 1")
	game._rebuild_pieces()
	game.debug_play_moves("e5d6")
	eq(game.piece_node_count(), 4, "en passant removed the pawn node")
	_assert_nodes_match(game)
	_close()


func test_highlights() -> void:
	var game := _open()
	var hl: Dictionary = game.board_view.highlight_state()
	eq(hl["selected"], -1, "nothing selected at the start")
	eq(hl["last_to"], -1, "no last move at the start")

	game.click_square(_sq("e2"))
	hl = game.board_view.highlight_state()
	eq(hl["selected"], _sq("e2"), "selected square highlighted")
	eq(hl["dots"], [_sq("e3"), _sq("e4")] as Array[int], "dots on the legal targets")
	eq(hl["rings"], [] as Array[int], "no captures available")

	game.click_square(_sq("e4"))
	hl = game.board_view.highlight_state()
	eq(hl["selected"], -1, "selection cleared after the move")
	eq(hl["dots"], [] as Array[int], "markers cleared after the move")
	eq(hl["last_from"], _sq("e2"), "last move from")
	eq(hl["last_to"], _sq("e4"), "last move to")

	# Capture targets get rings; e.p. targets are empty squares so they get dots.
	game.debug_play_moves("d7d5")
	game.click_square(_sq("e4"))
	hl = game.board_view.highlight_state()
	eq(hl["rings"], [_sq("d5")] as Array[int], "ring on the capturable pawn")
	eq(hl["dots"], [_sq("e5")] as Array[int], "dot on the push square")

	# Clicking the selected piece again, or off the board, deselects.
	game.click_square(_sq("e4"))
	eq(game.board_view.highlight_state()["selected"], -1, "click again to deselect")
	game.click_square(_sq("e4"))
	game.click_square(-1)
	eq(game.board_view.highlight_state()["selected"], -1, "click off the board to deselect")
	_close()


func test_check_highlight() -> void:
	var game := _open()
	game.debug_play_moves("e2e4,f7f6,d1h5")
	eq(game.board_view.highlight_state()["check"], _sq("e8"), "checked king highlighted")
	game.debug_play_moves("g7g6")
	eq(game.board_view.highlight_state()["check"], -1, "highlight gone once the check is answered")
	_close()


func test_promotion_picker() -> void:
	var game := _open()
	game.new_game("3r4/1P6/8/8/8/8/8/4K2k w - - 0 1")
	game.click_square(_sq("b7"))
	game.click_square(_sq("b8"))
	check(game.hud.is_asking_promotion(), "picker opens")
	eq(game.state.ply_count(), 0, "nothing played until a piece is chosen")
	game.click_square(_sq("e1"))
	eq(game.state.ply_count(), 0, "board is locked while the picker is open")

	game.hud.choose_promotion(0)
	check(not game.hud.is_asking_promotion(), "picker closes on cancel")
	eq(game.state.ply_count(), 0, "cancel plays nothing")

	game.click_square(_sq("b7"))
	game.click_square(_sq("b8"))
	game.hud.choose_promotion(Piece.KNIGHT)
	eq(game.state.board.piece_at(_sq("b8")), Piece.WHITE | Piece.KNIGHT, "underpromotion to a knight")
	eq(game.state.san_history[0], "b8=N")
	_assert_nodes_match(game)

	# Promotion by capture.
	game.new_game("2r5/1P6/8/8/8/8/8/4K2k w - - 0 1")
	game.click_square(_sq("b7"))
	game.click_square(_sq("c8"))
	check(game.hud.is_asking_promotion(), "picker opens for a capturing promotion")
	game.hud.choose_promotion(Piece.QUEEN)
	eq(game.state.board.piece_at(_sq("c8")), Piece.WHITE | Piece.QUEEN, "promotion to a queen")
	eq(game.state.san_history[0], "bxc8=Q")
	eq(game.piece_node_count(), 3, "captured rook removed")
	_assert_nodes_match(game)
	_close()


func test_undo_and_new_game() -> void:
	var game := _open()
	game.debug_play_moves("e2e4,d7d5,e4d5")
	eq(game.piece_node_count(), 31)
	game.undo_move()
	eq(game.state.ply_count(), 2, "one ply undone in hot-seat")
	eq(game.piece_node_count(), 32, "captured pawn is back")
	_assert_nodes_match(game)
	eq(game.board_view.highlight_state()["last_to"], _sq("d5"), "last-move highlight follows the undo")

	game.undo_move()
	game.undo_move()
	game.undo_move()  # nothing left: must be a no-op
	eq(game.state.to_fen(), Board.START_FEN, "back at the start")
	eq(game.board_view.highlight_state()["last_to"], -1)

	game.debug_play_moves("g1f3")
	game.new_game()
	eq(game.state.ply_count(), 0, "new game resets the state")
	_assert_nodes_match(game)
	_close()


func test_game_over_dialog() -> void:
	var game := _open()
	check(not game.hud.is_game_over_visible(), "hidden during play")
	game.debug_play_moves("f2f3,e7e5,g2g4,d8h4")
	check(game.hud.is_game_over_visible(), "shown at checkmate")
	eq(game.hud._game_over_title.text, "Checkmate")
	eq(game.hud._game_over_detail.text, "Black wins")
	game.click_square(_sq("a2"))
	game.click_square(_sq("a3"))
	eq(game.state.ply_count(), 4, "no moves after the game is over")

	game.undo_move()
	check(not game.hud.is_game_over_visible(), "undo closes the dialog")
	eq(game.state.status, GameState.Status.ONGOING)

	game.new_game("7k/8/6K1/8/8/8/5Q2/8 w - - 0 1")
	game.debug_play_moves("f2f7")
	check(game.hud.is_game_over_visible(), "shown at stalemate")
	eq(game.hud._game_over_title.text, "Stalemate")

	game.new_game("4k3/8/8/8/8/8/8/R3K3 w - - 99 60")
	game.debug_play_moves("a1a2")
	eq(game.hud._game_over_title.text, "Draw")
	eq(game.hud._game_over_detail.text, "The 50-move rule")
	_close()


func test_hud_move_list_and_captures() -> void:
	var game := _open()
	check(game.hud._undo_button.disabled, "undo disabled with no moves")
	game.debug_play_moves("e2e4,d7d5,e4d5,d8d5,b1c3")
	var text: String = game.hud.move_list_text()
	for san: String in ["e4", "d5", "exd5", "Qxd5", "Nc3"]:
		check(text.contains(san), "move list shows %s (got: %s)" % [san, text])
	check(text.contains("3."), "move numbers shown")
	eq(game.hud._captured_by_white.text, UiStyle.glyph(Piece.PAWN), "white captured a pawn")
	eq(game.hud._captured_by_black.text, UiStyle.glyph(Piece.PAWN), "black captured a pawn")
	eq(game.hud._turn_label.text, "Black to move")
	check(not game.hud._undo_button.disabled, "undo enabled")

	game.debug_play_moves("d5g2")
	eq(game.hud._captured_by_black.text, UiStyle.glyph(Piece.PAWN) + UiStyle.glyph(Piece.PAWN) + "  +1",
			"material balance shown for the side ahead")
	_close()


func _screen_pos(game: Node, square: int, height: float = 0.0) -> Vector2:
	var local := Board3D.square_to_local(square) + Vector3(0.0, height, 0.0)
	return game.camera_rig.camera.unproject_position(game.board_view.to_global(local))


func _click_at(game: Node, screen_pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = screen_pos
		event.global_position = screen_pos
		game.get_viewport().push_input(event)


func test_mouse_picking_through_the_camera() -> void:
	var game := _open()
	var cam: Camera3D = game.camera_rig.camera
	# Every square center, projected to the screen and picked back.
	var wrong := 0
	for rank in 8:
		for file in 8:
			var s := Board.sq(file, rank)
			if game.board_view.pick_square(cam, _screen_pos(game, s)) != s:
				wrong += 1
	eq(wrong, 0, "all 64 square centers pick correctly from White's side")
	# Clicking the top of a tall piece picks that piece, not the square behind.
	eq(game.board_view.pick_square(cam, _screen_pos(game, Board.E1, 1.2), game.state.board), Board.E1,
			"clicking the king's crown picks e1")
	eq(game.board_view.pick_square(cam, Vector2(5, 5), game.state.board), -1, "clicking the table picks nothing")

	game.camera_rig.face_side(Piece.BLACK, false)
	wrong = 0
	for rank in 8:
		for file in 8:
			var s := Board.sq(file, rank)
			if game.board_view.pick_square(cam, _screen_pos(game, s)) != s:
				wrong += 1
	eq(wrong, 0, "all 64 square centers pick correctly from Black's side")
	game.camera_rig.face_side(Piece.WHITE, false)

	_close()


func test_animated_moves() -> void:
	var game := _open()
	var tree := Engine.get_main_loop() as SceneTree
	GameSettings.animations = true
	game.new_game("4k3/1P6/8/3p4/4P3/8/8/4K2R w K - 0 1")

	# A capture: the pawn lifts off, the board is locked meanwhile, and the
	# victim is gone when it is over.
	var pawn: Piece3D = game._pieces[_sq("e4")]
	var victim: Piece3D = game._pieces[_sq("d5")]
	game.click_square(_sq("e4"))
	game.click_square(_sq("d5"))
	check(game._busy, "input is locked while the move animates")
	var peak := 0.0
	for i in 12:
		await tree.process_frame
		peak = maxf(peak, pawn.position.y)
	check(peak > 0.05, "piece lifts off the board (peak %.2f)" % peak)
	game.click_square(_sq("e8"))
	eq(game._selected, -1, "clicks are ignored mid-animation")
	await tree.create_timer(1.1).timeout
	check(not game._busy, "unlocked after the animation")
	check(pawn.position.is_equal_approx(Board3D.square_to_local(_sq("d5"))), "pawn set down on d5")
	check(not is_instance_valid(victim) or victim.is_queued_for_deletion(), "captured pawn removed")

	# Castling moves both pieces; promotion swaps the model on arrival.
	game.debug_play_moves("e8d7")
	GameSettings.animations = true
	game.click_square(_sq("e1"))
	game.click_square(_sq("g1"))
	await tree.create_timer(0.9).timeout
	_assert_nodes_match(game)
	game.debug_play_moves("d7d6")
	GameSettings.animations = true
	game.click_square(_sq("b7"))
	game.click_square(_sq("b8"))
	game.hud.choose_promotion(Piece.ROOK)
	var promoted: Piece3D = game._pieces[_sq("b8")]
	eq(promoted.piece, Piece.WHITE | Piece.PAWN, "still a pawn while it travels")
	await tree.create_timer(0.9).timeout
	eq(promoted.piece, Piece.WHITE | Piece.ROOK, "becomes a rook on arrival")
	_assert_nodes_match(game)
	_close()


func test_auto_rotate_camera() -> void:
	var game := _open()
	GameSettings.auto_rotate_camera = true
	game.new_game()
	eq(game.camera_rig.facing_side(), Piece.WHITE, "starts behind White")
	game.debug_play_moves("e2e4")
	eq(game.camera_rig.facing_side(), Piece.BLACK, "swings to Black after White moves")
	game.debug_play_moves("e7e5")
	eq(game.camera_rig.facing_side(), Piece.WHITE, "and back")
	game.hud.auto_rotate_toggled.emit(false)
	game.debug_play_moves("g1f3")
	eq(game.camera_rig.facing_side(), Piece.WHITE, "stays put when the toggle is off")
	game.hud.flip_requested.emit()
	eq(game.camera_rig.facing_side(), Piece.BLACK, "flip button turns the board")
	_close()


# Every piece node must sit on the square the rules say it is on, and be the
# right piece.
func _assert_nodes_match(game: Node) -> void:
	var mismatches := 0
	var count := 0
	for rank in 8:
		for file in 8:
			var s := Board.sq(file, rank)
			var p: int = game.state.board.piece_at(s)
			var node: Piece3D = game._pieces.get(s)
			if p == Piece.NONE:
				if node != null:
					mismatches += 1
				continue
			count += 1
			if node == null or node.piece != p \
					or not node.position.is_equal_approx(Board3D.square_to_local(s)):
				mismatches += 1
	eq(mismatches, 0, "piece nodes match the position")
	eq(game.piece_node_count(), count, "no stray nodes")
