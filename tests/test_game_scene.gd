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
	check(absf(tilt - GameSettings.camera_pitch) < 2.0,
			"camera tilt %.1f deg follows the setting (%.0f)" % [tilt, GameSettings.camera_pitch])
	check(tilt >= 40.0 and tilt <= 65.0, "the default view is angled, not top-down")
	# The HUD slider changes the angle and the setting.
	var before := GameSettings.camera_pitch
	game.hud.camera_pitch_changed.emit(30.0)
	game.camera_rig.snap()
	forward = -cam.global_transform.basis.z
	check(absf(rad_to_deg(asin(-forward.y)) - 30.0) < 2.0, "the slider lowers the camera")
	eq(GameSettings.camera_pitch, 30.0, "and is remembered")
	game.hud.camera_pitch_changed.emit(before)
	game.camera_rig.snap()
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


func _has_effect(game: Node, effect_name: String) -> bool:
	for child in game.board_view.get_children():
		if String(child.name).contains(effect_name) and not child.is_queued_for_deletion():
			return true
	return false


func test_capture_effects() -> void:
	var game := _open()
	var tree := Engine.get_main_loop() as SceneTree
	GameSettings.animations = true
	game.new_game("4k3/8/8/3p4/8/2N5/8/4K2R w K - 0 1")

	# The pieces drop in at the start of a game without leaving their squares.
	var rook: Piece3D = game._pieces[_sq("h1")]
	check(rook.get_child(0).position.y > 1.0, "pieces start above the board")
	check(rook.position.is_equal_approx(Board3D.square_to_local(_sq("h1"))), "but the node is on its square")
	await tree.create_timer(1.0).timeout
	check(absf(rook.get_child(0).position.y) < 0.001, "and land on it")

	# Selecting lifts the piece; deselecting sets it down.
	game.click_square(_sq("h1"))
	await tree.create_timer(0.3).timeout
	check(rook.get_child(0).position.y > 0.1, "selected piece is lifted")
	game.click_square(-1)
	await tree.create_timer(0.3).timeout
	check(absf(rook.get_child(0).position.y) < 0.001, "and set down again")

	# A knight capture: the victim is crushed on its own square, with debris.
	var victim: Piece3D = game._pieces[_sq("d5")]
	var hits := [0]
	victim.struck.connect(func() -> void: hits[0] += 1)
	game.click_square(_sq("c3"))
	game.click_square(_sq("d5"))
	check(not _has_effect(game, "CaptureFx"), "no debris before the blow lands")
	await tree.create_timer(0.72).timeout
	eq(hits[0], 1, "the victim is struck once")
	check(_has_effect(game, "CaptureFx"), "debris spawned on impact")
	check(is_instance_valid(victim) and victim.scale.y < 0.2, "crushed flat under the knight")
	check(victim.position.is_equal_approx(Board3D.square_to_local(_sq("d5"))), "without leaving its square")
	await tree.create_timer(1.6).timeout
	check(not is_instance_valid(victim), "victim freed")
	check(not _has_effect(game, "CaptureFx"), "debris cleans itself up")
	_assert_nodes_match(game)

	# Any other piece knocks its victim away, along the line of the attack.
	game.new_game("4k3/8/8/8/3p4/8/8/3RK3 w - - 0 1")
	victim = game._pieces[_sq("d4")]
	game.click_square(_sq("d1"))
	game.click_square(_sq("d4"))
	await tree.create_timer(0.62).timeout
	check(is_instance_valid(victim) and victim.position.z < Board3D.square_to_local(_sq("d4")).z - 0.2,
			"victim is thrown away from the attacker")
	await tree.create_timer(1.0).timeout
	check(not is_instance_valid(victim), "and removed")
	_assert_nodes_match(game)
	_close()


