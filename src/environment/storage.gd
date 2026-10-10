# ==============================================================================
# storage.gd — склад WorkSite: deposit / withdraw, сытость, WP = Marker3D
# ОБНОВЛЕНО: 2026-10-09 — cleanup
# ==============================================================================
extends Node3D
class_name StorageSite

## Сытость на складе (не штуки предметов)
@export var stored_food: int = 0
@export var max_storage: int = 500

var active_work_id: String = "deposit"
var meal_portion: float = 25.0
## work_id -> { skill, work_type, work_anim, base_work_time }
var _works: Dictionary = {}
var _occupied_slots: Dictionary = {}

@onready var work_points_container: Node3D = $WorkPoints
@onready var dev_label: Label3D = get_node_or_null("DevLabel")


func _ready() -> void:
	add_to_group("storage")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_load_from_config()
	_update_dev_ui()


func _load_from_config() -> void:
	_works.clear()
	if not ConfigLoader:
		_works["deposit"] = _default_work("trader", "delivering", "deposit", 1.0)
		_works["withdraw"] = _default_work("trader", "withdraw", "withdraw", 1.0)
		return

	_load_work("deposit", "work_deposit")
	_load_work("withdraw", "work_withdraw")
	if _works.is_empty():
		_load_work("deposit", "work")

	max_storage = int(ConfigLoader.get_config_value("storage", "capacity", "max_storage", max_storage))
	meal_portion = float(ConfigLoader.get_config_value("storage", "meal", "portion_satiety", meal_portion))


func _default_work(skill: String, wtype: String, anim: String, t: float) -> Dictionary:
	return {"skill": skill, "work_type": wtype, "work_anim": anim, "base_work_time": t}


func _load_work(work_id: String, section: String) -> void:
	if ConfigLoader.get_config_value("storage", section, "skill", null) == null \
			and ConfigLoader.get_config_value("storage", section, "work_type", null) == null:
		return
	_works[work_id] = {
		"skill": str(ConfigLoader.get_config_value("storage", section, "skill", "trader")),
		"work_type": str(ConfigLoader.get_config_value("storage", section, "work_type", work_id)),
		"work_anim": str(ConfigLoader.get_config_value("storage", section, "work_anim", work_id)),
		"base_work_time": float(ConfigLoader.get_config_value("storage", section, "base_work_time", 1.0)),
	}


func set_active_work(work_id: String) -> void:
	if _works.has(work_id) or work_id == "deposit" or work_id == "withdraw":
		active_work_id = work_id


func _wf(key: String, fallback: Variant) -> Variant:
	if _works.has(active_work_id):
		return _works[active_work_id].get(key, fallback)
	return fallback


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
	return float(_wf("base_work_time", 1.0))


func get_work_skill() -> String:
	return str(_wf("skill", "trader"))


func get_work_type() -> String:
	return str(_wf("work_type", "delivering"))


func get_work_anim() -> String:
	return str(_wf("work_anim", "work"))


func has_space() -> bool:
	return max_storage <= 0 or stored_food < max_storage


func has_food() -> bool:
	return stored_food > 0


func get_meal_portion() -> int:
	return maxi(int(round(meal_portion)), 1)


func _satiety_for_item(item_id: String, amount: int) -> int:
	var nut: float = 25.0
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		nut = float(ConfigLoader.get_item_nutrition(item_id, 25.0))
	return int(round(nut * float(maxi(amount, 0))))


func withdraw_food(amount: int = 1) -> int:
	if amount <= 0 or stored_food <= 0:
		return 0
	var take: int = mini(amount, stored_food)
	stored_food -= take
	_update_dev_ui()
	return take


func deposit_food(amount: int) -> int:
	if amount <= 0:
		return 0
	var prev: int = stored_food
	if max_storage > 0:
		stored_food = mini(stored_food + amount, max_storage)
	else:
		stored_food += amount
	var actual: int = stored_food - prev
	_update_dev_ui()
	return actual


# --- WorkSite ---
func can_accept_work(worker: Node = null) -> bool:
	if active_work_id == "withdraw":
		if not has_food():
			return false
		if worker != null and "data" in worker and worker.data:
			return worker.data.item_amount <= 0
		return true
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
	var got: int = withdraw_food(get_meal_portion())
	if got <= 0:
		return {"ok": false, "reason": "empty"}
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


# --- WP: только Marker3D, ближайшая свободная ---
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
	var req_id: int = requester.get_instance_id() if requester else 0
	var from: Vector3 = requester.global_position if requester and is_instance_valid(requester) else global_position

	var used: Dictionary = {}
	for rid in _occupied_slots.keys():
		if int(rid) != req_id:
			used[int(_occupied_slots[rid])] = true

	var best_i: int = -1
	var best_d: float = INF
	for i in range(markers.size()):
		if used.has(i):
			continue
		var m: Node3D = markers[i] as Node3D
		if m == null:
			continue
		var d: float = from.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best_i = i

	if best_i >= 0:
		if req_id != 0:
			_occupied_slots[req_id] = best_i
		return (markers[best_i] as Node3D).global_position

	# нет свободных Marker — центр (лучше не доходить сюда)
	return global_position


func release_work_point(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_occupied_slots.erase(requester.get_instance_id())


func _cleanup_slots() -> void:
	var dead: Array = []
	for req_id in _occupied_slots.keys():
		var obj = instance_from_id(req_id)
		if not obj or not is_instance_valid(obj):
			dead.append(req_id)
	for req_id in dead:
		_occupied_slots.erase(req_id)


func _update_dev_ui() -> void:
	if not dev_label:
		return
	dev_label.text = "Satiety: %d/%d\n%s" % [stored_food, max_storage, active_work_id]
