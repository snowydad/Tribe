# ==============================================================================
# ОБНОВЛЕНО: 2026-10-06 22:15 — drop v2: cargo → deliver first (не gather)
# ФАЙЛ: src/characters/CharacterDecision.gd
# ОБНОВЛЕНО: 2026-10-04 15:11 CEST — edible via items.ini
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


func knows_harvest() -> bool:
	return host.target_harvest != null and is_instance_valid(host.target_harvest)


## Готов → harvest; не готов → wander (loop: погулял → idle → снова check)
func try_work_or_wander_harvest(site: Node3D = null) -> bool:
	var s: Node3D = site if site else (host.target_harvest if host else null)
	if s == null or not is_instance_valid(s):
		return false
	if WorkSite.can_accept(s, host):
		host.start_harvesting(s)
		return true
	host.wander_nearby(10.0, 15.0)
	return true



func has_edible_cargo() -> bool:
	if not hands_busy():
		return false
	var d = _data()
	var item := str(d.carried_item)
	# edible: только items.ini / ConfigLoader
	if ConfigLoader and ConfigLoader.has_method("is_item_edible"):
		return bool(ConfigLoader.is_item_edible(item, false))
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		return float(ConfigLoader.get_item_nutrition(item, 0.0)) > 0.0
	return false



func storage_has_space(st: Node = null) -> bool:
	# site: has_space() на объекте. Мир: обход group — место знает storage.has_space()
	if st and is_instance_valid(st):
		if st.has_method("has_space"):
			return bool(st.has_space())
		if st.has_method("can_accept_work"):
			return bool(st.can_accept_work(host))
		return WorkSite.can_accept(st, host)
	var tree = host.get_tree() if host else null
	if tree == null:
		return false
	for s in tree.get_nodes_in_group("storage"):
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
	if tree == null:
		return false
	for s in tree.get_nodes_in_group("storage"):
		if s and is_instance_valid(s) and storage_has_food(s):
			return true
	return false


## Склад полон (нет места под deposit)
func storage_is_full() -> bool:
	# есть ≥1 склад и ни у одного нет места
	var tree = host.get_tree() if host else null
	if tree == null:
		return false
	var found := false
	for s in tree.get_nodes_in_group("storage"):
		if s == null or not is_instance_valid(s):
			continue
		found = true
		if storage_has_space(s):
			return false
	return found


func find_storage_with_food() -> Node3D:
	var tree = host.get_tree() if host else null
	if tree == null:
		return null
	var best: Node3D = null
	var best_d: float = INF
	for s in tree.get_nodes_in_group("storage"):
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



func  is_cargo_hold_g() -> bool:
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
## Если deposit full — приоритет eat storage, не harvest.
func should_eat_from_storage() -> bool:
	if hands_busy() or not _data():
		return false
	if _data().hunger <= 25.0:
		return false
	return storage_has_food()


## D: руки пусты + hunger > 25 + нет еды на deposit + знает harvest-site.
## Full deposit + food → eat storage, not harvest site.
func should_go_harvest() -> bool:
	if hands_busy() or not _data():
		return false
	if _data().hunger <= 25.0:
		return false
	# есть еда на deposit (в т.ч. full) — eat storage, не harvest
	if storage_has_food():
		return false
	# full без еды — harvest тоже не начинаем пока full
	if storage_is_full():
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
	d.carried_item = "food"  # тип еды со склада; later item table
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
	# keep WP if already near this storage
	var keep: Vector3 = host._current_target_pos
	var near_st: bool = host.global_position.distance_to(st.global_position) <= maxf(host.docking_distance * 1.5, 2.5)
	var d_wp: float = Vector2(host.global_position.x, host.global_position.z).distance_to(Vector2(keep.x, keep.z))
	if near_st and d_wp <= maxf(host.arrival_distance, 0.5) * 2.0:
		host._current_target_pos = keep
	else:
		host._current_target_pos = host._get_free_work_point_safe(st)
	# soft arrive: у WP или рядом со складом → есть
	var arrive_lim: float = maxf(host.arrival_distance, 0.5) * 2.0
	var pos_xz = Vector2(host.global_position.x, host.global_position.z)
	var target_xz = Vector2(host._current_target_pos.x, host._current_target_pos.z)
	if pos_xz.distance_to(target_xz) <= arrive_lim or near_st:
		withdraw_one_and_eat(st)
	else:
		host.move_intent = "eat"
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

