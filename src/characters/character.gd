# ==============================================================================
# character.gd — FSM, nav, work, drop. Matrix → CharacterDecision.
# ОБНОВЛЕНО: 2026-10-10 — peer push: walker shoves idle
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

var target_harvest: Node3D = null  # любой WorkSite category harvest
var target_storage: Node3D = null
var target_obstacle: Node3D = null

var _current_target_pos: Vector3 = Vector3.ZERO
var _work_timer: float = 0.0
## stuck: step aside → repath same goal A
var stuck_time: float = 2.0
var stuck_max_cycles: int = 3
var stuck_side_distance: float = 1.0
## толчок: идущий → стоящему
var push_radius: float = 0.7
var push_strength: float = 2.5
var push_min_speed: float = 0.15  # я «иду» если быстрее
var _stuck_t: float = 0.0
var _stuck_cycles: int = 0
var _nav_side_step: bool = false
var _path_goal_A: Vector3 = Vector3.ZERO
var _last_pos_xz: Vector2 = Vector2.ZERO
var _stuck_cd: float = 0.0
var _pushed_t: float = 0.0
var _dev_ui_timer: float = 0.0
var _is_unloading_at_storage: bool = false

## Matrix decisions
var decision = CharacterDecisionScript.new()

var drop_site: Node3D = null
## intent движения для UI: wander|eat|deliver|work|move|drop|""
var move_intent: String = ""
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
	add_to_group("character")

	# Чтение параметров скорости и навигации из конфигурационных файлов (.ini)
	if ConfigLoader:
		if ConfigLoader.has_method("get_character_value"):
			speed = float(ConfigLoader.get_character_value("base_stats", "move_speed", speed))
			work_speed = float(ConfigLoader.get_character_value("base_stats", "work_speed", work_speed))
			eat_speed = float(ConfigLoader.get_character_value("base_stats", "eat_speed", 1.0))
			arrival_distance = float(ConfigLoader.get_character_value("navigation", "arrival_distance", arrival_distance))
			docking_distance = float(ConfigLoader.get_character_value("navigation", "docking_distance", docking_distance))
			stuck_time = float(ConfigLoader.get_character_value("navigation", "stuck_time", stuck_time))
			stuck_max_cycles = int(ConfigLoader.get_character_value("navigation", "stuck_max_cycles", stuck_max_cycles))
			stuck_side_distance = float(ConfigLoader.get_character_value("navigation", "stuck_side_distance", stuck_side_distance))
			push_radius = float(ConfigLoader.get_character_value("navigation", "push_radius", push_radius))
			push_strength = float(ConfigLoader.get_character_value("navigation", "push_strength", push_strength))
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
			stuck_time = float(ConfigLoader.get_config_value("character", "navigation", "stuck_time", stuck_time))
			stuck_max_cycles = int(ConfigLoader.get_config_value("character", "navigation", "stuck_max_cycles", stuck_max_cycles))
			stuck_side_distance = float(ConfigLoader.get_config_value("character", "navigation", "stuck_side_distance", stuck_side_distance))
			push_radius = float(ConfigLoader.get_config_value("character", "navigation", "push_radius", push_radius))
			push_strength = float(ConfigLoader.get_config_value("character", "navigation", "push_strength", push_strength))
			decision.cargo_drop_delay = float(ConfigLoader.get_config_value("character", "base_stats", "cargo_drop_delay", decision.cargo_drop_delay))
			drop_think_time = float(ConfigLoader.get_config_value("character", "base_stats", "drop_think_time", drop_think_time))
			wander_radius_min = float(ConfigLoader.get_config_value("character", "base_stats", "wander_radius_min", wander_radius_min))
			wander_radius_max = float(ConfigLoader.get_config_value("character", "base_stats", "wander_radius_max", wander_radius_max))

	# Настройка агента и подключение RVO2 Avoidance
	if nav_agent:
		nav_agent.target_desired_distance = arrival_distance
		nav_agent.path_desired_distance = arrival_distance
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
			if _pushed_t > 0.0:
				_pushed_t -= delta
				# лёгкое трение, не мгновенный стоп — чтобы толчок был виден
				velocity.x = move_toward(velocity.x, 0.0, speed * delta * 2.0)
				velocity.z = move_toward(velocity.z, 0.0, speed * delta * 2.0)
			else:
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
			if not (data and data.item_amount > 0) and not _is_unloading_at_storage:
				_is_unloading_at_storage = false
				target_storage = null
				move_intent = ""
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
				if target_storage and is_instance_valid(target_storage) and target_storage.has_method("set_active_work"):
					target_storage.set_active_work("deposit")
				if target_storage and is_instance_valid(target_storage) and data and data.item_amount > 0 \
						and _at_work_point(target_storage) and WorkSite.can_accept(target_storage, self):
					_is_unloading_at_storage = true
					_work_timer = 0.0
					_stop_horizontal_movement(delta)
					_rotate_towards_target(target_storage, delta)
					_process_delivering_unload(delta)
					move_and_slide()
				elif target_storage and is_instance_valid(target_storage) and data and data.item_amount > 0 \
						and not WorkSite.can_accept(target_storage, self):
					if decision.handle_full_storage_with_cargo():
						move_and_slide()
					else:
						current_state = State.IDLE
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

	_push_peers(delta)
	_update_animation()
	# DevLabel не каждый кадр — меньше аллокаций строк (важно при нескольких персах)
	_dev_ui_timer += delta
	if _dev_ui_timer >= 0.2:
		_dev_ui_timer = 0.0
		_update_dev_ui()

