class_name MoveGenerator
extends RefCounted
## Move generation for a Board. All functions are static and allocation-light.
##
## `generate_pseudo_legal` ignores whether the mover's king is left in check;
## `generate_legal` filters with make/unmake. Castling is fully validated at
## generation time (rights, empty squares, not in / through / into check).

const KNIGHT_OFFSETS := [-33, -31, -18, -14, 14, 18, 31, 33]
const KING_OFFSETS := [-17, -16, -15, -1, 1, 15, 16, 17]
const BISHOP_DIRS := [-17, -15, 15, 17]
const ROOK_DIRS := [-16, -1, 1, 16]


## Pseudo-legal moves for the side to move. With `captures_only`, generates
## captures (including e.p.) and all promotions - what quiescence search needs.
static func generate_pseudo_legal(b: Board, captures_only: bool = false) -> PackedInt32Array:
	var moves := PackedInt32Array()
	var sqs := b.squares
	var us := b.side_to_move
	var them := us ^ 24
	var white := us == Piece.WHITE
	var pawn_dir := 16 if white else -16
	var pawn_start := 1 if white else 6
	var pawn_promo := 7 if white else 0
	var ep := b.ep_square

	for rank in 8:
		for file in 8:
			var from := rank * 16 + file
			var p := sqs[from]
			if p == 0 or (p & 24) != us:
				continue
			var type := p & 7

			if type == Piece.PAWN:
				var to := from + pawn_dir
				if (to & 0x88) == 0 and sqs[to] == 0:
					if (to >> 4) == pawn_promo:
						for pt in range(Piece.QUEEN, Piece.PAWN, -1):
							moves.append(from | (to << 7) | (pt << 14))
					elif not captures_only:
						moves.append(from | (to << 7))
						if rank == pawn_start and sqs[to + pawn_dir] == 0:
							moves.append(from | ((to + pawn_dir) << 7) | (Move.FLAG_DOUBLE_PUSH << 17))
				for i in 2:
					to = from + pawn_dir - 1 + 2 * i
					if to & 0x88:
						continue
					var t := sqs[to]
					if t != 0:
						if (t & 24) == them:
							if (to >> 4) == pawn_promo:
								for pt in range(Piece.QUEEN, Piece.PAWN, -1):
									moves.append(from | (to << 7) | (pt << 14) | (Move.FLAG_CAPTURE << 17))
							else:
								moves.append(from | (to << 7) | (Move.FLAG_CAPTURE << 17))
					elif to == ep:
						moves.append(from | (to << 7) | ((Move.FLAG_CAPTURE | Move.FLAG_EN_PASSANT) << 17))

			elif type == Piece.KNIGHT or type == Piece.KING:
				var offsets: Array = KNIGHT_OFFSETS if type == Piece.KNIGHT else KING_OFFSETS
				for d: int in offsets:
					var to := from + d
					if to & 0x88:
						continue
					var t := sqs[to]
					if t == 0:
						if not captures_only:
							moves.append(from | (to << 7))
					elif (t & 24) == them:
						moves.append(from | (to << 7) | (Move.FLAG_CAPTURE << 17))

			else:
				if type != Piece.ROOK:  # bishop, queen
					for d: int in BISHOP_DIRS:
						var to := from + d
						while (to & 0x88) == 0:
							var t := sqs[to]
							if t == 0:
								if not captures_only:
									moves.append(from | (to << 7))
							else:
								if (t & 24) == them:
									moves.append(from | (to << 7) | (Move.FLAG_CAPTURE << 17))
								break
							to += d
				if type != Piece.BISHOP:  # rook, queen
					for d: int in ROOK_DIRS:
						var to := from + d
						while (to & 0x88) == 0:
							var t := sqs[to]
							if t == 0:
								if not captures_only:
									moves.append(from | (to << 7))
							else:
								if (t & 24) == them:
									moves.append(from | (to << 7) | (Move.FLAG_CAPTURE << 17))
								break
							to += d

	if not captures_only and b.castling != 0:
		_add_castling(b, moves)
	return moves


