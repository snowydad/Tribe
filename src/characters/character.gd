# ==============================================================================
# ФАЙЛ: src/characters/Character.gd
# НАЗНАЧЕНИЕ: Контроллер персонажа с зафиксированным инпутом, считыванием .ini
# (move_speed, work_speed), поддержкой RVO2 Avoidance для обхода
# NavigationObstacle3D, спуском по дуге при Context Drop и
# непрерывным рабочим циклом фуражира + поддержка анимаций.
# ==============================================================================
extends CharacterBody3D

# --- СОСТОЯНИЯ ПЕРСОНАЖА (FSM) ---
enum State { IDLE, MOVING, CARRIED, GATHERING, DELIVERING, CLEARING, EATING }

@export_group("Data")
@export var data: CharacterData

@export_group("Movement Settings")
@export var speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var max_step_distance: float = 0.3
@export var arrival_distance: float = 0.4 # Дистанция финишной остановки (из character.ini [navigation])
@export var docking_distance: float = 1.8 # Дистанция доводки (из character.ini [navigation])

@export_group("Fallback Work Timers (in seconds)")
@export var default_gather_time: float = 2.0
@export var default_deposit_time: float = 1.0
@export var default_clear_time: float = 3.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var dev_label: Label3D = $DevLabel
@onready var selection_ring: MeshInstance3D = $SelectionRing

var current_state: State = State.IDLE
var is_selected: bool = false
var is_being_dragged: bool = false

var target_berries: Node3D = null
var target_storage: Node3D = null
var target_obstacle: Node3D = null

var _current_target_pos: Vector3 = Vector3.ZERO
var _work_timer: float = 0.0
var _idle_check_timer: float = 0.0
var _is_unloading_at_storage: bool = false

var work_speed: float = 1.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_player: AnimationPlayer = null

func _ready() -> void:
	if not data:
		data = CharacterData.new()
		data.generate_identity()

	_ensure_dev_label_exists()
	_anim_player = _find_animation_player(self)

	# Чтение параметров скорости и навигации из конфигурационных файлов (.ini)
	if ConfigLoader:
		speed = float(ConfigLoader.get_config_value("character", "base_stats", "move_speed", speed))
		work_speed = float(ConfigLoader.get_config_value("character", "base_stats", "work_speed", work_speed))
		arrival_distance = float(ConfigLoader.get_config_value("character", "navigation", "arrival_distance", arrival_distance))
		docking_distance = float(ConfigLoader.get_config_value("character", "navigation", "docking_distance", docking_distance))

	# Настройка агента и подключение RVO2 Avoidance
	if nav_agent:
		nav_agent.target_desired_distance = arrival_distance
		nav_agent.path_desired_distance = max(arrival_distance, 0.4)
		nav_agent.avoidance_enabled = true
		if not nav_agent.velocity_computed.is_connected(_on_safe_velocity_computed):
			nav_agent.velocity_computed.connect(_on_safe_velocity_computed)

	if TimeManager:
		TimeManager.year_passed.connect(_on_year_passed)

	set_selected(false)
	_update_dev_ui()

func _physics_process(delta: float) -> void:
	# 1. Захват в воздухе (Drag & Drop)
	if is_being_dragged:
		velocity = Vector3.ZERO
		current_state = State.CARRIED
		_update_animation()
		_update_dev_ui()
		return

	# 2. Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 3. Машина состояний (FSM)
	match current_state:
		State.IDLE:
			_stop_horizontal_movement(delta)
			_process_idle_behavior(delta)
			move_and_slide()
		State.CARRIED:
			_stop_horizontal_movement(delta)
			move_and_slide()
		State.MOVING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			else:
				_process_nav_movement(delta)
		State.GATHERING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			else:
				_stop_horizontal_movement(delta)
				_rotate_towards_target(target_berries, delta)
				_process_gathering(delta)
				move_and_slide()
		State.DELIVERING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			elif _is_unloading_at_storage:
				_stop_horizontal_movement(delta)
				_rotate_towards_target(target_storage, delta)
				_process_delivering_unload(delta)
				move_and_slide()
			else:
				_process_nav_movement(delta)
		State.CLEARING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			else:
				_stop_horizontal_movement(delta)
				_rotate_towards_target(target_obstacle, delta)
				_process_clearing(delta)
				move_and_slide()

	_update_animation()
	_update_dev_ui()

