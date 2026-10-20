# ==============================================================================
# character.gd — FSM, work, drop. HOW-nav → CharacterNavigation.
# ОБНОВЛЕНО: 2026-10-20 — go_work think; talent work
# ==============================================================================
extends CharacterBody3D

const CharacterDecisionScript = preload("res://src/characters/CharacterDecision.gd")
const CharacterNavigationScript = preload("res://src/characters/CharacterNavigation.gd")

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
var target_campfire: Node3D = null

# --- thought bubble ---
var _thought_root: Node3D = null
var _thought_bubble: Sprite3D = null
var _thought_icon: Sprite3D = null
var _thought_id: String = ""
var _thought_cfg_loaded: bool = false
var _th_hunger_thr: float = 40.0
var _th_bubble_path: String = "res://assets/ui/thought_bubble.png"
var _th_icon_food: String = "res://assets/ui/icon_food.png"
var _th_bubble_h: float = 2.15
var _th_bubble_px: float = 0.0035
var _th_icon_px: float = 0.0022
var _th_icon_y: float = 0.08

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
var _pushed_t: float = 0.0
var _dev_ui_timer: float = 0.0
var _is_unloading_at_storage: bool = false

## Matrix decisions
var decision = CharacterDecisionScript.new()
var nav = null  # CharacterNavigation — HOW move

var drop_site: Node3D = null
## intent движения для UI: wander|eat|deliver|work|move|drop|""
var move_intent: String = ""
var _awaiting_drop_decide: bool = false
var _drop_think_left: float = -1.0
var drop_think_time: float = 2.0
var wander_radius_min: float = 5.0
var wander_radius_max: float = 15.0
var wander_min_y: float = -1.0  # ниже — вода; y > -1 ок (по пояс)
var wander_speed_min: float = 0.5  # доля move_speed при stroll
var wander_speed_max: float = 0.75
var _wander_speed_factor: float = 0.6  # rand на каждый wander

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
	_setup_thought_bubble()
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
			wander_min_y = float(ConfigLoader.get_character_value("base_stats", "wander_min_y", wander_min_y))
			wander_speed_min = float(ConfigLoader.get_character_value("base_stats", "wander_speed_min", wander_speed_min))
			wander_speed_max = float(ConfigLoader.get_character_value("base_stats", "wander_speed_max", wander_speed_max))
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
			wander_min_y = float(ConfigLoader.get_config_value("character", "base_stats", "wander_min_y", wander_min_y))
			wander_speed_min = float(ConfigLoader.get_config_value("character", "base_stats", "wander_speed_min", wander_speed_min))
			wander_speed_max = float(ConfigLoader.get_config_value("character", "base_stats", "wander_speed_max", wander_speed_max))

	# NavigationAgent + CharacterNavigation (HOW)
	if nav_agent:
		nav_agent.avoidance_enabled = true
		if "debug_enabled" in nav_agent:
			var on := true
			if DevCheatManager and DevCheatManager.has_method("is_dev_overlays_on"):
				on = bool(DevCheatManager.is_dev_overlays_on())
			nav_agent.debug_enabled = on
	if nav == null:
		nav = CharacterNavigationScript.new()
		nav.name = "CharacterNavigation"
		add_child(nav)
	nav.setup(self, nav_agent)
	nav.configure(arrival_distance, max_step_distance, rotation_speed, stuck_time, stuck_max_cycles, stuck_side_distance)
	if not nav.arrived.is_connected(_on_movement_finished):
		nav.arrived.connect(_on_movement_finished)

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

	# нужда есть → EAT (не только IDLE; сборщики)
	if decision and current_state != State.DEAD and not is_being_dragged:
		decision.tick_eat_need()

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
				_dampen_horizontal(delta)
				if _pushed_t <= 0.0:
					_safe_rotate_towards(target_harvest, delta)
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
				_dampen_horizontal(delta)
				if _pushed_t <= 0.0:
					var look = target_campfire if (target_campfire and decision and decision.want_stoking) else target_storage
					_safe_rotate_towards(look, delta)
				_process_delivering_unload(delta)
				move_and_slide()
			else:
				# костёр: wood dump
				if target_campfire and is_instance_valid(target_campfire) and decision and decision.want_stoking \
						and data and data.item_amount > 0:
					if _at_work_point(target_campfire):
						_is_unloading_at_storage = true
						_work_timer = 0.0
						_dampen_horizontal(delta)
						_safe_rotate_towards(target_campfire, delta)
						_process_delivering_unload(delta)
						move_and_slide()
					else:
						_process_nav_movement(delta)
				elif target_storage and is_instance_valid(target_storage) and target_storage.has_method("set_active_work"):
					target_storage.set_active_work("deposit")
					if data and data.item_amount > 0 \
							and _at_work_point(target_storage) and WorkSite.can_accept(target_storage, self):
						_is_unloading_at_storage = true
						_work_timer = 0.0
						_dampen_horizontal(delta)
						if _pushed_t <= 0.0:
							_safe_rotate_towards(target_storage, delta)
						_process_delivering_unload(delta)
						move_and_slide()
					elif data and data.item_amount > 0 and not WorkSite.can_accept(target_storage, self):
						if decision.handle_full_storage_with_cargo():
							move_and_slide()
						else:
							current_state = State.IDLE
							move_and_slide()
					else:
						_process_nav_movement(delta)
				else:
					_process_nav_movement(delta)

		State.EATING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			else:
				_dampen_horizontal(delta)
				_process_eating(delta)
				move_and_slide()

		State.CLEARING:
			if not is_on_floor():
				_process_arc_drop_movement(delta)
				move_and_slide()
			else:
				_dampen_horizontal(delta)
				if _pushed_t <= 0.0:
					_safe_rotate_towards(target_obstacle, delta)
				_process_clearing(delta)
				move_and_slide()

	_push_peers(delta)
	_update_animation()
	# DevLabel не каждый кадр — меньше аллокаций строк (важно при нескольких персах)
	_dev_ui_timer += delta
	if _dev_ui_timer >= 0.2:
		_dev_ui_timer = 0.0
		_update_dev_ui()
		_update_thought_bubble()

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


