class_name Hud
extends CanvasLayer
## In-game HUD: side panel (turn, move list, captured pieces, camera angle,
## buttons), the promotion picker, the game-over dialog and the cinematic
## layer (letterbox bars, vignette, impact flash, the "Checkmate" banner).
## Purely presentational - it shows a GameState and emits signals;
## scenes/game.gd does the work. The look comes from UiStyle.

signal undo_requested
signal new_game_requested
signal flip_requested
signal menu_requested
signal auto_rotate_toggled(enabled: bool)
## The camera-angle slider moved (degrees above the horizontal).
signal camera_pitch_changed(degrees: float)
## The slider was released: a good moment to save the setting.
signal camera_pitch_committed
## `type` is Piece.QUEEN / ROOK / BISHOP / KNIGHT, or 0 if cancelled.
signal promotion_chosen(type: int)

## Width of the side panel in UI pixels (the camera shifts the board to
## stay centered in what is left).
const PANEL_WIDTH := 300
## Narrower side panel on a phone held sideways, and the strip under the
## board on one held upright.
const COMPACT_PANEL_WIDTH := 264
const PORTRAIT_PANEL_HEIGHT := 292
const LETTERBOX_HEIGHT := 78.0
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

var _panel: PanelContainer
var _layout: int = UiLayout.Mode.WIDE
var _last_state: GameState
var _auto_rotate_on := false
var _auto_rotate_available := true
var _menu_available := true
var _dialog_centers: Array[CenterContainer] = []
var _camera_slider: HSlider
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _vignette: TextureRect
var _flash: ColorRect
var _banner: Label
var _banner_sub: Label
var _bars_tween: Tween
var _flash_tween: Tween
var _banner_tween: Tween
var _dialog_tween: Tween


func _init() -> void:
	layer = 10
	_build_cinematic_layer()
	_build_side_panel()
	_build_promotion_picker()
	_build_game_over_dialog()


# ----------------------------------------------------------------- public ---

## Updates everything in the side panel from the game state.
func refresh(state: GameState) -> void:
	_last_state = state
	var white := state.side_to_move() == Piece.WHITE
	var chip := StyleBoxFlat.new()
	# A seal in the color of the side to move.
	chip.bg_color = Color(0.96, 0.92, 0.80) if white else Color(0.07, 0.06, 0.06)
	chip.border_color = UiStyle.ACCENT
	chip.set_border_width_all(2)
	chip.set_corner_radius_all(13)
	chip.shadow_color = Color(0, 0, 0, 0.5)
	chip.shadow_size = 3
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
	_auto_rotate_on = enabled
	_auto_rotate_available = available
	_auto_rotate.set_pressed_no_signal(enabled)
	_auto_rotate.disabled = not available


func set_menu_available(available: bool) -> void:
	_menu_available = available
	_menu_button.visible = available


## The current layout (a UiLayout.Mode).
func layout() -> int:
	return _layout


## Rearranges the HUD for a layout: rebuilds the panel (beside or under the
## board) and recenters the dialogs and the banner over what is left.
func set_layout(mode: int) -> void:
	if mode == _layout:
		return
	_layout = mode
	var slider_value := _camera_slider.value
	remove_child(_panel)
	_panel.queue_free()
	_build_side_panel(mode)
	_camera_slider.set_value_no_signal(slider_value)
	var inset := panel_inset(mode)
	for center in _dialog_centers:
		center.offset_right = -inset.x
		center.offset_bottom = -inset.y
	var banner_holder: Control = _banner.get_parent().get_parent()
	banner_holder.offset_right = -inset.x
	banner_holder.offset_bottom = -(inset.y + (120.0 if mode == UiLayout.Mode.PORTRAIT else 260.0))
	_banner.add_theme_font_size_override("font_size", 104 if mode == UiLayout.Mode.WIDE else 62)
	_banner_sub.add_theme_font_size_override("font_size", 26 if mode == UiLayout.Mode.WIDE else 18)
	_game_over_title.add_theme_font_size_override("font_size", 54 if mode == UiLayout.Mode.WIDE else 40)
	_game_over_title.custom_minimum_size.x = 380.0 if mode == UiLayout.Mode.WIDE else 300.0
	for b in _promotion_buttons:
		b.custom_minimum_size = Vector2(88, 88) if mode == UiLayout.Mode.WIDE else Vector2(72, 72)
	if _last_state != null:
		refresh(_last_state)


