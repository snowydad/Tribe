# ==============================================================================
# CAMERA_3D.GD — RTS / Colony Sim Контроллер Камеры (Godot 4)
# ==============================================================================
# 
# СТРУКТУРА УЗЛОВ В СЦЕНЕ:
#   CameraAnchor (Node3D)          <-- [Этот скрипт висит здесь] Позиция (X, Z), наклон и слежение за Y рельефа
#    └── SpringArm3D               <-- Отвечает за зум (Length) и защищает от проникания сквозь террейн
#         └── Camera3D             <-- Сам узел камеры (линза), направлен строго в CameraAnchor
#
# КЛЮЧЕВЫЕ МЕХАНИКИ:
# 1. 3D-Drag (Захват рельефа):
#    При клике ЛКМ запрашивается точка на ландшафте (или на sea_level). 
#    Камера смещается так, чтобы точка оставалась под курсором.
#
# 2. Авто-слежение за рельефом (_adjust_height_to_terrain):
#    Пускает луч вниз по маске terrain_collision_mask (игнорируя персонажей) 
#    и удерживает узел на высоте anchor_height_offset над землей (не опускаясь ниже sea_level).
#
# 3. Динамический Зум и Наклон (Pitch):
#    Изменение длины SpringArm3D плавно пересчитывает угол наклона (lerp).
#
# 4. Инерция и Упругие границы (Rubber Banding):
#    Плавный докат при броске и экспоненциальное сопротивление у краёв острова.
# ==============================================================================

extends Node3D

# --- НАСТРОЙКИ ЗУМА И НАКЛОНА ---
@export_group("Zoom & Pitch Settings")
## Скорость приближения/отдаления при прокрутке колесика
@export var zoom_speed: float = 1.0

## Минимальная длина SpringArm3D (максимальный зум к земле)
@export var min_zoom: float = 3.0

## Максимальная длина SpringArm3D (максимальный зум вверх)
@export var max_zoom: float = 25.0

## Угол наклона (в градусах) при максимальном приближении (почти горизонт)
@export var pitch_at_min_zoom: float = -20.0

## Угол наклона (в градусах) при максимальном отдалении (вид сверху)
@export var pitch_at_max_zoom: float = -60.0


# --- НАСТРОЙКИ ДРАГА И РЕЛЬЕФА ---
@export_group("Drag & Surface")
## Высота плоскости моря (минимальный уровень Y = 0.0)
@export var sea_level: float = 0.0

## Высота удерживания якоря над поверхностью земли (в метрах)
@export var anchor_height_offset: float = 3.0

## Маска физики для террейна (Layer 1 = World), чтобы игнорировать персов
@export_flags_3d_physics var terrain_collision_mask: int = 1


# --- ОГРАНИЧЕНИЯ И РЕЗИНОВЫЕ ГРАНИЦЫ ---
@export_group("Limits & Rubber Banding")
## Минимальная граница перемещения [X_min, Z_min]
@export var bounds_min: Vector2 = Vector2(-50.0, -50.0)

## Максимальная граница перемещения [X_max, Z_max]
@export var bounds_max: Vector2 = Vector2(50.0, 50.0)

## Максимальный запас вытягивания камеры за границы (в метрах)
@export var rubber_band_margin: float = 10.0

## Скорость возвратной пружины при отпускании ЛКМ за границей
@export var return_speed: float = 12.0


# --- НАСТРОЙКИ ИНЕРЦИИ ---
@export_group("Inertia")
## Сила торможения инерции (чем больше значение, тем короче тормозной путь)
@export var friction: float = 15.0


# --- ССЫЛКИ НА УЗЛЫ ---
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# --- ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ---
var is_locked: bool = false:
	set(value):
		is_locked = value
		if is_locked:
			force_reset_drag()

var _is_dragging: bool = false
var _drag_plane: Plane
var _drag_start_world_pos: Vector3 = Vector3.ZERO
var _pan_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	_update_zoom_and_pitch()

func _process(delta: float) -> void:
	# 1. Постоянно удерживаем якорь над рельефом (игнорируя персов и не тоня в воде)
	_adjust_height_to_terrain()

	if is_locked:
		return

	# 2. Отработка возврата от границ и инерции скольжения
	if not _is_dragging:
		if _is_position_out_of_bounds(global_position):
			var clamped_pos = _get_clamped_position(global_position)
			global_position = global_position.lerp(clamped_pos, return_speed * delta)
			_pan_velocity = Vector3.ZERO
		elif _pan_velocity.length_squared() > 0.001:
			var target_pos = global_position + _pan_velocity * delta
			global_position = _apply_rubber_band_to_position(target_pos)
			_pan_velocity = _pan_velocity.lerp(Vector3.ZERO, friction * delta)

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
				cancel_drag()

	elif event is InputEventMouseMotion and _is_dragging:
		var current_world_pos = _get_ground_position(event.position)
		if current_world_pos != Vector3.ZERO:
			var delta_pos = _drag_start_world_pos - current_world_pos
			var target_pos = global_position + delta_pos
			
			global_position = _apply_rubber_band_to_position(target_pos)
			_pan_velocity = delta_pos / get_process_delta_time()

## Подгоняет высоту Y якоря под рельеф острова (игнорирует персов и не тонет ниже sea_level)
func _adjust_height_to_terrain() -> void:
	var space_state = get_world_3d().direct_space_state
	var ray_from = Vector3(global_position.x, 100.0, global_position.z)
	var ray_to = Vector3(global_position.x, -50.0, global_position.z)
	
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collision_mask = terrain_collision_mask
	
	var result = space_state.intersect_ray(query)
	
	var ground_y: float = sea_level
	if result:
		ground_y = maxf(result.position.y, sea_level)
		
	var target_y = ground_y + anchor_height_offset
	global_position.y = lerp(global_position.y, target_y, 0.15)

func _start_drag(mouse_pos: Vector2) -> void:
	_drag_plane = Plane(Vector3.UP, global_position.y)
	var hit_pos = _get_ground_position(mouse_pos)
	if hit_pos != Vector3.ZERO:
		_is_dragging = true
		_drag_start_world_pos = hit_pos
		_pan_velocity = Vector3.ZERO

func cancel_drag() -> void:
	_is_dragging = false
	_drag_start_world_pos = Vector3.ZERO

func force_reset_drag() -> void:
	cancel_drag()
	_pan_velocity = Vector3.ZERO

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
