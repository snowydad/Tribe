# ==============================================================================
# CharacterDecision.gd — решения (eat / deliver / harvest / drop). Движение — host.
# ОБНОВЛЕНО: 2026-10-20 — talent→work, no talent→wander
# ==============================================================================
extends RefCounted

var host: CharacterBody3D

var cargo_drop_delay: float = 30.0
var _cargo_drop_timer: float = 0.0
var want_storage_meal: bool = false
var want_stoking: bool = false
var stoking_target: Node = null
var _idle_check_timer: float = 0.0
# idle wander (ini: base_stats)
var idle_wander_delay: float = 3.0
var wander_rest_min: float = 2.0
var wander_rest_max: float = 5.0
var _idle_boredom_t: float = 0.0
var _wander_rest_t: float = 0.0
var _wander_cfg_loaded: bool = false


func setup(h: CharacterBody3D) -> void:
	host = h
	_load_idle_wander_cfg()


func _is_night() -> bool:
	if TimeManager and TimeManager.has_method("is_night"):
		return bool(TimeManager.is_night())
	if TimeManager and TimeManager.has_method("is_night_hour") and TimeManager.has_method("get_game_hour"):
		return bool(TimeManager.is_night_hour(TimeManager.get_game_hour()))
	return false


## Отдых: вечер+ночь (см. TimeManager.is_rest_time)
func _is_rest_time() -> bool:
	if TimeManager and TimeManager.has_method("is_rest_time"):
		return bool(TimeManager.is_rest_time())
	return _is_night()


func _load_idle_wander_cfg() -> void:
	if _wander_cfg_loaded:
		return
	_wander_cfg_loaded = true
	if not ConfigLoader:
		return
	if ConfigLoader.has_method("get_character_value"):
		idle_wander_delay = float(ConfigLoader.get_character_value("base_stats", "idle_wander_delay", idle_wander_delay))
		wander_rest_min = float(ConfigLoader.get_character_value("base_stats", "wander_rest_min", wander_rest_min))
		wander_rest_max = float(ConfigLoader.get_character_value("base_stats", "wander_rest_max", wander_rest_max))
	elif ConfigLoader.has_method("get_config_value"):
		idle_wander_delay = float(ConfigLoader.get_config_value("character", "base_stats", "idle_wander_delay", idle_wander_delay))
		wander_rest_min = float(ConfigLoader.get_config_value("character", "base_stats", "wander_rest_min", wander_rest_min))
		wander_rest_max = float(ConfigLoader.get_config_value("character", "base_stats", "wander_rest_max", wander_rest_max))
	if wander_rest_max < wander_rest_min:
		wander_rest_max = wander_rest_min


func _tick_wander_rest(delta: float) -> void:
	if _wander_rest_t > 0.0:
		_wander_rest_t = maxf(_wander_rest_t - delta, 0.0)


func _try_idle_wander() -> void:
	# строго: очередь пуста
	var tm = _tm()
	if tm and tm.has_tasks():
		_idle_boredom_t = 0.0
		return
	if _wander_rest_t > 0.0:
		return
	if host == null or not host.has_method("wander_nearby"):
		return
	_idle_boredom_t = 0.0
	# rest наберётся в IDLE после прогулки (пока MOVING process_idle не тикает)
	_wander_rest_t = randf_range(wander_rest_min, wander_rest_max)
	host.wander_nearby()


func _data():
	return host.data if host else null


func _tm():
	return host.task_manager if host else null


func hands_busy() -> bool:
	var d = _data()
	return d != null and d.item_amount > 0


func knows_harvest() -> bool:
	return host != null and host.target_harvest != null and is_instance_valid(host.target_harvest)


func try_work_or_wander_harvest(site: Node3D = null) -> bool:
	var s: Node3D = site if site else (host.target_harvest if host else null)
	if s == null or not is_instance_valid(s):
		return false
	if WorkSite.can_accept(s, host):
		host.start_harvesting(s)
		return true
	host.wander_nearby()
	return true


func has_edible_cargo() -> bool:
	if not hands_busy():
		return false
	var item := str(_data().carried_item)
	if ConfigLoader and ConfigLoader.has_method("is_item_edible"):
		return bool(ConfigLoader.is_item_edible(item, false))
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		return float(ConfigLoader.get_item_nutrition(item, 0.0)) > 0.0
	return false


# --- storage queries ---