# --- УПРАВЛЕНИЕ АНИМАЦИЕЙ ---


## work_anim from site
func _work_anim_of(site: Node, fallback: String = "work") -> String:
	if site == null or not is_instance_valid(site):
		return fallback
	if site.has_method("get_work_anim"):
		var a: String = str(site.call("get_work_anim"))
		if a != "":
			return a
	if "work_anim" in site:
		var a2: String = str(site.work_anim)
		if a2 != "":
			return a2
	return fallback


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
		State.GATHERING:
			target_anim = "work"
			if target_harvest and is_instance_valid(target_harvest):
				var wa: String = _work_anim_of(target_harvest, "work")
				if wa != "":
					target_anim = wa
		State.CLEARING:
			target_anim = "work"
		State.DELIVERING:
			if _is_unloading_at_storage:
				target_anim = "work"
				if target_storage and is_instance_valid(target_storage):
					var da: String = _work_anim_of(target_storage, "work")
					if da != "":
						target_anim = da
			else:
				target_anim = "walk"

	if not _anim_player.has_animation(target_anim):
		if target_anim != "work" and _anim_player.has_animation("work"):
			target_anim = "work"
		else:
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


## Старт path к цели A (WP)
func _nav_go_to(goal: Vector3) -> void:
	_path_goal_A = goal
	_current_target_pos = goal
	_nav_side_step = false
	_stuck_t = 0.0
	_stuck_cycles = 0
	_last_pos_xz = Vector2(global_position.x, global_position.z)
	if nav_agent:
		nav_agent.target_position = goal


## Упёрся: шаг в сторону (от соседа / ⊥ к A), на mesh
func _nav_step_aside() -> void:
	if not nav_agent:
		return
	if not _nav_side_step:
		_path_goal_A = _current_target_pos
	var side: Vector3 = _side_step_dir()
	var raw: Vector3 = global_position + side * stuck_side_distance
	var map_rid: RID = nav_agent.get_navigation_map()
	var b: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, raw)
	_nav_side_step = true
	_stuck_t = 0.0
	_stuck_cd = stuck_time  # пауза, чтобы не мельтешить
	_current_target_pos = b
	nav_agent.target_position = b


## Направление side: от ближайшего перса, иначе ⊥ к A (L/R по cycle)
func _side_step_dir() -> Vector3:
	var away := _away_from_nearest_peer()
	if away.length_squared() > 0.01:
		return away.normalized()
	var to_a := _path_goal_A - global_position
	to_a.y = 0.0
	if to_a.length_squared() > 0.01:
		var f := to_a.normalized()
		var side := Vector3(-f.z, 0.0, f.x)
		if (_stuck_cycles % 2) == 1:
			side = -side
		return side
	return Vector3(1.0, 0.0, 0.0)


