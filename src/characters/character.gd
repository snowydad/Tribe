# ==============================================================================
# ФАЙЛ: src/characters/Character.gd
# ОБНОВЛЕНО: 2026-10-04 17:05 CEST — death_cause + UI dead
# НАЗНАЧЕНИЕ: Контроллер персонажа с зафиксированным инпутом, считыванием .ini
#            (move_speed, work_speed), поддержкой RVO2 Avoidance для обхода
#            NavigationObstacle3D, спуском по дуге при Context Drop,
#            непрерывным рабочим циклом фуражира, интеграцией TaskManager и анимациями.
#            Матрица → CharacterDecision; work только у WorkPoint (_at_work_point).
# ==============================================================================
extends CharacterBody3D

const CharacterDecisionScript = preload("res://src/characters/CharacterDecision.gd")

# --- СОСТОЯНИЯ ПЕРСОНАЖА (FSM) ---
enum State { IDLE, MOVING, CARRIED, GATHERING, DELIVERING, CLEARING, EATING, DEAD }

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
@onready var task_manager: TaskManager = $TaskManager

var current_state: State = State.IDLE
var is_selected: bool = false
var is_being_dragged: bool = false

var target_harvest: Node3D = null  # любой harvest WorkSite (ягоды, бананы, …)
var target_storage: Node3D = null
var target_obstacle: Node3D = null

var _current_target_pos: Vector3 = Vector3.ZERO
var _work_timer: float = 0.0
var _dev_ui_timer: float = 0.0
var _is_unloading_at_storage: bool = false

## Решения (матрица hunger/склад/еда) — cut #1
var decision = CharacterDecisionScript.new()

var drop_site: Node3D = null
var _awaiting_drop_decide: bool = false
var _drop_think_left: float = -1.0
var drop_think_time: float = 2.0
var wander_radius_min: float = 5.0
var wander_radius_max: float = 15.0

var work_speed: float = 1.0
var eat_speed: float = 1.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_player: AnimationPlayer = null
var _death_anim_played: bool = false

