# ==============================================================================
# ФАЙЛ: src/characters/CharacterDecision.gd
# ОБНОВЛЕНО: 2026-10-03 21:16 CEST — resolve_after_drop
# НАЗНАЧЕНИЕ: Решения что делать (есть / сдать / собирать / ждать).
#            Не двигает персонажа сам — зовёт host.start_* / host.move_*.
# ==============================================================================
class_name CharacterDecision
extends RefCounted

## Хост: CharacterBody3D со скриптом character.gd
var host: CharacterBody3D

var cargo_drop_delay: float = 30.0
var _cargo_drop_timer: float = 0.0
var want_storage_meal: bool = false
var _idle_check_timer: float = 0.0


func setup(h: CharacterBody3D) -> void:
	host = h


# --- helpers: доступ к данным хоста ---

func _data():
	return host.data if host else null


func _tm():
	return host.task_manager if host else null


func hands_busy() -> bool:
	var d = _data()
	return d != null and d.item_amount > 0


func knows_berries() -> bool:
	return host.target_berries != null and is_instance_valid(host.target_berries)


func has_edible_cargo() -> bool:
	if not hands_busy():
		return false
	var d = _data()
	var item := str(d.carried_item).strip_edges().to_lower()
	return item in ["berry", "berries", "fruit", "food", "mushroom", "fish"] or item.is_empty()


func storage_has_space(st: Node = null) -> bool:
	if st and is_instance_valid(st):
		if st.has_method("has_space"):
			return bool(st.has_space())
		if st.has_method("can_accept_work"):
			return bool(st.can_accept_work(host))
		return WorkSite.can_accept(st, host)
	var tree = host.get_tree() if host else null
	var storages = tree.get_nodes_in_group("storage") if tree else []
	for s in storages:
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
	var tree = host.get_tree() if host else null
	var storages = tree.get_nodes_in_group("storage") if tree else []
	for s in storages:
		if s and is_instance_valid(s) and storage_has_food(s):
			return true
	return false


## Склад полон (нет места под deposit)
func storage_is_full() -> bool:
	return not storage_has_space()


func find_storage_with_food() -> Node3D:
	var tree = host.get_tree() if host else null
	var storages = tree.get_nodes_in_group("storage") if tree else []
	var best: Node3D = null
	var best_d: float = INF
	for s in storages:
		var ns = s as Node3D
		if not ns or not is_instance_valid(ns):
			continue
		if not storage_has_food(ns):
			continue
		var d = host.global_position.distance_to(ns.global_position)
		if d < best_d:
			best_d = d
			best = ns
	return best


## G: full + energy==100 + hunger==0 → бездействует с грузом
func is_cargo_hold_g() -> bool:
	if not hands_busy():
		return false
	if storage_has_space():
		return false
	var d = _data()
	return d.energy >= 100.0 and d.hunger <= 0.0


## A / E / F / G
func should_eat_from_hands() -> bool:
	if not has_edible_cargo():
		return false
	if is_cargo_hold_g():
		return false
	var d = _data()
	if d.hunger >= 25.0:
		return true  # A
	if not storage_has_space():
		if d.hunger < 100.0:
			return true  # E
		if d.energy < 100.0:
			return true  # F
	return false


## B: hunger < 25 + склад не full + руки заняты → deliver
func should_deliver() -> bool:
	if not hands_busy():
		return false
	var d = _data()
	if d.hunger >= 25.0:
		return false
	return storage_has_space()


## C: руки пусты + hunger > 25 + на складе еда.
## Если склад full — приоритет выше куста (разгрузка через жор со склада).
func should_eat_from_storage() -> bool:
	if hands_busy() or not _data():
		return false
	if _data().hunger <= 25.0:
		return false
	return storage_has_food()


## D: руки пусты + hunger > 25 + склад пуст (0 еды) + знает куст.
## Full склад с едой → НЕ на куст (только eat storage).
func should_go_forage() -> bool:
	if hands_busy() or not _data():
		return false
	if _data().hunger <= 25.0:
		return false
	# есть еда на складе (в т.ч. full) — жрём со склада, не с куста
	if storage_has_food():
		return false
	# full без еды — странно, но на куст тоже не рвёмся пока full
	if storage_is_full():
		return false
	return knows_berries()


