extends "res://tests/test_case.gd"
## Rules: castling conditions, en passant (including pins), check/mate,
## stalemate and the automatic draws.

const CASTLE_BOTH := "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"


func _can(gs: GameState, uci: String) -> bool:
	return gs.find_uci(uci) != Move.NONE


func _play(gs: GameState, ucis: Array) -> void:
	for uci: String in ucis:
		check(gs.make_uci(uci), "move %s is legal" % uci)


# --------------------------------------------------------------- castling ---

func test_castling_available() -> void:
	var gs := GameState.new(CASTLE_BOTH)
	check(_can(gs, "e1g1"), "white O-O")
	check(_can(gs, "e1c1"), "white O-O-O")
	gs.reset("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
	check(_can(gs, "e8g8"), "black O-O")
	check(_can(gs, "e8c8"), "black O-O-O")


func test_castling_moves_the_rook() -> void:
	var gs := GameState.new(CASTLE_BOTH)
	_play(gs, ["e1g1", "e8c8"])
	eq(gs.to_fen(), "2kr3r/8/8/8/8/8/8/R4RK1 w - - 2 2", "both sides castled")
	check(gs.undo() and gs.undo(), "undo both")
	eq(gs.to_fen(), CASTLE_BOTH, "castling undone")


func test_no_castling_out_of_check() -> void:
	var gs := GameState.new("r3k2r/8/8/8/8/4r3/8/R3K2R w KQkq - 0 1")
	check(gs.is_check(), "king is in check")
	check(not _can(gs, "e1g1"), "no O-O out of check")
	check(not _can(gs, "e1c1"), "no O-O-O out of check")


func test_no_castling_through_check() -> void:
	var gs := GameState.new("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
	check(not _can(gs, "e1g1"), "f1 attacked: no O-O")
	check(_can(gs, "e1c1"), "O-O-O unaffected")
	gs.reset("r3k2r/8/8/8/8/3r4/8/R3K2R w KQkq - 0 1")
	check(_can(gs, "e1g1"), "O-O unaffected")
	check(not _can(gs, "e1c1"), "d1 attacked: no O-O-O")


func test_no_castling_into_check() -> void:
	var gs := GameState.new("r3k2r/8/8/8/8/6r1/8/R3K2R w KQkq - 0 1")
	check(not _can(gs, "e1g1"), "g1 attacked: no O-O")
	check(_can(gs, "e1c1"), "O-O-O unaffected")
	gs.reset("r3k2r/8/8/8/8/2r5/8/R3K2R w KQkq - 0 1")
	check(not _can(gs, "e1c1"), "c1 attacked: no O-O-O")


func test_castling_allowed_when_only_rook_or_b_file_attacked() -> void:
	var gs := GameState.new("4k3/8/8/8/8/1r6/8/R3K2R w KQ - 0 1")
	check(_can(gs, "e1c1"), "b1 attacked: O-O-O still legal")
	gs.reset("4k3/8/8/8/8/r6r/8/R3K2R w KQ - 0 1")
	check(_can(gs, "e1c1"), "a1 rook attacked: O-O-O still legal")
	check(_can(gs, "e1g1"), "h1 rook attacked: O-O still legal")


func test_no_castling_through_pieces() -> void:
	var gs := GameState.new("r3k2r/8/8/8/8/8/8/RN2K1NR w KQkq - 0 1")
	check(not _can(gs, "e1g1"), "g1 occupied")
	check(not _can(gs, "e1c1"), "b1 occupied")
	gs.reset("r2bk2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
	check(not _can(gs, "e8c8"), "d8 occupied")
	check(_can(gs, "e8g8"), "black O-O fine")


func test_castling_rights_lost_after_king_moves() -> void:
	var gs := GameState.new(CASTLE_BOTH)
	_play(gs, ["e1e2", "e8e7", "e2e1", "e7e8"])
	eq(gs.to_fen(), "r3k2r/8/8/8/8/8/8/R3K2R w - - 4 3", "kings back home, rights gone")
	check(not _can(gs, "e1g1"), "no O-O after king moved")
	check(not _can(gs, "e1c1"), "no O-O-O after king moved")


func test_castling_rights_lost_after_rook_moves_or_is_captured() -> void:
	var gs := GameState.new(CASTLE_BOTH)
	_play(gs, ["a1b1"])
	eq(gs.to_fen(), "r3k2r/8/8/8/8/8/8/1R2K2R b Kkq - 1 1", "a1 rook moved: Q gone")
	_play(gs, ["h8h1"])
	eq(gs.to_fen(), "r3k3/8/8/8/8/8/8/1R2K2r w q - 0 2", "h1 captured by h8 rook: K and k gone")
	check(gs.undo() and gs.undo(), "undo both")
	eq(gs.to_fen(), CASTLE_BOTH, "rights restored by undo")


# ------------------------------------------------------------- en passant ---

func test_en_passant_capture() -> void:
	var gs := GameState.new("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	check(_can(gs, "e5d6"), "exd6 e.p. is legal")
	_play(gs, ["e5d6"])
	eq(gs.to_fen(), "4k3/8/3P4/8/8/8/8/4K3 b - - 0 1", "captured pawn removed")
	eq(gs.captured_by(Piece.WHITE), PackedInt32Array([Piece.BLACK | Piece.PAWN]), "capture recorded")
	check(gs.undo(), "undo")
	eq(gs.to_fen(), "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e.p. undone")


func test_en_passant_only_immediately() -> void:
	var gs := GameState.new("4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1")
	_play(gs, ["d7d5"])
	eq(gs.board.ep_square, Board.sq_from_name("d6"), "e.p. square set after double push")
	check(_can(gs, "e5d6"), "e.p. available right away")
	_play(gs, ["e1e2", "e8e7"])
	check(not _can(gs, "e5d6"), "e.p. gone one move later")


func test_en_passant_horizontal_pin() -> void:
	# Capturing would remove both pawns from the 5th rank and expose the
	# king on a5 to the rook on h5.
	var gs := GameState.new("8/8/8/K2pP2r/8/8/8/4k3 w - d6 0 1")
	check(not _can(gs, "e5d6"), "e.p. illegal: discovered check along the rank")
	check(_can(gs, "e5e6"), "pawn can still push")


func test_en_passant_file_pin() -> void:
	var gs := GameState.new("4r1k1/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	check(not _can(gs, "e5d6"), "e.p. illegal: pawn pinned on the e-file")
	check(_can(gs, "e5e6"), "pinned pawn can move along the pin")


func test_en_passant_diagonal_pin() -> void:
	# The e5 pawn is pinned by the h8 bishop against the king on b2; both the
	# e.p. capture and the push would leave the a1-h8 diagonal.
	var gs := GameState.new("6kb/8/8/3pP3/8/8/1K6/8 w - d6 0 1")
	check(not _can(gs, "e5d6"), "e.p. illegal: pawn pinned on the long diagonal")
	check(not _can(gs, "e5e6"), "push illegal too")


func test_en_passant_can_capture_the_checking_pawn() -> void:
	# White just played c2-c4+, the only way to deal with the pawn is e.p.
	var gs := GameState.new("8/8/8/1k6/2Pp4/8/8/4K3 b - c3 0 1")
	check(gs.is_check(), "black is in check from the c4 pawn")
	check(_can(gs, "d4c3"), "e.p. capture of the checking pawn is legal")


# ------------------------------------------------------- mate / stalemate ---

func test_fools_mate() -> void:
	var gs := GameState.new()
	for san: String in ["f3", "e5", "g4", "Qh4"]:
		check(gs.make_san(san), san)
	eq(gs.status, GameState.Status.CHECKMATE, "checkmate detected")
	eq(gs.winner, Piece.BLACK, "black wins")
	eq(gs.result_string(), "0-1")
	eq(gs.san_history[3], "Qh4#", "SAN carries the mate mark")
	check(not gs.make_uci("a2a3"), "no moves after the game is over")
	check(gs.undo(), "undo the mate")
	eq(gs.status, GameState.Status.ONGOING, "game continues after undo")


func test_back_rank_mate() -> void:
	var gs := GameState.new("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1")
	_play(gs, ["a1a8"])
	eq(gs.status, GameState.Status.CHECKMATE)
	eq(gs.winner, Piece.WHITE)


func test_stalemate() -> void:
	var gs := GameState.new("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	eq(gs.status, GameState.Status.STALEMATE, "queen stalemate")
	eq(gs.legal_moves().size(), 0)
	check(not gs.is_check(), "not in check")
	eq(gs.result_string(), "1/2-1/2")

	gs.reset("5k2/5P2/5K2/8/8/8/8/8 b - - 0 1")
	eq(gs.status, GameState.Status.STALEMATE, "pawn stalemate")


func test_stalemate_reached_by_a_move() -> void:
	var gs := GameState.new("7k/8/6K1/8/8/8/5Q2/8 w - - 0 1")
	_play(gs, ["f2f7"])
	eq(gs.status, GameState.Status.STALEMATE)
	eq(gs.winner, 0)


func test_not_stalemate_when_another_piece_can_move() -> void:
	var gs := GameState.new("7k/5Q2/6K1/8/8/8/p7/8 b - - 0 1")
	eq(gs.status, GameState.Status.ONGOING, "the a-pawn can still move")
	eq(gs.legal_moves().size(), 4, "a1=Q/R/B/N")


func test_check_must_be_answered() -> void:
	var gs := GameState.new("4k3/8/8/8/8/8/4r3/R3K3 w Q - 0 1")
	check(gs.is_check(), "in check")
	# Only Kxe2, Kd1, Kf1 (d2/f2 are covered by the rook).
	eq(gs.legal_moves().size(), 3, "only king moves answer the check")


# ------------------------------------------------------------------ draws ---

func test_fifty_move_rule() -> void:
	var gs := GameState.new("4k3/8/8/8/8/8/8/R3K3 w - - 99 60")
	eq(gs.status, GameState.Status.ONGOING, "99 half-moves: still playing")
	_play(gs, ["a1a2"])
	eq(gs.status, GameState.Status.DRAW_FIFTY_MOVE, "100 half-moves: draw")
	check(gs.is_draw())


func test_fifty_move_counter_resets() -> void:
	var gs := GameState.new("4k3/7p/8/8/8/8/8/R3K3 b - - 99 60")
	_play(gs, ["h7h6"])
	eq(gs.status, GameState.Status.ONGOING, "pawn move resets the counter")
	eq(gs.board.halfmove_clock, 0)


func test_threefold_repetition() -> void:
	var gs := GameState.new()
	_play(gs, ["g1f3", "g8f6", "f3g1", "f6g8"])
	eq(gs.repetition_count(), 2, "start position seen twice")
	eq(gs.status, GameState.Status.ONGOING)
	_play(gs, ["g1f3", "g8f6", "f3g1", "f6g8"])
	eq(gs.repetition_count(), 3, "start position seen three times")
	eq(gs.status, GameState.Status.DRAW_REPETITION)
	check(gs.undo(), "undo")
	eq(gs.status, GameState.Status.ONGOING, "undo leaves the drawn state")


func test_insufficient_material() -> void:
	var dead := [
		"4k3/8/8/8/8/8/8/4K3 w - - 0 1",        # K v K
		"4k3/8/8/8/8/8/8/4KB2 w - - 0 1",       # K+B v K
		"4k3/8/8/8/8/8/8/4KN2 w - - 0 1",       # K+N v K
		"4kb2/8/8/8/8/8/8/4KB2 w - - 0 1",      # K+B v K+B, bishops on different colors
	]
	eq(GameState.new(dead[0]).status, GameState.Status.DRAW_INSUFFICIENT_MATERIAL, "K v K")
	eq(GameState.new(dead[1]).status, GameState.Status.DRAW_INSUFFICIENT_MATERIAL, "KB v K")
	eq(GameState.new(dead[2]).status, GameState.Status.DRAW_INSUFFICIENT_MATERIAL, "KN v K")
	# f1 is a light square, f8 a dark one: mate is still possible in theory.
	eq(GameState.new(dead[3]).status, GameState.Status.ONGOING, "KB v KB, opposite-colored bishops")
	# c1 and f8 are both dark squares.
	eq(GameState.new("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1").status,
			GameState.Status.DRAW_INSUFFICIENT_MATERIAL, "KB v KB, same-colored bishops")

	var alive := [
		"4k3/8/8/8/8/8/8/4KR2 w - - 0 1",
		"4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
		"4k3/8/8/8/8/8/8/3NKN2 w - - 0 1",
		"4k3/8/8/8/8/8/8/3BKN2 w - - 0 1",
	]
	for fen: String in alive:
		eq(GameState.new(fen).status, GameState.Status.ONGOING, "playable: " + fen)


func test_capture_into_insufficient_material() -> void:
	var gs := GameState.new("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
	_play(gs, ["e1e2"])
	eq(gs.status, GameState.Status.DRAW_INSUFFICIENT_MATERIAL, "KxR leaves bare kings")


# ------------------------------------------------------------- game state ---

func test_promotion() -> void:
	var gs := GameState.new("3r4/4P1k1/8/8/8/8/8/4K3 w - - 0 1")
	check(gs.needs_promotion(Board.sq_from_name("e7"), Board.sq_from_name("e8")), "push promotes")
	check(gs.needs_promotion(Board.sq_from_name("e7"), Board.sq_from_name("d8")), "capture promotes")
	eq(gs.find_move(Board.sq_from_name("e7"), Board.sq_from_name("e8")), Move.NONE,
			"a promotion needs a piece choice")
	eq(gs.legal_moves_from(Board.sq_from_name("e7")).size(), 8, "4 pieces x 2 targets")
	_play(gs, ["e7d8n"])
	eq(gs.to_fen(), "3N4/6k1/8/8/8/8/8/4K3 b - - 0 1", "underpromotion with capture")
	check(gs.undo(), "undo")
	eq(gs.to_fen(), "3r4/4P1k1/8/8/8/8/8/4K3 w - - 0 1", "pawn and rook restored")


func test_undo_whole_game() -> void:
	var gs := GameState.new()
	var line := ["e2e4", "d7d5", "e4d5", "d8d5", "b1c3", "d5a5", "d2d4", "g8f6", "g1f3", "c8g4",
			"f1e2", "b8c6", "e1g1", "e8c8"]
	_play(gs, line)
	eq(gs.ply_count(), line.size())
	eq(gs.captured_by(Piece.WHITE).size(), 1, "white captured one pawn")
	eq(gs.captured_by(Piece.BLACK).size(), 1, "black captured one pawn")
	while gs.undo():
		pass
	eq(gs.to_fen(), Board.START_FEN, "back at the start")
	eq(gs.ply_count(), 0)
	eq(gs.san_history.size(), 0)
	check(not gs.undo(), "nothing left to undo")


func test_illegal_moves_rejected() -> void:
	var gs := GameState.new()
	check(not gs.make_uci("e2e5"), "pawn can't jump three squares")
	check(not gs.make_uci("e7e5"), "not black's turn")
	check(not gs.make_uci("e1e2"), "square occupied by own piece")
	check(not gs.make_move(Move.NONE), "null move")
	eq(gs.ply_count(), 0, "nothing was played")