# --- УПРАВЛЕНИЕ АНИМАЦИЕЙ ---
func _update_animation() -> void:
	if not _anim_player or not is_instance_valid(_anim_player):
		_anim_player = _find_animation_player(self)

	if not _anim_player or not is_instance_valid(_anim_player):
		return

	var target_anim: String = "idle"

	match current_state:
		State.IDLE, State.CARRIED:
			target_anim = "idle"
		State.MOVING:
			target_anim = "walk"
		State.GATHERING, State.CLEARING:
			target_anim = "work"
		State.DELIVERING:
			if _is_unloading_at_storage:
				target_anim = "work"
			else:
				target_anim = "walk"

	if _anim_player.has_animation(target_anim):
		if _anim_player.current_animation != target_anim:
			_anim_player.play(target_anim)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if not node:
		return null

	var ap = node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		return ap

	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found

	return null

# --- ПОВЕДЕНИЕ В IDLE (АВТОМАТИЧЕСКИЙ ВОЗВРАТ К РАБОТЕ) ---
func _process_idle_behavior(delta: float) -> void:
	# 1. Если руки не пусты — несем на ближайший склад
	if data and data.item_amount > 0:
		_go_to_nearest_storage()
		return

	# 2. Проверка созревания ягод каждые 0.5 сек для запомненного куста
	if target_berries and is_instance_valid(target_berries):
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			var berries_ready: bool = false
			if target_berries.has_method("has_berries"):
				berries_ready = target_berries.has_berries()
			if berries_ready:
				print("[Character] %s noticed berries ripened! Returning to work..." % data.character_name)
				start_gathering_at_berries(target_berries)

# --- ЛОГИКА ДВИЖЕНИЯ И AVOIDANCE ---
## Движение по горизонтали XZ к точке WorkPoint во время спуска с воздуха (Context Drop)
func _process_arc_drop_movement(delta: float) -> void:
	var pos_xz = Vector2(global_position.x, global_position.z)
	var target_xz = Vector2(_current_target_pos.x, _current_target_pos.z)
	var dir_xz = target_xz - pos_xz
	var dist = dir_xz.length()

	if dist > 0.05:
		var move_dir = dir_xz.normalized()
		velocity.x = move_dir.x * max(speed, 3.0) * 1.2
		velocity.z = move_dir.y * max(speed, 3.0) * 1.2
	else:
		global_position.x = _current_target_pos.x
		global_position.z = _current_target_pos.z
		velocity.x = 0.0
		velocity.z = 0.0

## Перемещение по навигационной сетке с поддержкой RVO Avoidance (обход NavigationObstacle3D)
func _process_nav_movement(delta: float) -> void:
	if not nav_agent or nav_agent.is_navigation_finished():
		_stop_horizontal_movement(delta)
		_on_movement_finished()
		move_and_slide()
		return

	var current_pos = global_position
	var next_path_pos = nav_agent.get_next_path_position()

	var dir = (next_path_pos - current_pos)
	dir.y = 0.0

	var dist_to_final = Vector2(current_pos.x, current_pos.z).distance_to(Vector2(_current_target_pos.x, _current_target_pos.z))

	if dist_to_final > arrival_distance and dir.length_squared() > 0.001:
		var move_dir = dir.normalized()
		var target_vel_x = move_dir.x * speed
		var target_vel_z = move_dir.z * speed
		var step_len = Vector2(target_vel_x * delta, target_vel_z * delta).length()

		if step_len > max_step_distance and delta > 0.0:
			var cap_factor = max_step_distance / step_len
			target_vel_x *= cap_factor
			target_vel_z *= cap_factor

		var intended_velocity = Vector3(target_vel_x, velocity.y, target_vel_z)

		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(intended_velocity)
		else:
			velocity.x = intended_velocity.x
			velocity.z = intended_velocity.z
			var target_angle = atan2(-move_dir.x, -move_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
			move_and_slide()
	else:
		_stop_horizontal_movement(delta)
		_on_movement_finished()
		move_and_slide()

## Колбэк RVO Avoidance от навигационного сервера Godot
func _on_safe_velocity_computed(safe_velocity: Vector3) -> void:
	if is_being_dragged or not is_on_floor():
		return

	if current_state == State.MOVING or (current_state == State.DELIVERING and not _is_unloading_at_storage):
		velocity.x = safe_velocity.x
		velocity.z = safe_velocity.z
		var vel_2d = Vector2(safe_velocity.x, safe_velocity.z)
		if vel_2d.length_squared() > 0.01:
			var target_angle = atan2(-vel_2d.x, -vel_2d.y)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * get_physics_process_delta_time())
		move_and_slide()