func _ready() -> void:
	if not data:
		data = CharacterData.new()
		data.generate_identity()
	
	_ensure_dev_label_exists()
	_anim_player = _find_animation_player(self)

	if not task_manager:
		task_manager = get_node_or_null("TaskManager") as TaskManager
		if not task_manager:
			task_manager = TaskManager.new()
			task_manager.name = "TaskManager"
			add_child(task_manager)

	if decision == null:
		decision = CharacterDecisionScript.new()
	decision.setup(self)

	# Чтение параметров скорости и навигации из конфигурационных файлов (.ini)
	if ConfigLoader:
		if ConfigLoader.has_method("get_character_value"):
			speed = float(ConfigLoader.get_character_value("base_stats", "move_speed", speed))
			work_speed = float(ConfigLoader.get_character_value("base_stats", "work_speed", work_speed))
			eat_speed = float(ConfigLoader.get_character_value("base_stats", "eat_speed", 1.0))
			arrival_distance = float(ConfigLoader.get_character_value("navigation", "arrival_distance", arrival_distance))
			docking_distance = float(ConfigLoader.get_character_value("navigation", "docking_distance", docking_distance))
			decision.cargo_drop_delay = float(ConfigLoader.get_character_value("base_stats", "cargo_drop_delay", decision.cargo_drop_delay))
			drop_think_time = float(ConfigLoader.get_character_value("base_stats", "drop_think_time", drop_think_time))
			wander_radius_min = float(ConfigLoader.get_character_value("base_stats", "wander_radius_min", wander_radius_min))
			wander_radius_max = float(ConfigLoader.get_character_value("base_stats", "wander_radius_max", wander_radius_max))
		elif ConfigLoader.has_method("get_config_value"):
			speed = float(ConfigLoader.get_config_value("character", "base_stats", "move_speed", speed))
			work_speed = float(ConfigLoader.get_config_value("character", "base_stats", "work_speed", work_speed))
			eat_speed = float(ConfigLoader.get_config_value("character", "base_stats", "eat_speed", 1.0))
			arrival_distance = float(ConfigLoader.get_config_value("character", "navigation", "arrival_distance", arrival_distance))
			docking_distance = float(ConfigLoader.get_config_value("character", "navigation", "docking_distance", docking_distance))
			decision.cargo_drop_delay = float(ConfigLoader.get_config_value("character", "base_stats", "cargo_drop_delay", decision.cargo_drop_delay))
			drop_think_time = float(ConfigLoader.get_config_value("character", "base_stats", "drop_think_time", drop_think_time))
			wander_radius_min = float(ConfigLoader.get_config_value("character", "base_stats", "wander_radius_min", wander_radius_min))
			wander_radius_max = float(ConfigLoader.get_config_value("character", "base_stats", "wander_radius_max", wander_radius_max))

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
	if data:
		data.update_needs(delta, _needs_activity())
		# Смерть: health <= 0
	if data and data.health <= 0.0:
		if current_state != State.DEAD:
			_die()
		velocity = Vector3.ZERO
		_update_animation()
		_dev_ui_timer += delta
		if _dev_ui_timer >= 0.2:
			_dev_ui_timer = 0.0
			_update_dev_ui()
		return

	# 1. Захват в воздухе (Drag & Drop)
	if is_being_dragged:
		velocity = Vector3.ZERO
		current_state = State.CARRIED
		_drop_think_left = -1.0
		_awaiting_drop_decide = false
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
			if _drop_think_left >= 0.0:
				_drop_think_left -= delta
				if _drop_think_left <= 0.0:
					_drop_think_left = -1.0
					_awaiting_drop_decide = false
					var site = drop_site
					drop_site = null
					decision.resolve_after_drop(site)
				move_and_slide()
			else:
				decision.process_idle(delta)
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
				_rotate_towards_target(target_harvest, delta)
				_process_gathering(delta)
				move_and_slide()

		State.DELIVERING:
			# Склад полон — не крутим разгрузку
			if data and data.item_amount > 0 and not decision.storage_has_space(target_storage):
				if decision.handle_full_storage_with_cargo():
					move_and_slide()
				else:
					current_state = State.IDLE
					move_and_slide()
			elif not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			elif _is_unloading_at_storage:
				_stop_horizontal_movement(delta)
				_rotate_towards_target(target_storage, delta)
				_process_delivering_unload(delta)
				move_and_slide()
			else:
				_process_nav_movement(delta)

		State.EATING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			else:
				_stop_horizontal_movement(delta)
				_process_eating(delta)
				move_and_slide()

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
	# DevLabel не каждый кадр — меньше аллокаций строк (важно при нескольких персах)
	_dev_ui_timer += delta
	if _dev_ui_timer >= 0.2:
		_dev_ui_timer = 0.0
		_update_dev_ui()

# --- УПРАВЛЕНИЕ АНИМАЦИЕЙ ---

func _update_animation() -> void:
	if not _anim_player or not is_instance_valid(_anim_player):
		_anim_player = _find_animation_player(self)
	if not _anim_player or not is_instance_valid(_anim_player):
		return

	var target_anim: String = "idle"
	match current_state:
		State.DEAD:
			target_anim = "die"
		State.IDLE, State.CARRIED:
			target_anim = "idle"
		State.MOVING:
			target_anim = "walk"
		State.EATING:
			# клип "eat", иначе fallback "work"
			target_anim = "eat" if _anim_player.has_animation("eat") else "work"
		State.GATHERING, State.CLEARING:
			target_anim = "work"
		State.DELIVERING:
			if _is_unloading_at_storage:
				target_anim = "work"
			else:
				target_anim = "walk"

	if not _anim_player.has_animation(target_anim):
		return
	# die — один раз, не рестартить каждый кадр
	if target_anim == "die":
		if _death_anim_played:
			return
		var anim := _anim_player.get_animation("die")
		if anim:
			anim.loop_mode = Animation.LOOP_NONE
		_anim_player.play("die")
		_death_anim_played = true
		return

	if _anim_player.current_animation != target_anim:
		_anim_player.play(target_anim)
		