## Старт path → CharacterNavigation
func _nav_go_to(goal: Vector3) -> void:
	_current_target_pos = goal
	if nav:
		nav.go_to(goal)
	elif nav_agent:
		nav_agent.target_position = goal


func _process_nav_movement(delta: float) -> void:
	if nav:
		nav.tick(delta)
	else:
		_on_movement_finished()


## RVO: только walk/deliver; иначе slide в CharacterNavigation
func nav_wants_safe_velocity() -> bool:
	if is_being_dragged or not is_on_floor():
		return false
	if current_state == State.MOVING:
		return true
	if current_state == State.DELIVERING and not _is_unloading_at_storage:
		return true
	return false


## Поворот (работа / fallback) — делегируем nav, если есть
func _face_dir(dir_x: float, dir_z: float, delta: float, min_speed: float = 0.35) -> void:
	if nav and nav.has_method("face_dir"):
		nav.face_dir(dir_x, dir_z, delta, min_speed)
		return
	var dlen := Vector2(dir_x, dir_z).length()
	if dlen < min_speed:
		return
	var target_angle := atan2(-dir_x, -dir_z)
	rotation.y = lerp_angle(rotation.y, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))


## Стоп, но если толкнули — мягкое трение (иначе «вкопанный»)
func _dampen_horizontal(delta: float) -> void:
	if _pushed_t > 0.0:
		_pushed_t -= delta
		velocity.x = move_toward(velocity.x, 0.0, speed * delta * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta * 2.0)
	else:
		_stop_horizontal_movement(delta)


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
		if other_spd >= my_spd * 0.95:
			continue
		var dir: Vector3 = offset / dist
		var w: float = 1.0 - (dist / push_radius)
		var impulse: float = push_strength * w * my_spd * delta * 10.0
		if other_spd < 0.05:
			impulse *= 1.5
		other.velocity.x += dir.x * impulse
		other.velocity.z += dir.z * impulse
		other.set("_pushed_t", 0.5)
		other.move_and_slide()
		velocity.x -= dir.x * impulse * 0.15
		velocity.z -= dir.z * impulse * 0.15


func _safe_rotate_towards(target_node, delta: float) -> void:
	# не передавать freed в typed API — проверка до call
	if target_node == null or not is_instance_valid(target_node):
		return
	_rotate_towards_target(target_node, delta)


func _rotate_towards_target(target_node, delta: float) -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	var dir = (target_node.global_position - global_position)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	_face_dir(dir.x, dir.z, delta, 0.01)



