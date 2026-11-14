class_name GameState
extends RefCounted
## A full game: a Board plus move history, SAN list, captured pieces and the
## game result (checkmate, stalemate and the automatic draws).
##
## This is the object the UI talks to. The AI searches on `board.clone()`.

enum Status {
	ONGOING,
	CHECKMATE,
	STALEMATE,
	DRAW_FIFTY_MOVE,
	DRAW_REPETITION,
	DRAW_INSUFFICIENT_MATERIAL,
}

var board: Board
var status: Status = Status.ONGOING
## Piece.WHITE / Piece.BLACK after a checkmate, otherwise 0.
var winner: int = 0
var start_fen: String = Board.START_FEN

## One entry per ply played.
var move_history := PackedInt32Array()
var san_history := PackedStringArray()
## Piece captured on each ply (Piece.NONE if the move was not a capture).
var captured_history := PackedInt32Array()

# Zobrist keys of every position reached, starting with the initial one.
var _hash_history := PackedInt64Array()
var _legal_cache := PackedInt32Array()
var _legal_valid := false


func _init(fen: String = Board.START_FEN) -> void:
	board = Board.new()
	reset(fen)


## Starts a new game from `fen`. Returns false (and starts from the standard
## position) if the FEN is invalid.
func reset(fen: String = Board.START_FEN) -> bool:
	var ok := board.load_fen(fen)
	if not ok:
		board.load_fen(Board.START_FEN)
	start_fen = board.to_fen()
	move_history.clear()
	san_history.clear()
	captured_history.clear()
	_hash_history.clear()
	_hash_history.append(board.zobrist)
	_legal_valid = false
	_update_status()
	return ok


# ---------------------------------------------------------------- queries ---

func side_to_move() -> int:
	return board.side_to_move


func is_check() -> bool:
	return MoveGenerator.in_check(board, board.side_to_move)


func is_game_over() -> bool:
	return status != Status.ONGOING


func is_draw() -> bool:
	return status != Status.ONGOING and status != Status.CHECKMATE


func ply_count() -> int:
	return move_history.size()


func last_move() -> int:
	return move_history[move_history.size() - 1] if not move_history.is_empty() else Move.NONE


func to_fen() -> String:
	return board.to_fen()


## Legal moves in the current position (cached until the position changes).
func legal_moves() -> PackedInt32Array:
	if not _legal_valid:
		_legal_cache = MoveGenerator.generate_legal(board)
		_legal_valid = true
	return _legal_cache