func _die() -> void:
	is_being_dragged = false
	_drop_think_left = -1.0
	_awaiting_drop_decide = false
	_is_unloading_at_storage = false
	_release_all_work_points()
	if task_manager:
		task_manager.clear_all()
	velocity = Vector3.ZERO
	_death_anim_played = false
	current_state = State.DEAD
	# если CharacterData ещё не проставил причину
	if data and str(data.death_cause) == "":
		if data.hunger > 90.0 and data.energy < 10.0:
			data.death_cause = "starvation+exhaustion"
		elif data.hunger > 90.0:
			data.death_cause = "starvation"
		elif data.energy < 10.0:
			data.death_cause = "exhaustion"
		else:
			data.death_cause = "needs"
	print("[Character] %s died (%s) hp=0 hunger=%.0f energy=%.0f" % [
		data.character_name if data else "?",
		data.death_cause if data else "?",
		data.hunger if data else 0.0,
		data.energy if data else 0.0,
	])

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
		var move_spd: float = speed * _energy_mult()
		var target_vel_x = move_dir.x * move_spd
		var target_vel_z = move_dir.z * move_spd
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
		# После context drop — think, не work
		if _awaiting_drop_decide:
			_begin_drop_think()
			return

		if decision.want_storage_meal and target_storage and is_instance_valid(target_storage):
			if _at_work_point(target_storage):
				if decision.withdraw_one_and_eat(target_storage):
					return
			decision.want_storage_meal = false
			if not _at_work_point(target_storage):
				decision.go_eat_from_storage()
				return
			current_state = State.IDLE
			return

		if task_manager and task_manager.get_current_task():
			var cur_t = task_manager.get_current_task()
			if cur_t and cur_t.type == TaskManager.TaskType.MOVE_TO:
				task_manager.complete_current_task()

		if decision.hands_busy():
			decision.resolve_cargo_action()
			return

		current_state = State.IDLE

	elif current_state == State.DELIVERING:
		# Разгрузка только у склада, иначе продолжаем идти
		if target_storage and is_instance_valid(target_storage) and _at_work_point(target_storage):
			_is_unloading_at_storage = true
			_work_timer = 0.0
		else:
			_is_unloading_at_storage = false
			if target_storage and is_instance_valid(target_storage):
				_current_target_pos = _get_free_work_point_safe(target_storage)
				if nav_agent:
					nav_agent.target_position = _current_target_pos
			else:
				current_state = State.IDLE

func _stop_horizontal_movement(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * delta * 10.0)
	velocity.z = move_toward(velocity.z, 0.0, speed * delta * 10.0)

# --- МНОЖИТЕЛЬ ОТ ENERGY (CharacterData.get_energy_speed_mult) ---

## activity для energy: work (−) / rest (+)
func _needs_activity() -> String:
	# работа: сбор, разгрузка, расчистка, еда
	match current_state:
		State.GATHERING, State.CLEARING, State.EATING:
			return "work"
		State.DELIVERING:
			return "work"  # несёт / сдаёт груз
		State.MOVING:
			return "work"  # идёт к цели — тоже расход
		_:
			return "rest"  # IDLE, CARRIED

func _energy_mult() -> float:
	if data and data.has_method("get_energy_speed_mult"):
		return float(data.get_energy_speed_mult())
	return 1.0

