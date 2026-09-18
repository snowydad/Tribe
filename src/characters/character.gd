# ==============================================================================
# ФАЙЛ: src/characters/Character.gd
# НАЗНАЧЕНИЕ: Контроллер персонажа (FSM + Динамический RVO Avoidance)
# ==============================================================================
extends CharacterBody3D

# --- СОСТОЯНИЯ ПЕРСОНАЖА (FSM) ---
enum State { IDLE, MOVING, CARRIED, GATHERING, DELIVERING, EATING }

@export_group("Data")
@export var data: CharacterData

@export_group("Movement Settings")
@export var speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var max_step_distance: float = 0.3

@export_group("Work Timers")
## Время (в секундах), необходимое для сбора 1 ягоды
@export var gather_time: float = 2.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var dev_label: Label3D = $DevLabel
@onready var selection_ring: MeshInstance3D = $SelectionRing

var current_state: State = State.IDLE
var is_selected: bool = false
var is_being_dragged: bool = false

# Временные ссылки на целевые объекты
var target_berries: Node3D = null
var target_storage: Node3D = null
var _work_timer: float = 0.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	if not data:
		data = CharacterData.new()
		data.generate_identity()
	
	if nav_agent:
		nav_agent.target_desired_distance = 1.0
		nav_agent.path_desired_distance = 0.5
		# Подписываемся на сигнал RVO Avoidance (Шаг 3)
		if not nav_agent.velocity_computed.is_connected(_on_safe_velocity_computed):
			nav_agent.velocity_computed.connect(_on_safe_velocity_computed)
	
	if TimeManager:
		TimeManager.year_passed.connect(_on_year_passed)
		
	set_selected(false)
	_update_dev_ui()

func _physics_process(delta: float) -> void:
	# 1. Если персонажа тащат в воздухе (Drag & Drop)
	if is_being_dragged:
		velocity = Vector3.ZERO
		current_state = State.CARRIED
		_update_dev_ui()
		return

	# 2. Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 3. Машина состояний (FSM)
	match current_state:
		State.IDLE, State.CARRIED:
			_stop_horizontal_movement(delta)

		State.MOVING, State.DELIVERING:
			_process_movement(delta)

		State.GATHERING:
			_stop_horizontal_movement(delta)
			_process_gathering(delta)

	# Вызываем move_and_slide() напрямую, если Avoidance выключен или перс стоит на месте
	if not nav_agent or not nav_agent.avoidance_enabled or not (current_state in [State.MOVING, State.DELIVERING]):
		move_and_slide()

	_update_dev_ui()

# --- ЛОГИКА ПЕРЕМЕЩЕНИЯ И ДИНАМИЧЕСКОГО ОБХОДА (RVO) ---

