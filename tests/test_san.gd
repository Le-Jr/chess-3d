extends "res://tests/test_case.gd"
## SAN generation and parsing.

const KIWIPETE := "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"


func _san(fen: String, uci: String) -> String:
	var gs := GameState.new(fen)
	var m := gs.find_uci(uci)
	if m == Move.NONE:
		return "<illegal %s>" % uci
	return San.move_to_san(gs.board, m)


func test_basic_moves() -> void:
	eq(_san(Board.START_FEN, "e2e4"), "e4")
	eq(_san(Board.START_FEN, "g1f3"), "Nf3")
	eq(_san(KIWIPETE, "d5e6"), "dxe6")
	eq(_san(KIWIPETE, "e5f7"), "Nxf7")
	eq(_san(KIWIPETE, "f3f6"), "Qxf6")


func test_castling() -> void:
	eq(_san(KIWIPETE, "e1g1"), "O-O")
	eq(_san(KIWIPETE, "e1c1"), "O-O-O")


func test_disambiguation() -> void:
	eq(_san("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "b1d2"), "Nbd2", "by file")
	eq(_san("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "f1d2"), "Nfd2", "by file")
	eq(_san("4k3/8/8/8/N7/8/N7/4K3 w - - 0 1", "a4c3"), "N4c3", "by rank")
	eq(_san("4k3/8/8/8/N7/8/N7/4K3 w - - 0 1", "a2c3"), "N2c3", "by rank")
	# Queens on e4, h4 and h1 can all reach e1; h4 shares a rank with one and
	# a file with the other, so the full square is needed.
	eq(_san("1k6/8/8/8/4Q2Q/8/8/K6Q w - - 0 1", "h4e1"), "Qh4e1", "by file and rank")
	# A pinned piece does not cause ambiguity: the d2 knight is pinned by the
	# d8 rook, so only the g1 knight can go to f3.
	eq(_san("3rk3/8/8/8/8/8/3N4/3K2N1 w - - 0 1", "g1f3"), "Nf3", "pinned twin ignored")


func test_en_passant_and_promotion() -> void:
	eq(_san("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1", "e5d6"), "exd6")
	eq(_san("8/4P1k1/8/8/8/8/8/4K3 w - - 0 1", "e7e8q"), "e8=Q")
	eq(_san("4k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8q"), "a8=Q+")
	eq(_san("4k3/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8n"), "a8=N")
	eq(_san("3r4/4P1k1/8/8/8/8/8/4K3 w - - 0 1", "e7d8r"), "exd8=R")


func test_check_and_mate_suffix() -> void:
	eq(_san("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "a1a8"), "Ra8+")
	eq(_san("6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1", "a1a8"), "Ra8#")


func test_parse() -> void:
	var b := Board.new(KIWIPETE)
	eq(Move.to_uci(San.san_to_move(b, "O-O")), "e1g1")
	eq(Move.to_uci(San.san_to_move(b, "0-0-0")), "e1c1")
	eq(Move.to_uci(San.san_to_move(b, "dxe6")), "d5e6")
	eq(Move.to_uci(San.san_to_move(b, "Nxf7!?")), "e5f7")
	eq(San.san_to_move(b, "Nf9"), Move.NONE, "nonsense rejected")
	eq(San.san_to_move(b, "Ke2"), Move.NONE, "illegal move rejected")
	eq(b.to_fen(), KIWIPETE, "parsing leaves the board untouched")


func test_game_move_list() -> void:
	var gs := GameState.new()
	var moves := ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Bxc6", "dxc6", "O-O", "Bg4"]
	for san: String in moves:
		check(gs.make_san(san), san)
	eq(Array(gs.san_history), moves, "SAN history matches what was played")
	eq(gs.to_fen(), "r2qkbnr/1pp2ppp/p1p5/4p3/4P1b1/5N2/PPPP1PPP/RNBQ1RK1 w kq - 2 6")