## У work-point / рядом с сайтом?
## ВАЖНО: не смотреть только на _current_target_pos — после drop это точка отпускания!
## «На месте» = персонаж рядом с самим site (или с work-point этого site).
func _at_work_point(site: Node3D = null) -> bool:
	var pos_xz := Vector2(global_position.x, global_position.z)
	var near := maxf(docking_distance, arrival_distance)

	if site and is_instance_valid(site):
		var site_xz := Vector2(site.global_position.x, site.global_position.z)
		# 1) рядом с корнем сайта
		if pos_xz.distance_to(site_xz) <= near:
			return true
		# 2) _current_target_pos — только если он относится к этому site (не точка drop)
		var tgt_xz := Vector2(_current_target_pos.x, _current_target_pos.z)
		if pos_xz.distance_to(tgt_xz) <= arrival_distance and tgt_xz.distance_to(site_xz) <= near * 2.0:
			return true
		return false

	# Без site — только «дошёл до назначенной точки» (MOVE_TO / drop)
	var tgt_xz2 := Vector2(_current_target_pos.x, _current_target_pos.z)
	return pos_xz.distance_to(tgt_xz2) <= arrival_distance
# --- РАБОЧИЕ ПРОЦЕССЫ ---

func _process_gathering(delta: float) -> void:
	if not target_harvest or not is_instance_valid(target_harvest):
		current_state = State.IDLE
		return

	# Готовность — у объекта (WorkSite)
	if not WorkSite.can_accept(target_harvest, self):
		current_state = State.IDLE
		decision._idle_check_timer = 0.0  # ждать полсекунды (idle poll)
		# target_harvest помним — idle/GATHER возобновит, когда can_accept
		return

	var required_time: float = WorkSite.get_time(target_harvest, default_gather_time)
	var skill_key: String = WorkSite.get_skill(target_harvest, "forager")
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		current_work_speed = data.get_effective_work_speed(skill_key)
	current_work_speed *= _energy_mult()

	_work_timer += delta * current_work_speed
	if _work_timer >= required_time:


		_work_timer = 0.0
		var result: Dictionary = WorkSite.do_work(target_harvest, self)
		if not result.get("ok", false):
			current_state = State.IDLE
			return

		# apply give
		if result.has("give"):
			var give: Dictionary = result["give"]
			data.carried_item = str(give.get("item", "resource"))
			data.item_amount = int(give.get("amount", 1))

		var xp_skill: String = str(result.get("xp_skill", skill_key))
		var xp_per_cycle: float = WorkSite.xp_from_config()
		if data.has_method("add_skill_xp"):
			data.add_skill_xp(xp_skill, xp_per_cycle)
		elif data.has_method("add_skill_exp"):
			data.add_skill_exp(xp_skill, xp_per_cycle)

		print("[Character] Work done at site: +%d %s" % [data.item_amount, data.carried_item])
		# A / B / E / F / G
		decision.resolve_cargo_action()

func start_eating() -> void:
	_work_timer = 0.0
	current_state = State.EATING

func _process_eating(delta: float) -> void:
	# eat_speed из character.ini [base_stats] = секунды на 1 порцию (не множитель)
	var req_eat_time: float = maxf(float(eat_speed), 0.01)
	_work_timer += delta
	if _work_timer >= req_eat_time:
		_work_timer = 0.0
		var nut_val: float = _nutrition_for_carried()
		var item_name: String = data.carried_item if data.carried_item != "" else "food"
		data.eat_food(nut_val)
		data.carried_item = ""
		data.item_amount = 0
		print("[Character] %s finished eating %s! New hunger: %.1f%%" % [data.character_name, item_name, data.hunger])
		if task_manager:
			task_manager.complete_current_task()
		current_state = State.IDLE


## Nutrition из items.ini — новые продукты не правят character
func _nutrition_for_carried() -> float:
	var item := str(data.carried_item) if data else ""
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		return float(ConfigLoader.get_item_nutrition(item, 25.0))
	return 25.0


