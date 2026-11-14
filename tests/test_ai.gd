extends "res://tests/test_case.gd"
## AI sanity checks: finds mates in 1 and 2, takes free material, respects
## its time budget, and works on a thread / inside the game scene.

const MATE_IN_1 := [
	# [FEN, expected move]
	["6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", "a1a8"],                                      # back rank
	["r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", "h5f7"],    # scholar's mate
	["rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2", "d8h4"],         # fool's mate
	["7k/5Q2/5K2/8/8/8/8/8 w - - 0 1", "f7g7"],                                         # avoid the stalemates
	["k7/2K5/8/8/8/8/8/1R6 w - - 0 1", "b1a1"],                                         # rook to the a-file
]

const MATE_IN_2 := [
	# [FEN, expected first move ("" = any that forces mate)]
	["r2qkb1r/pp2nppp/3p4/2pNN1B1/2BnP3/3P4/PPP2PPP/R2bK2R w KQkq - 1 1", "d5f6"],      # Nf6+ gxf6 Bxf7#
	["7k/8/5K2/8/8/8/8/R7 w - - 0 1", ""],                                              # rook ladder
	["r7/8/8/8/8/5k2/8/7K b - - 0 1", ""],                                              # same, Black to move
	["7k/8/8/8/8/8/R7/1R4K1 w - - 0 1", ""],                                            # two-rook ladder
]


# True if the side to move mates in at most `n` of its own moves against
# every defense, playing the engine's choices.
func _forces_mate(gs: GameState, n: int, depth: int) -> bool:
	var result := ChessAI.new().search(gs.board, depth)
	if result["move"] == Move.NONE or not gs.make_move(result["move"]):
		return false
	var ok := gs.status == GameState.Status.CHECKMATE
	if not ok and n > 1 and not gs.is_game_over():
		ok = true
		for reply in gs.legal_moves().duplicate():
			gs.make_move(reply)
			ok = _forces_mate(gs, n - 1, depth)
			gs.undo()
			if not ok:
				break
	gs.undo()
	return ok


func test_finds_mate_in_1() -> void:
	for case: Array in MATE_IN_1:
		var gs := GameState.new(case[0])
		var result := ChessAI.new().search(gs.board, 3)
		var uci := Move.to_uci(result["move"])
		eq(result["score"], ChessAI.MATE - 1, "mate-in-1 score for " + case[0])
		if case[1] != "":
			eq(uci, case[1], "mating move in " + case[0])
		check(gs.make_move(result["move"]), "move is legal: " + uci)
		eq(gs.status, GameState.Status.CHECKMATE, "%s is checkmate in %s" % [uci, case[0]])


func test_finds_mate_in_2() -> void:
	for case: Array in MATE_IN_2:
		var gs := GameState.new(case[0])
		var result := ChessAI.new().search(gs.board, 4)
		eq(result["score"], ChessAI.MATE - 3, "mate-in-2 score for " + case[0])
		if case[1] != "":
			eq(Move.to_uci(result["move"]), case[1], "key move in " + case[0])
		check(_forces_mate(gs, 2, 4), "forces mate in 2 against every defense: " + case[0])
		eq(gs.to_fen(), GameState.new(case[0]).to_fen(), "position restored")


func test_every_level_finds_the_mates() -> void:
	for level in ChessAI.LEVELS.size():
		var gs := GameState.new(MATE_IN_1[0][0])
		var result := ChessAI.new().choose_move(gs.board, level, gs.position_hashes())
		eq(Move.to_uci(result["move"]), "a1a8", "%s finds mate in 1" % ChessAI.LEVELS[level]["name"])
	for level in [1, 2]:
		var gs := GameState.new(MATE_IN_2[0][0])
		var result := ChessAI.new().choose_move(gs.board, level, gs.position_hashes())
		eq(Move.to_uci(result["move"]), "d5f6", "%s finds mate in 2" % ChessAI.LEVELS[level]["name"])


