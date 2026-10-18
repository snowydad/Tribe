# ==============================================================================
# shelter.gd — шалаш (базовое жильё). v1: уже «известен», без крафта.
# Слоты сна (SleepPoints) + WorkPoints. Стройка — задел на потом.
# ОБНОВЛЕНО: 2026-10-17
# ==============================================================================
extends Node3D
class_name ShelterSite

@export var bed_capacity: int = 4
@export var wood_required: int = 5
@export var work_time: float = 5.0
@export var work_type: String = "building"
@export var skill: String = "builder"
@export var work_anim: String = "build"
## v1: базовое знание — сразу пригоден для сна
@export var is_built: bool = true

var _bed_slots: Dictionary = {}  # requester_id -> bed index
var _work_slots: Dictionary = {}

@onready var sleep_points: Node3D = get_node_or_null("SleepPoints") as Node3D
@onready var work_points: Node3D = get_node_or_null("WorkPoints") as Node3D
@onready var dev_label: Label3D = get_node_or_null("DevLabel") as Label3D


func _ready() -> void:
	add_to_group("shelter")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_load_config()
	_update_dev_ui()


func _load_config() -> void:
	if not ConfigLoader:
		return
	if ConfigLoader.has_method("get_shelter_value"):
		work_time = float(ConfigLoader.get_shelter_value("work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_shelter_value("work", "work_type", work_type))
		skill = str(ConfigLoader.get_shelter_value("work", "skill", skill))
		work_anim = str(ConfigLoader.get_shelter_value("work", "work_anim", work_anim))
		wood_required = int(ConfigLoader.get_shelter_value("requirements", "wood_required", wood_required))
		bed_capacity = int(ConfigLoader.get_shelter_value("sleep", "bed_capacity", bed_capacity))
		if ConfigLoader.get_shelter_value("sleep", "starts_built", true) != null:
			is_built = bool(ConfigLoader.get_shelter_value("sleep", "starts_built", is_built))
	print("[Shelter] built=%s beds=%d wood_req=%d" % [is_built, bed_capacity, wood_required])


# --- WorkSite (стройка — задел; v1 can_accept false если built) ---
func can_accept_work(worker: Node = null) -> bool:
	# v1: уже построен — строить нечего; later: !is_built + wood
	if is_built:
		return false
	return true


func get_work_time() -> float:
	return work_time


func get_work_skill() -> String:
	return skill


func get_work_type() -> String:
	return work_type


func get_work_anim() -> String:
	return work_anim


func do_work(worker: Node) -> Dictionary:
	if is_built:
		return {"ok": false, "reason": "already_built"}
	# задел: один цикл → built (без списания wood пока)
	is_built = true
	_update_dev_ui()
	return {
		"ok": true,
		"xp_skill": skill,
		"built": true,
	}


func get_free_work_point(requester: Node3D = null) -> Vector3:
	return _claim_marker(work_points, _work_slots, requester)


func release_work_point(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_work_slots.erase(requester.get_instance_id())


# --- Сон ---
func has_free_bed() -> bool:
	if not is_built:
		return false
	_cleanup_beds()
	var markers := _markers_of(sleep_points)
	if markers.is_empty():
		# нет SleepPoints — «вместимость» виртуальная
		return _bed_slots.size() < bed_capacity
	var used: int = 0
	for v in _bed_slots.values():
		used += 1
	return used < mini(bed_capacity, markers.size())


func claim_bed(requester: Node3D) -> Vector3:
	if not is_built or requester == null:
		return global_position
	_cleanup_beds()
	var markers := _markers_of(sleep_points)
	var req_id: int = requester.get_instance_id()
	if _bed_slots.has(req_id):
		var i: int = int(_bed_slots[req_id])
		if i >= 0 and i < markers.size():
			return (markers[i] as Node3D).global_position
		return global_position + Vector3(0.5, 0, 0.5)

	if markers.is_empty():
		# виртуальный слот вокруг
		if _bed_slots.size() >= bed_capacity:
			return global_position
		var ang: float = float(_bed_slots.size()) * TAU / float(maxi(bed_capacity, 1))
		_bed_slots[req_id] = _bed_slots.size()
		return global_position + Vector3(cos(ang), 0, sin(ang)) * 1.2

	var used: Dictionary = {}
	for rid in _bed_slots.keys():
		used[int(_bed_slots[rid])] = true
	var best_i: int = -1
	var best_d: float = INF
	var from: Vector3 = requester.global_position
	for i in range(mini(markers.size(), bed_capacity)):
		if used.has(i):
			continue
		var m: Node3D = markers[i] as Node3D
		var d: float = from.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return global_position
	_bed_slots[req_id] = best_i
	return (markers[best_i] as Node3D).global_position


func release_bed(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_bed_slots.erase(requester.get_instance_id())


func is_occupant(requester: Node3D) -> bool:
	return requester != null and _bed_slots.has(requester.get_instance_id())


func get_rest_radius() -> float:
	return 3.0


static func find_with_free_bed(from: Node3D) -> Node3D:
	if from == null or from.get_tree() == null:
		return null
	var best: Node3D = null
	var best_d: float = INF
	for n in from.get_tree().get_nodes_in_group("shelter"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if n.has_method("has_free_bed") and not n.has_free_bed():
			continue
		if n.has_method("get") and "is_built" in n and not bool(n.is_built):
			continue
		var d: float = from.global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best


func _claim_marker(container: Node3D, slots: Dictionary, requester: Node3D) -> Vector3:
	_cleanup_dict(slots)
	var markers := _markers_of(container)
	var req_id: int = requester.get_instance_id() if requester else 0
	var from: Vector3 = requester.global_position if requester else global_position
	if markers.is_empty():
		var ang: float = randf() * TAU
		return global_position + Vector3(cos(ang), 0, sin(ang)) * 1.4
	var used: Dictionary = {}
	for rid in slots.keys():
		if int(rid) != req_id:
			used[int(slots[rid])] = true
	var best_i: int = -1
	var best_d: float = INF
	for i in range(markers.size()):
		if used.has(i):
			continue
		var m: Node3D = markers[i] as Node3D
		var d: float = from.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i >= 0:
		if req_id != 0:
			slots[req_id] = best_i
		return (markers[best_i] as Node3D).global_position
	return (markers[0] as Node3D).global_position


func _markers_of(container: Node3D) -> Array:
	var out: Array = []
	if container == null:
		return out
	for c in container.get_children():
		if c is Marker3D or c is Node3D:
			out.append(c)
	return out


func _cleanup_beds() -> void:
	_cleanup_dict(_bed_slots)


func _cleanup_dict(slots: Dictionary) -> void:
	var dead: Array = []
	for rid in slots.keys():
		var id: int = int(rid)
		var obj = instance_from_id(id)
		if obj == null or not is_instance_valid(obj):
			dead.append(rid)
	for rid in dead:
		slots.erase(rid)


func _update_dev_ui() -> void:
	if dev_label == null:
		return
	dev_label.text = "Shelter\n%s\nbeds %d/%d" % [
		"built" if is_built else "frame",
		_bed_slots.size(),
		bed_capacity,
	]


func _process(_delta: float) -> void:
	if Engine.get_frames_drawn() % 30 == 0:
		_update_dev_ui()