func _process_delivering_unload(delta: float) -> void:
	if not target_storage or not is_instance_valid(target_storage):
		_is_unloading_at_storage = false
		current_state = State.IDLE
		return

	if not decision.storage_has_space(target_storage):
		_is_unloading_at_storage = false
		decision.handle_full_storage_with_cargo()
		return

	var required_time: float = WorkSite.get_time(target_storage, default_deposit_time)
	var skill_key: String = WorkSite.get_skill(target_storage, "trader")
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		current_work_speed = data.get_effective_work_speed(skill_key)
	current_work_speed *= _energy_mult()

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

	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		var skill_key: String = "worker"
		if "skill" in target_obstacle:
			skill_key = str(target_obstacle.skill)
		current_work_speed = data.get_effective_work_speed(skill_key)
	current_work_speed *= _energy_mult()

	_work_timer += delta * current_work_speed
	if _work_timer >= required_time:
		_work_timer = 0.0
		if target_obstacle.has_method("clear_obstacle"):
			target_obstacle.clear_obstacle()
		var xp_per_cycle: float = 10.0
		if ConfigLoader:
			if ConfigLoader.has_method("get_config_value"):
				xp_per_cycle = float(ConfigLoader.get_config_value("skills", "skill_progression", "xp_per_work_cycle", 10.0))
			elif ConfigLoader.has_method("get_skill_value"):
				xp_per_cycle = float(ConfigLoader.get_skill_value("skill_progression", "xp_per_work_cycle", 10.0))

		if data.has_method("add_skill_xp"):
			data.add_skill_xp("worker", xp_per_cycle)
		elif data.has_method("add_skill_exp"):
			data.add_skill_exp("worker", xp_per_cycle)

		print("[Character] Cleared obstacle!")

		if target_obstacle and is_instance_valid(target_obstacle):
			if target_obstacle.has_method("release_work_point"):
				target_obstacle.release_work_point(self)
		if task_manager:
			task_manager.complete_current_task()
		current_state = State.IDLE
		target_obstacle = null

# --- КОМАНДЫ И ВЗАИМОДЕЙСТВИЕ ---

func _release_all_work_points() -> void:
	if target_harvest and is_instance_valid(target_harvest):
		if target_harvest.has_method("release_work_point"):
			target_harvest.release_work_point(self)
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
	decision.want_storage_meal = false
	decision._cargo_drop_timer = 0.0
	# target_harvest — память harvest-site; target_storage — склад
	if not (data and data.item_amount > 0):
		target_storage = null
	target_obstacle = null
	_current_target_pos = target_pos
	current_state = State.MOVING
	if task_manager:
		task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.MOVE_TO, target_pos, null, 100))
	if nav_agent:
		nav_agent.target_position = target_pos


## Context Drop: объект или пустое. Не start_work — приземление + think.
func on_context_drop(site: Node3D, land_pos: Vector3) -> void:
	is_being_dragged = false
	_is_unloading_at_storage = false
	decision.want_storage_meal = false
	_drop_think_left = -1.0
	drop_site = site if site and is_instance_valid(site) else null
	_awaiting_drop_decide = true

	var dest: Vector3 = land_pos
	if drop_site:
		dest = _get_free_work_point_safe(drop_site)
		var cat := WorkSite.get_category(drop_site)
		if cat == "harvest":
			target_harvest = drop_site
		elif cat == "deposit":
			target_storage = drop_site
		elif cat == "clear":
			target_obstacle = drop_site

	_soft_move_to(dest)
	var flat = Vector3(dest.x, global_position.y, dest.z)
	if is_on_floor() and global_position.distance_to(flat) <= maxf(arrival_distance, 0.5):
		_begin_drop_think()


## Движение без set_user_override — очередь (persistent GATHER и т.д.) жива
func _soft_move_to(target_pos: Vector3) -> void:
	_release_all_work_points()
	_current_target_pos = target_pos
	current_state = State.MOVING
	if nav_agent:
		nav_agent.target_position = target_pos


