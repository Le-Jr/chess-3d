class_name San
extends RefCounted
## Standard Algebraic Notation: "Nbd2", "exd6", "O-O", "e8=Q+", "Qh4#".

const _PIECE_LETTERS := ["", "", "N", "B", "R", "Q", "K"]


## SAN for a legal move in position `b`. Pass the legal move list if you
## already have it to avoid regenerating it.
static func move_to_san(b: Board, m: int, legal: PackedInt32Array = PackedInt32Array()) -> String:
	if legal.is_empty():
		legal = MoveGenerator.generate_legal(b)

	var from := Move.from_sq(m)
	var to := Move.to_sq(m)
	var type := b.squares[from] & 7
	var san := ""

	if Move.is_castle_kingside(m):
		san = "O-O"
	elif Move.is_castle_queenside(m):
		san = "O-O-O"
	else:
		if type == Piece.PAWN:
			if Move.is_capture(m):
				san += "abcdefgh"[from & 7]
		else:
			san += _PIECE_LETTERS[type]
			# Disambiguate against other pieces of the same type that can
			# also reach `to`.
			var ambiguous := false
			var same_file := false
			var same_rank := false
			for other in legal:
				var ofrom := Move.from_sq(other)
				if ofrom == from or Move.to_sq(other) != to:
					continue
				if b.squares[ofrom] != b.squares[from]:
					continue
				ambiguous = true
				if (ofrom & 7) == (from & 7):
					same_file = true
				if (ofrom >> 4) == (from >> 4):
					same_rank = true
			if ambiguous:
				if not same_file:
					san += "abcdefgh"[from & 7]
				elif not same_rank:
					san += str((from >> 4) + 1)
				else:
					san += Board.sq_name(from)
		if Move.is_capture(m):
			san += "x"
		san += Board.sq_name(to)
		if Move.is_promotion(m):
			san += "=" + _PIECE_LETTERS[Move.promotion(m)]

	b.make_move(m)
	if MoveGenerator.in_check(b, b.side_to_move):
		san += "#" if MoveGenerator.generate_legal(b).is_empty() else "+"
	b.unmake_move(m)
	return san


## Finds the legal move matching a SAN string (check/mate/annotation marks
## are optional, "0-0" is accepted). Returns Move.NONE if nothing matches.
static func san_to_move(b: Board, san: String) -> int:
	var wanted := _normalize(san)
	var legal := MoveGenerator.generate_legal(b)
	for m in legal:
		if _normalize(move_to_san(b, m, legal)) == wanted:
			return m
	return Move.NONE


static func _normalize(san: String) -> String:
	var s := san.strip_edges().replace("0", "O")
	for mark in ["+", "#", "!", "?"]:
		s = s.replace(mark, "")
	return s
