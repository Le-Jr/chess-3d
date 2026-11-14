extends "res://tests/test_case.gd"
## FEN import/export and Zobrist hashing.

const ROUND_TRIP := [
	"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
	"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
	"rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2",
	"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
	"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
	"r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
	"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
	"4k3/8/8/8/8/8/8/R3K3 w Q - 99 60",
	"8/8/8/8/8/5k2/8/5K2 b - - 12 87",
]

const INVALID := [
	"",
	"not a fen",
	"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1",            # 7 ranks
	"rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",   # bad digit
	"rnbqkbnr/ppppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",  # 9 files
	"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",   # bad side
	"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQxq - 0 1",   # bad castling
	"rnbq1bnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1",     # no black king
	"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKKNR w KQkq - 0 1",   # two white kings
	"P3k3/8/8/8/8/8/8/4K3 w - - 0 1",                             # pawn on rank 8
	"4k3/8/8/8/8/8/8/4K3 w - z9 0 1",                             # bad e.p. square
]


func test_round_trip() -> void:
	for fen: String in ROUND_TRIP:
		var b := Board.new()
		check(b.load_fen(fen), "loads: " + fen)
		eq(b.to_fen(), fen, "round trip")


func test_invalid_rejected() -> void:
	var b := Board.new(ROUND_TRIP[3])
	var before := b.to_fen()
	for fen: String in INVALID:
		check(not b.load_fen(fen), "rejects: '%s'" % fen)
	eq(b.to_fen(), before, "board untouched by rejected FENs")


func test_short_fen_defaults() -> void:
	var b := Board.new()
	check(b.load_fen("4k3/8/8/8/8/8/8/4K3 b"), "placement + side is enough")
	eq(b.to_fen(), "4k3/8/8/8/8/8/8/4K3 b - - 0 1", "defaults filled in")


func test_sanitizes_impossible_state() -> void:
	# Castling rights without the rook / king at home are dropped.
	var b := Board.new("4k2r/8/8/8/8/8/8/R3K3 w KQkq - 0 1")
	eq(b.to_fen(), "4k2r/8/8/8/8/8/8/R3K3 w Qk - 0 1", "bogus castling rights dropped")
	# An e.p. square with no pawn in front of it is dropped.
	b.load_fen("4k3/8/8/8/8/8/8/4K3 w - e6 0 1")
	eq(b.ep_square, -1, "bogus e.p. square dropped")


func test_square_names() -> void:
	eq(Board.sq_name(Board.A1), "a1")
	eq(Board.sq_name(Board.H8), "h8")
	eq(Board.sq_from_name("e4"), Board.sq(4, 3))
	eq(Board.sq_from_name("i4"), -1)
	eq(Board.sq_from_name("e9"), -1)
	eq(Board.sq_from_name("e"), -1)


func test_piece_placement() -> void:
	var b := Board.new()
	eq(b.piece_at(Board.E1), Piece.WHITE | Piece.KING)
	eq(b.piece_at(Board.sq(3, 7)), Piece.BLACK | Piece.QUEEN)
	eq(b.piece_at(Board.sq(4, 3)), Piece.NONE)
	eq(b.king_square[0], Board.E1)
	eq(b.king_square[1], Board.E8)


func test_incremental_hash_matches_full_hash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for game in 6:
		var b := Board.new()
		var played := PackedInt32Array()
		for ply in 150:
			var moves := MoveGenerator.generate_legal(b)
			if moves.is_empty():
				break
			var m := moves[rng.randi_range(0, moves.size() - 1)]
			b.make_move(m)
			played.append(m)
			if b.zobrist != b.compute_hash():
				check(false, "hash drift after %s (game %d, ply %d)" % [Move.to_uci(m), game, ply])
				return
		for i in range(played.size() - 1, -1, -1):
			b.unmake_move(played[i])
		eq(b.to_fen(), Board.START_FEN, "random game %d fully unmade" % game)
		eq(b.zobrist, Board.new().zobrist, "hash restored")
		eq(b.undo_depth(), 0, "undo stack empty")


func test_transpositions_share_a_hash() -> void:
	var a := GameState.new()
	for uci: String in ["g1f3", "g8f6", "b1c3", "b8c6"]:
		check(a.make_uci(uci), uci)
	var b := GameState.new()
	for uci: String in ["b1c3", "b8c6", "g1f3", "g8f6"]:
		check(b.make_uci(uci), uci)
	eq(a.board.zobrist, b.board.zobrist, "same position, different move order")
	check(a.board.zobrist != GameState.new().board.zobrist, "differs from the start position")


func test_clone_is_independent() -> void:
	var a := Board.new()
	var c := a.clone()
	c.make_move(MoveGenerator.generate_legal(c)[0])
	eq(a.to_fen(), Board.START_FEN, "original untouched")
	check(c.to_fen() != Board.START_FEN, "clone moved")
