# ==============================================================================
# campfire.gd — костёр WorkSite: fuel (wood), lit/embers. v1 без happy.
# ОБНОВЛЕНО: 2026-10-28 — construction + wood via stoking path
# ==============================================================================
extends Node3D
class_name CampfireSite

@export var max_wood: int = 10
@export var fuel_seconds_per_wood: float = 10.0
@export var work_time: float = 1.0
@export var work_type: String = "fueling"
@export var skill: String = "worker"
@export var work_anim: String = "deposit"

## запас в «поленьях» (целые); горение жрёт fuel_time (сек)
var wood_stock: int = 0
var fuel_time: float = 0.0
## lit | embers
var fire_state: String = "embers"

## player-placed build
var under_construction: bool = false
var build_progress: float = 0.0
var build_time: float = 30.0
var build_wood_needed: int = 5
var _build_wood_used: int = 0

var _occupied_slots: Dictionary = {}

@onready var dev_label: Label3D = get_node_or_null("DevLabel") as Label3D
@onready var fire_light: OmniLight3D = get_node_or_null("FireLight") as OmniLight3D


func _ready() -> void:
	add_to_group("campfire")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_load_from_config()
	if under_construction:
		_begin_construction()
	_sync_light()
	_update_dev_ui()


## call before add_child, or set under_construction=true before enter tree
func setup_as_construction() -> void:
	under_construction = true
	build_progress = 0.0


func _begin_construction() -> void:
	wood_stock = 0
	fuel_time = 0.0
	fire_state = "embers"
	build_progress = 0.0
	_build_wood_used = 0
	if ConfigLoader and ConfigLoader.has_method("get_campfire_value"):
		build_time = float(ConfigLoader.get_campfire_value("build", "build_time", build_time))
		build_wood_needed = int(ConfigLoader.get_campfire_value("build", "build_wood_needed", build_wood_needed))
	elif ConfigLoader and ConfigLoader.has_method("get_config_value"):
		build_time = float(ConfigLoader.get_config_value("campfire", "build", "build_time", build_time))
		build_wood_needed = int(ConfigLoader.get_config_value("campfire", "build", "build_wood_needed", build_wood_needed))
	build_wood_needed = maxi(build_wood_needed, 1)
	_sync_light()
	print("[Campfire] under construction time=%.1f wood_need=%d" % [build_time, build_wood_needed])


func is_built() -> bool:
	return not under_construction


## work-sec from character (wood delivery later)
func contribute_build(amount: float) -> float:
	if not under_construction or amount <= 0.0:
		return 0.0
	var before := build_progress
	build_progress = minf(build_progress + amount, build_time)
	_update_dev_ui()
	if build_progress >= build_time:
		_finish_construction()
	return build_progress - before


func _finish_construction() -> void:
	under_construction = false
	build_progress = build_time
	# empty fuel until stoked
	wood_stock = 0
	fuel_time = 0.0
	fire_state = "embers"
	_sync_light()
	_update_dev_ui()
	print("[Campfire] construction complete")


