class_name Board
extends RefCounted
## Position representation on a 0x88 board, with make/unmake and FEN.
##
## Square index = rank * 16 + file (a1 = 0x00, h1 = 0x07, a8 = 0x70, h8 = 0x77).
## An index is off the board when `index & 0x88` is non-zero.
## Pure logic: no Node dependencies, safe to use from a worker thread as long
## as each thread works on its own Board (see `clone()`).

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8

const A1 := 0x00
const E1 := 0x04
const H1 := 0x07
const A8 := 0x70
const E8 := 0x74
const H8 := 0x77

const _UNDO_STRIDE := 5

var squares := PackedInt32Array()
var side_to_move: int = Piece.WHITE
var castling: int = 0
## En-passant target square, or -1.
var ep_square: int = -1
var halfmove_clock: int = 0
var fullmove_number: int = 1
## King squares, indexed by color index (0 = white, 1 = black).
var king_square := PackedInt32Array([E1, E8])
## Zobrist key of the position (pieces, side, castling rights, capturable e.p.).
var zobrist: int = 0

var _undo := PackedInt64Array()

static var _zob_piece := PackedInt64Array()
static var _zob_castle := PackedInt64Array()
static var _zob_ep := PackedInt64Array()
static var _zob_side: int = 0
static var _castle_mask := PackedInt32Array()


func _init(fen: String = START_FEN) -> void:
	_ensure_tables()
	squares.resize(128)
	if not load_fen(fen):
		load_fen(START_FEN)


# ---------------------------------------------------------------- squares ---

static func sq(file: int, rank: int) -> int:
	return rank * 16 + file


static func file_of(square: int) -> int:
	return square & 7


static func rank_of(square: int) -> int:
	return square >> 4


static func is_on_board(square: int) -> bool:
	return (square & 0x88) == 0


## "e4" for a square index.
static func sq_name(square: int) -> String:
	return "abcdefgh"[square & 7] + str((square >> 4) + 1)


## Square index for "e4", or -1 if the name is invalid.
static func sq_from_name(name: String) -> int:
	if name.length() != 2:
		return -1
	var f := name.unicode_at(0) - 97
	var r := name.unicode_at(1) - 49
	if f < 0 or f > 7 or r < 0 or r > 7:
		return -1
	return r * 16 + f


func piece_at(square: int) -> int:
	return squares[square]


# -------------------------------------------------------------------- FEN ---

## Loads a FEN string. Returns false (leaving the board untouched) if the FEN
## is malformed. Castling rights and the e.p. square are sanitized: rights
## without king/rook on their home squares and impossible e.p. squares are
## dropped.
func load_fen(fen: String) -> bool:
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 2:
		return false

	var new_sq := PackedInt32Array()
	new_sq.resize(128)
	var rows := parts[0].split("/")
	if rows.size() != 8:
		return false
	var kings := [-1, -1]
	var king_count := [0, 0]
	for i in 8:
		var rank := 7 - i
		var file := 0
		for ch: String in rows[i]:
			if ch.is_valid_int():
				var n := ch.to_int()
				if n < 1 or n > 8:
					return false
				file += n
			else:
				var p := Piece.from_char(ch)
				if p == Piece.NONE or file > 7:
					return false
				if (p & 7) == Piece.PAWN and (rank == 0 or rank == 7):
					return false
				new_sq[rank * 16 + file] = p
				if (p & 7) == Piece.KING:
					kings[p >> 4] = rank * 16 + file
					king_count[p >> 4] += 1
				file += 1
		if file != 8:
			return false
	if king_count[0] != 1 or king_count[1] != 1:
		return false

	var new_side: int
	if parts[1] == "w":
		new_side = Piece.WHITE
	elif parts[1] == "b":
		new_side = Piece.BLACK
	else:
		return false

	var new_castling := 0
	if parts.size() > 2:
		for ch: String in parts[2]:
			if ch == "K":
				new_castling |= CASTLE_WK
			elif ch == "Q":
				new_castling |= CASTLE_WQ
			elif ch == "k":
				new_castling |= CASTLE_BK
			elif ch == "q":
				new_castling |= CASTLE_BQ
			elif ch != "-":
				return false
	var wk := Piece.WHITE | Piece.KING
	var wr := Piece.WHITE | Piece.ROOK
	var bk := Piece.BLACK | Piece.KING
	var br := Piece.BLACK | Piece.ROOK
	if new_sq[E1] != wk or new_sq[H1] != wr:
		new_castling &= ~CASTLE_WK
	if new_sq[E1] != wk or new_sq[A1] != wr:
		new_castling &= ~CASTLE_WQ
	if new_sq[E8] != bk or new_sq[H8] != br:
		new_castling &= ~CASTLE_BK
	if new_sq[E8] != bk or new_sq[A8] != br:
		new_castling &= ~CASTLE_BQ

	var new_ep := -1
	if parts.size() > 3 and parts[3] != "-":
		new_ep = sq_from_name(parts[3])
		if new_ep == -1:
			return false
		# The pawn that just double-pushed belongs to the side NOT to move.
		var ep_rank := 5 if new_side == Piece.WHITE else 2
		var pushed_dir := -16 if new_side == Piece.WHITE else 16
		var pushed_pawn := (new_side ^ 24) | Piece.PAWN
		if (new_ep >> 4) != ep_rank or new_sq[new_ep] != 0 \
				or new_sq[new_ep + pushed_dir] != pushed_pawn \
				or new_sq[new_ep - pushed_dir] != 0:
			new_ep = -1

	var new_half := 0
	if parts.size() > 4:
		if not parts[4].is_valid_int() or parts[4].to_int() < 0:
			return false
		new_half = parts[4].to_int()
	var new_full := 1
	if parts.size() > 5:
		if not parts[5].is_valid_int():
			return false
		new_full = maxi(1, parts[5].to_int())

	squares = new_sq
	side_to_move = new_side
	castling = new_castling
	ep_square = new_ep
	halfmove_clock = new_half
	fullmove_number = new_full
	king_square = PackedInt32Array([kings[0], kings[1]])
	_undo.clear()
	zobrist = compute_hash()
	return true