func _process_movement(delta: float) -> void:
	if nav_agent and not nav_agent.is_navigation_finished() and not nav_agent.is_target_reached():
		var next_path_pos = nav_agent.get_next_path_position()
		var dir = (next_path_pos - global_position)
		dir.y = 0.0
		
		var dist_to_final = global_position.distance_to(nav_agent.target_position)

		if dist_to_final > 0.8 and dir.length_squared() > 0.001:
			var move_dir = dir.normalized()
			var target_vel_x = move_dir.x * speed
			var target_vel_z = move_dir.z * speed
			
			# Ограничитель шага при высоком time_scale
			var step_len = Vector2(target_vel_x * delta, target_vel_z * delta).length()
			if step_len > max_step_distance and delta > 0.0:
				var cap_factor = max_step_distance / step_len
				target_vel_x *= cap_factor
				target_vel_z *= cap_factor
			
			var intended_velocity = Vector3(target_vel_x, velocity.y, target_vel_z)
			
			var target_angle = atan2(-move_dir.x, -move_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

			if nav_agent.avoidance_enabled:
				# Передаем желаемую скорость в RVO-сервер для динамического обхода препятствий
				nav_agent.set_velocity(intended_velocity)
			else:
				velocity.x = intended_velocity.x
				velocity.z = intended_velocity.z
		else:
			_stop_horizontal_movement(delta)
			_on_movement_finished()
	else:
		_stop_horizontal_movement(delta)
		_on_movement_finished()

## Callback от RVO Avoidance сервера с рассчитанной безопасной скоростью (в обход кустов/шалашей)
func _on_safe_velocity_computed(safe_velocity: Vector3) -> void:
	if current_state in [State.MOVING, State.DELIVERING]:
		velocity.x = safe_velocity.x
		velocity.z = safe_velocity.z
		move_and_slide()

func _on_movement_finished() -> void:
	if current_state == State.MOVING:
		if target_berries and is_instance_valid(target_berries):
			current_state = State.GATHERING
			_work_timer = 0.0
		else:
			current_state = State.IDLE
	elif current_state == State.DELIVERING:
		_deposit_food_to_storage()

func _stop_horizontal_movement(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * delta * 10.0)
	velocity.z = move_toward(velocity.z, 0.0, speed * delta * 10.0)

# --- КОМАНДЫ И ВЗАИМОДЕЙСТВИЕ ---

## Обычное движение в точку на карте
func move_to_position(target_pos: Vector3) -> void:
	is_being_dragged = false
	target_berries = null
	target_storage = null
	current_state = State.MOVING
	if nav_agent:
		nav_agent.target_position = target_pos

## Назначение сбора на кусте ягод
func start_gathering_at_berries(berries_node: Node3D) -> void:
	is_being_dragged = false
	target_berries = berries_node
	_work_timer = 0.0
	current_state = State.MOVING
	
	if nav_agent:
		if berries_node.has_method("get_free_work_point"):
			nav_agent.target_position = berries_node.get_free_work_point()
		else:
			nav_agent.target_position = berries_node.global_position

func _process_gathering(delta: float) -> void:
	if not target_berries or not is_instance_valid(target_berries) or not target_berries.has_method("harvest_berry") or not target_berries.has_berries():
		current_state = State.IDLE
		target_berries = null
		return

	_work_timer += delta
	if _work_timer >= gather_time:
		_work_timer = 0.0
		if target_berries.harvest_berry():
			data.carried_item = "berry"
			data.item_amount = 1
			print("[Character] Harvested 1 berry! Heading to storage...")
			_go_to_nearest_storage()

## Поиск ближайшего склада на сцене (по группе "storage")
func _go_to_nearest_storage() -> void:
	var storages = get_tree().get_nodes_in_group("storage")
	if storages.size() > 0:
		var nearest_storage: Node3D = storages as Node3D
		var min_dist: float = global_position.distance_to(nearest_storage.global_position)
		
		for s in storages:
			var node_s = s as Node3D
			if node_s:
				var dist = global_position.distance_to(node_s.global_position)
				if dist < min_dist:
					min_dist = dist
					nearest_storage = node_s
					
		target_storage = nearest_storage
		current_state = State.DELIVERING
		if nav_agent:
			nav_agent.target_position = target_storage.global_position
	else:
		print("[Character] No storage found in group 'storage'!")
		current_state = State.IDLE

## Разгрузка ресурсов на складе
func _deposit_food_to_storage() -> void:
	if target_storage and is_instance_valid(target_storage) and target_storage.has_method("deposit_food"):
		target_storage.deposit_food(data.item_amount)
		data.carried_item = ""
		data.item_amount = 0
		print("[Character] Deposited berries to storage.")
		
		# Если на кусте еще остались ягоды — возвращаемся за следующей
		if target_berries and is_instance_valid(target_berries) and target_berries.has_berries():
			start_gathering_at_berries(target_berries)
		else:
			current_state = State.IDLE

# --- ВЫДЕЛЕНИЕ И UI ---

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selection_ring:
		selection_ring.visible = selected

func _on_year_passed(_year: int) -> void:
	_update_dev_ui()

func _update_dev_ui() -> void:
	if not dev_label or not data:
		return
		
	var gender_str = "M" if data.gender == CharacterData.Gender.MALE else "F"
	var state_str = State.keys()[current_state]
	
	var text_info = "%s (%s) [%s]%s\n" % [data.character_name, gender_str, state_str, " *SEL*" if is_selected else ""]
	text_info += "Age: %d yr | HP: %.0f\n" % [data.age, data.health]
	text_info += "Carrying: %s (%d)\n" % [data.carried_item if data.carried_item != "" else "None", data.item_amount]
	text_info += "Vel: %.1f m/s" % velocity.length()
	
	dev_label.text = text_info
