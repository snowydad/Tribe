# ==============================================================================
# storage.gd — склад как WorkSite (несколько work_* из storage.ini)
# ОБНОВЛЕНО: 2026-10-09 — deposit/withdraw; склад хранит сытость; nearest free WP
# ==============================================================================
extends Node3D
class_name StorageSite

## Единицы сытости на складе (не штуки berry/mushroom)
@export var stored_food: int = 0
@export var max_storage: int = 500

@export_group("Work Points")
@export var procedural_radius: float = 2.0
@export var procedural_slots_count: int = 8

## Активная работа: "deposit" | "withdraw" (и позже upgrade/demolish)
var active_work_id: String = "deposit"

## work_id -> { skill, work_type, work_anim, base_work_time }
var _works: Dictionary = {}

var meal_portion: float = 25.0

@onready var work_points_container: Node3D = $WorkPoints
@onready var dev_label: Label3D = get_node_or_null("DevLabel")

var _occupied_slots: Dictionary = {}


func _ready() -> void:
	add_to_group("storage")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_load_from_config()
	_update_dev_ui()


func _load_from_config() -> void:
	_works.clear()
	if not ConfigLoader:
		_works["deposit"] = {
			"skill": "trader", "work_type": "delivering",
			"work_anim": "deposit", "base_work_time": 1.0
		}
		_works["withdraw"] = {
			"skill": "trader", "work_type": "withdraw",
			"work_anim": "withdraw", "base_work_time": 1.0
		}
		return

	_load_work_section("deposit", "work_deposit")
	_load_work_section("withdraw", "work_withdraw")
	# legacy [work] — если новых секций нет
	if _works.is_empty():
		_load_work_section("deposit", "work")

	max_storage = int(ConfigLoader.get_config_value("storage", "capacity", "max_storage", max_storage))
	meal_portion = float(ConfigLoader.get_config_value("storage", "meal", "portion_satiety", meal_portion))

	print("[Storage] works=%s max=%d meal_portion=%.0f" % [str(_works.keys()), max_storage, meal_portion])


func _load_work_section(work_id: String, section: String) -> void:
	if not ConfigLoader:
		return
	# секция есть, если есть skill или work_type
	var skill_v = ConfigLoader.get_config_value("storage", section, "skill", null)
	var type_v = ConfigLoader.get_config_value("storage", section, "work_type", null)
	if skill_v == null and type_v == null:
		return
	_works[work_id] = {
		"skill": str(ConfigLoader.get_config_value("storage", section, "skill", "trader")),
		"work_type": str(ConfigLoader.get_config_value("storage", section, "work_type", work_id)),
		"work_anim": str(ConfigLoader.get_config_value("storage", section, "work_anim", work_id)),
		"base_work_time": float(ConfigLoader.get_config_value("storage", section, "base_work_time", 1.0)),
	}


func set_active_work(work_id: String) -> void:
	if _works.has(work_id):
		active_work_id = work_id
	elif work_id == "deposit" or work_id == "withdraw":
		active_work_id = work_id


func _work_field(key: String, fallback: Variant) -> Variant:
	if _works.has(active_work_id):
		return _works[active_work_id].get(key, fallback)
	return fallback


## Ближайший склад
static func find_nearest(from: Node3D) -> Node3D:
	if from == null or not is_instance_valid(from) or from.get_tree() == null:
		return null
	var best: Node3D = null
	var best_d: float = INF
	for n in from.get_tree().get_nodes_in_group("storage"):
		var s := n as Node3D
		if s == null or not is_instance_valid(s):
			continue
		var d: float = from.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func get_work_time() -> float:
	return float(_work_field("base_work_time", 1.0))


func get_work_skill() -> String:
	return str(_work_field("skill", "trader"))


func get_work_type() -> String:
	return str(_work_field("work_type", "delivering"))


func get_work_anim() -> String:
	return str(_work_field("work_anim", "work"))


func has_space() -> bool:
	return max_storage <= 0 or stored_food < max_storage


func has_food() -> bool:
	return stored_food > 0


func space_left() -> int:
	if max_storage <= 0:
		return 999999
	return maxi(max_storage - stored_food, 0)


## nutrition 1 шт предмета → сытость (items.ini)
func _satiety_for_item(item_id: String, amount: int) -> int:
	var nut: float = 25.0
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		nut = float(ConfigLoader.get_item_nutrition(item_id, 25.0))
	return int(round(nut * float(maxi(amount, 0))))


## Снять сытость (для еды). amount — единицы сытости.
func withdraw_food(amount: int = 1) -> int:
	if amount <= 0 or stored_food <= 0:
		return 0
	var take: int = mini(amount, stored_food)
	stored_food -= take
	print("[Storage] Withdraw satiety -%d | Total: %d/%d" % [take, stored_food, max_storage])
	_update_dev_ui()
	return take


