# ==============================================================================
# CharacterDecision.gd — решения (eat / deliver / harvest / drop). Движение — host.
# ОБНОВЛЕНО: 2026-10-09 — cleanup, логика та же
# ==============================================================================
class_name CharacterDecision
extends RefCounted

var host: CharacterBody3D

var cargo_drop_delay: float = 30.0
var _cargo_drop_timer: float = 0.0
var want_storage_meal: bool = false
var _idle_check_timer: float = 0.0


func setup(h: CharacterBody3D) -> void:
	host = h


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
	if hands_busy() or not _data():
		return false
	if _data().hunger <= 25.0:
		return false
	if storage_has_food() or storage_is_full():
		return false
	return knows_harvest()


func start_eat_hands() -> void:
	_cargo_drop_timer = 0.0
	want_storage_meal = false
	host._is_unloading_at_storage = false
	var tm = _tm()
	if tm:
		tm.push_subtask(TaskManager.Task.new(TaskManager.TaskType.EAT, Vector3.ZERO, null, 90))
	host.start_eating()


func resolve_cargo_action() -> void:
	if not hands_busy():
		return
	if should_eat_from_hands():
		start_eat_hands()
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
		if host.nav_agent:
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
					if has_edible_cargo():
						host.start_eating()
						return
					tm.complete_current_task()
				TaskManager.TaskType.MOVE_TO:
					host.move_to_position(cur.target_pos)
					drop_eat_if_hungry()
					return
				TaskManager.TaskType.BUILD, _:
					if cur.target_node and is_instance_valid(cur.target_node):
						host.go_work(cur.target_node)
						return

	# 2) drop on object
	if drop_site and is_instance_valid(drop_site):
		if has_talent_for_site(drop_site) or remembers_site(drop_site):
			host.start_work_at(drop_site)
			return
		remember_site(drop_site)
		host.wander_nearby()
		drop_eat_if_hungry()
		return

	# 3) blank
	host.wander_nearby()
	drop_eat_if_hungry()


# --- idle ---

func process_idle(delta: float) -> void:
	tick_cargo_drop(delta)

	if hands_busy():
		if should_eat_from_hands():
			start_eat_hands()
			return
		if should_deliver():
			host._go_to_nearest_storage()
			return
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			if should_deliver():
				host._go_to_nearest_storage()
		return

	# empty hands
	if should_eat_from_storage():
		go_eat_from_storage()
		return

	if should_go_harvest():
		try_work_or_wander_harvest(host.target_harvest)
		return

	var tm = _tm()
	if tm and tm.has_tasks():
		var cur_task = tm.get_current_task()
		if cur_task:
			match cur_task.type:
				TaskManager.TaskType.GATHER:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						host.target_harvest = cur_task.target_node
						if should_eat_from_storage():
							go_eat_from_storage()
							return
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
				TaskManager.TaskType.EAT:
					if has_edible_cargo():
						host.start_eating()
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

	# poll harvest / full storage meal
	if knows_harvest() or storage_is_full():
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			if hands_busy():
				return
			if should_eat_from_storage():
				go_eat_from_storage()
				return
			if knows_harvest():
				try_work_or_wander_harvest(host.target_harvest)
