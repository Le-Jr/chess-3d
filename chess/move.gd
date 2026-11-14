class_name Move
extends RefCounted
## Moves are packed into a single int so the search can generate and store
## millions of them without allocating objects. This class is the only place
## that knows the bit layout:
##
##   bits  0..6   from square (0x88 index)
##   bits  7..13  to square   (0x88 index)
##   bits 14..16  promotion piece type (0 = none)
##   bits 17..21  flags

const NONE := 0  # a1 -> a1, never a real move

const FLAG_CAPTURE := 1
const FLAG_DOUBLE_PUSH := 2
const FLAG_EN_PASSANT := 4
const FLAG_CASTLE_KING := 8
const FLAG_CASTLE_QUEEN := 16


static func make(from: int, to: int, move_flags: int = 0, promo: int = 0) -> int:
	return from | (to << 7) | (promo << 14) | (move_flags << 17)


static func from_sq(m: int) -> int:
	return m & 0x7F


static func to_sq(m: int) -> int:
	return (m >> 7) & 0x7F


## Promotion piece type (Piece.KNIGHT..Piece.QUEEN), or 0.
static func promotion(m: int) -> int:
	return (m >> 14) & 7


static func flags(m: int) -> int:
	return m >> 17


static func is_capture(m: int) -> bool:
	return ((m >> 17) & FLAG_CAPTURE) != 0


static func is_en_passant(m: int) -> bool:
	return ((m >> 17) & FLAG_EN_PASSANT) != 0


static func is_promotion(m: int) -> bool:
	return ((m >> 14) & 7) != 0


static func is_castle(m: int) -> bool:
	return ((m >> 17) & (FLAG_CASTLE_KING | FLAG_CASTLE_QUEEN)) != 0


static func is_castle_kingside(m: int) -> bool:
	return ((m >> 17) & FLAG_CASTLE_KING) != 0


static func is_castle_queenside(m: int) -> bool:
	return ((m >> 17) & FLAG_CASTLE_QUEEN) != 0


## Long algebraic / UCI notation: "e2e4", "e7e8q".
static func to_uci(m: int) -> String:
	if m == NONE:
		return "0000"
	var s := Board.sq_name(m & 0x7F) + Board.sq_name((m >> 7) & 0x7F)
	var promo := (m >> 14) & 7
	if promo != 0:
		s += Piece.to_char(Piece.BLACK | promo)
	return s
