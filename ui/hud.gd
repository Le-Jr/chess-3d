class_name Hud
extends CanvasLayer
## In-game HUD: side panel (turn, move list, captured pieces, buttons), the
## promotion picker and the game-over dialog. Purely presentational - it
## shows a GameState and emits signals; scenes/game.gd does the work.

signal undo_requested
signal new_game_requested
signal flip_requested
signal menu_requested
signal auto_rotate_toggled(enabled: bool)
## `type` is Piece.QUEEN / ROOK / BISHOP / KNIGHT, or 0 if cancelled.
signal promotion_chosen(type: int)

## Width of the side panel in UI pixels (the camera shifts the board to
## stay centered in what is left).
const PANEL_WIDTH := 290
const PANEL_MARGIN := 12
const PIECE_VALUES := [0, 1, 3, 3, 5, 9, 0]

var _turn_chip: Panel
var _turn_label: Label
var _status_label: Label
var _moves: RichTextLabel
var _captured_by_white: Label
var _captured_by_black: Label
var _undo_button: Button
var _auto_rotate: CheckButton
var _menu_button: Button

var _promotion: Control
var _promotion_buttons: Array[Button] = []
var _game_over: Control
var _game_over_title: Label
var _game_over_detail: Label
var _thinking := false


func _init() -> void:
	layer = 10
	_build_side_panel()
	_build_promotion_picker()
	_build_game_over_dialog()


# ----------------------------------------------------------------- public ---

## Updates everything in the side panel from the game state.
func refresh(state: GameState) -> void:
	var white := state.side_to_move() == Piece.WHITE
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(0.95, 0.94, 0.9) if white else Color(0.12, 0.12, 0.14)
	chip.border_color = Color(0.55, 0.55, 0.58)
	chip.set_border_width_all(2)
	chip.set_corner_radius_all(11)
	_turn_chip.add_theme_stylebox_override("panel", chip)

	if state.is_game_over():
		_turn_label.text = "Game over"
		_status_label.text = state.status_text()
	else:
		_turn_label.text = "%s to move" % Piece.color_name(state.side_to_move())
		if _thinking:
			_status_label.text = "Computer is thinking..."
		elif state.is_check():
			_status_label.text = "Check!"
		else:
			_status_label.text = "Move %d" % state.board.fullmove_number
	_status_label.add_theme_color_override("font_color",
			UiStyle.ACCENT if (state.is_check() or state.is_game_over()) else UiStyle.TEXT_DIM)

	_moves.text = _move_list_bbcode(state)
	_captured_by_white.text = _captured_text(state, Piece.WHITE)
	_captured_by_black.text = _captured_text(state, Piece.BLACK)
	_undo_button.disabled = state.ply_count() == 0


## Shows "Computer is thinking..." in the status line.
func set_thinking(thinking: bool, state: GameState) -> void:
	_thinking = thinking
	refresh(state)


func set_auto_rotate(enabled: bool, available: bool) -> void:
	_auto_rotate.set_pressed_no_signal(enabled)
	_auto_rotate.disabled = not available


func set_menu_available(available: bool) -> void:
	_menu_button.visible = available


## Opens the promotion picker for `color`; answers with `promotion_chosen`.
func ask_promotion(color: int) -> void:
	var glyph_color := Color(0.96, 0.95, 0.9) if color == Piece.WHITE else Color(0.1, 0.1, 0.12)
	var outline := Color(0.1, 0.1, 0.12) if color == Piece.WHITE else Color(0.85, 0.85, 0.85)
	for b in _promotion_buttons:
		b.add_theme_color_override("font_color", glyph_color)
		b.add_theme_color_override("font_hover_color", glyph_color)
		b.add_theme_color_override("font_outline_color", outline)
	_promotion.visible = true


func is_asking_promotion() -> bool:
	return _promotion.visible


## Picks a promotion piece as if its button was clicked (0 cancels).
func choose_promotion(type: int) -> void:
	_promotion.visible = false
	promotion_chosen.emit(type)


func show_game_over(state: GameState) -> void:
	match state.status:
		GameState.Status.CHECKMATE:
			_game_over_title.text = "Checkmate"
			_game_over_detail.text = "%s wins" % Piece.color_name(state.winner)
		GameState.Status.STALEMATE:
			_game_over_title.text = "Stalemate"
			_game_over_detail.text = "The game is a draw"
		_:
			_game_over_title.text = "Draw"
			var reason := state.status_text().trim_prefix("Draw by ")
			_game_over_detail.text = reason.left(1).to_upper() + reason.substr(1)
	_game_over.visible = true


func hide_game_over() -> void:
	_game_over.visible = false


func is_game_over_visible() -> bool:
	return _game_over.visible


## The move list as plain text ("1. e4 e5 2. Nf3"), for tests and copying.
func move_list_text() -> String:
	return _moves.get_parsed_text().strip_edges()


# ------------------------------------------------------------- formatting ---

func _move_list_bbcode(state: GameState) -> String:
	var sans := state.san_history
	if sans.is_empty():
		return "[color=#8a8a8e]No moves yet[/color]"
	# Games started from a FEN with Black to move begin with "1... e5".
	var first_number := 1
	var black_starts := false
	var parts := state.start_fen.split(" ")
	if parts.size() >= 6:
		first_number = maxi(1, parts[5].to_int())
		black_starts = parts[1] == "b"

	var out := "[table=3]"
	var ply := 0
	var number := first_number
	var last := sans.size() - 1
	while ply < sans.size():
		out += "[cell][color=#8a8a8e]%d.  [/color][/cell]" % number
		if black_starts and ply == 0:
			out += "[cell]...   [/cell]"
		else:
			out += "[cell]%s   [/cell]" % _san_cell(sans[ply], ply == last)
			ply += 1
		if ply < sans.size():
			out += "[cell]%s[/cell]" % _san_cell(sans[ply], ply == last)
			ply += 1
		else:
			out += "[cell][/cell]"
		number += 1
	return out + "[/table]"


