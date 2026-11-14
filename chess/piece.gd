class_name Piece
extends RefCounted
## Piece encoding shared by the whole project.
##
## A piece is a small int: `color | type`. 0 means "empty square".
## Colors are bit flags (WHITE = 8, BLACK = 16) so that `color ^ 24` flips the
## side and `piece >> 4` gives a 0/1 color index (white = 0, black = 1).

const NONE := 0

const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const WHITE := 8
const BLACK := 16

const TYPE_MASK := 7
const COLOR_MASK := 24

const _CHARS := ".pnbrqk"


static func make(color: int, type: int) -> int:
	return color | type


static func type_of(piece: int) -> int:
	return piece & TYPE_MASK


static func color_of(piece: int) -> int:
	return piece & COLOR_MASK


static func opposite(color: int) -> int:
	return color ^ COLOR_MASK


## 0 for white, 1 for black. Works on a color or on a piece.
static func color_index(color_or_piece: int) -> int:
	return (color_or_piece & COLOR_MASK) >> 4


## FEN character for a piece ("P", "n", ...). Empty string for NONE.
static func to_char(piece: int) -> String:
	if piece == NONE:
		return ""
	var c: String = _CHARS[piece & TYPE_MASK]
	return c.to_upper() if (piece & COLOR_MASK) == WHITE else c


## Piece for a FEN character, or NONE if the character is not a piece.
static func from_char(ch: String) -> int:
	if ch.length() != 1:
		return NONE
	var t := _CHARS.find(ch.to_lower())
	if t < 1:
		return NONE
	return (WHITE if ch == ch.to_upper() else BLACK) | t


static func color_name(color: int) -> String:
	return "White" if color == WHITE else "Black"