func _begin_drop_think() -> void:
	current_state = State.IDLE
	_awaiting_drop_decide = true
	_drop_think_left = maxf(0.05, drop_think_time)
	if data:
		print("[Character] %s drop-think %.1fs (site=%s)" % [
			data.character_name,
			_drop_think_left,
			drop_site.name if drop_site and is_instance_valid(drop_site) else "empty"
		])


func wander_nearby() -> void:
	_awaiting_drop_decide = false
	_drop_think_left = -1.0
	var r: float = randf_range(wander_radius_min, wander_radius_max)
	var a: float = randf() * TAU
	var dest: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	dest.y = global_position.y
	print("[Character] %s wander ~%.0fm" % [data.character_name if data else "?", r])
	_soft_move_to(dest)


## Универсальная точка входа: объект сам говорит, какой это тип работы (ini / WorkSite).
func start_work_at(site: Node3D) -> void:
	if not site or not is_instance_valid(site):
		return
	var category := WorkSite.get_category(site)
	match category:
		"harvest":
			start_harvesting(site)
		"deposit":
			start_delivering_to_storage(site)
		"clear":
			start_clearing_obstacle(site)
		"build":
			# TODO: building FSM later
			print("[Character] BUILD not implemented yet for %s" % site.name)
			move_to_position(site.global_position)
		_:
			# fallback: work point walk
			move_to_position(_get_free_work_point_safe(site))

## @deprecated имя; используй start_harvesting
func start_gathering_at_berries(site: Node3D) -> void:
	start_harvesting(site)


func start_harvesting(site: Node3D) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	target_harvest = site
	target_obstacle = null
	_work_timer = 0.0
	_current_target_pos = _get_free_work_point_safe(site)

	if task_manager:
		task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.GATHER, Vector3.ZERO, site, 10, true))

	var site_ready := WorkSite.can_accept(site, self)
	var at_site := _at_work_point(site)

	if at_site and is_on_floor():
		# Уже у куста на земле
		current_state = State.GATHERING if site_ready else State.IDLE
	else:
		# Далеко / в воздухе → идём (или летим дугой) к work point, НЕ gather на месте
		current_state = State.MOVING
		if nav_agent:
			nav_agent.target_position = _current_target_pos

func start_delivering_to_storage(storage_node: Node3D) -> void:
	if not storage_node or not is_instance_valid(storage_node):
		return
	if not (data and data.item_amount > 0):
		_is_unloading_at_storage = false
		current_state = State.IDLE
		return

	if target_storage and is_instance_valid(target_storage) and target_storage != storage_node:
		if target_storage.has_method("release_work_point"):
			target_storage.release_work_point(self)

	is_being_dragged = false
	target_storage = storage_node
	target_obstacle = null
	_work_timer = 0.0
	_current_target_pos = _get_free_work_point_safe(storage_node)

	if _at_work_point(storage_node) and is_on_floor():
		current_state = State.DELIVERING
		_is_unloading_at_storage = true
	else:
		current_state = State.DELIVERING
		_is_unloading_at_storage = false
		if nav_agent:
			nav_agent.target_position = _current_target_pos


func start_clearing_obstacle(obstacle_node: Node3D) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	target_obstacle = obstacle_node
	target_harvest = null
	_work_timer = 0.0
	_current_target_pos = _get_free_work_point_safe(obstacle_node)

	if task_manager:
		task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.CLEAR, Vector3.ZERO, obstacle_node, 10, true))

	if _at_work_point(obstacle_node) and is_on_floor():
		current_state = State.CLEARING
	else:
		current_state = State.MOVING
		if nav_agent:
			nav_agent.target_position = _current_target_pos