func test_checkmate_topples_the_king() -> void:
	var game := _open()
	var tree := Engine.get_main_loop() as SceneTree
	game.debug_play_moves("f2f3,e7e5,g2g4")
	GameSettings.animations = true
	var king: Piece3D = game._pieces[_sq("e1")]
	game.click_square(_sq("d8"))
	game.click_square(_sq("h4"))
	# The checkmate sequence: slow motion, film bars, a banner, a close shot.
	await tree.create_timer(0.75).timeout
	check(Engine.time_scale < 0.5, "time slows down for the mate (scale %.2f)" % Engine.time_scale)
	check(game.hud.is_letterboxed(), "film bars slide in")
	check(game.hud.is_announcing(), "the banner is up")
	eq(game.hud._banner.text, "Checkmate")
	eq(game.hud._banner_sub.text, "Black is victorious")
	check(game.camera_rig.is_in_cinematic(), "the camera flies to the king")
	check(not game.hud.is_game_over_visible(), "the dialog waits for the shot to play out")
	var cam: Camera3D = game.camera_rig.camera
	check(cam.global_position.distance_to(king.global_position) < 9.0, "and gets close to him")
	# Wait for the sequence in real time (it ignores the slowed clock).
	var waited := 0
	while not game.hud.is_game_over_visible() and waited < 600:
		await tree.process_frame
		waited += 1
		OS.delay_msec(10)
	check(game.hud.is_game_over_visible(), "then the game-over dialog is shown")
	eq(Engine.time_scale, 1.0, "and time runs normally again")
	await tree.create_timer(1.2).timeout
	check(king.basis.y.y < 0.2, "the mated king lies on its side (up.y = %.2f)" % king.basis.y.y)
	check(not game.hud.is_letterboxed(), "the bars are gone")

	# Undo in the middle of a new sequence cuts it short.
	game.undo_move()
	king = game._pieces[_sq("e1")]
	check(king.basis.y.y > 0.99, "undo stands the king back up")
	GameSettings.animations = true
	game.click_square(_sq("d8"))
	game.click_square(_sq("h4"))
	await tree.create_timer(0.75).timeout
	check(Engine.time_scale < 0.5, "the sequence starts again")
	game.undo_move()
	eq(Engine.time_scale, 1.0, "undo restores normal time at once")
	check(not game.hud.is_announcing() and not game.camera_rig.is_in_cinematic(), "and ends the shot")
	_close()
	eq(Engine.time_scale, 1.0, "leaving the scene never leaves time slowed")


func test_capture_zoom() -> void:
	var game := _open()
	var tree := Engine.get_main_loop() as SceneTree
	GameSettings.animations = true
	game.new_game("4k3/8/8/8/3q4/8/8/3RK3 w - - 0 1")
	await tree.create_timer(1.0).timeout
	var cam: Camera3D = game.camera_rig.camera
	var target: Vector3 = game.board_view.to_global(Board3D.square_to_local(_sq("d4")))
	var rest := cam.global_position.distance_to(target)
	game.click_square(_sq("d1"))
	game.click_square(_sq("d4"))
	var closest := rest
	var slowest := 1.0
	var peak := 0.0
	for i in 90:
		await tree.process_frame
		OS.delay_msec(8)
		closest = minf(closest, cam.global_position.distance_to(target))
		slowest = minf(slowest, Engine.time_scale)
		peak = maxf(peak, game.camera_rig.effect_weight())
	check(peak > 0.5, "the camera pushes in on the capture (weight %.2f)" % peak)
	check(closest < rest - 1.0, "getting closer to the square (%.1f -> %.1f)" % [rest, closest])
	check(slowest < 0.5, "time stalls on the blow")
	await tree.create_timer(1.5).timeout
	eq(Engine.time_scale, 1.0, "and resumes")
	check(game.camera_rig.effect_weight() < 0.01, "the camera returns to its seat")
	_close()


func test_sword_cursor() -> void:
	var plain := UiStyle.cursor_image(false)
	eq(plain.get_size(), Vector2i(UiStyle.CURSOR_SIZE, UiStyle.CURSOR_SIZE), "cursor size")
	var tip := plain.get_pixel(int(UiStyle.CURSOR_HOTSPOT.x) + 2, int(UiStyle.CURSOR_HOTSPOT.y) + 2)
	check(tip.a > 0.5, "the blade starts at the hotspot")
	eq(plain.get_pixel(UiStyle.CURSOR_SIZE - 2, 1).a, 0.0, "the corners are transparent")
	var glowing := UiStyle.cursor_image(true)
	var extra := 0
	for y in UiStyle.CURSOR_SIZE:
		for x in UiStyle.CURSOR_SIZE:
			if glowing.get_pixel(x, y).a > 0.05 and plain.get_pixel(x, y).a <= 0.05:
				extra += 1
	check(extra > 100, "the hover cursor has a halo (%d px)" % extra)