func _on_movement_finished() -> void:
	if current_state == State.MOVING:
		# wander: rest в decision
		if move_intent == "wander" or move_intent == "rest":
			var was_rest: bool = move_intent == "rest"
			move_intent = "rest" if was_rest else ""
			current_state = State.IDLE
			if decision and decision.has_method("on_wander_finished"):
				decision.on_wander_finished()
			if was_rest:
				move_intent = "rest"  # держим метку ночи для UI
			return
		# После context drop — think, не work
		if _awaiting_drop_decide:
			_begin_drop_think()
			return

		if decision and decision.want_storage_meal and target_storage and is_instance_valid(target_storage):
			if _at_work_point(target_storage) or _near_site(target_storage, 3.0):
				if decision.withdraw_one_and_eat(target_storage):
					return
				decision.want_storage_meal = false
				current_state = State.IDLE
				return
			decision.go_eat_from_storage()
			return

		# stoking: забрать wood со склада
		if decision and decision.want_stoking and target_storage and is_instance_valid(target_storage):
			if _at_work_point(target_storage) or _near_site(target_storage):
				var fire = decision.stoking_target if decision.stoking_target else target_campfire
				if _try_pickup_wood_at_storage(target_storage):
					if fire and is_instance_valid(fire):
						start_stoking(fire)
						return
				if fire and is_instance_valid(fire):
					start_stoking(fire)
				else:
					current_state = State.IDLE
				return

		# stoking: дошли до костра с wood
		if decision and decision.want_stoking and target_campfire and is_instance_valid(target_campfire):
			if _at_work_point(target_campfire) or _near_site(target_campfire):
				if data and data.item_amount > 0:
					_is_unloading_at_storage = true
					_work_timer = 0.0
					current_state = State.DELIVERING
					return
				start_stoking(target_campfire)
				return

		if task_manager and task_manager.get_current_task():
			var cur_t = task_manager.get_current_task()
			if cur_t and cur_t.type == TaskManager.TaskType.MOVE_TO:
				task_manager.complete_current_task()
			elif cur_t and cur_t.type == TaskManager.TaskType.GATHER and cur_t.target_node:
				start_harvesting(cur_t.target_node)
				return
			elif cur_t and cur_t.type == TaskManager.TaskType.DELIVER and cur_t.target_node:
				if cur_t.target_node.is_in_group("campfire") or cur_t.target_node.has_method("needs_fuel"):
					start_stoking(cur_t.target_node)
				else:
					start_delivering_to_storage(cur_t.target_node)
				return
			elif cur_t and cur_t.type == TaskManager.TaskType.CLEAR and cur_t.target_node:
				start_clearing_obstacle(cur_t.target_node)
				return

		if target_storage and is_instance_valid(target_storage) and (_at_work_point(target_storage) or _near_site(target_storage)):
			if WorkSite.can_accept(target_storage, self):
				start_delivering_to_storage(target_storage)
				return
			current_state = State.IDLE
			return
		if target_harvest and is_instance_valid(target_harvest) and (_at_work_point(target_harvest) or _near_site(target_harvest)):
			if WorkSite.can_accept(target_harvest, self):
				start_harvesting(target_harvest)
				return
			wander_nearby()
			return

		if decision and decision.hands_busy():
			decision.resolve_cargo_action()
			return

		current_state = State.IDLE

	elif current_state == State.DELIVERING:
		if target_campfire and is_instance_valid(target_campfire) and decision and decision.want_stoking:
			if data and data.item_amount > 0 and _at_work_point(target_campfire):
				_is_unloading_at_storage = true
				_work_timer = 0.0
			elif data and data.item_amount > 0:
				_nav_go_to(_get_free_work_point_safe(target_campfire))
			else:
				start_stoking(target_campfire)
			return
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


## speed * energy * (wander 0.5..0.75 if stroll). age — позже
func _happiness_mult() -> float:
	if data and data.has_method("get_happiness_speed_mult"):
		return float(data.get_happiness_speed_mult())
	return 1.0


func get_current_move_speed() -> float:
	var s: float = speed * _energy_mult() * _happiness_mult()
	if move_intent == "wander" or move_intent == "rest":
		var wmin: float = wander_speed_min
		var wmax: float = wander_speed_max
		if wmax < wmin:
			wmax = wmin
		# rest — спокойный шаг (середина wander-диапазона)
		if move_intent == "rest":
			s *= clampf((wmin + wmax) * 0.5, wmin, wmax)
		else:
			s *= clampf(_wander_speed_factor, wmin, wmax) if _wander_speed_factor > 0.0 else randf_range(wmin, wmax)
	return maxf(s, 0.05)


## UI: текущий work mult (skill + energy + happy)
func get_effective_work_speed_now(skill_key: String = "") -> float:
	var sk: String = skill_key
	if sk == "" and target_harvest and is_instance_valid(target_harvest):
		sk = WorkSite.get_skill(target_harvest, "")
	if sk == "" and data:
		sk = str(data.talent)
	var w: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		w = float(data.get_effective_work_speed(sk if sk != "" else "forager"))
	return w * _energy_mult() * _happiness_mult()



