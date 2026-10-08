# ==============================================================================
# storage.gd — склад как WorkSite (данные из storage.ini)
# ОБНОВЛЕНО: 2026-10-08 — WP: nearest free Marker3D (no sticky occupied)
# ==============================================================================
extends Node3D
class_name StorageSite

@export var stored_food: int = 0
@export var max_storage: int = 500

@export_group("Work Points")
@export var procedural_radius: float = 2.0
@export var procedural_slots_count: int = 8

var work_time: float = 1.0
var skill: String = "trader"
var work_type: String = "delivering"

@onready var work_points_container: Node3D = $WorkPoints
@onready var dev_label: Label3D = get_node_or_null("DevLabel")

var _occupied_slots: Dictionary = {}

func _ready() -> void:
	add_to_group("storage")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)

	if ConfigLoader:
		work_time = float(ConfigLoader.get_config_value("storage", "work", "base_work_time", 1.0))
		skill = str(ConfigLoader.get_config_value("storage", "work", "skill", "trader"))
		work_type = str(ConfigLoader.get_config_value("storage", "work", "work_type", "delivering"))
		max_storage = int(ConfigLoader.get_config_value("storage", "capacity", "max_storage", 500))
		print("[Storage] Config loaded: work_time=%.1fs, max_storage=%d, skill=%s" % [work_time, max_storage, skill])

	_update_dev_ui()


## Ближайший склад к from (группа storage). Знает склад, не character.
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
	return work_time

func has_space() -> bool:
	return max_storage <= 0 or stored_food < max_storage

func has_food() -> bool:
	return stored_food > 0

## Снять еду со склада (для поедания персом). Возвращает сколько реально сняли.
func withdraw_food(amount: int = 1) -> int:
	if amount <= 0 or stored_food <= 0:
		return 0
	var take: int = mini(amount, stored_food)
	stored_food -= take
	print("[Storage] Food withdrawn: -%d | Total: %d/%d" % [take, stored_food, max_storage])
	_update_dev_ui()
	return take

func deposit_food(amount: int) -> void:
	var prev_food = stored_food
	if max_storage > 0:
		stored_food = min(stored_food + amount, max_storage)
	else:
		stored_food += amount
	var actual_deposited = stored_food - prev_food
	print("[Storage] Food deposited: +%d | Total stored food: %d/%d" % [actual_deposited, stored_food, max_storage])
	_update_dev_ui()

# --- WorkSite contract ---
func can_accept_work(worker: Node = null) -> bool:
	if not has_space():
		return false
	if worker == null:
		return true
	if "data" in worker and worker.data:
		return worker.data.item_amount > 0
	return true

func get_work_skill() -> String:
	return skill

func get_work_type() -> String:
	return work_type

func do_work(worker: Node = null) -> Dictionary:
	if worker == null or not ("data" in worker) or worker.data == null:
		return {"ok": false, "reason": "no_worker"}
	if worker.data.item_amount <= 0:
		return {"ok": false, "reason": "empty_hands"}
	if not has_space():
		return {"ok": false, "reason": "full"}

	var amount: int = worker.data.item_amount
	var item: String = worker.data.carried_item if worker.data.carried_item != "" else "resource"
	deposit_food(amount)
	worker.data.carried_item = ""
	worker.data.item_amount = 0
	return {
		"ok": true,
		"take": {"item": item, "amount": amount},
		"xp_skill": skill,
	}

## Только Marker3D (не Dev и не прочий мусор в WorkPoints)
func _work_markers() -> Array:
	var out: Array = []
	if work_points_container == null:
		return out
	for c in work_points_container.get_children():
		if c is Marker3D:
			out.append(c)
	return out


## Ближайшая СВОБОДНАЯ WP к requester (не липнем к занятой)
func get_free_work_point(requester: Node3D = null) -> Vector3:
	_cleanup_slots()
	var markers: Array = _work_markers()
	var requester_id: int = requester.get_instance_id() if requester else 0
	var from_pos: Vector3 = requester.global_position if requester != null and is_instance_valid(requester) else global_position

	# слоты, занятые другими персами
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

	# все Marker заняты — procedural снаружи
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
	dev_label.text = "Storage Food: %d/%d\nWork: %.1fs (%s)" % [stored_food, max_storage, work_time, skill]
