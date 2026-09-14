# ==============================================================================
# ФАЙЛ: src/main/camera_3d.gd
# НАЗНАЧЕНИЕ: RTS-камера без паразитного сдвига при захвате персонажа
# ==============================================================================
extends Node3D

@export_group("Zoom & Pitch Settings")
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 3.0
@export var max_zoom: float = 25.0
@export var pitch_at_min_zoom: float = -20.0
@export var pitch_at_max_zoom: float = -60.0

@export_group("Movement & Friction")
@export var pan_speed: float = 1.0
@export var friction: float = 15.0

@export_group("Rubber Band Bounds")
@export var bounds_min: Vector2 = Vector2(-50, -50)
@export var bounds_max: Vector2 = Vector2(50, 50)
@export var rubber_band_margin: float = 10.0
@export var return_speed: float = 12.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var is_locked: bool = false:
	set(value):
		is_locked = value
		if is_locked:
			cancel_drag()

var _is_dragging: bool = false
var _drag_plane: Plane
var _drag_start_world_pos: Vector3 = Vector3.ZERO
var _pan_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	_update_zoom_and_pitch()

func cancel_drag() -> void:
	_is_dragging = false
	_drag_start_world_pos = Vector3.ZERO
	_pan_velocity = Vector3.ZERO

func force_reset_drag() -> void:
	cancel_drag()

func _unhandled_input(event: InputEvent) -> void:
	if is_locked:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(-zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(event.position)
			else:
				_stop_drag()

	elif event is InputEventMouseMotion and _is_dragging:
		var current_world_pos = _get_ground_position(event.position)
		if current_world_pos != Vector3.ZERO:
			var move_delta = _drag_start_world_pos - current_world_pos
			var target_pos = global_position + move_delta
			
			global_position = _apply_rubber_band_to_position(target_pos)
			_pan_velocity = move_delta / get_process_delta_time()

func _process(delta: float) -> void:
	if is_locked or _is_dragging:
		return

	# Инерция и возврат от границ
	if _is_position_out_of_bounds(global_position):
		var clamped_pos = _get_clamped_position(global_position)
		global_position = global_position.lerp(clamped_pos, return_speed * delta)
		_pan_velocity = Vector3.ZERO
	elif _pan_velocity.length_squared() > 0.001:
		var target_pos = global_position + _pan_velocity * delta
		global_position = _apply_rubber_band_to_position(target_pos)
		_pan_velocity = _pan_velocity.lerp(Vector3.ZERO, friction * delta)

func _start_drag(mouse_pos: Vector2) -> void:
	_drag_plane = Plane(Vector3.UP, global_position.y)
	var hit_pos = _get_ground_position(mouse_pos)
	if hit_pos != Vector3.ZERO:
		_is_dragging = true
		_drag_start_world_pos = hit_pos

func _stop_drag() -> void:
	_is_dragging = false
	_drag_start_world_pos = Vector3.ZERO

func _get_ground_position(mouse_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.ZERO
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var intersection = _drag_plane.intersects_ray(ray_origin, ray_dir)
	return intersection if intersection != null else Vector3.ZERO

func _apply_rubber_band_to_position(pos: Vector3) -> Vector3:
	var res_x = _get_axis_resistance(pos.x, bounds_min.x, bounds_max.x)
	var res_z = _get_axis_resistance(pos.z, bounds_min.y, bounds_max.y)
	return Vector3(res_x, pos.y, res_z)

func _get_axis_resistance(val: float, min_val: float, max_val: float) -> float:
	if val < min_val:
		var over = min_val - val
		var factor = 1.0 - (over / (over + rubber_band_margin))
		return min_val - (over * factor)
	elif val > max_val:
		var over = val - max_val
		var factor = 1.0 - (over / (over + rubber_band_margin))
		return max_val + (over * factor)
	return val

func _is_position_out_of_bounds(pos: Vector3) -> bool:
	return pos.x < bounds_min.x or pos.x > bounds_max.x or pos.z < bounds_min.y or pos.z > bounds_max.y

func _get_clamped_position(pos: Vector3) -> Vector3:
	return Vector3(
		clamp(pos.x, bounds_min.x, bounds_max.x),
		pos.y,
		clamp(pos.z, bounds_min.y, bounds_max.y)
	)

func _zoom(amount: float) -> void:
	if not spring_arm:
		return
	spring_arm.spring_length = clamp(spring_arm.spring_length + amount, min_zoom, max_zoom)
	_update_zoom_and_pitch()

func _update_zoom_and_pitch() -> void:
	if not spring_arm:
		return
	var t = clamp((spring_arm.spring_length - min_zoom) / (max_zoom - min_zoom), 0.0, 1.0)
	rotation_degrees.x = lerp(pitch_at_min_zoom, pitch_at_max_zoom, t)