func _load_from_config() -> void:
	if not ConfigLoader:
		_apply_start_fuel(2)
		return
	var getv = Callable()
	if ConfigLoader.has_method("get_campfire_value"):
		work_time = float(ConfigLoader.get_campfire_value("work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_campfire_value("work", "work_type", work_type))
		skill = str(ConfigLoader.get_campfire_value("work", "skill", skill))
		work_anim = str(ConfigLoader.get_campfire_value("work", "work_anim", work_anim))
		fuel_seconds_per_wood = float(ConfigLoader.get_campfire_value("fuel", "fuel_seconds_per_wood", fuel_seconds_per_wood))
		max_wood = int(ConfigLoader.get_campfire_value("fuel", "max_wood", max_wood))
		var start_w: int = int(ConfigLoader.get_campfire_value("fuel", "start_wood", 2))
		_apply_start_fuel(start_w)
	elif ConfigLoader.has_method("get_config_value"):
		work_time = float(ConfigLoader.get_config_value("campfire", "work", "base_work_time", work_time))
		fuel_seconds_per_wood = float(ConfigLoader.get_config_value("campfire", "fuel", "fuel_seconds_per_wood", fuel_seconds_per_wood))
		max_wood = int(ConfigLoader.get_config_value("campfire", "fuel", "max_wood", max_wood))
		_apply_start_fuel(int(ConfigLoader.get_config_value("campfire", "fuel", "start_wood", 2)))
	else:
		_apply_start_fuel(2)
	print("[Campfire] fuel/wood=%.1fs max=%d stock=%d time=%.1f" % [
		fuel_seconds_per_wood, max_wood, wood_stock, fuel_time
	])


func _apply_start_fuel(start_w: int) -> void:
	wood_stock = clampi(start_w, 0, max_wood)
	fuel_time = float(wood_stock) * fuel_seconds_per_wood
	fire_state = "lit" if fuel_time > 0.0 else "embers"


func _process(delta: float) -> void:
	if under_construction:
		return
	if fuel_time > 0.0:
		fuel_time = maxf(fuel_time - delta, 0.0)
		# wood_stock ≈ ceil(fuel / per_wood) для UI
		if fuel_seconds_per_wood > 0.0:
			wood_stock = mini(max_wood, int(ceil(fuel_time / fuel_seconds_per_wood)))
		if fuel_time <= 0.0:
			wood_stock = 0
			fire_state = "embers"
			_sync_light()
			_update_dev_ui()
		elif int(fuel_time) % 2 == 0:
			_update_dev_ui()
	else:
		if fire_state != "embers":
			fire_state = "embers"
			_sync_light()


func _sync_light() -> void:
	if fire_light == null:
		fire_light = get_node_or_null("FireLight") as OmniLight3D
	if fire_light:
		fire_light.visible = fire_state == "lit" and fuel_time > 0.0
		if fire_light.visible:
			var t: float = clampf(fuel_time / maxf(float(max_wood) * fuel_seconds_per_wood, 1.0), 0.15, 1.0)
			fire_light.light_energy = lerpf(0.4, 2.5, t)


# --- API ---
## Радиус «у костра» = omni_range FireLight (для ночного отдыха)
func get_rest_radius() -> float:
	if fire_light == null:
		fire_light = get_node_or_null("FireLight") as OmniLight3D
	if fire_light:
		return maxf(float(fire_light.omni_range), 1.0)
	return 10.0


func needs_fuel() -> bool:
	# construction reuses stoking loop until built
	if under_construction:
		return true
	return wood_stock < max_wood and fuel_time < float(max_wood) * fuel_seconds_per_wood


func is_lit() -> bool:
	return fire_state == "lit" and fuel_time > 0.0


func fuel_room() -> int:
	## сколько ещё поленьев влезет
	if fuel_seconds_per_wood <= 0.0:
		return maxi(max_wood - wood_stock, 0)
	var max_t: float = float(max_wood) * fuel_seconds_per_wood
	var room_t: float = maxf(max_t - fuel_time, 0.0)
	return int(floor(room_t / fuel_seconds_per_wood + 0.001))


func add_wood(amount: int = 1) -> int:
	if amount <= 0:
		return 0
	var room: int = fuel_room()
	var put: int = mini(amount, room)
	if put <= 0:
		return 0
	fuel_time += float(put) * fuel_seconds_per_wood
	wood_stock = mini(max_wood, wood_stock + put)
	if fuel_time > 0.0:
		fire_state = "lit"
	_sync_light()
	_update_dev_ui()
	return put


# --- WorkSite ---
func can_accept_work(worker: Node = null) -> bool:
	if under_construction:
		if worker != null and "data" in worker and worker.data:
			var item := str(worker.data.carried_item).to_lower()
			return worker.data.item_amount > 0 and (item == "wood" or item == "log")
		return true
	if not needs_fuel():
		return false
	if worker != null and "data" in worker and worker.data:
		var item := str(worker.data.carried_item).to_lower()
		return worker.data.item_amount > 0 and (item == "wood" or item == "log")
	return true


func get_work_skill() -> String:
	return skill


func get_work_type() -> String:
	# fueling → deposit → start_stoking (не "building" → BUILD not implemented)
	return work_type


func get_work_anim() -> String:
	if under_construction:
		return "work"
	return work_anim


func get_work_time() -> float:
	return work_time


func do_work(worker: Node = null) -> Dictionary:
	if worker == null or not ("data" in worker) or worker.data == null:
		return {"ok": false, "reason": "no_worker"}
	if worker.data.item_amount <= 0:
		return {"ok": false, "reason": "empty_hands"}
	var item := str(worker.data.carried_item).to_lower()
	if item != "wood" and item != "log":
		return {"ok": false, "reason": "not_wood"}
	# --- construction: wood as materials ---
	if under_construction:
		var take_n: int = 1
		worker.data.item_amount -= take_n
		if worker.data.item_amount <= 0:
			worker.data.carried_item = ""
			worker.data.item_amount = 0
		_build_wood_used += take_n
		var chunk: float = build_time / float(maxi(build_wood_needed, 1))
		contribute_build(chunk)
		return {
			"ok": true,
			"take": {"item": "wood", "amount": take_n},
			"xp_skill": skill,
			"work_type": "building",
			"work_anim": "work",
			"build_progress": build_progress,
			"under_construction": under_construction,
		}
	if not needs_fuel():
		return {"ok": false, "reason": "full"}
	var amount: int = worker.data.item_amount
	var put: int = add_wood(amount)
	if put <= 0:
		return {"ok": false, "reason": "full"}
	worker.data.item_amount -= put
	if worker.data.item_amount <= 0:
		worker.data.carried_item = ""
		worker.data.item_amount = 0
	return {
		"ok": true,
		"take": {"item": "wood", "amount": put},
		"xp_skill": skill,
		"work_type": work_type,
		"work_anim": work_anim,
		"fuel_time": fuel_time,
	}


func get_free_work_point(requester: Node3D = null) -> Vector3:
	var markers: Array = []
	var wp := get_node_or_null("WorkPoints") as Node3D
	if wp:
		for c in wp.get_children():
			if c is Marker3D:
				markers.append(c)
	var req_id: int = requester.get_instance_id() if requester else 0
	var from: Vector3 = requester.global_position if requester and is_instance_valid(requester) else global_position
	var used: Dictionary = {}
	for rid in _occupied_slots.keys():
		if int(rid) != req_id:
			used[int(_occupied_slots[rid])] = true
	var best_i := -1
	var best_d := INF
	for i in range(markers.size()):
		if used.has(i):
			continue
		var m: Node3D = markers[i]
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
	var a := randf() * TAU
	return global_position + Vector3(cos(a), 0.0, sin(a)) * 1.2


func release_work_point(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_occupied_slots.erase(requester.get_instance_id())



func get_display_name() -> String:
	if Loc and Loc.has_method("object_name"):
		return Loc.object_name("campfire")
	return "Campfire"


func get_info_text() -> String:
	if under_construction:
		var pct := 0 if build_time <= 0.0 else int(100.0 * build_progress / build_time)
		return "BUILDING\n%d%%\nmat %d/%d" % [pct, _build_wood_used, build_wood_needed]
	return "Fire:%s\nWood:%d/%d\nFuel:%.0fs" % [fire_state, wood_stock, max_wood, fuel_time]


func _update_dev_ui() -> void:
	if not dev_label:
		return
	var show_dev := true
	if DevCheatManager and DevCheatManager.has_method("is_dev_overlays_on"):
		show_dev = DevCheatManager.is_dev_overlays_on()
	dev_label.visible = show_dev
	if under_construction:
		var pct := 0 if build_time <= 0.0 else int(100.0 * build_progress / build_time)
		dev_label.text = "BUILDING\n%d%%\nmat %d/%d" % [pct, _build_wood_used, build_wood_needed]
	else:
		dev_label.text = "Fire:%s\nWood:%d/%d\nFuel:%.0fs" % [fire_state, wood_stock, max_wood, fuel_time]