## Разворот лицом к целевому объекту
func _rotate_towards_target(target_node: Node3D, delta: float) -> void:
	if not target_node or not is_instance_valid(target_node):
		return

	var dir = (target_node.global_position - global_position)
	dir.y = 0.0

	if dir.length_squared() > 0.001:
		var target_angle = atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

func _on_movement_finished() -> void:
	if current_state == State.MOVING:
		if target_berries and is_instance_valid(target_berries):
			current_state = State.GATHERING
			_work_timer = 0.0
		elif target_obstacle and is_instance_valid(target_obstacle):
			current_state = State.CLEARING
			_work_timer = 0.0
		else:
			current_state = State.IDLE
	elif current_state == State.DELIVERING:
		_is_unloading_at_storage = true
		_work_timer = 0.0

func _stop_horizontal_movement(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * delta * 10.0)
	velocity.z = move_toward(velocity.z, 0.0, speed * delta * 10.0)

# --- РАБОЧИЕ ПРОЦЕССЫ ---
func _process_gathering(delta: float) -> void:
	if not target_berries or not is_instance_valid(target_berries):
		current_state = State.IDLE
		return

	var berries_available: bool = true
	if target_berries.has_method("has_berries"):
		berries_available = target_berries.has_berries()

	if not berries_available or not target_berries.has_method("harvest_berry"):
		current_state = State.IDLE
		return

	var required_time: float = default_gather_time
	if target_berries.has_method("get_work_time"):
		required_time = target_berries.get_work_time()

	# Расчет скорости работы с учетом врожденного таланта и навыка персонажа
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		var skill_key: String = "forager"
		if "skill" in target_berries:
			skill_key = str(target_berries.skill)
		current_work_speed = data.get_effective_work_speed(skill_key)

	_work_timer += delta * current_work_speed
	if _work_timer >= required_time:
		_work_timer = 0.0
		if target_berries.harvest_berry():
			var item_type: String = "berry"
			if target_berries.has_method("get_resource_type"):
				item_type = target_berries.get_resource_type()
			elif "resource_type" in target_berries:
				item_type = str(target_berries.resource_type)

			var amount: int = 1
			if target_berries.has_method("get_yield_amount"):
				amount = target_berries.get_yield_amount()
			elif "yield_amount" in target_berries:
				amount = int(target_berries.yield_amount)

			data.carried_item = item_type
			data.item_amount = amount

			# Начисление опыта навыка из character_skills.ini [skill_progression] xp_per_work_cycle
			var xp_per_cycle: float = 10.0
			if ConfigLoader:
				xp_per_cycle = float(ConfigLoader.get_config_value("skills", "skill_progression", "xp_per_work_cycle", 10.0))

			if data.has_method("add_skill_xp"):
				data.add_skill_xp("forager", xp_per_cycle)
			elif data.has_method("add_skill_exp"):
				data.add_skill_exp("forager", xp_per_cycle)

			print("[Character] Harvested %d %s! Heading to storage..." % [amount, item_type])
			_go_to_nearest_storage()

func _process_delivering_unload(delta: float) -> void:
	if not target_storage or not is_instance_valid(target_storage):
		_is_unloading_at_storage = false
		current_state = State.IDLE
		return

	var required_time: float = default_deposit_time
	if target_storage.has_method("get_work_time"):
		required_time = target_storage.get_work_time()

	# Расчет скорости разгрузки с учетом таланта и навыка персонажа (trader)
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		var skill_key: String = "trader"
		if "skill" in target_storage:
			skill_key = str(target_storage.skill)
		current_work_speed = data.get_effective_work_speed(skill_key)

	_work_timer += delta * current_work_speed
	if _work_timer >= required_time:
		_work_timer = 0.0
		_is_unloading_at_storage = false
		_deposit_food_to_storage()