func legal_moves_from(square: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for m in legal_moves():
		if (m & 0x7F) == square:
			out.append(m)
	return out


## True if moving from -> to is a legal pawn promotion (the UI should then
## ask which piece and call find_move with it).
func needs_promotion(from: int, to: int) -> bool:
	for m in legal_moves():
		if Move.from_sq(m) == from and Move.to_sq(m) == to and Move.is_promotion(m):
			return true
	return false


## The legal move from -> to (with the given promotion piece type, 0 for
## none), or Move.NONE.
func find_move(from: int, to: int, promo: int = 0) -> int:
	for m in legal_moves():
		if Move.from_sq(m) == from and Move.to_sq(m) == to and Move.promotion(m) == promo:
			return m
	return Move.NONE


## The legal move for a UCI string like "e2e4" or "e7e8q", or Move.NONE.
func find_uci(uci: String) -> int:
	if uci.length() < 4 or uci.length() > 5:
		return Move.NONE
	var from := Board.sq_from_name(uci.substr(0, 2))
	var to := Board.sq_from_name(uci.substr(2, 2))
	if from == -1 or to == -1:
		return Move.NONE
	var promo := 0
	if uci.length() == 5:
		promo = Piece.type_of(Piece.from_char(uci[4]))
		if promo < Piece.KNIGHT or promo > Piece.QUEEN:
			return Move.NONE
	return find_move(from, to, promo)


## How many times the current position has occurred in this game.
func repetition_count() -> int:
	return _hash_history.count(board.zobrist)


## Zobrist keys of every position of the game so far, oldest first (the
## last one is the current position). The AI uses it to see repetitions.
func position_hashes() -> PackedInt64Array:
	return _hash_history.duplicate()


## Pieces captured BY `color` so far (i.e. pieces of the other color).
func captured_by(color: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in captured_history:
		if p != Piece.NONE and Piece.color_of(p) != color:
			out.append(p)
	return out


## "1-0", "0-1", "1/2-1/2" or "*".
func result_string() -> String:
	if status == Status.ONGOING:
		return "*"
	if status == Status.CHECKMATE:
		return "1-0" if winner == Piece.WHITE else "0-1"
	return "1/2-1/2"


func status_text() -> String:
	match status:
		Status.CHECKMATE:
			return "Checkmate - %s wins" % Piece.color_name(winner)
		Status.STALEMATE:
			return "Draw by stalemate"
		Status.DRAW_FIFTY_MOVE:
			return "Draw by the 50-move rule"
		Status.DRAW_REPETITION:
			return "Draw by threefold repetition"
		Status.DRAW_INSUFFICIENT_MATERIAL:
			return "Draw by insufficient material"
	var text := "%s to move" % Piece.color_name(board.side_to_move)
	if is_check():
		text += " (check)"
	return text


# ---------------------------------------------------------------- actions ---

## Plays a legal move. Returns false if the game is over or the move is not
## legal in the current position.
func make_move(m: int) -> bool:
	if status != Status.ONGOING or not legal_moves().has(m):
		return false
	var captured := board.squares[Move.to_sq(m)]
	if Move.is_en_passant(m):
		captured = (board.side_to_move ^ 24) | Piece.PAWN
	var san := San.move_to_san(board, m, legal_moves())

	board.make_move(m)
	move_history.append(m)
	san_history.append(san)
	captured_history.append(captured)
	_hash_history.append(board.zobrist)
	_legal_valid = false
	_update_status()
	return true


func make_uci(uci: String) -> bool:
	return make_move(find_uci(uci))


func make_san(san: String) -> bool:
	return make_move(San.san_to_move(board, san))


## Takes back the last ply. Returns false if there is nothing to undo.
func undo() -> bool:
	if move_history.is_empty():
		return false
	board.unmake_move(move_history[move_history.size() - 1])
	move_history.resize(move_history.size() - 1)
	san_history.resize(san_history.size() - 1)
	captured_history.resize(captured_history.size() - 1)
	_hash_history.resize(_hash_history.size() - 1)
	_legal_valid = false
	_update_status()
	return true


# --------------------------------------------------------------- internal ---

func _update_status() -> void:
	winner = 0
	if legal_moves().is_empty():
		if is_check():
			status = Status.CHECKMATE
			winner = board.side_to_move ^ 24
		else:
			status = Status.STALEMATE
	elif has_insufficient_material():
		status = Status.DRAW_INSUFFICIENT_MATERIAL
	elif repetition_count() >= 3:
		status = Status.DRAW_REPETITION
	elif board.halfmove_clock >= 100:
		status = Status.DRAW_FIFTY_MOVE
	else:
		status = Status.ONGOING


## Dead positions where no sequence of legal moves can give mate:
## K v K, K+minor v K, and kings with any number of same-colored bishops.
func has_insufficient_material() -> bool:
	var knights := 0
	var bishops := 0
	var bishop_square_colors := 0
	for rank in 8:
		for file in 8:
			var t := board.squares[rank * 16 + file] & 7
			if t == Piece.PAWN or t == Piece.ROOK or t == Piece.QUEEN:
				return false
			if t == Piece.KNIGHT:
				knights += 1
			elif t == Piece.BISHOP:
				bishops += 1
				bishop_square_colors |= 1 << ((rank + file) & 1)
	if knights + bishops <= 1:
		return true
	return knights == 0 and bishop_square_colors != 3
