class_name UiLayout
extends RefCounted
## Responsive layout: decides how the screens arrange themselves for the
## current window, and scales the UI up on touch devices so text and buttons
## stay finger-sized.
##
##   WIDE      desktop: a full side panel beside the board
##   COMPACT   a phone or tablet held sideways: a narrower, denser side panel
##   PORTRAIT  a tall window: the panel goes under the board, which is framed
##             by its width
##
## Start the game with `-- --touch` to try the touch layouts on a desktop.

enum Mode { WIDE, COMPACT, PORTRAIT }

## The UI is authored for a window this many pixels on its short side...
const DESKTOP_SHORT_SIDE := 800.0
## ...and on touch screens it is scaled so the short side is this many UI
## pixels (roughly Android's density-independent pixels).
const TOUCH_SHORT_SIDE_MIN := 420.0
const TOUCH_SHORT_SIDE_MAX := 760.0
const TOUCH_SHORT_SIDE_FORCED := 480.0

## Set to try the touch layouts without a touch device (tests, `--touch`).
static var force_touch := false


## True on phones and tablets (native or in a mobile browser).
static func is_touch() -> bool:
	return force_touch or OS.has_feature("mobile") or OS.has_feature("web_android") \
			or OS.has_feature("web_ios") or OS.get_cmdline_user_args().has("--touch")


## The layout for a window of `window_size` (in real pixels).
static func mode_for(window_size: Vector2, touch: bool = is_touch()) -> Mode:
	if window_size.y > window_size.x * 1.05:
		return Mode.PORTRAIT
	return Mode.COMPACT if touch else Mode.WIDE


## How much the UI is enlarged for a window of `window_size`: 1 on desktop;
## on touch screens whatever makes the short side `short_side_ui` UI pixels.
static func scale_for(window_size: Vector2, touch: bool, base_size: Vector2,
		short_side_ui: float = TOUCH_SHORT_SIDE_FORCED) -> float:
	if not touch or window_size.x <= 0.0 or window_size.y <= 0.0:
		return 1.0
	# What the "canvas_items / expand" stretch already does on its own.
	var stretch := minf(window_size.x / base_size.x, window_size.y / base_size.y)
	var short_side := minf(window_size.x, window_size.y)
	return maxf(short_side / (stretch * short_side_ui), 0.5)


# Short side of the screen in UI pixels: by physical size where the screen
# reports its density, so a tablet gets more room than a phone.
static func _touch_short_side(window: Window) -> float:
	if not (OS.has_feature("mobile") or OS.has_feature("web")):
		return TOUCH_SHORT_SIDE_FORCED
	var dpi := DisplayServer.screen_get_dpi(window.current_screen)
	if dpi <= 0:
		return TOUCH_SHORT_SIDE_FORCED
	var short_side := minf(window.size.x, window.size.y)
	return clampf(short_side / dpi * 160.0, TOUCH_SHORT_SIDE_MIN, TOUCH_SHORT_SIDE_MAX)


## Keeps `node`'s window scaled for touch and calls `on_layout(mode)` now and
## whenever the window is resized or rotated. Call from _ready.
static func watch(node: Node, on_layout: Callable) -> void:
	var window := node.get_window()
	var update := func() -> void:
		if not is_instance_valid(node) or not node.is_inside_tree():
			return
		var size := Vector2(window.size)
		var base := Vector2(
				ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
				ProjectSettings.get_setting("display/window/size/viewport_height", 800))
		var factor := scale_for(size, is_touch(), base, _touch_short_side(window))
		if absf(window.content_scale_factor - factor) > 0.01:
			window.content_scale_factor = factor
		on_layout.call(mode_for(size))
	window.size_changed.connect(update)
	node.tree_exiting.connect(func() -> void:
		if window.size_changed.is_connected(update):
			window.size_changed.disconnect(update)
		window.content_scale_factor = 1.0)
	update.call()