func _process_clearing(delta: float) -> void:
	if not target_obstacle or not is_instance_valid(target_obstacle):
		current_state = State.IDLE
		target_obstacle = null
		return

	var required_time: float = default_clear_time
	if target_obstacle.has_method("get_work_time"):
		required_time = target_obstacle.get_work_time()

	# Расчет скорости расчистки с учетом таланта и навыка персонажа (worker)
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		var skill_key: String = "worker"
		if "skill" in target_obstacle:
			skill_key = str(target_obstacle.skill)
		current_work_speed = data.get_effective_work_speed(skill_key)

	_work_timer += delta * current_work_speed
	if _work_timer >= required_time:
		_work_timer = 0.0
		if target_obstacle.has_method("clear_obstacle"):
			target_obstacle.clear_obstacle()

		var xp_per_cycle: float = 10.0
		if ConfigLoader:
			xp_per_cycle = float(ConfigLoader.get_config_value("skills", "skill_progression", "xp_per_work_cycle", 10.0))

		if data.has_method("add_skill_xp"):
			data.add_skill_xp("worker", xp_per_cycle)
		elif data.has_method("add_skill_exp"):
			data.add_skill_exp("worker", xp_per_cycle)

		print("[Character] Cleared obstacle!")

		# Освобождаем слот перед тем как обнулим цель
		if target_obstacle and is_instance_valid(target_obstacle):
			if target_obstacle.has_method("release_work_point"):
				target_obstacle.release_work_point(self)

		current_state = State.IDLE
		target_obstacle = null

# --- КОМАНДЫ И ВЗАИМОДЕЙСТВИЕ ---
## Освобождает слоты у всех текущих целей (вызывать перед сменой задачи)
func _release_all_work_points() -> void:
	if target_berries and is_instance_valid(target_berries):
		if target_berries.has_method("release_work_point"):
			target_berries.release_work_point(self)

	if target_storage and is_instance_valid(target_storage):
		if target_storage.has_method("release_work_point"):
			target_storage.release_work_point(self)

	if target_obstacle and is_instance_valid(target_obstacle):
		if target_obstacle.has_method("release_work_point"):
			target_obstacle.release_work_point(self)

func move_to_position(target_pos: Vector3) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	target_berries = null
	target_storage = null
	target_obstacle = null
	_current_target_pos = target_pos
	current_state = State.MOVING
	if nav_agent:
		nav_agent.target_position = target_pos

func start_gathering_at_berries(berries_node: Node3D) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	target_berries = berries_node
	target_obstacle = null
	_work_timer = 0.0
	_current_target_pos = _get_free_work_point_safe(berries_node)

	if not is_on_floor():
		current_state = State.GATHERING
	else:
		var pos_xz = Vector2(global_position.x, global_position.z)
		var target_xz = Vector2(_current_target_pos.x, _current_target_pos.z)
		if pos_xz.distance_to(target_xz) <= arrival_distance:
			current_state = State.GATHERING
		else:
			current_state = State.MOVING
			if nav_agent:
				nav_agent.target_position = _current_target_pos

func start_delivering_to_storage(storage_node: Node3D) -> void:
	# Освобождаем слот у ПРЕДЫДУЩЕГО склада (если он другой)
	if target_storage and is_instance_valid(target_storage) and target_storage != storage_node:
		if target_storage.has_method("release_work_point"):
			target_storage.release_work_point(self)

	is_being_dragged = false
	target_storage = storage_node
	target_obstacle = null
	_work_timer = 0.0
	_current_target_pos = _get_free_work_point_safe(storage_node)
	current_state = State.DELIVERING

	if not is_on_floor():
		_is_unloading_at_storage = true
	else:
		var pos_xz = Vector2(global_position.x, global_position.z)
		var target_xz = Vector2(_current_target_pos.x, _current_target_pos.z)
		if pos_xz.distance_to(target_xz) <= arrival_distance:
			_is_unloading_at_storage = true
		else:
			_is_unloading_at_storage = false
			if nav_agent:
				nav_agent.target_position = _current_target_pos

func start_clearing_obstacle(obstacle_node: Node3D) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	target_obstacle = obstacle_node
	target_berries = null
	_work_timer = 0.0
	_current_target_pos = _get_free_work_point_safe(obstacle_node)

	if not is_on_floor():
		current_state = State.CLEARING
	else:
		var pos_xz = Vector2(global_position.x, global_position.z)
		var target_xz = Vector2(_current_target_pos.x, _current_target_pos.z)
		if pos_xz.distance_to(target_xz) <= arrival_distance:
			current_state = State.CLEARING
		else:
			current_state = State.MOVING
			if nav_agent:
				nav_agent.target_position = _current_target_pos