## UI: прогресс работы 0..1 и eta (сек). Не в работе → -1
func get_work_progress() -> Dictionary:
	var out := {"active": false, "progress": 0.0, "eta": -1.0, "required": 0.0, "mult": 0.0}
	var req: float = 0.0
	var mult: float = get_effective_work_speed_now()
	match current_state:
		State.GATHERING:
			if target_harvest and is_instance_valid(target_harvest):
				req = WorkSite.get_time(target_harvest, default_gather_time)
				mult = get_effective_work_speed_now(WorkSite.get_skill(target_harvest, "worker"))
			else:
				return out
		State.DELIVERING:
			if not _is_unloading_at_storage:
				return out
			if target_storage and is_instance_valid(target_storage):
				req = WorkSite.get_time(target_storage, default_deposit_time)
				mult = get_effective_work_speed_now(WorkSite.get_skill(target_storage, "worker"))
			else:
				return out
		State.CLEARING:
			if target_obstacle and is_instance_valid(target_obstacle):
				req = WorkSite.get_time(target_obstacle, 3.0)
				mult = get_effective_work_speed_now(WorkSite.get_skill(target_obstacle, "worker"))
			else:
				return out
		State.EATING:
			req = maxf(float(eat_speed), 0.01)
			mult = 1.0
		_:
			return out
	if req <= 0.0:
		return out
	var prog: float = clampf(_work_timer / req, 0.0, 1.0)
	var left: float = maxf(req - _work_timer, 0.0)
	var eta: float = left / maxf(mult, 0.01) if mult > 0.0 else -1.0
	out["active"] = true
	out["progress"] = prog
	out["eta"] = eta
	out["required"] = req
	out["mult"] = mult
	return out

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
		wander_nearby()
		return

	var required_time: float = WorkSite.get_time(target_harvest, default_gather_time)
	var skill_key: String = WorkSite.get_skill(target_harvest, "worker")
	var current_work_speed: float = work_speed
	if data and data.has_method("get_effective_work_speed"):
		current_work_speed = data.get_effective_work_speed(skill_key)
	current_work_speed *= _energy_mult() * _happiness_mult()

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
	# Campfire stoke unload
	if target_campfire and is_instance_valid(target_campfire) and (decision and decision.want_stoking):
		_process_stoking_unload(delta)
		return
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
	current_work_speed *= _energy_mult() * _happiness_mult()

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
				wander_nearby()
			return
		current_state = State.IDLE


func _process_stoking_unload(delta: float) -> void:
	var fire: Node3D = target_campfire
	if not fire or not is_instance_valid(fire):
		_is_unloading_at_storage = false
		if decision:
			decision.want_stoking = false
		current_state = State.IDLE
		return
	if not data or data.item_amount <= 0:
		# нужно ещё wood?
		if fire.has_method("needs_fuel") and fire.needs_fuel():
			start_stoking(fire)
		else:
			_is_unloading_at_storage = false
			if decision:
				decision.want_stoking = false
				decision.stoking_target = null
			target_campfire = null
			current_state = State.IDLE
		return
	if not _at_work_point(fire):
		_nav_go_to(_get_free_work_point_safe(fire))
		current_state = State.MOVING
		return
	var req: float = WorkSite.get_time(fire, 1.0)
	var mult: float = work_speed * _energy_mult() * _happiness_mult()
	_work_timer += delta * mult
	if _work_timer < req:
		return
	_work_timer = 0.0
	var result: Dictionary = WorkSite.do_work(fire, self)
	if result.get("ok", false):
		var sk: String = str(result.get("xp_skill", "worker"))
		var xp: float = WorkSite.xp_from_config()
		if data.has_method("add_skill_xp"):
			data.add_skill_xp(sk, xp)
		elif data.has_method("add_skill_exp"):
			data.add_skill_exp(sk, xp)
	# ещё нужно?
	if fire.has_method("needs_fuel") and fire.needs_fuel():
		if data.item_amount > 0 and str(data.carried_item).to_lower() in ["wood", "log"]:
			return  # next cycle same unload
		start_stoking(fire)
		return
	_is_unloading_at_storage = false
	if decision:
		decision.want_stoking = false
		decision.stoking_target = null
	target_campfire = null
	if fire.has_method("release_work_point"):
		fire.release_work_point(self)
	if task_manager:
		task_manager.complete_current_task()
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
	current_work_speed *= _energy_mult() * _happiness_mult()

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
	_nav_go_to(target_pos)


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
	# CharacterNavigation: только go_to включает tick (_active)
	_nav_go_to(target_pos)