func _away_from_nearest_peer() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.ZERO
	var best_d := 2.5  # только «в упор»
	var best := Vector3.ZERO
	for n in tree.get_nodes_in_group("character"):
		if n == self or not (n is Node3D) or not is_instance_valid(n):
			continue
		var o: Node3D = n as Node3D
		var d: float = global_position.distance_to(o.global_position)
		if d < best_d and d > 0.01:
			best_d = d
			var v: Vector3 = global_position - o.global_position
			v.y = 0.0
			best = v
	return best


## После шага в сторону — новый path к той же A
func _nav_repath_A() -> void:
	_nav_side_step = false
	_stuck_t = 0.0
	_stuck_cd = stuck_time
	_stuck_cycles += 1
	if _stuck_cycles >= stuck_max_cycles:
		_on_movement_finished()
		return
	_current_target_pos = _path_goal_A
	if nav_agent:
		nav_agent.target_position = _path_goal_A



## Идущий толкает стоящего / более медленного
func _push_peers(delta: float) -> void:
	if current_state == State.DEAD or current_state == State.CARRIED or is_being_dragged:
		return
	if not is_on_floor():
		return
	var my_spd := Vector2(velocity.x, velocity.z).length()
	if my_spd < push_min_speed:
		return  # стою — не толкаю
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("character"):
		if n == self or not is_instance_valid(n):
			continue
		if not (n is CharacterBody3D):
			continue
		var other: CharacterBody3D = n as CharacterBody3D
		if "current_state" in other and other.current_state == State.DEAD:
			continue
		if "is_being_dragged" in other and other.is_being_dragged:
			continue
		var offset: Vector3 = other.global_position - global_position
		offset.y = 0.0
		var dist: float = offset.length()
		if dist > push_radius or dist < 0.001:
			continue
		var other_spd := Vector2(other.velocity.x, other.velocity.z).length()
		# толкаем того, кто медленнее / стоит
		if other_spd >= my_spd * 0.9:
			continue
		var dir: Vector3 = offset / dist
		# импульс сильнее, чем ближе
		var w: float = 1.0 - (dist / push_radius)
		var impulse: float = push_strength * w * my_spd * delta * 10.0
		other.velocity.x += dir.x * impulse
		other.velocity.z += dir.z * impulse
		other.set("_pushed_t", 0.35)
		other.move_and_slide()
		velocity.x -= dir.x * impulse * 0.15
		velocity.z -= dir.z * impulse * 0.15

## Перемещение по navmesh
func _process_nav_movement(delta: float) -> void:
	if not nav_agent:
		_on_movement_finished()
		return

	var current_pos = global_position
	var pos_xz := Vector2(current_pos.x, current_pos.z)
	var dist_to_final = pos_xz.distance_to(Vector2(_current_target_pos.x, _current_target_pos.z))

	# дошли до текущей цели
	if nav_agent.is_navigation_finished() or dist_to_final <= arrival_distance:
		_stop_horizontal_movement(delta)
		if _nav_side_step:
			# был шаг в сторону → repath к A
			_nav_repath_A()
			move_and_slide()
			return
		_stuck_t = 0.0
		_stuck_cycles = 0
		_on_movement_finished()
		move_and_slide()
		return

	# stuck detect (с паузой после side/repath — меньше мельтешения)
	_stuck_cd = maxf(_stuck_cd - delta, 0.0)
	var hvel := Vector2(velocity.x, velocity.z).length()
	var moved := pos_xz.distance_to(_last_pos_xz)
	_last_pos_xz = pos_xz
	if _stuck_cd <= 0.0 and hvel < 0.05 and moved < 0.02:
		_stuck_t += delta
		if _stuck_t >= stuck_time:
			_stuck_t = 0.0
			if _nav_side_step:
				# застрял и на side — сразу repath A
				_nav_repath_A()
			else:
				_nav_step_aside()
			move_and_slide()
			return
	else:
		_stuck_t = 0.0

	var next_path_pos = nav_agent.get_next_path_position()
	var dir = (next_path_pos - current_pos)
	dir.y = 0.0

	if dir.length_squared() > 0.001:
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
		var target_angle = atan2(-move_dir.x, -move_dir.z)
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(intended_velocity)
		else:
			velocity.x = intended_velocity.x
			velocity.z = intended_velocity.z
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
			move_and_slide()
	else:
		_stop_horizontal_movement(delta)
		move_and_slide()