func to_fen() -> String:
	var rows := PackedStringArray()
	for rank in range(7, -1, -1):
		var row := ""
		var empty := 0
		for file in 8:
			var p := squares[rank * 16 + file]
			if p == 0:
				empty += 1
			else:
				if empty > 0:
					row += str(empty)
					empty = 0
				row += Piece.to_char(p)
		if empty > 0:
			row += str(empty)
		rows.append(row)

	var cs := ""
	if castling & CASTLE_WK:
		cs += "K"
	if castling & CASTLE_WQ:
		cs += "Q"
	if castling & CASTLE_BK:
		cs += "k"
	if castling & CASTLE_BQ:
		cs += "q"
	if cs == "":
		cs = "-"

	return "%s %s %s %s %d %d" % [
		"/".join(rows),
		"w" if side_to_move == Piece.WHITE else "b",
		cs,
		sq_name(ep_square) if ep_square != -1 else "-",
		halfmove_clock,
		fullmove_number,
	]


## Independent copy (including undo history), e.g. for a search thread.
func clone() -> Board:
	var b := Board.new()
	b.squares = squares.duplicate()
	b.side_to_move = side_to_move
	b.castling = castling
	b.ep_square = ep_square
	b.halfmove_clock = halfmove_clock
	b.fullmove_number = fullmove_number
	b.king_square = king_square.duplicate()
	b.zobrist = zobrist
	b._undo = _undo.duplicate()
	return b


# ------------------------------------------------------------ make/unmake ---

## Plays a (pseudo-legal) move. Legality is the caller's job: use
## MoveGenerator.generate_legal(), or make the move and test the king.
func make_move(m: int) -> void:
	var from := m & 0x7F
	var to := (m >> 7) & 0x7F
	var promo := (m >> 14) & 7
	var mflags := m >> 17
	var piece := squares[from]
	var color := piece & 24
	var ci := color >> 4
	var captured := squares[to]
	var old_castling := castling
	var old_ep := ep_square
	var old_half := halfmove_clock
	var old_hash := zobrist

	var h := zobrist ^ _zob_castle[castling] ^ _ep_key()

	squares[from] = 0
	h ^= _zob_piece[(piece << 7) | from]
	if captured != 0:
		h ^= _zob_piece[(captured << 7) | to]
	if mflags & Move.FLAG_EN_PASSANT:
		var cap_sq := to - 16 if color == Piece.WHITE else to + 16
		captured = squares[cap_sq]
		squares[cap_sq] = 0
		h ^= _zob_piece[(captured << 7) | cap_sq]

	var placed := piece if promo == 0 else (color | promo)
	squares[to] = placed
	h ^= _zob_piece[(placed << 7) | to]

	if (piece & 7) == Piece.KING:
		king_square[ci] = to
		if mflags & Move.FLAG_CASTLE_KING:
			var rook := squares[to + 1]
			squares[to + 1] = 0
			squares[to - 1] = rook
			h ^= _zob_piece[(rook << 7) | (to + 1)] ^ _zob_piece[(rook << 7) | (to - 1)]
		elif mflags & Move.FLAG_CASTLE_QUEEN:
			var rook := squares[to - 2]
			squares[to - 2] = 0
			squares[to + 1] = rook
			h ^= _zob_piece[(rook << 7) | (to - 2)] ^ _zob_piece[(rook << 7) | (to + 1)]

	castling &= _castle_mask[from] & _castle_mask[to]
	ep_square = ((from + to) >> 1) if (mflags & Move.FLAG_DOUBLE_PUSH) else -1
	if (piece & 7) == Piece.PAWN or captured != 0:
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	if color == Piece.BLACK:
		fullmove_number += 1
	side_to_move = color ^ 24

	h ^= _zob_side ^ _zob_castle[castling]
	zobrist = h
	zobrist ^= _ep_key()

	_undo.append(captured)
	_undo.append(old_castling)
	_undo.append(old_ep)
	_undo.append(old_half)
	_undo.append(old_hash)