func test_sound_effects_are_generated() -> void:
	for sound: int in Sfx.Sound.values():
		var stream := Sfx.stream_for(sound)
		check(stream.data.size() > 2000, "sound %d has samples" % sound)
		var peak := 0
		for i in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		check(peak > 3000 and peak <= 32767, "sound %d is audible and not clipped (peak %d)" % [sound, peak])
	var game := _open()
	check(game.sfx is Sfx, "the game scene has its sound player")
	_close()


func test_camera_shake_settles() -> void:
	var game := _open()
	var tree := Engine.get_main_loop() as SceneTree
	var cam: Camera3D = game.camera_rig.camera
	var rest := cam.h_offset
	game.camera_rig.shake(0.1)
	await tree.process_frame
	await tree.process_frame
	check(absf(cam.h_offset - rest) > 0.0001 or absf(cam.v_offset) > 0.0001, "shake moves the view")
	await tree.create_timer(0.8).timeout
	check(absf(cam.h_offset - rest) < 0.0001 and absf(cam.v_offset) < 0.0001, "and dies out")
	_close()


func test_layout_modes_and_ui_scale() -> void:
	eq(UiLayout.mode_for(Vector2(1280, 800), false), int(UiLayout.Mode.WIDE), "desktop window")
	eq(UiLayout.mode_for(Vector2(2400, 1080), true), int(UiLayout.Mode.COMPACT), "phone held sideways")
	eq(UiLayout.mode_for(Vector2(1080, 2400), true), int(UiLayout.Mode.PORTRAIT), "phone held upright")
	eq(UiLayout.mode_for(Vector2(600, 900), false), int(UiLayout.Mode.PORTRAIT), "a tall desktop window too")
	var base := Vector2(1280, 800)
	eq(UiLayout.scale_for(Vector2(1920, 1080), false, base), 1.0, "desktop UI is not enlarged")
	# On touch screens the short side ends up 480 UI pixels, either way up.
	for size: Vector2 in [Vector2(2400, 1080), Vector2(1080, 2400), Vector2(1280, 800)]:
		var stretch := minf(size.x / base.x, size.y / base.y)
		var factor := UiLayout.scale_for(size, true, base)
		var short_ui := minf(size.x, size.y) / (stretch * factor)
		check(absf(short_ui - 480.0) < 0.5, "%s: short side is %.0f UI px" % [size, short_ui])
		check(factor >= 1.0, "%s: the UI only ever grows (x%.2f)" % [size, factor])


func test_hud_rearranges_for_portrait() -> void:
	var game := _open()
	game.debug_play_moves("e2e4,d7d5,e4d5")
	var hud: Hud = game.hud
	eq(hud.layout(), int(UiLayout.Mode.WIDE), "starts in the desktop layout")
	check(hud._panel.anchor_left == 1.0, "panel hugs the right edge")

	game._on_layout(UiLayout.Mode.PORTRAIT)
	eq(hud.layout(), int(UiLayout.Mode.PORTRAIT))
	check(hud._panel.anchor_left == 0.0 and hud._panel.anchor_right == 1.0 and hud._panel.anchor_top == 1.0,
			"panel spans the bottom edge")
	eq(hud._turn_label.text, "Black to move", "the rebuilt panel shows the same state")
	check(hud.move_list_text().contains("exd5"), "move list carried over")
	check(hud._captured_by_white.text.begins_with(UiStyle.glyph(Piece.PAWN)), "captured pieces carried over")
	check(not hud._undo_button.disabled, "undo still enabled")
	check(game.camera_rig.fit_width, "the camera frames the board by the window's width")
	eq(game.camera_rig.camera.keep_aspect, Camera3D.KEEP_WIDTH)
	check(game.camera_rig.camera.v_offset < -0.1, "and lifts the board above the panel")
	check(absf(game.camera_rig.camera.h_offset) < 0.001, "with no sideways shift")

	# The buttons of the rebuilt panel still work.
	hud._undo_button.pressed.emit()
	eq(game.state.ply_count(), 2, "undo from the portrait panel")

	game._on_layout(UiLayout.Mode.COMPACT)
	check(hud._panel.anchor_left == 1.0, "sideways: back to a side panel")
	check(hud._panel.size.x < Hud.PANEL_WIDTH or hud._panel.offset_left > -(Hud.PANEL_WIDTH + Hud.PANEL_MARGIN),
			"a narrower one")
	check(not game.camera_rig.fit_width and game.camera_rig.camera.h_offset > 0.1, "camera shifts sideways again")
	game._on_layout(UiLayout.Mode.WIDE)
	eq(game.camera_rig.camera.keep_aspect, Camera3D.KEEP_HEIGHT)
	_close()