func _begin_drop_think() -> void:
	current_state = State.IDLE
	_awaiting_drop_decide = true
	var tmin: float = 2.0
	var tmax: float = 5.0
	if ConfigLoader:
		tmin = float(ConfigLoader.get_character_value("base_stats", "think_time_min", tmin))
		tmax = float(ConfigLoader.get_character_value("base_stats", "think_time_max", tmax))
	if tmax < tmin:
		tmax = tmin
	_drop_think_left = randf_range(tmin, tmax)
	if data:
		print("[Character] %s drop-think %.1fs (site=%s)" % [
			data.character_name,
			_drop_think_left,
			drop_site.name if drop_site and is_instance_valid(drop_site) else "empty"
		])


func wander_nearby(radius_min: float = -1.0, radius_max: float = -1.0) -> void:
	_awaiting_drop_decide = false
	_drop_think_left = -1.0
	var wmin: float = wander_speed_min
	var wmax: float = wander_speed_max
	if wmax < wmin:
		wmax = wmin
	_wander_speed_factor = randf_range(wmin, wmax)
	var rmin: float = wander_radius_min if radius_min < 0.0 else radius_min
	var rmax: float = wander_radius_max if radius_max < 0.0 else radius_max
	if rmax < rmin:
		rmax = rmin
	# 1 попытка за вызов (не 8×50 персов в тик). Неудача → idle, decision вызовет снова.
	var r: float = randf_range(rmin, rmax)
	var a: float = randf() * TAU
	var cand: Vector3 = global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	cand.y = global_position.y
	var dest: Vector3 = cand
	if nav_agent:
		var map_rid: RID = nav_agent.get_navigation_map()
		if map_rid.is_valid():
			var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, cand)
			var pull: float = Vector2(cand.x - on_mesh.x, cand.z - on_mesh.z).length()
			# y > -1 (вода 0, по пояс ок); pull — не «съехали» в никуда
			if pull > 2.0 or on_mesh.y <= wander_min_y:
				# в этом кадре не идём — rest/boredom снова наберёт
				move_intent = ""
				return
			var d_me: float = Vector2(global_position.x - on_mesh.x, global_position.z - on_mesh.z).length()
			if d_me < 0.5:
				move_intent = ""
				return
			dest = on_mesh
	move_intent = "wander"
	_soft_move_to(dest)


## Единый вход: игрок/AI → go_work(site). Всегда WP, потом can_accept.
## Ночь: шалаш (кровать) → иначе костёр
func go_night_rest() -> void:
	if go_rest_at_shelter():
		return
	go_rest_near_campfire()


## Слот сна в ближайшем шалаше с свободной кроватью
func go_rest_at_shelter() -> bool:
	_awaiting_drop_decide = false
	_drop_think_left = -1.0
	var tree := get_tree()
	if tree == null:
		return false
	var best: Node3D = null
	var best_d: float = INF
	for n in tree.get_nodes_in_group("shelter"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if n.has_method("has_free_bed") and not bool(n.has_free_bed()):
			continue
		if "is_built" in n and not bool(n.is_built):
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	if best == null:
		return false
	# release old bed if any other shelter
	_release_shelter_bed()
	var dest: Vector3 = best.global_position
	if best.has_method("claim_bed"):
		dest = best.claim_bed(self)
	target_storage = null  # not storage
	# remember hut for release
	set_meta("rest_shelter", best)
	move_intent = "rest"
	if data:
		print("[Rest] %s → shelter %s" % [data.character_name, best.name])
	_soft_move_to(dest)
	return true


func _release_shelter_bed() -> void:
	if has_meta("rest_shelter"):
		var hut = get_meta("rest_shelter")
		if hut and is_instance_valid(hut) and hut.has_method("release_bed"):
			hut.release_bed(self)
		remove_meta("rest_shelter")


func is_near_shelter_rest() -> bool:
	if has_meta("rest_shelter"):
		var hut = get_meta("rest_shelter")
		if hut and is_instance_valid(hut):
			if hut.has_method("is_occupant") and hut.is_occupant(self):
				return true
			return global_position.distance_to(hut.global_position) <= 2.5
	return false


## Вечер/ночь: точка в радиусе OmniLight костра (заметно «все у огня»)
func go_rest_near_campfire() -> void:
	_awaiting_drop_decide = false
	_drop_think_left = -1.0
	_release_shelter_bed()
	var fire: Node3D = _find_nearest_campfire()
	if fire == null:
		wander_nearby()
		return
	var radius: float = 10.0
	if fire.has_method("get_rest_radius"):
		radius = float(fire.get_rest_radius())
	radius = maxf(radius, 2.0)
	var dest: Vector3 = fire.global_position
	var ok := false
	for _i in range(6):
		# ближе к огню 15–70% range — кучкуются, заметнее
		var r: float = randf_range(radius * 0.15, radius * 0.7)
		var a: float = randf() * TAU
		var cand: Vector3 = fire.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		cand.y = global_position.y
		if nav_agent:
			var map_rid: RID = nav_agent.get_navigation_map()
			if map_rid.is_valid():
				var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, cand)
				var pull: float = Vector2(cand.x - on_mesh.x, cand.z - on_mesh.z).length()
				if pull > 2.5 or on_mesh.y <= wander_min_y:
					continue
				var d_me: float = Vector2(global_position.x - on_mesh.x, global_position.z - on_mesh.z).length()
				if d_me < 0.35:
					continue
				dest = on_mesh
				ok = true
				break
		else:
			dest = cand
			ok = true
			break
	if not ok:
		# fallback: чуть в сторону от центра (не в obstacle)
		var a2: float = randf() * TAU
		dest = fire.global_position + Vector3(cos(a2) * 1.5, 0.0, sin(a2) * 1.5)
		if nav_agent:
			var map_rid2: RID = nav_agent.get_navigation_map()
			if map_rid2.is_valid():
				dest = NavigationServer3D.map_get_closest_point(map_rid2, dest)
	move_intent = "rest"
	if data:
		print("[Rest] %s → campfire (r=%.1f dist=%.1f)" % [
			data.character_name, radius, global_position.distance_to(fire.global_position)
		])
	_soft_move_to(dest)