## Колбэк RVO Avoidance от навигационного сервера Godot
func _on_safe_velocity_computed(safe_velocity: Vector3) -> void:
	if is_being_dragged or not is_on_floor():
		return
	if current_state == State.MOVING or (current_state == State.DELIVERING and not _is_unloading_at_storage):
		velocity.x = safe_velocity.x
		velocity.z = safe_velocity.z
		var vel_2d = Vector2(safe_velocity.x, safe_velocity.z)
		if vel_2d.length_squared() > 0.05:
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
			# soft arrive: у WP или рядом со складом
			if _at_work_point(target_storage) or _near_site(target_storage):
				if decision.withdraw_one_and_eat(target_storage):
					return
				decision.want_storage_meal = false
				current_state = State.IDLE
				return
			# still far — re-path meal
			decision.go_eat_from_storage()
			return

		if task_manager and task_manager.get_current_task():
			var cur_t = task_manager.get_current_task()
			if cur_t and cur_t.type == TaskManager.TaskType.MOVE_TO:
				task_manager.complete_current_task()
			elif cur_t and cur_t.type == TaskManager.TaskType.GATHER and cur_t.target_node:
				start_harvesting(cur_t.target_node)
				return
			elif cur_t and cur_t.type == TaskManager.TaskType.DELIVER and cur_t.target_node:
				start_delivering_to_storage(cur_t.target_node)
				return
			elif cur_t and cur_t.type == TaskManager.TaskType.CLEAR and cur_t.target_node:
				start_clearing_obstacle(cur_t.target_node)
				return

		# go_work: дошли до WP текущего site
		if target_storage and is_instance_valid(target_storage) and _at_work_point(target_storage):
			if WorkSite.can_accept(target_storage, self):
				start_delivering_to_storage(target_storage)
				return
			current_state = State.IDLE
			return
		if target_harvest and is_instance_valid(target_harvest) and _at_work_point(target_harvest):
			if WorkSite.can_accept(target_harvest, self):
				start_harvesting(target_harvest)
				return
			wander_nearby(10.0, 15.0)
			return

		if decision.hands_busy():
			decision.resolve_cargo_action()
			return

		current_state = State.IDLE

	elif current_state == State.DELIVERING:
		if target_storage and is_instance_valid(target_storage) and target_storage.has_method("set_active_work"):
			target_storage.set_active_work("deposit")
		if target_storage and is_instance_valid(target_storage) and data and data.item_amount > 0:
			if _at_work_point(target_storage) and WorkSite.can_accept(target_storage, self):
				_is_unloading_at_storage = true
				_work_timer = 0.0
			elif WorkSite.can_accept(target_storage, self):
				_nav_go_to(_current_target_pos)
			else:
				decision.handle_full_storage_with_cargo()
		else:
			_is_unloading_at_storage = false
			target_storage = null
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


func _near_site(site: Node3D, mult: float = 1.0) -> bool:
	if not site or not is_instance_valid(site):
		return false
	return global_position.distance_to(site.global_position) <= docking_distance * mult


func _at_work_point(_site: Node3D = null) -> bool:
	var pos_xz := Vector2(global_position.x, global_position.z)
	var tgt_xz := Vector2(_current_target_pos.x, _current_target_pos.z)
	return pos_xz.distance_to(tgt_xz) <= arrival_distance


# --- РАБОЧИЕ ПРОЦЕССЫ ---

func _process_gathering(delta: float) -> void:
	if not target_harvest or not is_instance_valid(target_harvest):
		current_state = State.IDLE
		return

	# Готовность — у объекта (WorkSite)
	if not WorkSite.can_accept(target_harvest, self):
		# не готов → wander, после прихода process_idle снова проверит
		wander_nearby(10.0, 15.0)
		return

	var required_time: float = WorkSite.get_time(target_harvest, default_gather_time)
	var skill_key: String = WorkSite.get_skill(target_harvest, "worker")
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

		decision.resolve_cargo_action()