func _touch(game: Node, index: int, pos: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	# Already in viewport coordinates (the headless window is not 1280 x 800).
	game.get_viewport().push_input(event, true)


func _drag(game: Node, index: int, from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to
	event.relative = to - from
	game.get_viewport().push_input(event, true)


func test_touch_controls() -> void:
	var game := _open()
	var rig: CameraRig = game.camera_rig
	# A tap selects, a second tap moves.
	# (Aim at the pawn's body: from this angle its base is hidden behind the king.)
	var e2 := _screen_pos(game, _sq("e2"), 0.4)
	var e4 := _screen_pos(game, _sq("e4"))
	_touch(game, 0, e2, true)
	eq(game._selected, -1, "nothing happens until the finger lifts")
	_touch(game, 0, e2, false)
	eq(game._selected, _sq("e2"), "tap selects the pawn")
	_touch(game, 0, e4, true)
	_touch(game, 0, e4 + Vector2(3, -2), false)
	eq(game.state.ply_count(), 1, "second tap plays the move (a little finger wobble is fine)")

	# The mouse events the engine synthesizes from touches are ignored.
	var fake := InputEventMouseButton.new()
	fake.device = InputEvent.DEVICE_ID_EMULATION
	fake.button_index = MOUSE_BUTTON_LEFT
	fake.pressed = true
	fake.position = _screen_pos(game, _sq("e7"))
	game.get_viewport().push_input(fake, true)
	eq(game._selected, -1, "emulated mouse click does not act a second time")

	# Dragging one finger orbits the camera and is not a tap.
	var e7 := _screen_pos(game, _sq("e7"), 0.4)
	var yaw_before: float = rig._yaw_offset
	_touch(game, 0, e7, true)
	_drag(game, 0, e7, e7 + Vector2(60, 0))
	_touch(game, 0, e7 + Vector2(60, 0), false)
	eq(game._selected, -1, "a drag does not select the piece under it")
	check(absf(rig._yaw_offset - yaw_before) > 5.0, "it turns the camera (%.1f deg)" % (rig._yaw_offset - yaw_before))

	# Pinching zooms: fingers apart = closer, together = further.
	var mid := Vector2(500, 400)
	var zoom_before: float = rig._target_distance
	_touch(game, 0, mid - Vector2(50, 0), true)
	_touch(game, 1, mid + Vector2(50, 0), true)
	_drag(game, 1, mid + Vector2(50, 0), mid + Vector2(52, 0))
	_drag(game, 1, mid + Vector2(52, 0), mid + Vector2(120, 0))
	check(rig._target_distance < zoom_before - 1.0, "spreading two fingers zooms in (%.1f -> %.1f)" % [
			zoom_before, rig._target_distance])
	var zoomed: float = rig._target_distance
	_drag(game, 1, mid + Vector2(120, 0), mid + Vector2(40, 0))
	check(rig._target_distance > zoomed + 0.5, "pinching zooms out")
	_touch(game, 1, mid + Vector2(40, 0), false)
	_touch(game, 0, mid - Vector2(50, 0), false)
	eq(game._selected, -1, "lifting the fingers of a pinch is not a tap")
	eq(game.state.ply_count(), 1, "and plays nothing")
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
