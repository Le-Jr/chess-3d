class_name CameraRig
extends Node3D
## Orbit camera looking at the board center.
##
## - set_pitch() chooses the resting angle (the HUD's camera slider), from a
##   low dramatic view to almost straight down.
## - Right-drag orbits a little (yaw limited around the current side, pitch
##   clamped); mouse wheel zooms, clamped.
## - face_side() swings the camera 180 degrees to the other player's seat.
## - punch_in() pushes in on a square for a moment (a capture), cinematic()
##   flies to a close, low, slowly orbiting shot (checkmate) until release().
##   Both keep real time, so they work during slow motion.

## Range offered by the camera-angle setting.
const SETTING_MIN_PITCH := 24.0
const SETTING_MAX_PITCH := 80.0

## Degrees above the horizontal. 50 reads the piece silhouettes well; 80 is
## almost top-down.
@export_range(20.0, 88.0) var pitch_deg: float = 50.0
@export var min_pitch_deg: float = 20.0
@export var max_pitch_deg: float = 86.0
@export var distance: float = 14.2
@export var min_distance: float = 8.0
@export var max_distance: float = 20.0
## How far right-drag may turn the view away from the seat, in degrees.
@export var max_yaw_offset_deg: float = 70.0
@export var fov_deg: float = 40.0
## The camera aims at a point this far from the board center toward the
## viewer, which centers the board on screen despite the perspective.
@export var focus_offset: float = 0.85
## Width in UI pixels of a panel covering the right edge of the screen; the
## view shifts left by half of it so the board stays centered in the rest.
@export var screen_shift_px: float = 0.0
## Same, for a panel along the bottom edge: the view shifts up.
@export var screen_shift_y_px: float = 0.0
## Frame the board by the window's width instead of its height (a tall,
## portrait window), from `portrait_zoom` times further away.
@export var fit_width: bool = false
@export var portrait_zoom: float = 1.12
## Touch: degrees of orbit per UI pixel dragged with one finger.
@export var touch_sensitivity: float = 0.32
## Higher = snappier camera motion.
@export var smoothing: float = 7.0
@export var orbit_sensitivity: float = 0.28
@export var zoom_step: float = 0.9

var camera: Camera3D

# Seat yaw: 0 = behind White (+Z), 180 = behind Black. Kept unbounded so the
# camera always swings the same way around.
var _seat_yaw := 0.0
var _yaw_offset := 0.0
var _target_pitch := 50.0
var _target_distance := 14.2

var _yaw := 0.0
var _pitch := 50.0
var _dist := 14.2
var _dragging := false
var _touches := {}       # finger index -> position
var _pinch_span := 0.0   # distance between two fingers at the last event
var _shake := 0.0

# The current effect shot, blended over the normal view by _fx_weight.
var _fx_weight := 0.0
var _fx_point := Vector3.ZERO  # what the shot looks at (board space)
var _fx_pull := 0.0            # how far the aim moves toward it at full weight
var _fx_dist := 14.2
var _fx_pitch := -1.0          # degrees, or < 0 to keep the current pitch
var _fx_yaw := 0.0             # extra yaw, degrees
var _fx_orbit := 0.0           # degrees per second added to _fx_yaw
var _fx_fov := 0.0             # degrees removed from the field of view
var _fx_tween: Tween
var _last_usec := 0


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)


func _ready() -> void:
	camera.fov = fov_deg
	_target_pitch = pitch_deg
	_target_distance = distance
	_last_usec = Time.get_ticks_usec()
	snap()


## Which side the camera currently sits behind.
func facing_side() -> int:
	return Piece.WHITE if posmod(roundi(_seat_yaw / 180.0), 2) == 0 else Piece.BLACK


## Moves the camera behind `color`'s side of the board.
func face_side(color: int, animate: bool = true) -> void:
	if facing_side() != color:
		_seat_yaw += 180.0
	_yaw_offset = 0.0
	if not animate:
		snap()


func flip(animate: bool = true) -> void:
	face_side(Piece.opposite(facing_side()), animate)