## Reverts `m`, which must be the most recently made move.
func unmake_move(m: int) -> void:
	var from := m & 0x7F
	var to := (m >> 7) & 0x7F
	var promo := (m >> 14) & 7
	var mflags := m >> 17

	var base := _undo.size() - _UNDO_STRIDE
	var captured: int = _undo[base]
	castling = _undo[base + 1]
	ep_square = _undo[base + 2]
	halfmove_clock = _undo[base + 3]
	zobrist = _undo[base + 4]
	_undo.resize(base)

	var color := side_to_move ^ 24
	side_to_move = color
	if color == Piece.BLACK:
		fullmove_number -= 1

	var piece := squares[to]
	if promo != 0:
		piece = color | Piece.PAWN
	squares[from] = piece

	if mflags & Move.FLAG_EN_PASSANT:
		squares[to] = 0
		squares[to - 16 if color == Piece.WHITE else to + 16] = captured
	else:
		squares[to] = captured

	if (piece & 7) == Piece.KING:
		king_square[color >> 4] = from
		if mflags & Move.FLAG_CASTLE_KING:
			squares[to + 1] = squares[to - 1]
			squares[to - 1] = 0
		elif mflags & Move.FLAG_CASTLE_QUEEN:
			squares[to - 2] = squares[to + 1]
			squares[to + 1] = 0


## Number of moves that can currently be unmade.
func undo_depth() -> int:
	@warning_ignore("integer_division")
	return _undo.size() / _UNDO_STRIDE


# ---------------------------------------------------------------- hashing ---

## Zobrist key computed from scratch (make_move maintains it incrementally).
func compute_hash() -> int:
	var h := 0
	for rank in 8:
		for file in 8:
			var s := rank * 16 + file
			var p := squares[s]
			if p != 0:
				h ^= _zob_piece[(p << 7) | s]
	if side_to_move == Piece.BLACK:
		h ^= _zob_side
	h ^= _zob_castle[castling]
	h ^= _ep_key()
	return h


# The e.p. square only counts toward the position's identity when the side to
# move actually has a pawn that could capture there (FIDE repetition rule).
func _ep_key() -> int:
	if ep_square == -1:
		return 0
	var pawn := side_to_move | Piece.PAWN
	var back := ep_square - 16 if side_to_move == Piece.WHITE else ep_square + 16
	if (((back - 1) & 0x88) == 0 and squares[back - 1] == pawn) \
			or (((back + 1) & 0x88) == 0 and squares[back + 1] == pawn):
		return _zob_ep[ep_square & 7]
	return 0


static func _ensure_tables() -> void:
	if not _zob_piece.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EEDC0DE
	# Indexed by (piece << 7) | square; pieces go up to 16 | 6 = 22.
	var zp := PackedInt64Array()
	zp.resize(32 * 128)
	for i in zp.size():
		zp[i] = (rng.randi() << 32) | rng.randi()
	var zc := PackedInt64Array()
	zc.resize(16)
	for i in 16:
		zc[i] = (rng.randi() << 32) | rng.randi()
	var ze := PackedInt64Array()
	ze.resize(8)
	for i in 8:
		ze[i] = (rng.randi() << 32) | rng.randi()
	_zob_side = (rng.randi() << 32) | rng.randi()

	var mask := PackedInt32Array()
	mask.resize(128)
	mask.fill(15)
	mask[A1] = 15 & ~CASTLE_WQ
	mask[H1] = 15 & ~CASTLE_WK
	mask[E1] = 15 & ~(CASTLE_WK | CASTLE_WQ)
	mask[A8] = 15 & ~CASTLE_BQ
	mask[H8] = 15 & ~CASTLE_BK
	mask[E8] = 15 & ~(CASTLE_BK | CASTLE_BQ)

	_zob_castle = zc
	_zob_ep = ze
	_castle_mask = mask
	_zob_piece = zp  # assigned last: it is the "tables are ready" marker
