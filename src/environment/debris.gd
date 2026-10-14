# ==============================================================================
# debris.gd — завал (WorkSite). ini: debris.ini. output = wood.
# ОБНОВЛЕНО: 2026-10-14 — name = debris everywhere (not obstacle)
# ==============================================================================
extends Node3D
class_name DebrisSite

@export_group("Pile")
@export var max_logs: int = 5
@export var work_time: float = 3.0

@export_group("Work (from obstacle.ini)")
@export var work_type: String = "chop"
@export var skill: String = "lumberjack"
@export var work_anim: String = "clear"
@export var resource_type: String = "wood"
@export var yield_amount: int = 1

@export_group("Work Points")
@export var work_points_parent: Node3D

@onready var dev_label: Label3D = get_node_or_null("DevLabel") as Label3D

var current_logs: int = 5
var is_dead: bool = false
var _occupied_slots: Dictionary = {}


func _ready() -> void:
	add_to_group("obstacle")
	add_to_group("debris")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_load_from_config()
	if current_logs <= 0:
		current_logs = max_logs
	_update_dev_ui()
	_update_visuals()


func _load_from_config() -> void:
	if not ConfigLoader:
		return
	if ConfigLoader.has_method("get_debris_value"):
		work_time = float(ConfigLoader.get_debris_value("work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_debris_value("work", "work_type", work_type))
		skill = str(ConfigLoader.get_debris_value("work", "skill", skill))
		work_anim = str(ConfigLoader.get_debris_value("work", "work_anim", work_anim))
		max_logs = int(ConfigLoader.get_debris_value("output", "max_amount", max_logs))
		resource_type = str(ConfigLoader.get_debris_value("output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_debris_value("output", "yield_amount", yield_amount))
	elif ConfigLoader.has_method("get_config_value"):
		work_time = float(ConfigLoader.get_config_value("debris", "work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_config_value("debris", "work", "work_type", work_type))
		skill = str(ConfigLoader.get_config_value("debris", "work", "skill", skill))
		work_anim = str(ConfigLoader.get_config_value("debris", "work", "work_anim", work_anim))
		max_logs = int(ConfigLoader.get_config_value("debris", "output", "max_amount", max_logs))
		resource_type = str(ConfigLoader.get_config_value("debris", "output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_config_value("debris", "output", "yield_amount", yield_amount))
	current_logs = max_logs
	print("[Debris] Config: work=%s anim=%s skill=%s time=%.1f item=%s max=%d" % [
		work_type, work_anim, skill, work_time, resource_type, max_logs
	])


# --- WorkSite ---
func can_accept_work(_worker: Node = null) -> bool:
	return not is_dead and current_logs > 0


func get_work_skill() -> String:
	return skill


func get_work_type() -> String:
	return work_type


func get_work_anim() -> String:
	return work_anim


func get_work_time() -> float:
	return work_time


func do_work(_worker: Node = null) -> Dictionary:
	if not can_accept_work(_worker):
		return {"ok": false, "reason": "empty" if current_logs <= 0 else "dead"}
	var take: int = mini(yield_amount, current_logs)
	current_logs -= take
	_update_dev_ui()
	_update_visuals()
	var result := {
		"ok": true,
		"give": {"item": resource_type, "amount": take},
		"xp_skill": skill,
		"work_type": work_type,
		"work_anim": work_anim,
	}
	if current_logs <= 0:
		_finish_pile()
	return result


## совместимость со старым clear path
func clear_obstacle() -> void:
	do_work(null)


func _finish_pile() -> void:
	is_dead = true
	if is_in_group("interactable"):
		remove_from_group("interactable")
	if is_in_group(WorkSite.GROUP):
		remove_from_group(WorkSite.GROUP)
	if is_in_group("obstacle"):
		remove_from_group("obstacle")
	var ia := get_node_or_null("InteractiveArea") as Area3D
	if ia:
		ia.monitoring = false
		ia.monitorable = false
	print("[Debris] Pile cleared — free")
	# чуть паузы на VFX/аним потом
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		queue_free()


# --- WP ---
func _work_markers() -> Array:
	var out: Array = []
	var parent: Node3D = work_points_parent
	if parent == null:
		parent = get_node_or_null("WorkPoints") as Node3D
	if parent == null:
		return out
	for c in parent.get_children():
		if c is Marker3D:
			out.append(c)
	return out


func get_free_work_point(requester: Node3D = null) -> Vector3:
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
	if markers.size() > 0:
		return (markers[0] as Node3D).global_position
	var ang: float = randf() * TAU
	return global_position + Vector3(cos(ang), 0.0, sin(ang)) * 1.2


func release_work_point(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_occupied_slots.erase(requester.get_instance_id())


func _update_visuals() -> void:
	# масштаб кучи по остатку (placeholder)
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh and max_logs > 0:
		var t: float = clampf(float(current_logs) / float(max_logs), 0.15, 1.0)
		mesh.scale = Vector3(t, t, t)


func _update_dev_ui() -> void:
	if not dev_label:
		return
	if DevCheatManager and DevCheatManager.has_method("is_dev_overlays_on") and not DevCheatManager.is_dev_overlays_on():
		dev_label.visible = false
		return
	dev_label.visible = true
	dev_label.text = "Wood: %d/%d\n%s / %s" % [current_logs, max_logs, work_type, skill]
