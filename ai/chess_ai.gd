class_name ChessAI
extends RefCounted
## The built-in chess engine.
##
## Negamax with alpha-beta (principal variation search), iterative deepening,
## a transposition table, move ordering (hash move, MVV-LVA captures, killer
## moves, history heuristic), check extensions, late-move reductions and a
## capture-only quiescence search. Evaluation is material + piece-square
## tables, tapered between middlegame and endgame, with a small "mop-up" term
## so it can actually deliver mate in won endgames.
##
## A ChessAI instance is single-use-at-a-time and works on its own copy of
## the board, so it is safe to run on a Thread (see AiPlayer).

const MATE := 100000
const INFINITY := 1000000
## Scores beyond this are "mate in N" scores.
const MATE_THRESHOLD := MATE - 1000
const MAX_PLY := 96

## Difficulty presets: search depth, time budget, and (Easy only) how many
## centipawns worse than the best move a randomly chosen move may be.
const LEVELS := [
	{"name": "Easy", "depth": 2, "time_ms": 600, "noise": 90},
	{"name": "Medium", "depth": 5, "time_ms": 3000, "noise": 0},
	{"name": "Hard", "depth": 9, "time_ms": 5000, "noise": 0},
]

const PIECE_VALUE := [0, 100, 320, 330, 500, 900, 0]
# Game-phase weight per piece type; 24 = all pieces on the board.
const PHASE_WEIGHT := [0, 0, 1, 1, 2, 4, 0]