func start_eating() -> void:
	_work_timer = 0.0
	move_intent = "eat"
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
		if decision:
			decision.want_storage_meal = false
		move_intent = ""
		target_storage = null
		current_state = State.IDLE


## Nutrition из items.ini — новые продукты не правят character
func _nutrition_for_carried() -> float:
	var item := str(data.carried_item) if data else ""
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		return float(ConfigLoader.get_item_nutrition(item, 25.0))
	return 25.0


func _process_delivering_unload(delta: float) -> void:
	# deposit: только WorkSite API (do_work на site)
	if not target_storage or not is_instance_valid(target_storage):
		_is_unloading_at_storage = false
		current_state = State.IDLE
		return

	if not WorkSite.can_accept(target_storage, self):
		_is_unloading_at_storage = false
		decision.handle_full_storage_with_cargo()
		return

	var required_time: float = WorkSite.get_time(target_storage, default_deposit_time)
	var skill_key: String = WorkSite.get_skill(target_storage, "worker")
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		current_work_speed = data.get_effective_work_speed(skill_key)
	current_work_speed *= _energy_mult()

	_work_timer += delta * current_work_speed
	if _work_timer >= required_time:
		_work_timer = 0.0
		_is_unloading_at_storage = false
		var result: Dictionary = WorkSite.do_work(target_storage, self)
		if not result.get("ok", false):
			if task_manager:
				task_manager.complete_current_task()
			if target_storage.has_method("release_work_point"):
				target_storage.release_work_point(self)
			decision.handle_full_storage_with_cargo()
			return
		var xp_skill: String = str(result.get("xp_skill", skill_key))
		var xp_per_cycle: float = WorkSite.xp_from_config()
		if data.has_method("add_skill_xp"):
			data.add_skill_xp(xp_skill, xp_per_cycle)
		elif data.has_method("add_skill_exp"):
			data.add_skill_exp(xp_skill, xp_per_cycle)
		var take = result.get("take", {})
		if task_manager:
			task_manager.complete_current_task()
		if target_storage.has_method("release_work_point"):
			target_storage.release_work_point(self)
		target_storage = null
		move_intent = ""
		# harvest готов → work; иначе wander-wait
		if data and data.item_amount <= 0 and target_harvest and is_instance_valid(target_harvest):
			if WorkSite.can_accept(target_harvest, self):
				start_harvesting(target_harvest)
			else:
				wander_nearby(10.0, 15.0)
			return
		current_state = State.IDLE

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


## Context Drop v2: приземление → think 2–5s → resolve_after_drop (не сразу work).
func on_context_drop(site: Node3D, land_pos: Vector3) -> void:
	is_being_dragged = false
	move_intent = "drop"
	_is_unloading_at_storage = false
	decision.want_storage_meal = false
	_drop_think_left = -1.0

	var is_obj := site != null and is_instance_valid(site) and (
		WorkSite.is_site(site) or site.has_method("do_work") or site.has_method("get_free_work_point")
	)
	drop_site = site if is_obj else null

	var dest: Vector3 = land_pos
	if is_obj:
		dest = _get_free_work_point_safe(site)

	_awaiting_drop_decide = true
	_current_target_pos = dest
	# Уже на земле у точки — сразу think; иначе дойти/долететь
	if is_on_floor():
		var pos_xz := Vector2(global_position.x, global_position.z)
		var dst_xz := Vector2(dest.x, dest.z)
		if pos_xz.distance_to(dst_xz) <= arrival_distance:
			_begin_drop_think()
			return
	current_state = State.MOVING
	_nav_go_to(dest)


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
	# v2: think 2–5 сек
	_drop_think_left = randf_range(2.0, 5.0)
	if data:
		print("[Character] %s drop-think %.1fs (site=%s)" % [
			data.character_name,
			_drop_think_left,
			drop_site.name if drop_site and is_instance_valid(drop_site) else "empty"
		])