func storage_has_space(st: Node = null) -> bool:
	if st and is_instance_valid(st):
		if st.has_method("has_space"):
			return bool(st.has_space())
		return false
	if host == null or host.get_tree() == null:
		return false
	for s in host.get_tree().get_nodes_in_group("storage"):
		if s and is_instance_valid(s) and storage_has_space(s):
			return true
	return false


func storage_has_food(st: Node = null) -> bool:
	if st and is_instance_valid(st):
		if st.has_method("has_food"):
			return bool(st.has_food())
		if "stored_food" in st:
			return int(st.stored_food) > 0
		return false
	if host == null or host.get_tree() == null:
		return false
	for s in host.get_tree().get_nodes_in_group("storage"):
		if s and is_instance_valid(s) and storage_has_food(s):
			return true
	return false


func storage_is_full() -> bool:
	if host == null or host.get_tree() == null:
		return false
	var found := false
	for s in host.get_tree().get_nodes_in_group("storage"):
		if s == null or not is_instance_valid(s):
			continue
		found = true
		if storage_has_space(s):
			return false
	return found


func find_storage_with_food() -> Node3D:
	if host == null or host.get_tree() == null:
		return null
	var best: Node3D = null
	var best_d: float = INF
	for s in host.get_tree().get_nodes_in_group("storage"):
		var ns := s as Node3D
		if not ns or not is_instance_valid(ns) or not storage_has_food(ns):
			continue
		var d: float = host.global_position.distance_to(ns.global_position)
		if d < best_d:
			best_d = d
			best = ns
	return best


# --- matrix ---

func is_cargo_hold_g() -> bool:
	if not hands_busy() or storage_has_space():
		return false
	var d = _data()
	return d != null and d.energy >= 100.0 and d.hunger <= 0.0


func should_eat_from_hands() -> bool:
	if not has_edible_cargo() or is_cargo_hold_g():
		return false
	var d = _data()
	if d.hunger >= 25.0:
		return true
	if not storage_has_space():
		return d.hunger < 100.0 or d.energy < 100.0
	return false


func should_deliver() -> bool:
	if not hands_busy():
		return false
	if _data().hunger >= 25.0:
		return false
	return storage_has_space()


func should_eat_from_storage() -> bool:
	if hands_busy() or not _data():
		return false
	if _data().hunger <= 25.0:
		return false
	return storage_has_food()


func should_go_harvest() -> bool:
	# Сбор: руки пусты + знает куст + склад не full.
	# НЕ блокируем из‑за «на складе уже еда» / «сыт» — иначе никто не запасает.
	# Голод → EAT (ensure_eat_task) приоритетнее в process_idle.
	if hands_busy() or not _data():
		return false
	if storage_is_full():
		return false
	return knows_harvest()


## Нужда есть → один EAT subtask (не стартует анимацию; выполнение — execute_eat_task)
func ensure_eat_task() -> void:
	if not host:
		return
	if not (should_eat_from_hands() or should_eat_from_storage()):
		return
	var tm = _tm()
	if tm == null:
		return
	if tm.has_task_of_type(TaskManager.TaskType.EAT):
		return
	tm.push_subtask(TaskManager.Task.new(TaskManager.TaskType.EAT, Vector3.ZERO, null, 90))


func promote_eat_task() -> bool:
	var tm = _tm()
	if tm == null:
		return false
	if not tm.has_task_of_type(TaskManager.TaskType.EAT):
		return false
	return tm.promote_task_type(TaskManager.TaskType.EAT)


func tick_eat_need() -> void:
	if host == null:
		return
	if host.current_state == host.State.DEAD or host.current_state == host.State.CARRIED:
		return
	if host.current_state == host.State.EATING:
		return
	if not (should_eat_from_hands() or should_eat_from_storage()):
		return
	ensure_eat_task()
	if host.current_state == host.State.GATHERING:
		return
	if host.current_state == host.State.DELIVERING and host._is_unloading_at_storage:
		return
	if not promote_eat_task():
		return
	if host.move_intent == "eat" and host.current_state == host.State.MOVING:
		return
	execute_eat_task()


## Выполнить текущий EAT (руки или склад) — без повторного push
func execute_eat_task() -> void:
	_cargo_drop_timer = 0.0
	if has_edible_cargo():
		want_storage_meal = false
		host._is_unloading_at_storage = false
		host.start_eating()
		return
	if should_eat_from_storage() or storage_has_food():
		go_eat_from_storage()
		return
	# есть нельзя — снять таск
	var tm = _tm()
	if tm and tm.get_current_task() and tm.get_current_task().type == TaskManager.TaskType.EAT:
		tm.complete_current_task()


