class_name UiStyle
extends RefCounted
## Shared look for the menus and the HUD (all UI is built in code): dark
## leather panels with gilded frames and corner studs, parchment-colored serif
## text, blackletter titles where the system has such a font, and a sword for
## a mouse cursor. Nothing here needs an image or font file.

const TEXT := Color(0.94, 0.88, 0.74)       # parchment
const TEXT_DIM := Color(0.68, 0.59, 0.44)
const ACCENT := Color(0.95, 0.76, 0.34)     # gold leaf
const GOLD_DARK := Color(0.52, 0.37, 0.14)
const BLOOD := Color(0.62, 0.10, 0.08)
const PANEL_BG := Color(0.090, 0.062, 0.045, 0.94)
const BUTTON_BG := Color(0.205, 0.135, 0.085)
const BUTTON_HOVER := Color(0.33, 0.215, 0.115)
const BUTTON_PRESSED := Color(0.95, 0.76, 0.34)
const INK := Color(0.10, 0.065, 0.035)      # text on gold

## Filled chess glyphs, indexed by piece type.
const GLYPHS := ["", "♟", "♞", "♝", "♜", "♛", "♚"]
const PIECE_NAMES := ["", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]

const CURSOR_SIZE := 44
const CURSOR_HOTSPOT := Vector2(3, 3)

## Fallback for the glyphs, indexed by piece type.
const LETTERS := ["", "P", "N", "B", "R", "Q", "K"]

static var _glyph_font: SystemFont
static var _has_glyphs := -1  # -1 = not checked yet
static var _body_font: SystemFont
static var _title_font: SystemFont
static var _theme: Theme
static var _cursors := {}


# ------------------------------------------------------------------ fonts ---

## Serif text face (Palatino / Book Antiqua / Georgia, whichever exists).
static func body_font() -> Font:
	if _body_font == null:
		_body_font = SystemFont.new()
		_body_font.font_names = PackedStringArray([
			"Palatino Linotype", "Book Antiqua", "Palatino", "Constantia", "Georgia",
			"URW Palladio L", "Noto Serif", "DejaVu Serif", "serif"])
	return _body_font


## Display face for titles: a blackletter if the system has one, otherwise a
## bold serif.
static func title_font() -> Font:
	if _title_font == null:
		_title_font = SystemFont.new()
		_title_font.font_names = PackedStringArray([
			"Old English Text MT", "UnifrakturMaguntia", "Cloister Black", "Luminari",
			"Palatino Linotype", "Book Antiqua", "Georgia", "DejaVu Serif", "serif"])
		_title_font.font_weight = 700
	return _title_font


## A font that has the chess glyphs on Windows, macOS and Linux.
static func glyph_font() -> Font:
	if _glyph_font == null:
		_glyph_font = SystemFont.new()
		_glyph_font.font_names = PackedStringArray([
			"Segoe UI Symbol", "Apple Symbols", "DejaVu Sans", "Noto Sans Symbols2", "Noto Sans Symbols",
			"FreeSerif"])
	return _glyph_font


## The chess symbol for a piece type - or its letter where the device has
## no font with chess symbols (some phones and all web browsers).
static func glyph(type: int) -> String:
	if _has_glyphs == -1:
		_has_glyphs = 1 if glyph_font().has_char("♟".unicode_at(0)) else 0
	return GLYPHS[type] if _has_glyphs == 1 else LETTERS[type]


# ------------------------------------------------------------------ theme ---