# Piece-square tables (Tomasz Michniewski's "simplified evaluation function"),
# written from White's point of view with rank 8 on the first row.
const PST_PAWN := [
	  0,   0,   0,   0,   0,   0,   0,   0,
	 50,  50,  50,  50,  50,  50,  50,  50,
	 10,  10,  20,  30,  30,  20,  10,  10,
	  5,   5,  10,  25,  25,  10,   5,   5,
	  0,   0,   0,  20,  20,   0,   0,   0,
	  5,  -5, -10,   0,   0, -10,  -5,   5,
	  5,  10,  10, -20, -20,  10,  10,   5,
	  0,   0,   0,   0,   0,   0,   0,   0,
]
const PST_KNIGHT := [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20,   0,   0,   0,   0, -20, -40,
	-30,   0,  10,  15,  15,  10,   0, -30,
	-30,   5,  15,  20,  20,  15,   5, -30,
	-30,   0,  15,  20,  20,  15,   0, -30,
	-30,   5,  10,  15,  15,  10,   5, -30,
	-40, -20,   0,   5,   5,   0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const PST_BISHOP := [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-10,   0,   5,  10,  10,   5,   0, -10,
	-10,   5,   5,  10,  10,   5,   5, -10,
	-10,   0,  10,  10,  10,  10,   0, -10,
	-10,  10,  10,  10,  10,  10,  10, -10,
	-10,   5,   0,   0,   0,   0,   5, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
const PST_ROOK := [
	  0,   0,   0,   0,   0,   0,   0,   0,
	  5,  10,  10,  10,  10,  10,  10,   5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	  0,   0,   0,   5,   5,   0,   0,   0,
]
const PST_QUEEN := [
	-20, -10, -10,  -5,  -5, -10, -10, -20,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-10,   0,   5,   5,   5,   5,   0, -10,
	 -5,   0,   5,   5,   5,   5,   0,  -5,
	  0,   0,   5,   5,   5,   5,   0,  -5,
	-10,   5,   5,   5,   5,   5,   0, -10,
	-10,   0,   5,   0,   0,   0,   0, -10,
	-20, -10, -10,  -5,  -5, -10, -10, -20,
]
const PST_KING_MIDDLE := [
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	 20,  20,   0,   0,   0,   0,  20,  20,
	 20,  30,  10,   0,   0,  10,  30,  20,
]
const PST_KING_END := [
	-50, -40, -30, -20, -20, -30, -40, -50,
	-30, -20, -10,   0,   0, -10, -20, -30,
	-30, -10,  20,  30,  30,  20, -10, -30,
	-30, -10,  30,  40,  40,  30, -10, -30,
	-30, -10,  30,  40,  40,  30, -10, -30,
	-30, -10,  20,  30,  30,  20, -10, -30,
	-30, -30,   0,   0,   0,   0, -30, -30,
	-50, -30, -30, -30, -30, -30, -30, -50,
]

const _TT_EXACT := 0
const _TT_LOWER := 1
const _TT_UPPER := 2
const _MOVE_MASK := 0x3FFFFF
const _TT_SCORE_OFFSET := 2000000
const _TT_MAX_ENTRIES := 600000

# Material + piece-square value, indexed by (piece << 7) | square, always
# from the piece owner's point of view.
static var _mg := PackedInt32Array()
static var _eg := PackedInt32Array()
static var _phase_weight := PackedInt32Array(PHASE_WEIGHT)

## Nodes visited by the last search.
var nodes := 0

var _b: Board
var _stop := false
var _timed := false
var _deadline := 0
var _tt := {}
var _killers := PackedInt32Array()
var _history := PackedInt32Array()
var _path := PackedInt64Array()
var _root_move := Move.NONE
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	ensure_tables()
	_rng.randomize()


## Asks a running search to return as soon as possible (thread-safe enough:
## it is a single flag the search polls).
func stop() -> void:
	_stop = true


## Picks a move at a difficulty level (index into LEVELS). `history` is the
## list of Zobrist keys of the game so far (GameState.position_hashes()),
## used to avoid / seek draws by repetition.
func choose_move(board: Board, level: int, history: PackedInt64Array = PackedInt64Array()) -> Dictionary:
	var params: Dictionary = LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	var result := search(board, params["depth"], params["time_ms"], history)
	if params["noise"] > 0 and result["move"] != Move.NONE and absi(result["score"]) < MATE_THRESHOLD:
		result["move"] = _noisy_pick(params["noise"], result["move"])
	return result


## Iterative-deepening search. Returns {"move", "score", "depth", "nodes",
## "time_ms"}; "move" is Move.NONE only when there is no legal move. The
## score is in centipawns from the side to move's point of view.
func search(board: Board, max_depth: int, time_ms: int = 0,
		history: PackedInt64Array = PackedInt64Array()) -> Dictionary:
	_b = board.clone()
	_stop = false
	_timed = false
	nodes = 0
	_tt.clear()
	_killers.resize(MAX_PLY * 2)
	_killers.fill(0)
	_history.resize(128 * 128)
	_history.fill(0)
	_path = history.duplicate()
	if _path.is_empty() or _path[_path.size() - 1] != _b.zobrist:
		_path.append(_b.zobrist)

	var started := Time.get_ticks_msec()
	_deadline = started + time_ms

	var best_move := Move.NONE
	var best_score := 0
	var reached := 0
	for depth in range(1, max_depth + 1):
		_root_move = Move.NONE
		var score := _negamax(depth, -INFINITY, INFINITY, 0)
		if _stop:
			# An interrupted iteration still searched the previous best move
			# first, so a move it preferred over that one is trustworthy.
			if _root_move != Move.NONE:
				best_move = _root_move
			break
		best_move = _root_move
		best_score = score
		reached = depth
		if best_move == Move.NONE:
			break  # checkmate or stalemate at the root
		if absi(score) >= MATE_THRESHOLD and depth >= MATE - absi(score):
			break  # found a forced mate; deeper search cannot improve it
		# Depth 1 always completes; after that the clock applies.
		_timed = time_ms > 0
		if _timed and Time.get_ticks_msec() - started > time_ms * 0.5:
			break  # the next iteration would not finish in time anyway

	return {
		"move": best_move,
		"score": best_score,
		"depth": reached,
		"nodes": nodes,
		"time_ms": Time.get_ticks_msec() - started,
	}


# ----------------------------------------------------------------- search ---

func _negamax(depth: int, alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if (nodes & 1023) == 0 and _timed and Time.get_ticks_msec() >= _deadline:
		_stop = true
	if _stop:
		return 0

	var b := _b
	if ply > 0 and (b.halfmove_clock >= 100 or _is_repetition()):
		return 0
	if ply >= MAX_PLY - 1:
		return _evaluate()

	var us := b.side_to_move
	var them := us ^ 24
	var ci := us >> 4
	var in_check := MoveGenerator.is_square_attacked(b, b.king_square[ci], them)
	if in_check:
		depth += 1
	if depth <= 0:
		return _quiesce(alpha, beta, ply)

	var key := b.zobrist
	var tt_move := Move.NONE
	var entry: int = _tt.get(key, 0)
	if entry != 0:
		tt_move = entry & _MOVE_MASK
		if ply > 0 and ((entry >> 22) & 0x3F) >= depth:
			var tt_score := (entry >> 30) - _TT_SCORE_OFFSET
			if tt_score >= MATE_THRESHOLD:
				tt_score -= ply
			elif tt_score <= -MATE_THRESHOLD:
				tt_score += ply
			var tt_flag := (entry >> 28) & 3
			if tt_flag == _TT_EXACT \
					or (tt_flag == _TT_LOWER and tt_score >= beta) \
					or (tt_flag == _TT_UPPER and tt_score <= alpha):
				return tt_score

	var keys := _order(MoveGenerator.generate_pseudo_legal(b), tt_move, ply)
	var alpha_orig := alpha
	var best := -INFINITY
	var best_move := Move.NONE
	var legal := 0
	var i := keys.size() - 1
	while i >= 0:
		var m: int = keys[i] & _MOVE_MASK
		i -= 1
		b.make_move(m)
		if MoveGenerator.is_square_attacked(b, b.king_square[ci], them):
			b.unmake_move(m)
			continue
		legal += 1
		_path.append(b.zobrist)

		var score: int
		if legal == 1:
			score = -_negamax(depth - 1, -beta, -alpha, ply + 1)
		else:
			# Late quiet moves are searched shallower with a null window
			# first; anything that beats alpha gets a proper re-search.
			var reduction := 0
			if depth >= 3 and legal > 4 and not in_check and (m >> 14) == 0:
				reduction = 1
			score = -_negamax(depth - 1 - reduction, -alpha - 1, -alpha, ply + 1)
			if score > alpha and reduction > 0:
				score = -_negamax(depth - 1, -alpha - 1, -alpha, ply + 1)
			if score > alpha and score < beta:
				score = -_negamax(depth - 1, -beta, -alpha, ply + 1)

		_path.resize(_path.size() - 1)
		b.unmake_move(m)
		if _stop:
			return 0

		if score > best:
			best = score
			best_move = m
			if score > alpha:
				alpha = score
				if ply == 0:
					_root_move = m
				if alpha >= beta:
					if (m >> 14) == 0:  # quiet move caused the cutoff
						if _killers[ply * 2] != m:
							_killers[ply * 2 + 1] = _killers[ply * 2]
							_killers[ply * 2] = m
						var h := (m & 0x7F) * 128 + ((m >> 7) & 0x7F)
						_history[h] = mini(_history[h] + depth * depth, 200000)
					break

	if legal == 0:
		return -MATE + ply if in_check else 0
	if ply == 0 and _root_move == Move.NONE:
		_root_move = best_move

	var flag := _TT_EXACT
	if best <= alpha_orig:
		flag = _TT_UPPER
	elif best >= beta:
		flag = _TT_LOWER
	var stored := best
	if stored >= MATE_THRESHOLD:
		stored += ply
	elif stored <= -MATE_THRESHOLD:
		stored -= ply
	if _tt.size() >= _TT_MAX_ENTRIES:
		_tt.clear()
	_tt[key] = best_move | (mini(depth, 63) << 22) | (flag << 28) | ((stored + _TT_SCORE_OFFSET) << 30)
	return best


# Captures and promotions only, until the position is quiet.
func _quiesce(alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if (nodes & 1023) == 0 and _timed and Time.get_ticks_msec() >= _deadline:
		_stop = true
	if _stop:
		return 0

	var stand := _evaluate()
	if stand >= beta or ply >= MAX_PLY - 1:
		return stand
	if stand > alpha:
		alpha = stand

	var b := _b
	var us := b.side_to_move
	var them := us ^ 24
	var ci := us >> 4
	var keys := _order(MoveGenerator.generate_pseudo_legal(b, true), Move.NONE, ply)
	var i := keys.size() - 1
	while i >= 0:
		var m: int = keys[i] & _MOVE_MASK
		i -= 1
		b.make_move(m)
		if MoveGenerator.is_square_attacked(b, b.king_square[ci], them):
			b.unmake_move(m)
			continue
		var score := -_quiesce(-beta, -alpha, ply + 1)
		b.unmake_move(m)
		if _stop:
			return 0
		if score > alpha:
			alpha = score
			if alpha >= beta:
				break
	return alpha


# Returns sort keys (score << 22 | move); iterate from the end for best-first.
func _order(moves: PackedInt32Array, tt_move: int, ply: int) -> PackedInt64Array:
	var keys := PackedInt64Array()
	var count := moves.size()
	keys.resize(count)
	var sqs := _b.squares
	var k1 := _killers[ply * 2]
	var k2 := _killers[ply * 2 + 1]
	for i in count:
		var m := moves[i]
		var s: int
		if m == tt_move:
			s = 1000000
		elif (m >> 17) & 1:
			# MVV-LVA: most valuable victim first, least valuable attacker first.
			var victim := sqs[(m >> 7) & 0x7F] & 7
			if victim == 0:
				victim = Piece.PAWN  # en passant
			s = 500000 + victim * 16 - (sqs[m & 0x7F] & 7) + ((m >> 14) & 7) * 128
		elif (m >> 14) & 7:
			s = 400000 + ((m >> 14) & 7)
		elif m == k1:
			s = 300000
		elif m == k2:
			s = 299999
		else:
			s = _history[(m & 0x7F) * 128 + ((m >> 7) & 0x7F)]
		keys[i] = (s << 22) | m
	keys.sort()
	return keys


# True if the current position already occurred (in the game or earlier in
# this search line). One repetition is treated as a draw.
func _is_repetition() -> bool:
	var n := _path.size()
	var key := _b.zobrist
	var limit := maxi(0, n - 1 - _b.halfmove_clock)
	var i := n - 3
	while i >= limit:
		if _path[i] == key:
			return true
		i -= 2
	return false


# Easy mode: score every root move with a shallow search and pick randomly
# among those within `noise` centipawns of the best.
func _noisy_pick(noise: int, fallback: int) -> int:
	_stop = false
	_timed = false
	var b := _b
	var scored: Array[Vector2i] = []
	var best := -INFINITY
	for m in MoveGenerator.generate_legal(b):
		b.make_move(m)
		_path.append(b.zobrist)
		var score := -_negamax(1, -INFINITY, INFINITY, 1)
		_path.resize(_path.size() - 1)
		b.unmake_move(m)
		scored.append(Vector2i(m, score))
		best = maxi(best, score)
	if scored.is_empty() or best >= MATE_THRESHOLD:
		return fallback
	var candidates: Array[int] = []
	for entry in scored:
		if entry.y >= best - noise:
			candidates.append(entry.x)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


# ------------------------------------------------------------- evaluation ---

## Static evaluation of a position in centipawns, from the side to move's
## point of view.
func evaluate(board: Board) -> int:
	_b = board
	return _evaluate()


func _evaluate() -> int:
	var b := _b
	var sqs := b.squares
	var mg := 0
	var eg := 0
	var phase := 0
	var white_bishops := 0
	var black_bishops := 0
	var phase_weight := _phase_weight
	for rank in 8:
		var base := rank * 16
		for file in 8:
			var s := base + file
			var p := sqs[s]
			if p == 0:
				continue
			var idx := (p << 7) | s
			var t := p & 7
			if p & 8:
				mg += _mg[idx]
				eg += _eg[idx]
				if t == Piece.BISHOP:
					white_bishops += 1
			else:
				mg -= _mg[idx]
				eg -= _eg[idx]
				if t == Piece.BISHOP:
					black_bishops += 1
			phase += phase_weight[t]

	if white_bishops >= 2:
		mg += 30
		eg += 40
	if black_bishops >= 2:
		mg -= 30
		eg -= 40

	# Mop-up: when clearly winning with few pieces left, drive the losing
	# king to the edge and bring our king next to it.
	if phase <= 8 and absi(eg) >= 300:
		var winner_king := b.king_square[0] if eg > 0 else b.king_square[1]
		var loser_king := b.king_square[1] if eg > 0 else b.king_square[0]
		var lf := loser_king & 7
		var lr := loser_king >> 4
		var edge := maxi(3 - lf, lf - 4) + maxi(3 - lr, lr - 4)
		var apart := absi((winner_king & 7) - lf) + absi((winner_king >> 4) - lr)
		var bonus := edge * 12 + (14 - apart) * 5
		eg += bonus if eg > 0 else -bonus

	if phase > 24:
		phase = 24
	@warning_ignore("integer_division")
	var score := (mg * phase + eg * (24 - phase)) / 24
	return score if b.side_to_move == Piece.WHITE else -score


## Builds the evaluation tables. Called automatically; call it yourself on
## the main thread before starting searches on other threads.
static func ensure_tables() -> void:
	if not _mg.is_empty():
		return
	var mg := PackedInt32Array()
	var eg := PackedInt32Array()
	mg.resize(32 * 128)
	eg.resize(32 * 128)
	var mid_tables := [[], PST_PAWN, PST_KNIGHT, PST_BISHOP, PST_ROOK, PST_QUEEN, PST_KING_MIDDLE]
	var end_tables := [[], PST_PAWN, PST_KNIGHT, PST_BISHOP, PST_ROOK, PST_QUEEN, PST_KING_END]
	for type in range(Piece.PAWN, Piece.KING + 1):
		for rank in 8:
			for file in 8:
				var s := rank * 16 + file
				var white_idx := (7 - rank) * 8 + file
				var black_idx := rank * 8 + file
				var value: int = PIECE_VALUE[type]
				mg[((Piece.WHITE | type) << 7) | s] = value + mid_tables[type][white_idx]
				eg[((Piece.WHITE | type) << 7) | s] = value + end_tables[type][white_idx]
				mg[((Piece.BLACK | type) << 7) | s] = value + mid_tables[type][black_idx]
				eg[((Piece.BLACK | type) << 7) | s] = value + end_tables[type][black_idx]
	_eg = eg
	_mg = mg  # assigned last: it is the "tables are ready" marker