func _go_to_nearest_storage() -> void:
	var storages = get_tree().get_nodes_in_group("storage")
	if storages.size() > 0:
		var nearest_storage: Node3D = storages.front() as Node3D
		if not nearest_storage:
			current_state = State.IDLE
			return

		var min_dist: float = global_position.distance_to(nearest_storage.global_position)
		for s in storages:
			var node_s = s as Node3D
			if node_s:
				var dist = global_position.distance_to(node_s.global_position)
				if dist < min_dist:
					min_dist = dist
					nearest_storage = node_s

		start_delivering_to_storage(nearest_storage)
	else:
		print("[Character] No storage found in group 'storage'!")
		current_state = State.IDLE

func _deposit_food_to_storage() -> void:
	if target_storage and is_instance_valid(target_storage) and target_storage.has_method("deposit_food"):
		if data.item_amount > 0:
			var deposited_amount: int = data.item_amount
			var carried_type: String = data.carried_item if data.carried_item != "" else "resource"
			target_storage.deposit_food(data.item_amount)
			data.carried_item = ""
			data.item_amount = 0

			# Начисление опыта навыка торговца/носильщика (trader) из конфига
			var xp_per_cycle: float = 10.0
			if ConfigLoader:
				xp_per_cycle = float(ConfigLoader.get_config_value("skills", "skill_progression", "xp_per_work_cycle", 10.0))

			var skill_key: String = "trader"
			if "skill" in target_storage:
				skill_key = str(target_storage.skill)

			if data.has_method("add_skill_xp"):
				data.add_skill_xp(skill_key, xp_per_cycle)
			elif data.has_method("add_skill_exp"):
				data.add_skill_exp(skill_key, xp_per_cycle)

			print("[Character] Deposited %d %s to storage." % [deposited_amount, carried_type])

		if target_berries and is_instance_valid(target_berries):
			var still_has: bool = true
			if target_berries.has_method("has_berries"):
				still_has = target_berries.has_berries()

			if still_has:
				# start_gathering_at_berries вызовет _release_all_work_points → освободит слот склада
				start_gathering_at_berries(target_berries)
				return

		# Некуда возвращаться — идём в IDLE, освобождаем слот склада
		if target_storage and is_instance_valid(target_storage):
			if target_storage.has_method("release_work_point"):
				target_storage.release_work_point(self)

		current_state = State.IDLE

func _get_free_work_point_safe(node: Node3D) -> Vector3:
	if not node or not is_instance_valid(node):
		return global_position

	if not node.has_method("get_free_work_point"):
		return node.global_position

	for method in node.get_method_list():
		if method["name"] == "get_free_work_point":
			if method["args"].size() == 0:
				return node.get_free_work_point()
			else:
				return node.get_free_work_point(self)

	return node.global_position

func set_selected(selected: bool) -> void:
	is_selected = selected
	if selection_ring:
		selection_ring.visible = selected

func _on_year_passed(_year: int) -> void:
	_update_dev_ui()

func _ensure_dev_label_exists() -> void:
	if not dev_label:
		dev_label = get_node_or_null("DevLabel") as Label3D

	if not dev_label:
		dev_label = Label3D.new()
		dev_label.name = "DevLabel"
		dev_label.position = Vector3(0, 2.2, 0)
		dev_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dev_label.no_depth_test = true
		dev_label.pixel_size = 0.005
		dev_label.modulate = Color(1.0, 1.0, 1.0)
		add_child(dev_label)

	dev_label.visible = true

func _update_dev_ui() -> void:
	if not dev_label or not data:
		return

	var gender_str = "M" if data.gender == CharacterData.Gender.MALE else "F"
	var state_str = State.keys()[current_state]

	if current_state == State.DELIVERING and _is_unloading_at_storage:
		state_str = "UNLOADING"

	var talent_str = data.talent.capitalize() if "talent" in data else "None"
	var forager_lvl = 0

	if "skills" in data and data.skills.has("forager"):
		forager_lvl = data.skills["forager"].get("level", 0)

	var text_info = "%s (%s) [%s]%s\n" % [data.character_name, gender_str, state_str, " *SEL*" if is_selected else ""]
	text_info += "Talent: %s | Forager Lvl: %d\n" % [talent_str, forager_lvl]
	text_info += "Age: %d yr | HP: %.0f\n" % [data.age, data.health]
	text_info += "Carrying: %s (%d) | Spd: %.1f | WSpd: %.1f\n" % [
		data.carried_item if data.carried_item != "" else "None",
		data.item_amount,
		speed,
		work_speed
	] 
	text_info += "Vel: %.1f m/s" % velocity.length()

	dev_label.text = text_info