func wander_nearby(radius_min: float = -1.0, radius_max: float = -1.0) -> void:
	_awaiting_drop_decide = false
	_drop_think_left = -1.0
	move_intent = "wander"
	var rmin: float = wander_radius_min if radius_min < 0.0 else radius_min
	var rmax: float = wander_radius_max if radius_max < 0.0 else radius_max
	if rmax < rmin:
		rmax = rmin
	var r: float = randf_range(rmin, rmax)
	var a: float = randf() * TAU
	var dest: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	dest.y = global_position.y
	_soft_move_to(dest)


## Единый вход: игрок/AI → go_work(site). Всегда WP, потом can_accept.
func go_work(site: Node3D) -> void:
	start_work_at(site)


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
			print("[Character] BUILD not implemented yet for %s" % site.name)
			_go_to_site_wp(site)
		_:
			_go_to_site_wp(site)


func start_harvesting(site: Node3D) -> void:
	# с грузом не собираем — сначала сдача
	if data and data.item_amount > 0:
		if target_storage and is_instance_valid(target_storage):
			start_delivering_to_storage(target_storage)
		else:
			_go_to_nearest_storage()
		return

	is_being_dragged = false
	_is_unloading_at_storage = false
	_awaiting_drop_decide = false
	target_obstacle = null
	_work_timer = 0.0

	# Уже на WP этого site (после drop) — не release и не брать другой слот
	var keep_pos: Vector3 = _current_target_pos
	var d_wp: float = Vector2(global_position.x, global_position.z).distance_to(Vector2(keep_pos.x, keep_pos.z))
	var d_site: float = global_position.distance_to(site.global_position)
	var already_on_wp: bool = is_on_floor() \
		and d_wp <= arrival_distance \
		and d_site <= maxf(docking_distance * 2.0, 4.0)

	if already_on_wp:
		# слот drop уже занят — оставляем keep_pos
		target_harvest = site
		_current_target_pos = keep_pos
	else:
		_release_all_work_points()
		target_harvest = site
		_current_target_pos = _get_free_work_point_safe(site)

	if task_manager:
		task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.GATHER, Vector3.ZERO, site, 10, true))

	var site_ready := WorkSite.can_accept(site, self)
	if not site_ready:
		# общая схема wait: wander (без special-case «стоять у куста»)
		if has_method("wander_nearby"):
			wander_nearby()
		else:
			current_state = State.IDLE
		return
	# уже на WP → сразу work, без MOVING
	if already_on_wp or (_at_work_point(site) and is_on_floor()):
		move_intent = "work"
		current_state = State.GATHERING
	else:
		move_intent = "work"
		current_state = State.MOVING
		_nav_go_to(_current_target_pos)


func start_delivering_to_storage(storage_node: Node3D) -> void:
	if not storage_node or not is_instance_valid(storage_node):
		return

	# без груза — не deliver
	if not (data and data.item_amount > 0):
		_is_unloading_at_storage = false
		target_storage = null
		move_intent = ""
		current_state = State.IDLE
		return

	if target_storage and is_instance_valid(target_storage) and target_storage != storage_node:
		if target_storage.has_method("release_work_point"):
			target_storage.release_work_point(self)

	is_being_dragged = false
	_awaiting_drop_decide = false
	move_intent = "deliver"
	target_obstacle = null
	_work_timer = 0.0
	_is_unloading_at_storage = false
	target_storage = storage_node
	if target_storage.has_method("set_active_work"):
		target_storage.set_active_work("deposit")

	# ВСЕГДА WP склада (не keep_pos куста — иначе unload у berries)
	_current_target_pos = _get_free_work_point_safe(storage_node)

	if task_manager:
		task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.DELIVER, Vector3.ZERO, storage_node, 10, true))

	var can_work := WorkSite.can_accept(storage_node, self)
	# «на WP» = у точки СКЛАДА, не у куста
	var on_storage_wp: bool = is_on_floor() and _at_work_point(storage_node)

	if on_storage_wp and can_work:
		current_state = State.DELIVERING
		_is_unloading_at_storage = true
	elif on_storage_wp and not can_work:
		current_state = State.IDLE
	else:
		current_state = State.DELIVERING
		_nav_go_to(_current_target_pos)