## Screen space the panel takes, in UI pixels: (from the right edge, from the
## bottom edge). The camera shifts the board by half of it.
static func panel_inset(mode: int) -> Vector2:
	match mode:
		UiLayout.Mode.PORTRAIT:
			return Vector2(0.0, PORTRAIT_PANEL_HEIGHT + PANEL_MARGIN)
		UiLayout.Mode.COMPACT:
			return Vector2(COMPACT_PANEL_WIDTH + PANEL_MARGIN, 0.0)
	return Vector2(PANEL_WIDTH + PANEL_MARGIN, 0.0)


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


## Sets the camera-angle slider without emitting camera_pitch_changed.
func set_camera_pitch(degrees: float) -> void:
	_camera_slider.set_value_no_signal(degrees)


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
	_kill(_dialog_tween)
	_game_over.modulate.a = 1.0
	if GameSettings.animations and is_inside_tree():
		# The scroll unrolls: fade in while growing to full size.
		var dialog: Control = _game_over.get_child(0).get_child(0)
		dialog.pivot_offset = dialog.size * 0.5
		dialog.scale = Vector2(0.82, 0.82)
		_game_over.modulate.a = 0.0
		_dialog_tween = create_tween().set_parallel(true)
		_dialog_tween.tween_property(_game_over, "modulate:a", 1.0, 0.35)
		_dialog_tween.tween_property(dialog, "scale", Vector2.ONE, 0.45) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_game_over() -> void:
	_kill(_dialog_tween)
	_game_over.visible = false


# -------------------------------------------------------------- cinematic ---