func remembers_site(site: Node3D) -> bool:
	if not site or not is_instance_valid(site) or not host:
		return false
	if host.target_harvest != null and is_instance_valid(host.target_harvest) and host.target_harvest == site:
		return true
	if host.target_storage != null and is_instance_valid(host.target_storage) and host.target_storage == site:
		return true
	return false


func remember_site(site: Node3D) -> void:
	if not site or not is_instance_valid(site) or not host:
		return
	var cat := WorkSite.get_category(site)
	if cat == "deposit":
		host.target_storage = site
	else:
		# harvest / other
		host.target_harvest = site
	print("[Decision] remember site %s (%s)" % [site.name, cat])


## eat* после drop: с рук, если hunger > порог (ini / 25)
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
	if d.hunger <= thr:
		return false
	if not has_edible_cargo():
		return false
	start_eat_hands()
	return true




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
	# Drop v2 после think:
	# 0) есть cargo → сдать (склад), НЕ идти собирать
	# 1) task queue → work @ task (GATHER только без cargo)
	# 2) object: talent/memory/wander
	# 3) blank: wander
	var tm = _tm()

	# --- 0) груз в руках: продолжить доставку ---
	if hands_busy():
		# drop прямо на deposit → сдать сюда
		if drop_site and is_instance_valid(drop_site) and WorkSite.get_category(drop_site) == "deposit":
			host.start_delivering_to_storage(drop_site)
			return
		# DELIVER в очереди
		if tm and tm.has_tasks():
			var cur = tm.get_current_task()
			if cur and cur.type == TaskManager.TaskType.DELIVER and cur.target_node and is_instance_valid(cur.target_node):
				host.start_delivering_to_storage(cur.target_node)
				return
		# память склада
		if host.target_storage and is_instance_valid(host.target_storage):
			host.start_delivering_to_storage(host.target_storage)
			return
		# любой ближайший склад
		host._go_to_nearest_storage()
		return

	# --- 1) задача в очереди (рук пусты) ---
	if tm and tm.has_tasks():
		var cur = tm.get_current_task()
		if cur:
			match cur.type:
				TaskManager.TaskType.GATHER:
					if cur.target_node and is_instance_valid(cur.target_node):
						try_work_or_wander_harvest(cur.target_node)
						return
				TaskManager.TaskType.DELIVER:
					# без груза deliver бессмысленен
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
				TaskManager.TaskType.BUILD:
					if cur.target_node and is_instance_valid(cur.target_node):
						host.go_work(cur.target_node)
						return
				_:
					if cur.target_node and is_instance_valid(cur.target_node):
						host.go_work(cur.target_node)
						return

	# --- 2) drop на object ---
	if drop_site and is_instance_valid(drop_site):
		if has_talent_for_site(drop_site):
			host.start_work_at(drop_site)
			return
		if remembers_site(drop_site):
			host.start_work_at(drop_site)
			return
		remember_site(drop_site)
		host.wander_nearby(10.0, 15.0)
		drop_eat_if_hungry()
		return

	# --- 3) blank ---
	host.wander_nearby(10.0, 15.0)
	drop_eat_if_hungry()



# --- IDLE: матрица + TaskManager + poll harvest ---

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

	if should_go_harvest():
		try_work_or_wander_harvest(host.target_harvest)
		return

	var tm = _tm()
	var d = _data()
	if tm and tm.has_tasks():
		var cur_task = tm.get_current_task()
		if cur_task:
			match cur_task.type:
				TaskManager.TaskType.GATHER:
					if cur_task.target_node and is_instance_valid(cur_task.target_node):
						host.target_harvest = cur_task.target_node
						if storage_is_full():
							if d and d.hunger > 25.0 and storage_has_food():
								go_eat_from_storage()
								return
						if d and d.hunger > 25.0 and storage_has_food():
							go_eat_from_storage()
							return
						try_work_or_wander_harvest(cur_task.target_node)
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

	# Poll: harvest ready / full → storage
	if knows_harvest() or storage_is_full():
		_idle_check_timer += delta
		if _idle_check_timer >= 0.5:
			_idle_check_timer = 0.0
			if d and d.item_amount > 0:
				return
			# Full + hunger > 25 → склад (даже без knows_harvest)
			if storage_is_full() and d and d.hunger > 25.0 and storage_has_food():
				go_eat_from_storage()
				return
			if not knows_harvest():
				return
			# site не готов → wander; готов → work
			try_work_or_wander_harvest(host.target_harvest)
			return