func _go_to_site_wp(site: Node3D) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	_awaiting_drop_decide = false
	_nav_go_to(_get_free_work_point_safe(site))
	current_state = State.MOVING


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
	# знание «кто storage» — у StorageSite
	return StorageSite.find_nearest(self)

func _go_to_nearest_storage() -> void:
	var nearest_storage = StorageSite.find_nearest(self)
	if nearest_storage:
		go_work(nearest_storage)
	else:
		print("[Character] No storage found!")
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


## Строка action для HUD / DevLabel (think, wander, eat, walk:eat…)
func get_action_label() -> String:
	var d = data
	var cargo := ""
	if d and d.item_amount > 0 and str(d.carried_item) != "":
		cargo = "%s%d" % [str(d.carried_item), int(d.item_amount)]

	if current_state == State.DEAD:
		var cause := str(d.death_cause) if d and str(d.death_cause) != "" else ""
		return "dead (%s)" % cause if cause != "" else "dead"

	# think: пауза после отпускания (IDLE + timer)
	if _drop_think_left >= 0.0 or (_awaiting_drop_decide and current_state == State.IDLE):
		return "think"

	match current_state:
		State.CARRIED:
			return "carried"
		State.EATING:
			return "eat"
		State.GATHERING:
			if target_harvest and is_instance_valid(target_harvest):
				var wa2: String = _work_anim_of(target_harvest, "")
				if wa2 != "":
					return wa2
				var wt: String = WorkSite.get_type(target_harvest, "")
				if wt != "":
					return wt
			return "gather"
		State.CLEARING:
			return "clear"
		State.DELIVERING:
			if _is_unloading_at_storage:
				return "delivering: %s" % cargo if cargo != "" else "delivering"
			return "walk:deliver" if cargo != "" else "walk:deliver"
		State.MOVING:
			if move_intent == "wander":
				return "wander"
			if move_intent == "eat" or (decision and decision.want_storage_meal):
				return "walk:eat"
			if move_intent == "deliver" or cargo != "":
				return "carry: %s" % cargo if cargo != "" else "walk:deliver"
			if move_intent == "work":
				return "walk:work"
			if move_intent == "drop":
				return "walk:drop"
			return "walk"
		State.IDLE:
			if cargo != "":
				return "idle (hold: %s)" % cargo
			return "idle"
		_:
			return State.keys()[current_state] if current_state < State.size() else str(current_state)
	return "idle"


func _update_dev_ui() -> void:
	if not dev_label or not data:
		return
		
	var gender_str = "M" if data.gender == CharacterData.Gender.MALE else "F"
	var state_str = get_action_label()
	
	var talent_str = data.talent.capitalize() if "talent" in data else "None"
	var skill_lvl = 0
	if "skills" in data and target_harvest and is_instance_valid(target_harvest):
		var sk = WorkSite.get_skill(target_harvest, "")
		if sk != "" and data.skills.has(sk):
			skill_lvl = data.skills[sk].get("level", 0)
	
	var site_hint := "-"
	if target_harvest and is_instance_valid(target_harvest):
		site_hint = "H:" + WorkSite.get_type(target_harvest)
	elif target_storage and is_instance_valid(target_storage):
		if decision and decision.want_storage_meal:
			site_hint = "E:meal"
		elif data and data.item_amount > 0:
			site_hint = "D:" + WorkSite.get_type(target_storage)
		else:
			site_hint = "S:" + WorkSite.get_type(target_storage)

	var text_info = "%s (%s) [%s]%s\n" % [data.character_name, gender_str, state_str, " *SEL*" if is_selected else ""]
	text_info += "Site: %s\n" % site_hint
	text_info += "Talent: %s | Skill Lvl: %d\n" % [talent_str, skill_lvl]
	text_info += "Age: %d yr | HP: %.0f | Hng: %.0f%%\n" % [data.age, data.health, data.hunger]
	text_info += "Carrying: %s (%d) | Spd: %.1f | WSpd: %.1f\n" % [
		data.carried_item if data.carried_item != "" else "None",
		data.item_amount,
		speed,
		work_speed
	]
	text_info += "Vel: %.1f m/s" % velocity.length()
	
	dev_label.text = text_info