func _find_nearest_campfire() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_d: float = INF
	for n in tree.get_nodes_in_group("campfire"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


func is_near_campfire_rest() -> bool:
	var fire: Node3D = _find_nearest_campfire()
	if fire == null:
		return false
	var radius: float = 10.0
	if fire.has_method("get_rest_radius"):
		radius = float(fire.get_rest_radius())
	return global_position.distance_to(fire.global_position) <= maxf(radius, 1.5) * 1.05


func go_work(site: Node3D) -> void:
	if not site or not is_instance_valid(site):
		return
	# harvest / clear / build: как drop — think → remember → work|wander
	var cat := WorkSite.get_category(site)
	if cat in ["harvest", "clear", "build"]:
		on_context_drop(site, site.global_position)
		return
	# склад / костёр — сразу
	start_work_at(site)


func start_work_at(site: Node3D) -> void:
	if not site or not is_instance_valid(site):
		return
	var category := WorkSite.get_category(site)
	match category:
		"harvest":
			start_harvesting(site)
		"deposit":
			if site.is_in_group("campfire") or (site.has_method("needs_fuel") and site.has_method("add_wood")):
				start_stoking(site)
			else:
				start_delivering_to_storage(site)
		"clear":
			start_clearing_obstacle(site)
		"build":
			print("[Character] BUILD not implemented yet for %s" % site.name)
			_go_to_site_wp(site)
		_:
			_go_to_site_wp(site)


func start_harvesting(site: Node3D) -> void:
	# ночь + пустые руки — не начинаем сбор (доделывают только уже начатое)
	if decision and decision.has_method("_is_rest_time") and decision._is_rest_time():
		if not (data and data.item_amount > 0):
			if has_method("go_night_rest"):
				go_night_rest()
			elif has_method("go_rest_near_campfire"):
				go_rest_near_campfire()
			return
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

	# без груза — всё равно идём на WP склада (клик как у куста; deposit/eat решат на месте)
	if not (data and data.item_amount > 0):
		_is_unloading_at_storage = false
		is_being_dragged = false
		_awaiting_drop_decide = false
		target_storage = storage_node
		if storage_node.has_method("set_active_work"):
			storage_node.set_active_work("withdraw")
		_current_target_pos = _get_free_work_point_safe(storage_node)
		# голод → eat-таск; иначе просто прийти к складу
		if decision and decision.has_method("should_eat_from_storage") and decision.should_eat_from_storage():
			decision.want_storage_meal = true
			if decision.has_method("ensure_eat_task"):
				decision.ensure_eat_task()
			move_intent = "eat"
		else:
			move_intent = "work"
		if task_manager:
			task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.MOVE_TO, _current_target_pos, storage_node, 10, false))
		if is_on_floor() and _at_work_point(storage_node):
			current_state = State.IDLE
			if decision and move_intent == "eat" and decision.has_method("execute_eat_task"):
				decision.promote_eat_task()
				decision.execute_eat_task()
		else:
			current_state = State.MOVING
			_nav_go_to(_current_target_pos)
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