## Slides the black bars of a cinematic shot in or out and darkens the
## corners of the picture.
func set_letterbox(on: bool, animate: bool = true) -> void:
	_kill(_bars_tween)
	var height := LETTERBOX_HEIGHT if on else 0.0
	var shade := 1.0 if on else 0.0
	if not animate or not is_inside_tree():
		_bar_top.offset_bottom = height
		_bar_bottom.offset_top = -height
		_vignette.modulate.a = shade
		return
	_bars_tween = create_tween().set_parallel(true)
	_ignore_time_scale(_bars_tween)
	_bars_tween.tween_property(_bar_top, "offset_bottom", height, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bars_tween.tween_property(_bar_bottom, "offset_top", -height, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_bars_tween.tween_property(_vignette, "modulate:a", shade, 0.45)


func is_letterboxed() -> bool:
	return _bar_top.offset_bottom > 0.5


## A flash of light over the whole picture (a blow landing).
func impact_flash(strength: float = 0.22, color: Color = Color(1.0, 0.86, 0.62)) -> void:
	if not is_inside_tree():
		return
	_kill(_flash_tween)
	_flash.color = Color(color, strength)
	_flash_tween = create_tween()
	_ignore_time_scale(_flash_tween)
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.32).set_ease(Tween.EASE_OUT)


## Slams a big title over the board ("Checkmate"), with a line under it.
func announce(title: String, subtitle: String = "") -> void:
	_kill(_banner_tween)
	_banner.text = title
	_banner_sub.text = subtitle
	var holder: Control = _banner.get_parent()
	holder.visible = true
	if not is_inside_tree():
		holder.modulate.a = 1.0
		return
	holder.pivot_offset = holder.size * 0.5
	holder.scale = Vector2(2.2, 2.2)
	holder.modulate.a = 0.0
	_banner_tween = create_tween().set_parallel(true)
	_ignore_time_scale(_banner_tween)
	_banner_tween.tween_property(holder, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(holder, "scale", Vector2.ONE, 0.38) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func hide_announcement(animate: bool = true) -> void:
	_kill(_banner_tween)
	var holder: Control = _banner.get_parent()
	if not animate or not is_inside_tree() or not holder.visible:
		holder.visible = false
		return
	_banner_tween = create_tween()
	_ignore_time_scale(_banner_tween)
	_banner_tween.tween_property(holder, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(holder.hide)


func is_announcing() -> bool:
	return (_banner.get_parent() as Control).visible


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


# Cinematic tweens keep real time while the game runs in slow motion.
static func _ignore_time_scale(tween: Tween) -> void:
	if tween.has_method("set_ignore_time_scale"):
		tween.call("set_ignore_time_scale", true)


func is_game_over_visible() -> bool:
	return _game_over.visible


## The move list as plain text ("1. e4 e5 2. Nf3"), for tests and copying.
func move_list_text() -> String:
	return _moves.get_parsed_text().strip_edges()


# ------------------------------------------------------------- formatting ---

func _move_list_bbcode(state: GameState) -> String:
	var sans := state.san_history
	if sans.is_empty():
		return "[color=#ad9670][i]No moves yet[/i][/color]"
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
		out += "[cell][color=#ad9670]%d.  [/color][/cell]" % number
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
	return "[color=#f2c257][b]%s[/b][/color]" % san if is_last else san


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

# Builds the panel for a layout: a full side panel (WIDE), a denser one for
# a phone held sideways (COMPACT), or a strip under the board (PORTRAIT).
func _build_side_panel(mode: int = UiLayout.Mode.WIDE) -> void:
	var portrait := mode == UiLayout.Mode.PORTRAIT
	var compact := mode != UiLayout.Mode.WIDE
	_panel = PanelContainer.new()
	_panel.name = "SidePanel"
	_panel.theme = UiStyle.theme()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(6, 8 if compact else 16))
	UiStyle.decorate(_panel)
	if portrait:
		_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_panel.offset_left = PANEL_MARGIN
		_panel.offset_right = -PANEL_MARGIN
		_panel.offset_top = -(PORTRAIT_PANEL_HEIGHT + PANEL_MARGIN)
		_panel.offset_bottom = -PANEL_MARGIN
	else:
		_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_panel.offset_left = -(panel_inset(mode).x)
		_panel.offset_right = -PANEL_MARGIN
		_panel.offset_top = PANEL_MARGIN
		_panel.offset_bottom = -PANEL_MARGIN
	add_child(_panel)
	# Under the dialogs, which were added first.
	move_child(_panel, _flash.get_index() + 3)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5 if compact else 8)
	_panel.add_child(box)

	var turn_row := HBoxContainer.new()
	turn_row.add_theme_constant_override("separation", 10)
	box.add_child(turn_row)
	_turn_chip = Panel.new()
	_turn_chip.custom_minimum_size = Vector2(22, 22) if compact else Vector2(26, 26)
	_turn_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_row.add_child(_turn_chip)
	_turn_label = UiStyle.make_title("White to move", 20 if compact else 24)
	turn_row.add_child(_turn_label)

	_status_label = UiStyle.make_label("", 14, UiStyle.TEXT_DIM)
	if portrait:
		# Beside the turn, to save a line.
		_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		turn_row.add_child(_status_label)
	else:
		box.add_child(_status_label)
	if not compact:
		box.add_child(UiStyle.make_divider())
		box.add_child(UiStyle.make_heading("Chronicle"))

	_moves = RichTextLabel.new()
	_moves.add_theme_font_override("normal_font", UiStyle.body_font())
	_moves.add_theme_font_override("italics_font", UiStyle.body_font())
	var bold := FontVariation.new()
	bold.base_font = UiStyle.body_font()
	bold.variation_embolden = 0.8
	_moves.add_theme_font_override("bold_font", bold)
	_moves.bbcode_enabled = true
	_moves.scroll_following = true
	_moves.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_moves.custom_minimum_size = Vector2(0, 44)
	_moves.add_theme_font_size_override("normal_font_size", 15)
	_moves.add_theme_font_size_override("bold_font_size", 15)
	_moves.add_theme_color_override("default_color", UiStyle.TEXT)
	box.add_child(_moves)

	_captured_by_white = _make_captured_label(Color(0.16, 0.16, 0.18), Color(0.8, 0.8, 0.8), compact)
	_captured_by_black = _make_captured_label(Color(0.96, 0.95, 0.9), Color(0.25, 0.25, 0.27), compact)
	if portrait:
		# Side by side.
		var fallen := HBoxContainer.new()
		fallen.add_theme_constant_override("separation", 10)
		box.add_child(fallen)
		for label: Label in [_captured_by_white, _captured_by_black]:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fallen.add_child(label)
	else:
		if not compact:
			box.add_child(UiStyle.make_divider())
			box.add_child(UiStyle.make_heading("Fallen"))
		box.add_child(_captured_by_white)
		box.add_child(_captured_by_black)
		if not compact:
			box.add_child(UiStyle.make_divider())
			box.add_child(UiStyle.make_heading("Camera angle"))

	# Camera angle: from a low, dramatic view to almost straight down.
	_camera_slider = HSlider.new()
	_camera_slider.name = "CameraAngle"
	_camera_slider.min_value = CameraRig.SETTING_MIN_PITCH
	_camera_slider.max_value = CameraRig.SETTING_MAX_PITCH
	_camera_slider.step = 1.0
	_camera_slider.value = GameSettings.camera_pitch
	_camera_slider.focus_mode = Control.FOCUS_NONE
	_camera_slider.custom_minimum_size = Vector2(0, 22)
	_camera_slider.tooltip_text = "Camera angle: low and dramatic  <->  top-down"
	_camera_slider.value_changed.connect(func(v: float) -> void: camera_pitch_changed.emit(v))
	_camera_slider.drag_ended.connect(func(_changed: bool) -> void: camera_pitch_committed.emit())

	_auto_rotate = CheckButton.new()
	_auto_rotate.text = "Rotate each turn" if compact else "Rotate board each turn"
	_auto_rotate.add_theme_font_size_override("font_size", 14)
	_auto_rotate.focus_mode = Control.FOCUS_NONE
	_auto_rotate.set_pressed_no_signal(_auto_rotate_on)
	_auto_rotate.disabled = not _auto_rotate_available
	_auto_rotate.toggled.connect(func(on: bool) -> void: auto_rotate_toggled.emit(on))

	if portrait:
		# Slider and switch share a line.
		var camera_row := HBoxContainer.new()
		camera_row.add_theme_constant_override("separation", 12)
		box.add_child(camera_row)
		camera_row.add_child(UiStyle.make_label("Angle", 13, UiStyle.TEXT_DIM))
		_camera_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_camera_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		camera_row.add_child(_camera_slider)
		camera_row.add_child(_auto_rotate)
	else:
		box.add_child(_camera_slider)
		box.add_child(_auto_rotate)

	var buttons := GridContainer.new()
	buttons.columns = 4 if portrait else 2
	buttons.add_theme_constant_override("h_separation", 6 if compact else 8)
	buttons.add_theme_constant_override("v_separation", 6 if compact else 8)
	box.add_child(buttons)
	_undo_button = _add_button(buttons, "Undo", func() -> void: undo_requested.emit())
	_add_button(buttons, "Flip" if portrait else "Flip board", func() -> void: flip_requested.emit())
	_add_button(buttons, "New" if portrait else "New game", func() -> void: new_game_requested.emit())
	_menu_button = _add_button(buttons, "Menu", func() -> void: menu_requested.emit())
	_menu_button.visible = _menu_available


func _make_captured_label(color: Color, outline: Color, small: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", UiStyle.glyph_font())
	l.add_theme_font_size_override("font_size", 19 if small else 24)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 3)
	l.custom_minimum_size = Vector2(0, 25 if small else 32)
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
		shade.color = Color(0.03, 0.015, 0.0, 0.5)
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
	_dialog_centers.append(center)
	var panel := PanelContainer.new()
	panel.theme = UiStyle.theme()
	var style := UiStyle.panel(6, 26)
	style.border_color = UiStyle.ACCENT
	style.shadow_size = 28
	panel.add_theme_stylebox_override("panel", style)
	UiStyle.decorate(panel)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box


func _build_promotion_picker() -> void:
	_promotion = _make_overlay(true)
	_promotion.name = "PromotionPicker"
	var box := _make_dialog(_promotion)
	var title := UiStyle.make_title("Promote pawn to", 26)
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
	_game_over_title = UiStyle.make_title("Checkmate", 54)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_title.custom_minimum_size = Vector2(380, 0)
	box.add_child(_game_over_title)
	box.add_child(UiStyle.make_divider())
	_game_over_detail = UiStyle.make_label("", 21)
	_game_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_game_over_detail)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_add_button(row, "New game", func() -> void: new_game_requested.emit())
	_add_button(row, "Undo", func() -> void: undo_requested.emit())
	_add_button(row, "View board", hide_game_over)