## Sets the resting camera angle, in degrees above the horizontal.
func set_pitch(degrees: float, animate: bool = true) -> void:
	pitch_deg = clampf(degrees, min_pitch_deg, max_pitch_deg)
	_target_pitch = pitch_deg
	if not animate:
		snap()


## Adapts the framing to the screen layout: `portrait` frames the board by
## the window's width; the shifts are the UI pixels covered by a panel on
## the right (negative: on the left) and along the bottom.
func set_frame(portrait: bool, shift_x_px: float, shift_y_px: float) -> void:
	fit_width = portrait
	screen_shift_px = shift_x_px
	screen_shift_y_px = shift_y_px
	if is_inside_tree():
		_apply()


## Jumps straight to the target view (no easing).
func snap() -> void:
	_yaw = _seat_yaw + _yaw_offset
	_pitch = _target_pitch
	_dist = _target_distance
	_apply()


# ---------------------------------------------------------------- effects ---

## Jolts the view briefly (a capture landing). `strength` is in board units.
func shake(strength: float = 0.06) -> void:
	_shake = maxf(_shake, strength)


## Pushes in toward `point` (board space) and eases back: `zoom` is the
## fraction of the distance closed, `time` the whole effect in real seconds.
func punch_in(point: Vector3, zoom: float = 0.2, time: float = 0.6) -> void:
	if is_in_cinematic() or not is_inside_tree():
		return
	_start_fx(point, 0.6, _dist * (1.0 - zoom), -1.0, 0.0, 3.0)
	_fx_tween.tween_property(self, "_fx_weight", 1.0, time * 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(self, "_fx_weight", 0.0, time * 0.78) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Flies to a close shot of `point` from `shot_pitch_deg` above the horizon
## and `shot_distance` away, turned `yaw_deg` from the current view and then
## orbiting at `orbit_deg_per_sec`. Stays there until release().
func cinematic(point: Vector3, shot_pitch_deg: float, shot_distance: float, yaw_deg: float = 0.0,
		orbit_deg_per_sec: float = 0.0, time: float = 1.1) -> void:
	if not is_inside_tree():
		return
	_start_fx(point, 1.0, shot_distance, shot_pitch_deg, orbit_deg_per_sec, 2.0)
	_fx_yaw = yaw_deg
	_fx_tween.tween_property(self, "_fx_weight", 1.0, time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Returns from the effect shot to the normal view over `time` real seconds.
func release(time: float = 1.0) -> void:
	_kill_fx_tween()
	if time <= 0.0 or not is_inside_tree() or _fx_weight <= 0.0:
		_fx_weight = 0.0
		_fx_orbit = 0.0
		_fx_pull = 0.0
		_apply()
		return
	_fx_orbit = 0.0
	_fx_tween = create_tween()
	_ignore_time_scale(_fx_tween)
	_fx_tween.tween_property(self, "_fx_weight", 0.0, time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx_tween.tween_callback(func() -> void: _fx_pull = 0.0)


## True while a cinematic() shot is flying in or held.
func is_in_cinematic() -> bool:
	return _fx_pull >= 1.0


## How much of the view is taken over by the current effect (0..1).
func effect_weight() -> float:
	return _fx_weight


func _start_fx(point: Vector3, pull: float, dist: float, pitch: float, orbit: float, fov: float) -> void:
	_kill_fx_tween()
	_fx_point = point
	_fx_pull = pull
	_fx_dist = dist
	_fx_pitch = pitch
	_fx_orbit = orbit
	_fx_fov = fov
	_fx_yaw = 0.0
	_fx_tween = create_tween()
	_ignore_time_scale(_fx_tween)


func _kill_fx_tween() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = null


# Effect tweens keep real time while the game runs in slow motion.
static func _ignore_time_scale(tween: Tween) -> void:
	if tween.has_method("set_ignore_time_scale"):
		tween.call("set_ignore_time_scale", true)


# ---------------------------------------------------------------- process ---

func _process(delta: float) -> void:
	# Real elapsed time, so the effects are not slowed by Engine.time_scale.
	var now := Time.get_ticks_usec()
	var real_delta := minf((now - _last_usec) / 1000000.0, 0.1)
	_last_usec = now

	var w := 1.0 - exp(-smoothing * delta)
	var target_yaw := _seat_yaw + _yaw_offset
	var busy := _shake > 0.0 or _fx_weight > 0.0 or _fx_tween != null
	if _shake > 0.0:
		_shake *= exp(-11.0 * real_delta)
		if _shake < 0.003:
			_shake = 0.0
	if _fx_weight > 0.0:
		_fx_yaw += _fx_orbit * real_delta
	if _fx_tween != null and not _fx_tween.is_valid():
		_fx_tween = null
	if not busy and is_equal_approx(_yaw, target_yaw) and is_equal_approx(_pitch, _target_pitch) \
			and is_equal_approx(_dist, _target_distance):
		return
	_yaw = lerpf(_yaw, target_yaw, w)
	_pitch = lerpf(_pitch, _target_pitch, w)
	_dist = lerpf(_dist, _target_distance, w)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	# Touch: one finger orbits, two fingers pinch to zoom. The mouse events
	# the engine synthesizes from touches are ignored, so nothing counts twice.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_span = 0.0
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() == 1:
			_yaw_offset = clampf(_yaw_offset - drag.relative.x * touch_sensitivity,
					-max_yaw_offset_deg, max_yaw_offset_deg)
			_target_pitch = clampf(_target_pitch + drag.relative.y * touch_sensitivity,
					min_pitch_deg, max_pitch_deg)
		elif _touches.size() >= 2:
			var points: Array = _touches.values()
			var span: float = (points[0] as Vector2).distance_to(points[1])
			if _pinch_span > 1.0 and span > 1.0:
				_target_distance = clampf(_target_distance * _pinch_span / span, min_distance, max_distance)
			_pinch_span = span
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - zoom_step, min_distance, max_distance)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + zoom_step, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw_offset = clampf(_yaw_offset - mm.relative.x * orbit_sensitivity,
				-max_yaw_offset_deg, max_yaw_offset_deg)
		_target_pitch = clampf(_target_pitch + mm.relative.y * orbit_sensitivity,
				min_pitch_deg, max_pitch_deg)


func _apply() -> void:
	var fx := _fx_weight
	var yaw := deg_to_rad(_yaw + _fx_yaw * fx)
	var pitch := deg_to_rad(lerpf(_pitch, _fx_pitch, fx) if _fx_pitch >= 0.0 else _pitch)
	var dist := lerpf(_dist, _fx_dist, fx) * (portrait_zoom if fit_width else 1.0)
	camera.keep_aspect = Camera3D.KEEP_WIDTH if fit_width else Camera3D.KEEP_HEIGHT
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var focus := Vector3(sin(yaw), 0.0, cos(yaw)) * focus_offset
	focus = focus.lerp(_fx_point, fx * _fx_pull)
	camera.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), focus + dir * dist)
	camera.fov = fov_deg - _fx_fov * fx
	var shift := Vector2.ZERO
	if (screen_shift_px != 0.0 or screen_shift_y_px != 0.0) and is_inside_tree():
		# The field of view spans the window's width or its height, depending
		# on which one frames the board.
		var view := get_viewport().get_visible_rect().size
		var span := view.x if fit_width else view.y
		var units_per_px := 2.0 * dist * tan(deg_to_rad(camera.fov) * 0.5) / maxf(span, 1.0)
		shift = Vector2(screen_shift_px, -screen_shift_y_px) * 0.5 * units_per_px
	camera.h_offset = shift.x + randf_range(-1.0, 1.0) * _shake
	camera.v_offset = shift.y + randf_range(-1.0, 1.0) * _shake


## Sets the view directly (debugging / screenshots); ignores the usual clamps.
func set_view(yaw_offset_deg: float, new_pitch_deg: float, new_distance: float) -> void:
	_yaw_offset = yaw_offset_deg
	_target_pitch = new_pitch_deg
	_target_distance = new_distance
	snap()