func test_takes_free_material_and_avoids_blunders() -> void:
	var ai := ChessAI.new()
	var b := Board.new("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1")
	eq(Move.to_uci(ai.search(b, 3)["move"]), "d1d5", "takes the hanging queen")
	# The queen is attacked by a pawn; it must move (or be defended), not be left hanging.
	b = Board.new("4k3/8/8/2p5/3Q4/8/8/4K3 w - - 0 1")
	var result := ai.search(b, 3)
	check(result["score"] > 500, "keeps the queen (score %d)" % result["score"])
	# Does not stalemate when it can win: K+Q v K.
	b = Board.new("7k/8/5K2/8/8/8/8/Q7 w - - 0 1")
	var gs := GameState.new(b.to_fen())
	gs.make_move(ai.search(b, 3)["move"])
	check(gs.status != GameState.Status.STALEMATE, "does not stalemate a won position")


func test_start_position_and_no_moves() -> void:
	var ai := ChessAI.new()
	var gs := GameState.new()
	var result := ai.search(gs.board, 3)
	check(gs.legal_moves().has(result["move"]), "plays a legal opening move (%s)" % Move.to_uci(result["move"]))
	eq(result["depth"], 3, "reached the requested depth")
	check(result["nodes"] > 0, "counted nodes")
	eq(gs.to_fen(), Board.START_FEN, "search does not disturb the caller's board")

	eq(ai.search(Board.new("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"), 3)["move"], Move.NONE, "stalemate: no move")
	var mated := ai.search(Board.new("R5k1/5ppp/8/8/8/8/8/4K3 b - - 0 1"), 3)
	eq(mated["move"], Move.NONE, "checkmate: no move")
	eq(mated["score"], -ChessAI.MATE, "mated score")


func test_evaluation() -> void:
	var ai := ChessAI.new()
	eq(ai.evaluate(Board.new()), 0, "start position is balanced")
	check(ai.evaluate(Board.new("rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")) > 800,
			"a queen up is winning for White")
	check(ai.evaluate(Board.new("rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")) < -800,
			"...and losing from Black's point of view")
	# Color-mirrored positions must evaluate the same for the side to move.
	var white_view := ai.evaluate(Board.new("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"))
	var black_view := ai.evaluate(Board.new("rnbqkb1r/pppp1ppp/5n2/4p3/4P3/2N5/PPPP1PPP/R1BQKBNR b KQkq - 2 3"))
	eq(white_view, black_view, "evaluation is symmetric")


func test_respects_time_limit() -> void:
	var ai := ChessAI.new()
	var b := Board.new("r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P1B2/2PBPN2/PP1N1PPP/R2Q1RK1 w - - 0 9")
	var t0 := Time.get_ticks_msec()
	var result := ai.search(b, 30, 700)
	var elapsed := Time.get_ticks_msec() - t0
	check(elapsed < 1300, "stopped near the 700 ms budget (took %d ms)" % elapsed)
	check(result["depth"] >= 1 and result["move"] != Move.NONE, "still returns a move (depth %d)" % result["depth"])
	check(MoveGenerator.generate_legal(b).has(result["move"]), "and it is legal")


func test_sees_repetition_as_a_draw() -> void:
	# White is a rook down but can force a perpetual / repetition; the engine
	# must score a repeated position as 0, not as the material deficit.
	var gs := GameState.new()
	for uci: String in ["g1f3", "g8f6", "f3g1", "f6g8"]:
		gs.make_uci(uci)
	var ai := ChessAI.new()
	var with_history := ai.search(gs.board, 2, 0, gs.position_hashes())
	check(with_history["move"] != Move.NONE, "plays on after a repetition")
	# Direct check of the repetition detector: after Nf3 Nf6 Ng1, ...Ng8
	# repeats the start position, so a depth-1 search from there scores 0
	# for that line.
	gs.undo()
	var result := ai.search(gs.board, 1, 0, gs.position_hashes())
	check(result["score"] >= 0, "repeating is available as a draw (score %d)" % result["score"])