## Костёр: wood в руках → WP → deposit; иначе склад wood / debris → снова сюда
func start_stoking(fire: Node3D) -> void:
	if not fire or not is_instance_valid(fire):
		return
	target_campfire = fire
	if decision:
		decision.want_stoking = true
		decision.stoking_target = fire
	is_being_dragged = false
	_is_unloading_at_storage = false
	_awaiting_drop_decide = false
	_work_timer = 0.0
	# уже есть wood
	if data and data.item_amount > 0 and str(data.carried_item).to_lower() in ["wood", "log"]:
		_release_all_work_points()
		_current_target_pos = _get_free_work_point_safe(fire)
		move_intent = "deliver"
		if _at_work_point(fire) and is_on_floor():
			current_state = State.DELIVERING
			_is_unloading_at_storage = true  # reuse unload timer path → specialized below
		else:
			current_state = State.MOVING
			_nav_go_to(_current_target_pos)
		if task_manager:
			task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.DELIVER, Vector3.ZERO, fire, 20, true))
		return
	# нет wood — склад приоритет
	var st := _find_storage_with_wood()
	if st:
		target_storage = st
		_current_target_pos = _get_free_work_point_safe(st)
		move_intent = "work"
		current_state = State.MOVING
		_nav_go_to(_current_target_pos)
		if task_manager:
			task_manager.set_user_override_task(TaskManager.Task.new(TaskManager.TaskType.MOVE_TO, _current_target_pos, st, 30, false))
		return
	# завал
	var deb := _find_nearest_debris()
	if deb:
		start_harvesting(deb)
		return
	# нечего нести
	if decision:
		decision.want_stoking = false
		decision.stoking_target = null
	current_state = State.IDLE
	print("[Character] stoking: no wood source")


func _find_storage_with_wood() -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for n in get_tree().get_nodes_in_group("storage"):
		if not is_instance_valid(n):
			continue
		var has := false
		if n.has_method("has_wood"):
			has = bool(n.has_wood())
		elif "stored_wood" in n:
			has = int(n.stored_wood) > 0
		if not has:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