## Theme for everything that is not styled control by control (line edits,
## popups, sliders, check buttons, separators, tooltips). Set it on the root
## control of a panel.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 15

	var field := _flat(Color(0.05, 0.035, 0.025, 0.9), GOLD_DARK, 1, 3)
	field.set_content_margin_all(7)
	var field_focus := _flat(Color(0.07, 0.05, 0.03, 0.95), ACCENT, 1, 3)
	field_focus.set_content_margin_all(7)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.7))
	t.set_color("caret_color", "LineEdit", ACCENT)

	var popup := _flat(Color(0.10, 0.07, 0.05, 0.98), GOLD_DARK, 2, 4)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _flat(BUTTON_HOVER, Color.TRANSPARENT, 0, 3))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_constant("v_separation", "PopupMenu", 8)

	var tip := _flat(Color(0.08, 0.055, 0.04, 0.97), GOLD_DARK, 1, 3)
	tip.set_content_margin_all(6)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)

	var line := StyleBoxLine.new()
	line.color = Color(GOLD_DARK, 0.8)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)

	for type: String in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, ACCENT)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, ACCENT)
		t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.5))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_icon("checked", "CheckButton", _toggle_icon(true, false))
	t.set_icon("unchecked", "CheckButton", _toggle_icon(false, false))
	t.set_icon("checked_disabled", "CheckButton", _toggle_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckButton", _toggle_icon(false, true))

	var groove := _flat(Color(0.04, 0.03, 0.02), GOLD_DARK, 1, 3)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	var fill := _flat(Color(ACCENT, 0.75), Color.TRANSPARENT, 0, 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _gem_icon(false))
	t.set_icon("grabber_highlight", "HSlider", _gem_icon(true))

	var scroll := _flat(Color(GOLD_DARK, 0.7), Color.TRANSPARENT, 0, 3)
	scroll.content_margin_left = 3
	scroll.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", scroll)
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(ACCENT, Color.TRANSPARENT, 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(ACCENT, Color.TRANSPARENT, 0, 3))
	t.set_stylebox("scroll", "VScrollBar", _flat(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, 3))
	_theme = t
	return t


static func _flat(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	return sb


# ----------------------------------------------------------------- panels ---

## Stylebox of a framed leather panel. Use decorate() on the control that
## carries it to add the inner gilt line and the corner studs.
static func panel(radius: int = 6, margin: int = 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(mini(radius, 6))
	sb.set_content_margin_all(margin + 4)
	sb.border_color = GOLD_DARK
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 14
	return sb


## Draws the ornaments of a framed panel on `control`: a thin inner gilt line
## and a diamond stud in each corner.
static func decorate(control: Control) -> void:
	control.draw.connect(func() -> void:
		var size := control.size
		var inset := 6.0
		var rect := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
		control.draw_rect(rect, Color(ACCENT, 0.28), false, 1.0)
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y),
				rect.end, Vector2(rect.position.x, rect.end.y)]:
			_draw_diamond(control, corner, 6.5, GOLD_DARK)
			_draw_diamond(control, corner, 4.0, ACCENT)
			_draw_diamond(control, corner, 1.6, INK))


static func _draw_diamond(control: Control, center: Vector2, r: float, color: Color) -> void:
	control.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)]),
		color)


## A horizontal rule with a diamond in the middle.
static func make_divider(height: int = 14) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var mid := c.size * 0.5
		var gap := 12.0
		c.draw_line(Vector2(0, mid.y), Vector2(mid.x - gap, mid.y), Color(GOLD_DARK, 0.9), 1.0)
		c.draw_line(Vector2(mid.x + gap, mid.y), Vector2(c.size.x, mid.y), Color(GOLD_DARK, 0.9), 1.0)
		_draw_diamond(c, mid, 5.0, GOLD_DARK)
		_draw_diamond(c, mid, 3.0, ACCENT)
		_draw_diamond(c, mid - Vector2(gap - 3.0, 0), 1.8, GOLD_DARK)
		_draw_diamond(c, mid + Vector2(gap - 3.0, 0), 1.8, GOLD_DARK))
	return c


# ---------------------------------------------------------------- buttons ---

