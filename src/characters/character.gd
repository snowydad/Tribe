# ==============================================================================
# CHARACTER.GD — Контроллер перемещения и поворота персонажа / Сущности (Godot 4) /
# ==============================================================================
# 
# СТРУКТУРА УЗЛОВ В СЦЕНЕ:
#   Character (CharacterBody3D)     <-- [Этот скрипт висит здесь] Управление физикой и перемещением
#    ├── MeshInstance3D            <-- 3D-модель персонажа (бокс/меш)
#    ├── CollisionShape3D          <-- Физическая коллизия тела
#    └── NavigationAgent3D         <-- Автономный поиск пути по NavigationMesh (NavMesh)
#
# КЛЮЧЕВЫЕ МЕХАНИКИ:
# 1. Поиск пути (NavigationAgent3D):
#    Получает целевую 3D-точку на карте через метод `move_to_position()`. 
#    Запрашивает у серверной навигации Godot оптимальный маршрут с обходом препятствий.
#
# 2. Перемещение по XZ с гравитацией:
#    В `_physics_process` рассчитывается вектор направления к следующей 
#    точке пути (next_path_position). Высота (Y) отдана под стандартную гравитацию, 
#    чтобы персонаж корректно приземлялся на террейн и склоны.
#
# 3. Поворот к цели:
#    При движении персонаж плавно плавно разворачивается лицом (ось -Z / Z) 
#    в сторону направления своего движения.
# ==============================================================================

# ==============================================================================
# ФАЙЛ: src/characters/Character.gd
# НАЗНАЧЕНИЕ: Контроллер персонажа с расширенной телеметрией навигации
# ==============================================================================
extends CharacterBody3D

@export_group("Data")
@export var data: CharacterData

@export_group("Movement Settings")
@export var speed: float = 5.0
@export var rotation_speed: float = 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var dev_label: Label3D = $DevLabel
@onready var selection_ring: MeshInstance3D = $SelectionRing

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_selected: bool = false

var is_being_dragged: bool = false

func _ready() -> void:
	if not data:
		data = CharacterData.new()
		data.generate_identity()
	
	if TimeManager:
		TimeManager.year_passed.connect(_on_year_passed)
		
	set_selected(false)
	_update_dev_ui()

func _physics_process(delta: float) -> void:
	# Если персонажа тащат в воздухе — отключаем навигацию и физику ходьбы
	if is_being_dragged:
		velocity = Vector3.ZERO
		_update_dev_ui()
		return
	
	if not is_on_floor():
		velocity.y -= gravity * delta

	if nav_agent and not nav_agent.is_navigation_finished():
		var next_path_pos = nav_agent.get_next_path_position()
		var dir = (next_path_pos - global_position)
		dir.y = 0.0
		
		if dir.length_squared() > 0.01:
			var move_dir = dir.normalized()
			velocity.x = move_dir.x * speed
			velocity.z = move_dir.z * speed
			
			var target_angle = atan2(-move_dir.x, -move_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
		else:
			_stop_horizontal_movement()
	else:
		_stop_horizontal_movement()

	move_and_slide()
	_update_dev_ui()

func _stop_horizontal_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func move_to_position(target_pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = target_pos

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selection_ring:
		selection_ring.visible = selected

func _on_year_passed(_year: int) -> void:
	_update_dev_ui()

## Расширенная отладочная информация
func _update_dev_ui() -> void:
	if not dev_label or not data:
		return
		
	var gender_str = "M" if data.gender == CharacterData.Gender.MALE else "F"
	var text_info = "%s (%s)%s\n" % [data.character_name, gender_str, " [SELECTED]" if is_selected else ""]
	
	# ТЕЛЕМЕТРИЯ НАВИГАЦИИ
	if nav_agent:
		var is_finished = nav_agent.is_navigation_finished()
		var is_reachable = nav_agent.is_target_reachable()
		var dist_to_target = nav_agent.distance_to_target()
		
		text_info += "Nav state: %s | Reachable: %s\n" % ["FINISHED" if is_finished else "MOVING", "YES" if is_reachable else "NO"]
		text_info += "Dist to Target: %.2f m\n" % dist_to_target
	else:
		text_info += "NavAgent: NULL\n"
		
	text_info += "Vel: %.1f m/s | Floor: %s" % [velocity.length(), "YES" if is_on_floor() else "NO"]
	
	dev_label.text = text_info