func _san_cell(san: String, is_last: bool) -> String:
	return "[color=#edc25c][b]%s[/b][/color]" % san if is_last else san


func _captured_text(state: GameState, by: int) -> String:
	var pieces := Array(state.captured_by(by))
	pieces.sort_custom(func(a: int, b: int) -> bool: return PIECE_VALUES[a & 7] > PIECE_VALUES[b & 7])
	var text := ""
	for p: int in pieces:
		text += UiStyle.glyph(p & 7)
	# Material balance, shown next to the side that is ahead.
	var mine := 0
	for p: int in pieces:
		mine += PIECE_VALUES[p & 7]
	var theirs := 0
	for p in state.captured_by(Piece.opposite(by)):
		theirs += PIECE_VALUES[p & 7]
	if mine > theirs:
		text += "  +%d" % (mine - theirs)
	return text


# --------------------------------------------------------------- building ---

func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "SidePanel"
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -(PANEL_WIDTH + PANEL_MARGIN)
	panel.offset_right = -PANEL_MARGIN
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = -PANEL_MARGIN
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var turn_row := HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", 10)
	box.add_child(turn_row)
	_turn_chip = Panel.new()
	_turn_chip.custom_minimum_size = Vector2(22, 22)
	_turn_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_row.add_child(_turn_chip)
	_turn_label = UiStyle.make_label("White to move", 20)
	turn_row.add_child(_turn_label)

	_status_label = UiStyle.make_label("", 14, UiStyle.TEXT_DIM)
	box.add_child(_status_label)
	box.add_child(HSeparator.new())

	box.add_child(UiStyle.make_label("Moves", 13, UiStyle.TEXT_DIM))
	_moves = RichTextLabel.new()
	_moves.bbcode_enabled = true
	_moves.scroll_following = true
	_moves.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_moves.add_theme_font_size_override("normal_font_size", 15)
	_moves.add_theme_font_size_override("bold_font_size", 15)
	_moves.add_theme_color_override("default_color", UiStyle.TEXT)
	box.add_child(_moves)
	box.add_child(HSeparator.new())

	box.add_child(UiStyle.make_label("Captured", 13, UiStyle.TEXT_DIM))
	_captured_by_white = _make_captured_label(Color(0.16, 0.16, 0.18), Color(0.8, 0.8, 0.8))
	_captured_by_black = _make_captured_label(Color(0.96, 0.95, 0.9), Color(0.25, 0.25, 0.27))
	box.add_child(_captured_by_white)
	box.add_child(_captured_by_black)
	box.add_child(HSeparator.new())

	_auto_rotate = CheckButton.new()
	_auto_rotate.text = "Rotate board each turn"
	_auto_rotate.add_theme_font_size_override("font_size", 14)
	_auto_rotate.add_theme_color_override("font_color", UiStyle.TEXT)
	_auto_rotate.focus_mode = Control.FOCUS_NONE
	_auto_rotate.toggled.connect(func(on: bool) -> void: auto_rotate_toggled.emit(on))
	box.add_child(_auto_rotate)

	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	box.add_child(buttons)
	_undo_button = _add_button(buttons, "Undo", func() -> void: undo_requested.emit())
	_add_button(buttons, "Flip board", func() -> void: flip_requested.emit())
	_add_button(buttons, "New game", func() -> void: new_game_requested.emit())
	_menu_button = _add_button(buttons, "Menu", func() -> void: menu_requested.emit())


func _make_captured_label(color: Color, outline: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiStyle.glyph_font())
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 3)
	l.custom_minimum_size = Vector2(0, 32)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	return l


func _add_button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var b := UiStyle.make_button(text)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


# A full-screen layer that leaves room for the side panel, so dialogs are
# centered over the board.
func _make_overlay(dim: bool) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP if dim else Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.35)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(shade)
	return overlay


func _make_dialog(overlay: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -(PANEL_WIDTH + PANEL_MARGIN)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(14, 22))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box


func _build_promotion_picker() -> void:
	_promotion = _make_overlay(true)
	_promotion.name = "PromotionPicker"
	var box := _make_dialog(_promotion)
	var title := UiStyle.make_label("Promote pawn to", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for type: int in [Piece.QUEEN, Piece.ROOK, Piece.BISHOP, Piece.KNIGHT]:
		var b := UiStyle.make_button(UiStyle.glyph(type), 54)
		b.add_theme_font_override("font", UiStyle.glyph_font())
		b.add_theme_constant_override("outline_size", 4)
		b.custom_minimum_size = Vector2(88, 88)
		b.tooltip_text = UiStyle.PIECE_NAMES[type]
		b.pressed.connect(choose_promotion.bind(type))
		row.add_child(b)
		_promotion_buttons.append(b)

	var cancel := UiStyle.make_button("Cancel", 14)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(choose_promotion.bind(0))
	box.add_child(cancel)


func _build_game_over_dialog() -> void:
	_game_over = _make_overlay(false)
	_game_over.name = "GameOverDialog"
	var box := _make_dialog(_game_over)
	_game_over_title = UiStyle.make_label("Checkmate", 30, UiStyle.ACCENT)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_game_over_title)
	_game_over_detail = UiStyle.make_label("", 18)
	_game_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_game_over_detail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_add_button(row, "New game", func() -> void: new_game_requested.emit())
	_add_button(row, "Undo", func() -> void: undo_requested.emit())
	_add_button(row, "View board", hide_game_over)