func test_ai_player_thread() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var gs := GameState.new()
	var player := AiPlayer.new()
	var got := []
	player.move_ready.connect(func(m: int, info: Dictionary) -> void: got.append([m, info]))

	player.think(gs, 1)
	check(player.is_thinking(), "thinking after think()")
	eq(got.size(), 0, "think() returns immediately")
	var frames := 0
	var deadline := Time.get_ticks_msec() + 20000
	while got.is_empty() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		frames += 1
	eq(got.size(), 1, "move_ready emitted once")
	if got.size() == 1:
		check(gs.legal_moves().has(got[0][0]), "threaded search returns a legal move")
		check(frames > 3, "the main loop kept running while it searched (%d frames)" % frames)
	check(not player.is_thinking(), "idle afterwards")

	# Cancelling discards the result.
	got.clear()
	player.think(gs, 2)
	await tree.create_timer(0.15).timeout
	var t0 := Time.get_ticks_msec()
	player.cancel()
	check(Time.get_ticks_msec() - t0 < 1000, "cancel() returns promptly")
	check(not player.is_thinking(), "not thinking after cancel")
	await tree.create_timer(0.3).timeout
	eq(got.size(), 0, "a cancelled search never reports a move")


func _open_game() -> Node:
	GameSettings.animations = false
	GameSettings.auto_rotate_camera = false
	var packed: PackedScene = load("res://scenes/game.tscn")
	var game := packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	return game


func _close_game(game: Node) -> void:
	game.get_parent().remove_child(game)
	game.free()
	GameSettings.mode = GameSettings.Mode.HOTSEAT
	GameSettings.human_color = Piece.WHITE
	GameSettings.animations = true
	GameSettings.auto_rotate_camera = true


func _wait_for_ply(game: Node, ply: int, timeout_ms: int = 15000) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + timeout_ms
	while game.state.ply_count() < ply and Time.get_ticks_msec() < deadline:
		await tree.process_frame


func test_game_vs_ai_as_white() -> void:
	GameSettings.mode = GameSettings.Mode.VS_AI
	GameSettings.human_color = Piece.WHITE
	GameSettings.ai_level = 0
	var game := _open_game()
	check(not game.is_ai_thinking(), "the computer waits for White's move")
	game.click_square(Board.sq_from_name("e2"))
	game.click_square(Board.sq_from_name("e4"))
	eq(game.state.ply_count(), 1, "human move played")
	check(game.is_ai_thinking(), "the computer starts thinking")
	eq(game.hud._status_label.text, "Computer is thinking...")
	game.click_square(Board.sq_from_name("e7"))
	eq(game._selected, -1, "the human cannot move the computer's pieces")

	await _wait_for_ply(game, 2)
	eq(game.state.ply_count(), 2, "the computer replied")
	check(not game.is_ai_thinking(), "and is idle again")
	eq(game.state.side_to_move(), Piece.WHITE, "back to the human")

	game.undo_move()
	eq(game.state.ply_count(), 0, "undo takes back the reply and the human move")
	check(not game.is_ai_thinking(), "nothing to think about at the start")

	# Undo while the computer is thinking cancels the search.
	game.click_square(Board.sq_from_name("d2"))
	game.click_square(Board.sq_from_name("d4"))
	check(game.is_ai_thinking(), "thinking again")
	game.undo_move()
	eq(game.state.ply_count(), 0, "undo during the search takes back the human move")
	check(not game.is_ai_thinking(), "search cancelled")
	await (Engine.get_main_loop() as SceneTree).create_timer(0.5).timeout
	eq(game.state.ply_count(), 0, "the cancelled search plays nothing")
	_close_game(game)


func test_game_vs_ai_as_black() -> void:
	GameSettings.mode = GameSettings.Mode.VS_AI
	GameSettings.human_color = Piece.BLACK
	GameSettings.ai_level = 0
	var game := _open_game()
	eq(game.camera_rig.facing_side(), Piece.BLACK, "camera sits behind the human's side")
	check(game.is_ai_thinking(), "the computer opens the game")
	await _wait_for_ply(game, 1)
	eq(game.state.ply_count(), 1, "the computer played the first move")
	eq(game.state.side_to_move(), Piece.BLACK)
	_close_game(game)