func start_eat_hands() -> void:
	_cargo_drop_timer = 0.0
	want_storage_meal = false
	host._is_unloading_at_storage = false
	var tm = _tm()
	if tm:
		tm.push_subtask(TaskManager.Task.new(TaskManager.TaskType.EAT, Vector3.ZERO, null, 90))
	host.start_eating()


## Решение при грузе в руках (после сбора / idle / full storage)
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
	# G или ждать
	host._is_unloading_at_storage = false
	host.current_state = host.State.IDLE


## Дроп груза (G простоял cargo_drop_delay)
func tick_cargo_drop(delta: float) -> void:
	if not is_cargo_hold_g():
		_cargo_drop_timer = 0.0
		return
	_cargo_drop_timer += delta
	if _cargo_drop_timer >= cargo_drop_delay:
		_cargo_drop_timer = 0.0
		var d = _data()
		print("[Character] %s dropped cargo after %.0fs hold (storage full, hunger=0 energy=100)" % [
			d.character_name if d else "?", cargo_drop_delay
		])
		d.carried_item = ""
		d.item_amount = 0
		var tm = _tm()
		if tm and tm.has_tasks():
			var cur = tm.get_current_task()
			if cur and cur.type == TaskManager.TaskType.DELIVER:
				tm.complete_current_task()


func withdraw_one_and_eat(st: Node) -> bool:
	var d = _data()
	if not d or not st or not is_instance_valid(st):
		return false
	if not st.has_method("withdraw_food"):
		return false
	var got: int = int(st.withdraw_food(1))
	if got <= 0:
		return false
	d.carried_item = "berry"
	d.item_amount = got
	print("[Character] %s took food from storage (-%d)" % [d.character_name, got])
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
	var pos_xz = Vector2(host.global_position.x, host.global_position.z)
	var target_xz = Vector2(host._current_target_pos.x, host._current_target_pos.z)
	if pos_xz.distance_to(target_xz) <= host.arrival_distance:
		withdraw_one_and_eat(st)
	else:
		host.current_state = host.State.MOVING
		if host.nav_agent:
			host.nav_agent.target_position = host._current_target_pos


## full storage + cargo: решаем по матрице
func handle_full_storage_with_cargo() -> bool:
	if not hands_busy():
		return false
	if storage_has_space():
		return false
	resolve_cargo_action()
	return true


# --- DROP: после think — одно решение ---

func site_has_work(site: Node3D) -> bool:
	if not site or not is_instance_valid(site):
		return false
	var cat := WorkSite.get_category(site)
	match cat:
		"deposit":
			return hands_busy() and storage_has_space(site)
		"harvest":
			return (not hands_busy()) and WorkSite.can_accept(site, host)
		"clear":
			return WorkSite.can_accept(site, host)
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
		var raw = str(ConfigLoader.get_skill_value("talents_skills", talent, ""))
		raw = raw.replace('"', "").replace("'", "")
		for part in raw.split(","):
			if part.strip_edges().to_lower() == skill:
				return true
	return false