func _find_nearest_storage_node() -> Node3D:
	var storages = get_tree().get_nodes_in_group("storage")
	if storages.size() > 0:
		var nearest: Node3D = storages.front() as Node3D
		if nearest:
			var min_d: float = global_position.distance_to(nearest.global_position)
			for s in storages:
				var ns = s as Node3D
				if ns:
					var d = global_position.distance_to(ns.global_position)
					if d < min_d:
						min_d = d
						nearest = ns
			return nearest
	return null

func _go_to_nearest_storage() -> void:
	var nearest_storage = _find_nearest_storage_node()
	if nearest_storage:
		start_delivering_to_storage(nearest_storage)
	else:
		print("[Character] No storage found in group 'storage'!")
		current_state = State.IDLE

func _deposit_food_to_storage() -> void:
	if not target_storage or not is_instance_valid(target_storage):
		current_state = State.IDLE
		return

	if data.item_amount > 0:
		var result: Dictionary
		if WorkSite.is_site(target_storage):
			result = WorkSite.do_work(target_storage, self)  # склад сам забирает груз
		else:
			# fallback legacy
			if not decision.storage_has_space(target_storage):
				result = {"ok": false, "reason": "full"}
			else:
				var deposited_amount: int = data.item_amount
				var carried_type: String = data.carried_item if data.carried_item != "" else "resource"
				if target_storage.has_method("deposit_food"):
					target_storage.deposit_food(data.item_amount)
				data.carried_item = ""
				data.item_amount = 0
				result = {"ok": true, "take": {"item": carried_type, "amount": deposited_amount}, "xp_skill": WorkSite.get_skill(target_storage, "trader")}

		if not result.get("ok", false):
			# Склад полон / ошибка — груз остаётся, ждём или едим
			print("[Character] Deposit failed: %s" % str(result.get("reason", "unknown")))
			if task_manager:
				task_manager.complete_current_task()  # снять DELIVER из стека
			if target_storage and is_instance_valid(target_storage) and target_storage.has_method("release_work_point"):
				target_storage.release_work_point(self)
			decision.handle_full_storage_with_cargo()
			return

		var xp_skill: String = str(result.get("xp_skill", WorkSite.get_skill(target_storage, "trader")))
		var xp_per_cycle: float = WorkSite.xp_from_config()
		if data.has_method("add_skill_xp"):
			data.add_skill_xp(xp_skill, xp_per_cycle)
		elif data.has_method("add_skill_exp"):
			data.add_skill_exp(xp_skill, xp_per_cycle)
		var take = result.get("take", {})
		print("[Character] Deposited %s x%d" % [str(take.get("item", "?")), int(take.get("amount", 0))])

	if task_manager:
		task_manager.complete_current_task()

	# Вернуться к harvest только если руки пусты и склад не переполнен (есть смысл)
	if data and data.item_amount <= 0 and target_harvest and is_instance_valid(target_harvest):
		if decision.storage_has_space() and WorkSite.can_accept(target_harvest, self):
			start_work_at(target_harvest)
			return

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
	
	var site_hint := "-"
	if target_harvest and is_instance_valid(target_harvest):
		site_hint = "H:" + WorkSite.get_type(target_harvest)
	elif target_storage and is_instance_valid(target_storage):
		site_hint = "D:" + WorkSite.get_type(target_storage)

	var text_info = "%s (%s) [%s]%s\n" % [data.character_name, gender_str, state_str, " *SEL*" if is_selected else ""]
	text_info += "Site: %s\n" % site_hint
	text_info += "Talent: %s | Forager Lvl: %d\n" % [talent_str, forager_lvl]
	text_info += "Age: %d yr | HP: %.0f | Hng: %.0f%%\n" % [data.age, data.health, data.hunger]
	text_info += "Carrying: %s (%d) | Spd: %.1f | WSpd: %.1f\n" % [
		data.carried_item if data.carried_item != "" else "None",
		data.item_amount,
		speed,
		work_speed
	]
	text_info += "Vel: %.1f m/s" % velocity.length()
	
	dev_label.text = text_info