static func _button_box(color: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_bottom = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 6
	return sb


## Applies the shared button look (works for Button, CheckButton, OptionButton).
static func style_button(button: Button, font_size: int = 15) -> void:
	button.add_theme_stylebox_override("normal", _button_box(BUTTON_BG, GOLD_DARK))
	button.add_theme_stylebox_override("hover", _button_box(BUTTON_HOVER, ACCENT))
	button.add_theme_stylebox_override("pressed", _button_box(BUTTON_PRESSED, GOLD_DARK))
	button.add_theme_stylebox_override("disabled", _button_box(Color(0.12, 0.09, 0.07), Color(0.22, 0.17, 0.11)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", ACCENT)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(0.42, 0.35, 0.27))
	button.add_theme_font_override("font", body_font())
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE


## The one gilded call-to-action button of a screen.
static func style_primary(button: Button, font_size: int = 22) -> void:
	style_button(button, font_size)
	var normal := _button_box(ACCENT, Color(1.0, 0.92, 0.62))
	var hover := _button_box(ACCENT.lightened(0.18), Color.WHITE)
	for sb: StyleBoxFlat in [normal, hover]:
		sb.content_margin_top = 11
		sb.content_margin_bottom = 10
		sb.border_color = GOLD_DARK
		sb.set_border_width_all(2)
		sb.border_width_bottom = 4
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", _button_box(GOLD_DARK, ACCENT))
	button.add_theme_font_override("font", title_font())
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color_name, INK)


static func make_button(text: String, font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, font_size)
	return b


static func make_label(text: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## A title in the display face, with a dark drop shadow.
static func make_title(text: String, font_size: int = 30, color: Color = ACCENT) -> Label:
	var l := make_label(text, font_size, color)
	l.add_theme_font_override("font", title_font())
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 4)
	return l


## A small heading: spaced capitals in dim gold.
static func make_heading(text: String) -> Label:
	var l := make_label(text.to_upper(), 12, Color(ACCENT, 0.72))
	var spaced := FontVariation.new()
	spaced.base_font = body_font()
	spaced.spacing_glyph = 2
	l.add_theme_font_override("font", spaced)
	return l


# ------------------------------------------------------------------ icons ---

# CheckButton switch: a slot with a gold (on) or iron (off) stud.
static func _toggle_icon(on: bool, disabled: bool) -> Texture2D:
	var w := 40
	var h := 22
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var knob := Vector2(w - 11.0, h * 0.5) if on else Vector2(11.0, h * 0.5)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Rounded slot.
			var q := Vector2(clampf(p.x, 11.0, w - 11.0), h * 0.5)
			var d := p.distance_to(q)
			var color := Color(0, 0, 0, 0)
			if d < 8.5:
				color = Color(0.05, 0.035, 0.025)
				if on:
					color = color.lerp(GOLD_DARK, 0.55)
				if d > 7.2:
					color = GOLD_DARK
				color.a = clampf(8.5 - d, 0.0, 1.0)
			var kd := p.distance_to(knob)
			if kd < 8.0:
				var stud := ACCENT if on else Color(0.55, 0.50, 0.44)
				stud = stud.lightened(0.25 * clampf(1.0 - p.distance_to(knob - Vector2(2, 2)) / 6.0, 0.0, 1.0))
				if kd > 6.6:
					stud = INK
				color = color.blend(Color(stud, clampf(8.0 - kd, 0.0, 1.0)))
			if disabled:
				color.a *= 0.4
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


# Slider grabber: a gold diamond.
static func _gem_icon(bright: bool) -> Texture2D:
	var s := 18
	var image := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s, s) * 0.5
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var d := absf(p.x) + absf(p.y)
			var color := Color(0, 0, 0, 0)
			if d < 8.5:
				color = ACCENT.lightened(0.3) if bright else ACCENT
				color = color.darkened(0.25) if p.y > 0.0 else color
				if d > 6.6:
					color = INK
				color.a = clampf(8.5 - d, 0.0, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


# ----------------------------------------------------------------- cursor ---

## Swaps the mouse pointer for a sword (and a glowing sword where the game
## asks for the pointing-hand shape), or restores the system cursor.
static func set_sword_cursor(enabled: bool) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CUSTOM_CURSOR_SHAPE):
		return
	if not enabled:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	Input.set_custom_mouse_cursor(cursor_texture(false), Input.CURSOR_ARROW, CURSOR_HOTSPOT)
	Input.set_custom_mouse_cursor(cursor_texture(true), Input.CURSOR_POINTING_HAND, CURSOR_HOTSPOT)


static func cursor_texture(glowing: bool) -> Texture2D:
	if not _cursors.has(glowing):
		_cursors[glowing] = ImageTexture.create_from_image(cursor_image(glowing))
	return _cursors[glowing]


## The sword pointer, drawn pixel by pixel: the tip is the hotspot and the
## blade runs down to the right. `glowing` adds a golden halo.
static func cursor_image(glowing: bool) -> Image:
	var image := Image.create(CURSOR_SIZE, CURSOR_SIZE, false, Image.FORMAT_RGBA8)
	var steel := Color(0.90, 0.92, 0.96)
	var gold := ACCENT.lightened(0.15) if glowing else ACCENT
	var leather := Color(0.36, 0.17, 0.09)
	var samples := 3
	for y in CURSOR_SIZE:
		for x in CURSOR_SIZE:
			var sum := Color(0, 0, 0, 0)
			var weight := 0.0
			var halo := 0.0
			for sy in samples:
				for sx in samples:
					var p := Vector2(x + (sx + 0.5) / samples, y + (sy + 0.5) / samples) - CURSOR_HOTSPOT
					var t := (p.x + p.y) * 0.70710678   # along the sword, from the tip
					var s := (p.y - p.x) * 0.70710678   # across it
					var part := _sword_part(t, s, 0.0)
					var color := Color(0, 0, 0, 0)
					match part:
						1: color = steel.darkened(0.22) if s > 0.35 else (Color.WHITE if absf(s) < 0.35 else steel)
						2: color = gold.darkened(0.2) if s * t > 0.0 and absf(s) > 6.0 else gold
						3: color = leather.lightened(0.18) if int(t) % 2 == 0 else leather
						4: color = gold
						_:
							if _sword_part(t, s, 1.5) != 0:
								color = Color(INK, 1.0)
							elif glowing and _sword_part(t, s, 4.5) != 0:
								halo += 1.0
					if color.a > 0.0:
						sum += color
						weight += 1.0
			var n := float(samples * samples)
			var out := Color(0, 0, 0, 0)
			if weight > 0.0:
				out = Color(sum.r / weight, sum.g / weight, sum.b / weight, weight / n)
			if halo > 0.0:
				out = Color(ACCENT.lightened(0.3), 0.45 * halo / n).blend(out)
			image.set_pixel(x, y, out)
	return image


# Which part of the sword (grown by `grow` pixels) covers the point at `t`
# along / `s` across: 0 none, 1 blade, 2 guard, 3 grip, 4 pommel.
static func _sword_part(t: float, s: float, grow: float) -> int:
	var a := absf(s)
	if t >= -grow and t < 31.0 and a <= minf(3.1, 0.25 + t * 0.52) + grow:
		return 1
	if t >= 31.0 - grow and t <= 34.6 + grow and a <= 9.5 + grow:
		return 2
	if t > 34.6 and t <= 45.0 + grow and a <= 2.1 + grow:
		return 3
	if Vector2(t - 47.6, s).length() <= 3.7 + grow:
		return 4
	return 0
