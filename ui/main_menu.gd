extends Node3D
## Main menu: game mode, color, AI difficulty, look (materials) and piece set,
## over a slowly turning live preview of the board with the chosen look.

const GAME_SCENE := "res://scenes/game.tscn"
const PANEL_WIDTH := 400
const PANEL_MARGIN := 28

## 0 = White, 1 = Black, 2 = Random.
var _color_choice := 0
var _piece_sets: Array[Dictionary] = []

var _board: Board3D
var _camera_rig: CameraRig
var _preview_pieces: Array[Node] = []
var _yaw := 20.0

var _color_buttons: Array[Button] = []
var _level_buttons: Array[Button] = []
var _color_row: Control
var _level_row: Control
var _rotate_check: CheckButton
var _engine_row: Control
var _music: MenuMusic
var _panel: PanelContainer


func _ready() -> void:
	GameSettings.load_saved()
	Sfx.warm_up()
	_color_choice = 1 if GameSettings.human_color == Piece.BLACK else 0
	_piece_sets = GameSettings.available_piece_sets()

	Stage.build(self)
	_board = Board3D.new()
	add_child(_board)
	_camera_rig = CameraRig.new()
	_camera_rig.screen_shift_px = -(PANEL_WIDTH + PANEL_MARGIN)
	_camera_rig.set_process(false)
	_camera_rig.set_process_unhandled_input(false)
	add_child(_camera_rig)

	_music = MenuMusic.new()
	_music.name = "MenuMusic"
	add_child(_music)

	_build_ui()
	_refresh_preview()
	_update_enabled()
	UiLayout.watch(self, _on_layout)


# Desktop and sideways phones: the panel on the left, the board beside it.
# Upright: the board on top, the panel filling the rest (it scrolls).
func _on_layout(mode: int) -> void:
	if mode == UiLayout.Mode.PORTRAIT:
		var height := get_viewport().get_visible_rect().size.y
		var board_room := clampf(height * 0.32, 220.0, 420.0)
		_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_panel.offset_left = 12
		_panel.offset_right = -12
		_panel.offset_top = board_room
		_panel.offset_bottom = -12
		_camera_rig.set_frame(true, 0.0, height - board_room)
	else:
		var margin := 12 if mode == UiLayout.Mode.COMPACT else PANEL_MARGIN
		_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		_panel.offset_left = margin
		_panel.offset_right = margin + PANEL_WIDTH
		_panel.offset_top = margin
		_panel.offset_bottom = -margin
		_camera_rig.set_frame(false, -(PANEL_WIDTH + margin), 0.0)


func _process(delta: float) -> void:
	_yaw = fmod(_yaw + delta * 5.0, 360.0)
	_camera_rig.set_view(_yaw, 34.0, 15.5)


# ---------------------------------------------------------------- actions ---

## Applies the menu choices and switches to the game scene.
func start_game() -> void:
	apply_choices()
	GameSettings.save()
	get_tree().change_scene_to_file(GAME_SCENE)


## Resolves "Random" and stores the color choice in GameSettings.
func apply_choices() -> void:
	match _color_choice:
		0:
			GameSettings.human_color = Piece.WHITE
		1:
			GameSettings.human_color = Piece.BLACK
		_:
			GameSettings.human_color = Piece.WHITE if randi() % 2 == 0 else Piece.BLACK


func set_mode(index: int) -> void:
	GameSettings.mode = index as GameSettings.Mode
	_update_enabled()


func set_color_choice(index: int) -> void:
	_color_choice = index


func set_level(index: int) -> void:
	GameSettings.ai_level = index


func set_preset(index: int) -> void:
	GameSettings.material_preset = index
	_refresh_preview()


func set_piece_set(index: int) -> void:
	GameSettings.piece_set_path = _piece_sets[index]["path"]
	_refresh_preview()


func set_music(on: bool) -> void:
	GameSettings.music = on
	_music.set_enabled(on)


func _update_enabled() -> void:
	var vs_ai := GameSettings.mode == GameSettings.Mode.VS_AI
	for b in _color_buttons:
		b.disabled = not vs_ai
	for b in _level_buttons:
		b.disabled = not vs_ai
	_color_row.modulate.a = 1.0 if vs_ai else 0.45
	_level_row.modulate.a = 1.0 if vs_ai else 0.45
	_engine_row.modulate.a = 1.0 if vs_ai else 0.45
	_rotate_check.disabled = vs_ai
	_rotate_check.modulate.a = 0.45 if vs_ai else 1.0


# Rebuilds the preview board with the selected materials and piece set.
func _refresh_preview() -> void:
	_board.apply_preset(GameSettings.material_preset)
	for node in _preview_pieces:
		node.queue_free()
	_preview_pieces.clear()
	var piece_set := GameSettings.make_piece_set()
	var position := Board.new()
	for rank in 8:
		for file in 8:
			var square := Board.sq(file, rank)
			var p := position.piece_at(square)
			if p == Piece.NONE:
				continue
			var node := Piece3D.new()
			node.setup(p, piece_set)
			node.position = Board3D.square_to_local(square)
			_board.add_child(node)
			_preview_pieces.append(node)