func start_eat_hands() -> void:
	ensure_eat_task()
	promote_eat_task()
	execute_eat_task()


func resolve_cargo_action() -> void:
	if not hands_busy():
		return
	if should_eat_from_hands():
		ensure_eat_task()
		promote_eat_task()
		execute_eat_task()
		return
	# wood → костёр, если stoking
	if want_stoking and stoking_target and is_instance_valid(stoking_target):
		var item := str(_data().carried_item).to_lower() if _data() else ""
		if item in ["wood", "log"]:
			host.start_stoking(stoking_target)
			return
	if should_deliver():
		var nearest_st = host._find_nearest_storage_node()
		var tm = _tm()
		if tm and nearest_st:
			tm.push_subtask(TaskManager.Task.new(TaskManager.TaskType.DELIVER, Vector3.ZERO, nearest_st, 60))
		host._go_to_nearest_storage()
		return
	host._is_unloading_at_storage = false
	host.current_state = host.State.IDLE


func tick_cargo_drop(delta: float) -> void:
	if not is_cargo_hold_g():
		_cargo_drop_timer = 0.0
		return
	_cargo_drop_timer += delta
	if _cargo_drop_timer < cargo_drop_delay:
		return
	_cargo_drop_timer = 0.0
	var d = _data()
	d.carried_item = ""
	d.item_amount = 0
	var tm = _tm()
	if tm and tm.has_tasks():
		var cur = tm.get_current_task()
		if cur and cur.type == TaskManager.TaskType.DELIVER:
			tm.complete_current_task()


func withdraw_one_and_eat(st: Node) -> bool:
	var d = _data()
	if not d or not st or not is_instance_valid(st) or not st.has_method("withdraw_food"):
		return false
	var portion: int = 25
	if st.has_method("get_meal_portion"):
		portion = int(st.get_meal_portion())
	if st.has_method("set_active_work"):
		st.set_active_work("withdraw")
	var got: int = int(st.withdraw_food(portion))
	if got <= 0:
		return false
	d.carried_item = "food"
	d.item_amount = 1
	want_storage_meal = false
	_cargo_drop_timer = 0.0
	start_eat_hands()
	return true


func go_eat_from_storage() -> void:
	var st = find_storage_with_food()
	if not st:
		return
	want_storage_meal = true
	host._is_unloading_at_storage = false
	_cargo_drop_timer = 0.0
	host.target_storage = st
	host._current_target_pos = host._get_free_work_point_safe(st)

	var near_st: bool = host.global_position.distance_to(st.global_position) <= host.docking_distance
	var at_wp: bool = Vector2(host.global_position.x, host.global_position.z).distance_to(
		Vector2(host._current_target_pos.x, host._current_target_pos.z)
	) <= host.arrival_distance

	if at_wp or near_st:
		withdraw_one_and_eat(st)
	else:
		host.move_intent = "eat"
		host.current_state = host.State.MOVING
		# CharacterNavigation: go_to, не только agent.target
		if host.has_method("_nav_go_to"):
			host._nav_go_to(host._current_target_pos)
		elif host.nav_agent:
			host.nav_agent.target_position = host._current_target_pos


func handle_full_storage_with_cargo() -> bool:
	if not hands_busy() or storage_has_space():
		return false
	resolve_cargo_action()
	return true


# --- drop ---

func remembers_site(site: Node3D) -> bool:
	if not site or not is_instance_valid(site) or not host:
		return false
	if host.target_harvest and is_instance_valid(host.target_harvest) and host.target_harvest == site:
		return true
	if host.target_storage and is_instance_valid(host.target_storage) and host.target_storage == site:
		return true
	return false


func remember_site(site: Node3D) -> void:
	if not site or not is_instance_valid(site) or not host:
		return
	if WorkSite.get_category(site) == "deposit":
		host.target_storage = site
	else:
		host.target_harvest = site


func drop_eat_if_hungry() -> bool:
	var d = _data()
	if not d:
		return false
	var thr: float = 25.0
	if ConfigLoader:
		if ConfigLoader.has_method("get_character_value"):
			thr = float(ConfigLoader.get_character_value("base_stats", "drop_eat_hunger", thr))
		elif ConfigLoader.has_method("get_config_value"):
			thr = float(ConfigLoader.get_config_value("character", "base_stats", "drop_eat_hunger", thr))
	if d.hunger <= thr or not has_edible_cargo():
		return false
	start_eat_hands()
	return true


