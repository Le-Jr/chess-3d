class_name CameraRig
extends Node3D
## Orbit camera looking at the board center.
##
## - Right-drag orbits a little (yaw limited around the current side, pitch
##   clamped so the view stays "mostly top-down").
## - Mouse wheel zooms, clamped.
## - face_side() swings the camera 180 degrees to the other player's seat.

## Degrees above the horizontal. 60 = mostly top-down, but angled enough to
## read the piece silhouettes.
@export_range(30.0, 88.0) var pitch_deg: float = 60.0
@export var min_pitch_deg: float = 32.0
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
## Higher = snappier camera motion.
@export var smoothing: float = 7.0
@export var orbit_sensitivity: float = 0.28
@export var zoom_step: float = 0.9

var camera: Camera3D

# Seat yaw: 0 = behind White (+Z), 180 = behind Black. Kept unbounded so the
# camera always swings the same way around.
var _seat_yaw := 0.0
var _yaw_offset := 0.0
var _target_pitch := 60.0
var _target_distance := 14.2

var _yaw := 0.0
var _pitch := 60.0
var _dist := 14.2
var _dragging := false


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


## Jumps straight to the target view (no easing).
func snap() -> void:
	_yaw = _seat_yaw + _yaw_offset
	_pitch = _target_pitch
	_dist = _target_distance
	_apply()


func _process(delta: float) -> void:
	var w := 1.0 - exp(-smoothing * delta)
	var target_yaw := _seat_yaw + _yaw_offset
	if is_equal_approx(_yaw, target_yaw) and is_equal_approx(_pitch, _target_pitch) \
			and is_equal_approx(_dist, _target_distance):
		return
	_yaw = lerpf(_yaw, target_yaw, w)
	_pitch = lerpf(_pitch, _target_pitch, w)
	_dist = lerpf(_dist, _target_distance, w)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
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
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(_pitch)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var focus := Vector3(sin(yaw), 0.0, cos(yaw)) * focus_offset
	camera.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), focus + dir * _dist)
	if screen_shift_px != 0.0 and is_inside_tree():
		var view_height := get_viewport().get_visible_rect().size.y
		var units_per_px := 2.0 * _dist * tan(deg_to_rad(camera.fov) * 0.5) / maxf(view_height, 1.0)
		camera.h_offset = screen_shift_px * 0.5 * units_per_px


## Sets the view directly (debugging / screenshots); ignores the usual clamps.
func set_view(yaw_offset_deg: float, new_pitch_deg: float, new_distance: float) -> void:
	_yaw_offset = yaw_offset_deg
	_target_pitch = new_pitch_deg
	_target_distance = new_distance
	snap()