# Everything that is drawn over the 3D view but under the panels: the
# letterbox bars, the vignette, the impact flash and the big banner.
func _build_cinematic_layer() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0.05, 0.0, 0.0, 0.85))
	gradient.set_offset(0, 0.45)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 1.0)
	texture.width = 256
	texture.height = 256
	_vignette = TextureRect.new()
	_vignette.name = "Vignette"
	_vignette.texture = texture
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_bar_top = ColorRect.new()
	_bar_top.name = "LetterboxTop"
	_bar_top.color = Color.BLACK
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.name = "LetterboxBottom"
	_bar_bottom.color = Color.BLACK
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_bottom)

	var center := CenterContainer.new()
	center.name = "Banner"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_right = -(PANEL_WIDTH + PANEL_MARGIN)
	center.offset_bottom = -260.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	center.add_child(holder)
	_banner = UiStyle.make_title("Checkmate", 104)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color(0.20, 0.03, 0.02))
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.add_theme_constant_override("shadow_outline_size", 22)
	_banner.add_theme_constant_override("shadow_offset_y", 6)
	holder.add_child(_banner)
	_banner_sub = UiStyle.make_label("", 26, UiStyle.TEXT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner_sub.add_theme_constant_override("outline_size", 8)
	holder.add_child(_banner_sub)