static func _add_castling(b: Board, moves: PackedInt32Array) -> void:
	var sqs := b.squares
	var us := b.side_to_move
	var them := us ^ 24
	var white := us == Piece.WHITE
	var home := 0x00 if white else 0x70  # a-file square of the back rank
	var king_side := Board.CASTLE_WK if white else Board.CASTLE_BK
	var queen_side := Board.CASTLE_WQ if white else Board.CASTLE_BQ
	var e := home + 4
	if sqs[e] != (us | Piece.KING):
		return
	var rook := us | Piece.ROOK

	if (b.castling & king_side) and sqs[home + 7] == rook \
			and sqs[home + 5] == 0 and sqs[home + 6] == 0:
		if not is_square_attacked(b, e, them) \
				and not is_square_attacked(b, home + 5, them) \
				and not is_square_attacked(b, home + 6, them):
			moves.append(e | ((home + 6) << 7) | (Move.FLAG_CASTLE_KING << 17))

	# Queenside: b-file square must be empty but may be attacked.
	if (b.castling & queen_side) and sqs[home] == rook \
			and sqs[home + 1] == 0 and sqs[home + 2] == 0 and sqs[home + 3] == 0:
		if not is_square_attacked(b, e, them) \
				and not is_square_attacked(b, home + 3, them) \
				and not is_square_attacked(b, home + 2, them):
			moves.append(e | ((home + 2) << 7) | (Move.FLAG_CASTLE_QUEEN << 17))


## True if `square` is attacked by any piece of color `by`.
static func is_square_attacked(b: Board, square: int, by: int) -> bool:
	var sqs := b.squares

	# Pawns: a white pawn on s attacks s+15 and s+17.
	var pawn := by | Piece.PAWN
	var s: int
	if by == Piece.WHITE:
		s = square - 15
		if (s & 0x88) == 0 and sqs[s] == pawn:
			return true
		s = square - 17
		if (s & 0x88) == 0 and sqs[s] == pawn:
			return true
	else:
		s = square + 15
		if (s & 0x88) == 0 and sqs[s] == pawn:
			return true
		s = square + 17
		if (s & 0x88) == 0 and sqs[s] == pawn:
			return true

	var knight := by | Piece.KNIGHT
	for d: int in KNIGHT_OFFSETS:
		s = square + d
		if (s & 0x88) == 0 and sqs[s] == knight:
			return true

	var king := by | Piece.KING
	for d: int in KING_OFFSETS:
		s = square + d
		if (s & 0x88) == 0 and sqs[s] == king:
			return true

	var bishop := by | Piece.BISHOP
	var rook := by | Piece.ROOK
	var queen := by | Piece.QUEEN
	for d: int in BISHOP_DIRS:
		s = square + d
		while (s & 0x88) == 0:
			var t := sqs[s]
			if t != 0:
				if t == bishop or t == queen:
					return true
				break
			s += d
	for d: int in ROOK_DIRS:
		s = square + d
		while (s & 0x88) == 0:
			var t := sqs[s]
			if t != 0:
				if t == rook or t == queen:
					return true
				break
			s += d
	return false


## True if the king of `color` is attacked.
static func in_check(b: Board, color: int) -> bool:
	return is_square_attacked(b, b.king_square[color >> 4], color ^ 24)


## Fully legal moves for the side to move.
static func generate_legal(b: Board, captures_only: bool = false) -> PackedInt32Array:
	var pseudo := generate_pseudo_legal(b, captures_only)
	var legal := PackedInt32Array()
	var us := b.side_to_move
	var them := us ^ 24
	var ci := us >> 4
	for m in pseudo:
		b.make_move(m)
		if not is_square_attacked(b, b.king_square[ci], them):
			legal.append(m)
		b.unmake_move(m)
	return legal


## Counts leaf nodes of the legal move tree to `depth` (the standard
## move-generator correctness test).
static func perft(b: Board, depth: int) -> int:
	if depth <= 0:
		return 1
	var moves := generate_legal(b)
	if depth == 1:
		return moves.size()
	var nodes := 0
	for m in moves:
		b.make_move(m)
		nodes += perft(b, depth - 1)
		b.unmake_move(m)
	return nodes


## Perft split by root move ({"e2e4": count, ...}); handy for debugging
## against another engine's `go perft`.
static func divide(b: Board, depth: int) -> Dictionary:
	var out := {}
	for m in generate_legal(b):
		b.make_move(m)
		out[Move.to_uci(m)] = perft(b, depth - 1)
		b.unmake_move(m)
	return out