# --------------------------------------------------------------- building ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.theme = UiStyle.theme()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(6, 24))
	UiStyle.decorate(panel)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = PANEL_MARGIN
	panel.offset_right = PANEL_MARGIN + PANEL_WIDTH
	panel.offset_top = PANEL_MARGIN
	panel.offset_bottom = -PANEL_MARGIN
	layer.add_child(panel)
	_panel = panel

	# The options scroll when the window is too short for them (a phone
	# held sideways); the Start button stays in view underneath.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.name = "Options"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := UiStyle.make_title("Chess 3D", 54)
	box.add_child(title)
	box.add_child(UiStyle.make_label("Play on one computer, or against the engine.", 14, UiStyle.TEXT_DIM))
	box.add_child(UiStyle.make_divider())

	_add_choice_row(box, "Mode", ["Two players", "vs Computer"], int(GameSettings.mode), set_mode)
	_color_row = _add_choice_row(box, "Play as", ["White", "Black", "Random"], _color_choice,
			set_color_choice, _color_buttons)
	_level_row = _add_choice_row(box, "Difficulty", _level_names(), GameSettings.ai_level,
			set_level, _level_buttons)
	_engine_row = VBoxContainer.new()
	box.add_child(_engine_row)
	_engine_row.add_child(UiStyle.make_label("Stockfish executable (optional)", 13, UiStyle.TEXT_DIM))
	var engine_path := LineEdit.new()
	engine_path.name = "StockfishPath"
	engine_path.placeholder_text = "Empty = built-in engine"
	engine_path.text = GameSettings.stockfish_path
	engine_path.add_theme_font_size_override("font_size", 13)
	engine_path.text_changed.connect(func(text: String) -> void: GameSettings.stockfish_path = text.strip_edges())
	_engine_row.add_child(engine_path)
	# An external engine can only be started on a desktop.
	_engine_row.visible = not (UiLayout.is_touch() or OS.has_feature("web"))
	box.add_child(UiStyle.make_divider())
	box.add_child(UiStyle.make_label("Look", 13, UiStyle.TEXT_DIM))
	var looks := OptionButton.new()
	looks.name = "LookPicker"
	UiStyle.style_button(looks)
	for preset_name: String in MaterialPresets.NAMES:
		looks.add_item(preset_name)
	looks.select(GameSettings.material_preset)
	looks.item_selected.connect(set_preset)
	box.add_child(looks)

	box.add_child(UiStyle.make_label("Pieces", 13, UiStyle.TEXT_DIM))
	var sets := OptionButton.new()
	UiStyle.style_button(sets)
	var selected := 0
	for i in _piece_sets.size():
		sets.add_item(_piece_sets[i]["name"])
		if _piece_sets[i]["path"] == GameSettings.piece_set_path:
			selected = i
	sets.select(selected)
	sets.item_selected.connect(set_piece_set)
	box.add_child(sets)

	_rotate_check = CheckButton.new()
	_rotate_check.text = "Rotate board each turn"
	_rotate_check.button_pressed = GameSettings.auto_rotate_camera
	_rotate_check.add_theme_font_size_override("font_size", 14)
	_rotate_check.focus_mode = Control.FOCUS_NONE
	_rotate_check.toggled.connect(func(on: bool) -> void: GameSettings.auto_rotate_camera = on)
	box.add_child(_rotate_check)

	var sound_check := CheckButton.new()
	sound_check.name = "SoundCheck"
	sound_check.text = "Sound effects"
	sound_check.button_pressed = GameSettings.sound
	sound_check.add_theme_font_size_override("font_size", 14)
	sound_check.focus_mode = Control.FOCUS_NONE
	sound_check.toggled.connect(func(on: bool) -> void: GameSettings.sound = on)
	box.add_child(sound_check)

	var music_check := CheckButton.new()
	music_check.name = "MusicCheck"
	music_check.text = "Menu music"
	music_check.button_pressed = GameSettings.music
	music_check.add_theme_font_size_override("font_size", 14)
	music_check.focus_mode = Control.FOCUS_NONE
	music_check.toggled.connect(set_music)
	box.add_child(music_check)

	var start := UiStyle.make_button("Start game", 22)
	start.name = "StartButton"
	UiStyle.style_primary(start, 26)
	start.pressed.connect(start_game)
	column.add_child(start)

	# Phones and browsers have their own way out.
	if not (OS.has_feature("mobile") or OS.has_feature("web")):
		var quit := UiStyle.make_button("Quit", 15)
		quit.pressed.connect(func() -> void: get_tree().quit())
		column.add_child(quit)


func _level_names() -> Array:
	var names := []
	for level: Dictionary in ChessAI.LEVELS:
		names.append(level["name"])
	return names


# A label plus a row of mutually exclusive toggle buttons. Returns the row.
func _add_choice_row(parent: Control, title: String, options: Array, selected: int,
		on_selected: Callable, collect: Array[Button] = []) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 5)
	parent.add_child(wrapper)
	wrapper.add_child(UiStyle.make_label(title, 13, UiStyle.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	wrapper.add_child(row)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := UiStyle.make_button(str(options[i]), 14)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(on_selected.bind(i))
		row.add_child(b)
		collect.append(b)
	return wrapper


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
