class_name UiStyle
extends RefCounted
## Shared look for the menus and the HUD (all UI is built in code).

const TEXT := Color(0.92, 0.91, 0.88)
const TEXT_DIM := Color(0.66, 0.66, 0.68)
const ACCENT := Color(0.93, 0.76, 0.36)
const PANEL_BG := Color(0.075, 0.08, 0.095, 0.86)
const BUTTON_BG := Color(0.18, 0.19, 0.22)
const BUTTON_HOVER := Color(0.26, 0.27, 0.31)
const BUTTON_PRESSED := Color(0.93, 0.76, 0.36)

## Filled chess glyphs, indexed by piece type.
const GLYPHS := ["", "♟", "♞", "♝", "♜", "♛", "♚"]
const PIECE_NAMES := ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]

static var _glyph_font: SystemFont


static func panel(radius: int = 12, margin: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.border_color = Color(1, 1, 1, 0.07)
	sb.set_border_width_all(1)
	return sb


static func _button_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


## Applies the shared button look (works for Button, CheckButton, OptionButton).
static func style_button(button: Button, font_size: int = 15) -> void:
	button.add_theme_stylebox_override("normal", _button_box(BUTTON_BG))
	button.add_theme_stylebox_override("hover", _button_box(BUTTON_HOVER))
	button.add_theme_stylebox_override("pressed", _button_box(BUTTON_PRESSED))
	button.add_theme_stylebox_override("disabled", _button_box(Color(0.13, 0.13, 0.15)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.42))
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE


static func make_button(text: String, font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, font_size)
	return b


static func make_label(text: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## A font that has the chess glyphs on Windows, macOS and Linux.
static func glyph_font() -> Font:
	if _glyph_font == null:
		_glyph_font = SystemFont.new()
		_glyph_font.font_names = PackedStringArray([
			"Segoe UI Symbol", "Apple Symbols", "DejaVu Sans", "Noto Sans Symbols2", "FreeSerif"])
	return _glyph_font


static func glyph(type: int) -> String:
	return GLYPHS[type]