## Положить сытость (уже посчитанную)
func deposit_food(amount: int) -> int:
	if amount <= 0:
		return 0
	var prev: int = stored_food
	if max_storage > 0:
		stored_food = mini(stored_food + amount, max_storage)
	else:
		stored_food += amount
	var actual: int = stored_food - prev
	print("[Storage] Deposit satiety +%d | Total: %d/%d" % [actual, stored_food, max_storage])
	_update_dev_ui()
	return actual


## Порция для meal (ini [meal] portion_satiety)
func get_meal_portion() -> int:
	return maxi(int(round(meal_portion)), 1)


# --- WorkSite contract ---
func can_accept_work(worker: Node = null) -> bool:
	if active_work_id == "withdraw":
		if not has_food():
			return false
		if worker != null and "data" in worker and worker.data:
			return worker.data.item_amount <= 0
		return true
	# deposit (default)
	if not has_space():
		return false
	if worker == null:
		return true
	if "data" in worker and worker.data:
		return worker.data.item_amount > 0
	return true


func do_work(worker: Node = null) -> Dictionary:
	if worker == null or not ("data" in worker) or worker.data == null:
		return {"ok": false, "reason": "no_worker"}

	if active_work_id == "withdraw":
		return _do_withdraw(worker)

	return _do_deposit(worker)


func _do_deposit(worker: Node) -> Dictionary:
	if worker.data.item_amount <= 0:
		return {"ok": false, "reason": "empty_hands"}
	if not has_space():
		return {"ok": false, "reason": "full"}

	var amount: int = worker.data.item_amount
	var item: String = worker.data.carried_item if worker.data.carried_item != "" else "resource"
	var satiety: int = _satiety_for_item(item, amount)
	if satiety <= 0:
		satiety = amount
	var put: int = deposit_food(satiety)
	worker.data.carried_item = ""
	worker.data.item_amount = 0
	return {
		"ok": true,
		"take": {"item": item, "amount": amount, "satiety": put},
		"xp_skill": get_work_skill(),
		"work_type": get_work_type(),
		"work_anim": get_work_anim(),
	}


func _do_withdraw(worker: Node) -> Dictionary:
	if worker.data.item_amount > 0:
		return {"ok": false, "reason": "hands_full"}
	if not has_food():
		return {"ok": false, "reason": "empty"}
	var portion: int = get_meal_portion()
	var got: int = withdraw_food(portion)
	if got <= 0:
		return {"ok": false, "reason": "empty"}
	# одна «порция еды» на руках; nutrition при eat — из items / got
	worker.data.carried_item = "food"
	worker.data.item_amount = 1
	return {
		"ok": true,
		"give": {"item": "food", "amount": 1, "satiety": got},
		"xp_skill": get_work_skill(),
		"work_type": get_work_type(),
		"work_anim": get_work_anim(),
		"nutrition": float(got),
	}


# --- WP ---
func _work_markers() -> Array:
	var out: Array = []
	if work_points_container == null:
		work_points_container = get_node_or_null("WorkPoints") as Node3D
	if work_points_container == null:
		return out
	for c in work_points_container.get_children():
		if c is Marker3D:
			out.append(c)
	return out


func get_free_work_point(requester: Node3D = null) -> Vector3:
	_cleanup_slots()
	var markers: Array = _work_markers()
	var requester_id: int = requester.get_instance_id() if requester else 0
	var from_pos: Vector3 = requester.global_position if requester != null and is_instance_valid(requester) else global_position

	var used_by_others: Dictionary = {}
	for rid in _occupied_slots.keys():
		if int(rid) == requester_id:
			continue
		used_by_others[int(_occupied_slots[rid])] = true

	var best_i: int = -1
	var best_d: float = INF
	for i in range(markers.size()):
		if used_by_others.has(i):
			continue
		var m: Node3D = markers[i] as Node3D
		if m == null:
			continue
		var d: float = from_pos.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best_i = i

	if best_i >= 0:
		if requester_id != 0:
			_occupied_slots[requester_id] = best_i
		return (markers[best_i] as Node3D).global_position

	var slot_index: int = _find_first_free_slot()
	if requester_id != 0:
		_occupied_slots[requester_id] = slot_index
	var angle: float = float(slot_index) * (TAU / float(max(1, procedural_slots_count)))
	var offset := Vector3(cos(angle) * procedural_radius, 0.0, sin(angle) * procedural_radius)
	return global_position + offset


func release_work_point(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_occupied_slots.erase(requester.get_instance_id())


func _cleanup_slots() -> void:
	var to_remove: Array = []
	for req_id in _occupied_slots.keys():
		var obj = instance_from_id(req_id)
		if not obj or not is_instance_valid(obj):
			to_remove.append(req_id)
	for req_id in to_remove:
		_occupied_slots.erase(req_id)


func _find_first_free_slot() -> int:
	var used_slots = _occupied_slots.values()
	var candidate: int = 0
	while candidate in used_slots:
		candidate += 1
	return candidate


func _update_dev_ui() -> void:
	if not dev_label:
		return
	dev_label.text = "Satiety: %d/%d\nActive: %s\n%s / %s" % [
		stored_food, max_storage, active_work_id, get_work_type(), get_work_anim()
	]