func site_has_work(site: Node3D) -> bool:
	if not site or not is_instance_valid(site):
		return false
	match WorkSite.get_category(site):
		"deposit":
			return hands_busy() and storage_has_space(site)
		"harvest":
			return (not hands_busy()) and WorkSite.can_accept(site, host)
		_:
			return WorkSite.can_accept(site, host)


func has_talent_for_site(site: Node3D) -> bool:
	if not site or not is_instance_valid(site):
		return false
	if WorkSite.get_category(site) == "deposit":
		return true
	var skill := WorkSite.get_skill(site, "").strip_edges().to_lower()
	if skill.is_empty():
		return true
	var d = _data()
	if not d:
		return false
	var talent := str(d.talent).strip_edges().to_lower()
	if talent == skill:
		return true
	if ConfigLoader and ConfigLoader.has_method("get_skill_value"):
		var raw := str(ConfigLoader.get_skill_value("talents_skills", talent, "")).replace('"', "").replace("'", "")
		for part in raw.split(","):
			if part.strip_edges().to_lower() == skill:
				return true
	return false


func resolve_after_drop(drop_site: Node3D = null) -> void:
	var tm = _tm()

	# 0) cargo → deliver
	if hands_busy():
		if drop_site and is_instance_valid(drop_site) and WorkSite.get_category(drop_site) == "deposit":
			if drop_site.is_in_group("campfire") or drop_site.has_method("needs_fuel"):
				host.start_stoking(drop_site)
			else:
				host.start_delivering_to_storage(drop_site)
			return
		if tm and tm.has_tasks():
			var cur = tm.get_current_task()
			if cur and cur.type == TaskManager.TaskType.DELIVER and cur.target_node and is_instance_valid(cur.target_node):
				host.start_delivering_to_storage(cur.target_node)
				return
		if host.target_storage and is_instance_valid(host.target_storage):
			host.start_delivering_to_storage(host.target_storage)
			return
		host._go_to_nearest_storage()
		return

	# 1) task queue
	if tm and tm.has_tasks():
		var cur = tm.get_current_task()
		if cur:
			match cur.type:
				TaskManager.TaskType.GATHER:
					if cur.target_node and is_instance_valid(cur.target_node):
						try_work_or_wander_harvest(cur.target_node)
						return
				TaskManager.TaskType.DELIVER:
					tm.complete_current_task()
				TaskManager.TaskType.CLEAR:
					if cur.target_node and is_instance_valid(cur.target_node):
						host.start_clearing_obstacle(cur.target_node)
						return
				TaskManager.TaskType.EAT:
					execute_eat_task()
					return
				TaskManager.TaskType.MOVE_TO:
					host.move_to_position(cur.target_pos)
					drop_eat_if_hungry()
					return
				TaskManager.TaskType.BUILD, _:
					if cur.target_node and is_instance_valid(cur.target_node):
						host.go_work(cur.target_node)
						return

	# 2) drop/click on object: всегда remember → talent? work : wander (потом work из idle)
	if drop_site and is_instance_valid(drop_site):
		remember_site(drop_site)
		if has_talent_for_site(drop_site):
			host.start_work_at(drop_site)
		else:
			# без таланта: погулял → process_idle/knows_harvest → work
			host.wander_nearby()
		drop_eat_if_hungry()
		return

	# 3) blank
	host.wander_nearby()
	drop_eat_if_hungry()


# --- idle ---