func _find_nearest_debris() -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for g in ["debris", "obstacle"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n):
				continue
			if not WorkSite.can_accept(n, self):
				continue
			var d: float = global_position.distance_to(n.global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
	return best


func _try_pickup_wood_at_storage(st: Node3D) -> bool:
	if not st or not is_instance_valid(st) or not data:
		return false
	if data.item_amount > 0:
		return str(data.carried_item).to_lower() in ["wood", "log"]
	var got: int = 0
	if st.has_method("withdraw_wood"):
		got = int(st.withdraw_wood(1))
	elif "stored_wood" in st and int(st.stored_wood) > 0:
		st.stored_wood -= 1
		got = 1
		if st.has_method("_update_dev_ui"):
			st._update_dev_ui()
	if got > 0:
		data.carried_item = "wood"
		data.item_amount = got
		return true
	return false


func _go_to_site_wp(site: Node3D) -> void:
	_release_all_work_points()
	is_being_dragged = false
	_is_unloading_at_storage = false
	_awaiting_drop_decide = false
	_nav_go_to(_get_free_work_point_safe(site))
	current_state = State.MOVING


func start_clearing_obstacle(obstacle_node: Node3D) -> void:
	if decision and decision.has_method("_is_rest_time") and decision._is_rest_time():
		if not (data and data.item_amount > 0):
			if has_method("go_night_rest"):
				go_night_rest()
			elif has_method("go_rest_near_campfire"):
				go_rest_near_campfire()
			return
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
		_nav_go_to(_current_target_pos)

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
	_apply_dev_label_visibility()


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


func _apply_dev_label_visibility() -> void:
	if not dev_label:
		return
	var on := true
	if DevCheatManager and DevCheatManager.has_method("is_dev_overlays_on"):
		on = bool(DevCheatManager.is_dev_overlays_on())
	dev_label.visible = on


func _update_dev_ui() -> void:
	if not dev_label or not data:
		return
	_apply_dev_label_visibility()
	if not dev_label.visible:
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
		elif move_intent == "rest":
			if is_near_shelter_rest():
				site_hint = "R:hut"
			else:
				site_hint = "R:camp"
		elif data and data.item_amount > 0:
			site_hint = "D:" + WorkSite.get_type(target_storage)
		else:
			site_hint = "S:" + WorkSite.get_type(target_storage)

	var text_info = "%s (%s) [%s]%s\n" % [data.character_name, gender_str, state_str, " *SEL*" if is_selected else ""]
	text_info += "Site: %s\n" % site_hint
	text_info += "Talent: %s | Skill Lvl: %d\n" % [talent_str, skill_lvl]
	text_info += "Age: %d yr | HP: %.0f | Hng: %.0f | En: %.0f | Hap: %.0f\n" % [
		data.age, data.health, data.hunger, data.energy, data.happiness
	]
	text_info += "Carrying: %s (%d)\n" % [
		data.carried_item if data.carried_item != "" else "None",
		data.item_amount,
	]
	var wp: Dictionary = get_work_progress()
	if wp.get("active", false):
		text_info += "move:%.2f work:%.2f vel:%.2f (e:%.2f h:%.2f)\n" % [
			get_current_move_speed(),
			float(wp.get("mult", 0.0)),
			Vector2(velocity.x, velocity.z).length(),
			_energy_mult(),
			_happiness_mult(),
		]
		text_info += "work%%:%.0f eta:%.1fs" % [float(wp.get("progress", 0.0)) * 100.0, float(wp.get("eta", 0.0))]
	else:
		text_info += "move:%.2f work:%.2f vel:%.2f (e:%.2f h:%.2f)" % [
			get_current_move_speed(),
			get_effective_work_speed_now(),
			Vector2(velocity.x, velocity.z).length(),
			_energy_mult(),
			_happiness_mult(),
		]
	
	dev_label.text = text_info


# --- THOUGHTS / BUBBLE ---

func _load_thought_cfg() -> void:
	if _thought_cfg_loaded:
		return
	_thought_cfg_loaded = true
	if not ConfigLoader:
		return
	_th_hunger_thr = float(ConfigLoader.get_character_value("thoughts", "hunger_threshold", _th_hunger_thr))
	_th_bubble_path = str(ConfigLoader.get_character_value("thoughts", "bubble_path", _th_bubble_path)).replace('"', "")
	_th_icon_food = str(ConfigLoader.get_character_value("thoughts", "icon_food_path", _th_icon_food)).replace('"', "")
	_th_bubble_h = float(ConfigLoader.get_character_value("thoughts", "bubble_height", _th_bubble_h))
	_th_bubble_px = float(ConfigLoader.get_character_value("thoughts", "bubble_pixel_size", _th_bubble_px))
	_th_icon_px = float(ConfigLoader.get_character_value("thoughts", "icon_pixel_size", _th_icon_px))
	_th_icon_y = float(ConfigLoader.get_character_value("thoughts", "icon_local_y", _th_icon_y))


func _setup_thought_bubble() -> void:
	_load_thought_cfg()
	if _thought_root and is_instance_valid(_thought_root):
		return
	_thought_root = Node3D.new()
	_thought_root.name = "ThoughtBubble"
	_thought_root.position = Vector3(0.0, _th_bubble_h, 0.0)
	add_child(_thought_root)

	_thought_bubble = Sprite3D.new()
	_thought_bubble.name = "Bubble"
	_thought_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_thought_bubble.pixel_size = _th_bubble_px
	_thought_bubble.centered = true
	_thought_bubble.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if ResourceLoader.exists(_th_bubble_path):
		_thought_bubble.texture = load(_th_bubble_path) as Texture2D
	_thought_root.add_child(_thought_bubble)

	_thought_icon = Sprite3D.new()
	_thought_icon.name = "Icon"
	_thought_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_thought_icon.pixel_size = _th_icon_px
	_thought_icon.centered = true
	_thought_icon.position = Vector3(0.0, _th_icon_y, 0.02)
	_thought_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_thought_root.add_child(_thought_icon)

	_thought_root.visible = false


## { "id": "need_food", "icon": path, "text_id": "NEED_FOOD" } or empty
func get_thought() -> Dictionary:
	_load_thought_cfg()
	if current_state == State.DEAD or current_state == State.EATING:
		return {}
	if is_being_dragged:
		return {}
	if data == null:
		return {}
	if float(data.hunger) >= _th_hunger_thr:
		return {
			"id": "need_food",
			"icon": _th_icon_food,
			"text_id": "NEED_FOOD",
		}
	return {}


func get_thought_message() -> String:
	var th: Dictionary = get_thought()
	if th.is_empty():
		return ""
	var tid: String = str(th.get("text_id", ""))
	var nm: String = str(data.character_name) if data else "?"
	if Loc and Loc.has_method("t"):
		return Loc.t(tid, {"name": nm})
	# fallback EN
	if tid == "NEED_FOOD":
		return "%s is hungry — send them to the stocks" % nm
	return tid


func _update_thought_bubble() -> void:
	if _thought_root == null or not is_instance_valid(_thought_root):
		_setup_thought_bubble()
	var th: Dictionary = get_thought()
	var id: String = str(th.get("id", "")) if not th.is_empty() else ""
	if id == "":
		_thought_id = ""
		_thought_root.visible = false
		return
	_thought_root.visible = true
	if id != _thought_id:
		_thought_id = id
		var ipath: String = str(th.get("icon", ""))
		if _thought_icon and ResourceLoader.exists(ipath):
			_thought_icon.texture = load(ipath) as Texture2D
	_thought_root.position.y = _th_bubble_h


