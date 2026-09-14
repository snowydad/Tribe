# ==============================================================================
# MAIN.GD — Главный Менеджер Сцены и Точка Входа (Godot 4)
# ==============================================================================
# 
# СТРУКТУРА УЗЛОВ В СЦЕНЕ:
#   Main (Node3D)                   <-- [Этот скрипт висит здесь] Корневой узел игры
#    ├── Terrain (Instance)         <-- Игровая карта / Остров
#    ├── WorldEnvironment           <-- Окружение (небо, туман, свет)
#    ├── DirectionalLight3D         <-- Солнце
#    ├── CameraAnchor (Instance)    <-- RTS-камера с физикой и ограничениями
#    │    └── SpringArm3D
#    │         └── Camera3D
#    ├── Character (Instance)       <-- Персонаж / Юнит
#    └── CSGBox3D                   <-- Отладочный объект
#
# КЛЮЧЕВЫЕ МЕХАНИКИ:
# 1. Распознавание Клика / Драга:
#    Разделяет короткий клик мышкой (отправка юнита) от зажатия для перетаскивания 
#    камеры через проверку дистанции (drag_threshold < 5px).
#
# 2. Отправка Персонажа (Raycast с камеры):
#    Пускает 3D-луч из камеры в точку клика на экране и передает полученную 
#    координату поверхности в Character для перемещения по NavigationAgent3D.
# ==============================================================================

extends Node3D

# --- ССЫЛКИ НА УЗЛЫ В ИНСПЕКТОРЕ ---
@export_group("Scene Connections")
## Ссылка на камеру внутри иерархии CameraAnchor/SpringArm3D/Camera3D
@export var camera: Camera3D

## Ссылка на управляемого персонажа
@export var character: CharacterBody3D


# --- НАСТРОЙКИ ВВОДА ---
@export_group("Input Settings")
## Максимальное смещение мыши (в пикселях), при котором нажатие считается кликом, а не драгом
@export var click_threshold: float = 5.0

var click_start_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Авто-поиск узлов, если они не завязаны вручную в Инспекторе
	if not camera:
		camera = get_node_or_null("CameraAnchor/SpringArm3D/Camera3D")
	if not character:
		character = get_node_or_null("Character")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			click_start_pos = event.position
		else:
			# Отправляем персонажа только если это был короткий клик, а не перетаскивание
			if click_start_pos.distance_to(event.position) < click_threshold:
				_send_character_to_click(event.position)


func _send_character_to_click(screen_position: Vector2) -> void:
	if not camera:
		print("Ошибка: Камера не найдена!")
		return
		
	if not character:
		print("Ошибка: Персонаж не назначен!")
		return

	# Пускаем луч из 3D-камеры в точку клика на экране
	var ray_origin = camera.project_ray_origin(screen_position)
	var ray_end = ray_origin + camera.project_ray_normal(screen_position) * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result = space_state.intersect_ray(query)
	
	if result:
		print
		## Передаем целевую точку движения персонажу
		#if character.has_method("move_to_position"):
			#character.move_to_position(result.position)
