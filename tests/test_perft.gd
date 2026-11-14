extends "res://tests/test_case.gd"
## Perft: node counts of the legal move tree, compared against the published
## reference values (https://www.chessprogramming.org/Perft_Results).
## Depths marked "full" only run with `-- --full` (they take minutes in GDScript).

const KIWIPETE := "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
const POSITION_3 := "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
const POSITION_4 := "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
const POSITION_4_MIRROR := "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1"
const POSITION_5 := "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
const POSITION_6 := "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"


func _run(fen: String, expected: Array, full_expected: Array = []) -> void:
	var b := Board.new(fen)
	eq(b.to_fen(), fen, "FEN loads")
	var counts := expected.duplicate()
	if full:
		counts.append_array(full_expected)
	for i in counts.size():
		var depth := i + 1
		eq(MoveGenerator.perft(b, depth), counts[i], "perft(%d)" % depth)
	eq(b.to_fen(), fen, "board restored after perft")


func test_start_position() -> void:
	_run(Board.START_FEN, [20, 400, 8902, 197281], [4865609])


func test_kiwipete() -> void:
	_run(KIWIPETE, [48, 2039, 97862], [4085603])


func test_position_3() -> void:
	_run(POSITION_3, [14, 191, 2812, 43238], [674624])


func test_position_4() -> void:
	_run(POSITION_4, [6, 264, 9467], [422333])


func test_position_4_mirrored() -> void:
	_run(POSITION_4_MIRROR, [6, 264, 9467], [422333])


func test_position_5() -> void:
	_run(POSITION_5, [44, 1486, 62379], [2103487])


func test_position_6() -> void:
	_run(POSITION_6, [46, 2079, 89890], [3894594])