func resolve_after_drop(drop_site: Node3D = null) -> void:
	var d = _data()
	var tm = _tm()

	if should_eat_from_hands():
		start_eat_hands()
		return

	if hands_busy():
		if drop_site and is_instance_valid(drop_site) and WorkSite.get_category(drop_site) == "deposit":
			if storage_has_space(drop_site):
				host.start_delivering_to_storage(drop_site)
				return
			handle_full_storage_with_cargo()
			return
		resolve_cargo_action()
		return

	if should_eat_from_storage():
		go_eat_from_storage()
		return

	if tm and tm.has_tasks():
		var cur = tm.get_current_task()
		if cur:
			match cur.type:
				TaskManager.TaskType.GATHER:
					if cur.target_node and is_instance_valid(cur.target_node) and site_has_work(cur.target_node):
						host.start_gathering_at_berries(cur.target_node)
						return
				TaskManager.TaskType.DELIVER:
					if hands_busy() and cur.target_node and is_instance_valid(cur.target_node) and storage_has_space(cur.target_node):
						host.start_delivering_to_storage(cur.target_node)
						return
				TaskManager.TaskType.CLEAR:
					if cur.target_node and is_instance_valid(cur.target_node) and site_has_work(cur.target_node):
						host.start_clearing_obstacle(cur.target_node)
						return
				TaskManager.TaskType.EAT:
					if has_edible_cargo():
						host.start_eating()
						return
					tm.complete_current_task()
				_:
					pass

	if drop_site and is_instance_valid(drop_site):
		if site_has_work(drop_site) and has_talent_for_site(drop_site):
			host.start_work_at(drop_site)
			return
		if site_has_work(drop_site) and not has_talent_for_site(drop_site):
			host.wander_nearby()
			return
		host.current_state = host.State.IDLE
		return

	if knows_berries() and site_has_work(host.target_berries):
		host.start_work_at(host.target_berries)
		return
	if should_go_forage() and knows_berries():
		host.start_work_at(host.target_berries)
		return

	if d and d.hunger <= 25.0:
		host.wander_nearby()
	else:
		host.current_state = host.State.IDLE


# --- IDLE: матрица + TaskManager + poll куста ---

func process_idle(delta: float) -> void:
	tick_cargo_drop(delta)

	# --- Матрица: руки заняты ---
	if hands_busy():
		if should_eat_from_hands():
			start_eat_hands()
			return
		if should_deliver():
			host._go_to_nearest_storage()
			return
		# G / full wait
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			if should_deliver():
				host._go_to_nearest_storage()
		return

	# --- Руки пусты ---
	# Full + hunger > 25 → обязательно на склад поесть (склад должен пустеть)
	if storage_is_full() and _data() and _data().hunger > 25.0 and storage_has_food():
		go_eat_from_storage()
		return

	if should_eat_from_storage():
		go_eat_from_storage()
		return

	if should_go_forage():
		if WorkSite.can_accept(host.target_berries, host):
			host.start_work_at(host.target_berries)
			return

	var tm = _tm()
	var d = _data()
	if tm and tm.has_tasks():
		var cur_task = tm.get_current_task()
		if cur_task:
			match cur_task.type:
				TaskManager.TaskType.GATHER:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						host.target_berries = cur_task.target_node
						# Full: не ходим на куст. hunger>25 → жрём со склада.
						if storage_is_full():
							if d and d.hunger > 25.0 and storage_has_food():
								go_eat_from_storage()
							return
						if d and d.hunger > 25.0 and storage_has_food():
							# голодны и есть еда на складе — сначала склад, не куст
							go_eat_from_storage()
							return
						if WorkSite.can_accept(cur_task.target_node, host):
							host.start_gathering_at_berries(cur_task.target_node)
						return
				TaskManager.TaskType.DELIVER:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						if hands_busy() and WorkSite.can_accept(cur_task.target_node, host):
							host.start_delivering_to_storage(cur_task.target_node)
						elif hands_busy() and not WorkSite.can_accept(cur_task.target_node, host):
							handle_full_storage_with_cargo()
						elif not hands_busy():
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

	# Poll: куст созрел / full → склад
	if knows_berries() or storage_is_full():
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			if d and d.item_amount > 0:
				return
			# Full + hunger > 25 → склад (даже без knows_berries)
			if storage_is_full() and d and d.hunger > 25.0 and storage_has_food():
				go_eat_from_storage()
				return
			if not knows_berries():
				return
			# куст только если склад НЕ full и нет еды / есть место под сдачу
			if d and d.hunger > 25.0 and not storage_has_food():
				if WorkSite.can_accept(host.target_berries, host):
					host.start_work_at(host.target_berries)
				return
			if d and d.hunger <= 25.0 and storage_has_space():
				if WorkSite.can_accept(host.target_berries, host):
					print("[Character] %s: work site ready, resuming..." % d.character_name)
					host.start_work_at(host.target_berries)