func process_idle(delta: float) -> void:
	tick_cargo_drop(delta)
	_load_idle_wander_cfg()
	_tick_wander_rest(delta)

	# нужда есть → всегда таск EAT (после текущего, без дубля)
	if should_eat_from_hands() or should_eat_from_storage():
		ensure_eat_task()

	# --- НОЧЬ: добить руки/еду, потом к костру, без новой работы ---
	if _is_rest_time():
		# сначала сдать груз / съесть
		if hands_busy():
			if not should_eat_from_hands() and should_deliver():
				host._go_to_nearest_storage()
				return
			if should_eat_from_hands():
				ensure_eat_task()
				promote_eat_task()
				execute_eat_task()
				return
			# прочий груз без deliver — resolve
			resolve_cargo_action()
			return
		var tm_n = _tm()
		if tm_n and tm_n.has_tasks():
			var ct = tm_n.get_current_task()
			if ct and ct.type == TaskManager.TaskType.EAT:
				execute_eat_task()
				return
			# GATHER/CLEAR/DELIVER без груза — снять, не работать ночью
			if ct and ct.type in [TaskManager.TaskType.GATHER, TaskManager.TaskType.CLEAR]:
				tm_n.complete_current_task()
				return
			if ct and ct.type == TaskManager.TaskType.DELIVER and not hands_busy():
				tm_n.complete_current_task()
				return
		# руки пусты — шалаш, иначе костёр
		var near_safe: bool = false
		if host.has_method("is_near_shelter_rest") and host.is_near_shelter_rest():
			near_safe = true
		elif host.has_method("is_near_campfire_rest") and host.is_near_campfire_rest():
			near_safe = true
		if near_safe:
			host.move_intent = "rest"
			var near_delay: float = idle_wander_delay
			if host.has_method("is_near_shelter_rest") and host.is_near_shelter_rest():
				near_delay = idle_wander_delay * 3.0
			else:
				near_delay = minf(idle_wander_delay, 2.0)
			if _wander_rest_t <= 0.0 and _idle_boredom_t >= near_delay:
				_idle_boredom_t = 0.0
				_wander_rest_t = randf_range(1.0, 2.5)
				if host.has_method("go_night_rest"):
					host.go_night_rest()
			return
		if host.has_method("go_night_rest"):
			host.go_night_rest()
		elif host.has_method("go_rest_near_campfire"):
			host.go_rest_near_campfire()
		return

	if hands_busy():
		# eat уже в очереди; deliver только если не жрём с рук
		if not should_eat_from_hands() and should_deliver():
			host._go_to_nearest_storage()
			return
		if should_eat_from_hands():
			pass  # EAT в стеке — ниже
		else:
			_idle_check_timer += delta
			if _idle_check_timer >= 0.5:
				_idle_check_timer = 0.0
				if should_deliver():
					host._go_to_nearest_storage()
					return
			# нет deliver/eat — ниже tasks / harvest
			if not (should_eat_from_hands() or should_eat_from_storage()):
				# fall through only if tasks may exist
				pass

	var tm = _tm()
	if tm and tm.has_tasks():
		var cur_task = tm.get_current_task()
		if cur_task:
			match cur_task.type:
				TaskManager.TaskType.EAT:
					execute_eat_task()
					return
				TaskManager.TaskType.GATHER:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						host.target_harvest = cur_task.target_node
						if should_eat_from_hands() or should_eat_from_storage():
							ensure_eat_task()
						try_work_or_wander_harvest(cur_task.target_node)
						return
				TaskManager.TaskType.DELIVER:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						if hands_busy() and WorkSite.can_accept(cur_task.target_node, host):
							host.start_delivering_to_storage(cur_task.target_node)
						elif hands_busy():
							handle_full_storage_with_cargo()
						else:
							tm.complete_current_task()
						return
				TaskManager.TaskType.CLEAR:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						if not WorkSite.is_site(cur_task.target_node) or WorkSite.can_accept(cur_task.target_node, host):
							host.start_clearing_obstacle(cur_task.target_node)
						return
				TaskManager.TaskType.MOVE_TO:
					var pos_xz = Vector2(host.global_position.x, host.global_position.z)
					var tgt_xz = Vector2(cur_task.target_pos.x, cur_task.target_pos.z)
					if pos_xz.distance_to(tgt_xz) <= host.arrival_distance:
						tm.complete_current_task()
					else:
						host.move_to_position(cur_task.target_pos)
					return

	# нет активных тасков (или очередь пуста после complete) — harvest
	if not hands_busy() and should_go_harvest():
		try_work_or_wander_harvest(host.target_harvest)
		return

	# poll harvest / full storage meal
	if knows_harvest() or storage_is_full():
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			if hands_busy():
				return
			if should_eat_from_hands() or should_eat_from_storage():
				ensure_eat_task()
				return
			if knows_harvest():
				try_work_or_wander_harvest(host.target_harvest)

	# --- idle wander: нет задач + rest вышел ---
	var tm_idle = _tm()
	if tm_idle and tm_idle.has_tasks():
		_idle_boredom_t = 0.0
		return
	if _wander_rest_t > 0.0:
		return
	_idle_boredom_t += delta
	if _idle_boredom_t >= idle_wander_delay:
		_try_idle_wander()


func on_wander_finished() -> void:
	_wander_rest_t = randf_range(wander_rest_min, wander_rest_max)
	_idle_boredom_t = 0.0
