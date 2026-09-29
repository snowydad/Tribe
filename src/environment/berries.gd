# ==============================================================================
# berries.gd — куст ягод как WorkSite (данные из berries.ini)
# ==============================================================================
extends Node3D

@export_group("Crop Settings")
@export var max_berries: int = 5
@export var ripening_time: float = 15.0
@export var work_time: float = 3.0
@export var nutrition_value: float = 25.0

@export_group("Work (from ini)")
@export var work_type: String = "foraging"
@export var skill: String = "forager"
@export var resource_type: String = "berry"
@export var yield_amount: int = 1

@export_group("Work Points")
@export var work_points_parent: Node3D

@onready var dev_label: Label3D = $DevLabel

var current_berries: int = 5
var is_ripening: bool = false
var _ripen_timer: float = 0.0
var _occupied_slots: Dictionary = {}

func _ready() -> void:
	add_to_group("berries")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_ensure_dev_label_exists()

	if ConfigLoader and ConfigLoader.has_method("get_berries_value"):
		work_time = float(ConfigLoader.get_berries_value("work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_berries_value("work", "work_type", work_type))
		skill = str(ConfigLoader.get_berries_value("work", "skill", skill))
		max_berries = int(ConfigLoader.get_berries_value("output", "max_amount", max_berries))
		ripening_time = float(ConfigLoader.get_berries_value("output", "ripening_time", ripening_time))
		resource_type = str(ConfigLoader.get_berries_value("output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_berries_value("output", "yield_amount", yield_amount))
		nutrition_value = float(ConfigLoader.get_berries_value("nutrition", "nutrition_value", nutrition_value))
	elif ConfigLoader and ConfigLoader.has_method("get_config_value"):
		work_time = float(ConfigLoader.get_config_value("berries", "work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_config_value("berries", "work", "work_type", work_type))
		skill = str(ConfigLoader.get_config_value("berries", "work", "skill", skill))
		max_berries = int(ConfigLoader.get_config_value("berries", "output", "max_amount", max_berries))
		ripening_time = float(ConfigLoader.get_config_value("berries", "output", "ripening_time", ripening_time))
		resource_type = str(ConfigLoader.get_config_value("berries", "output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_config_value("berries", "output", "yield_amount", yield_amount))
		nutrition_value = float(ConfigLoader.get_config_value("berries", "nutrition", "nutrition_value", nutrition_value))

	if current_berries <= 0 and not is_ripening:
		current_berries = max_berries

	_update_dev_ui()
	_update_visuals()

func _process(delta: float) -> void:
	if is_ripening:
		_ripen_timer += delta
		_update_dev_ui()
		if _ripen_timer >= ripening_time:
			is_ripening = false
			_ripen_timer = 0.0
			current_berries = max_berries
			_update_dev_ui()
			_update_visuals()
			print("[Berries] Crop fully ripe! All %d berries restored." % max_berries)

# --- legacy API (совместимость) ---
func has_berries() -> bool:
	return current_berries > 0 and not is_ripening

func get_work_time() -> float:
	return work_time

func get_nutrition_value() -> float:
	return nutrition_value

func get_resource_type() -> String:
	return resource_type

func get_yield_amount() -> int:
	return yield_amount

func harvest_berry() -> bool:
	if current_berries > 0 and not is_ripening:
		current_berries -= 1
		_update_dev_ui()
		_update_visuals()
		if current_berries <= 0:
			current_berries = 0
			is_ripening = true
			_ripen_timer = 0.0
			_update_dev_ui()
			print("[Berries] All berries harvested! Starting ripening cycle...")
		return true
	return false

# --- WorkSite contract ---
func can_accept_work(_worker: Node = null) -> bool:
	return has_berries()

func get_work_skill() -> String:
	return skill

func get_work_type() -> String:
	return work_type

## Один цикл сбора. Инвентарь worker'а меняет character по полю "give".
func do_work(_worker: Node = null) -> Dictionary:
	if not harvest_berry():
		return {"ok": false, "reason": "not_ready"}
	return {
		"ok": true,
		"give": {"item": resource_type, "amount": yield_amount},
		"xp_skill": skill,
		"nutrition": nutrition_value,
	}

func get_free_work_point(requester: Node3D = null) -> Vector3:
	var req_id: int = requester.get_instance_id() if requester else 0
	var slot_index: int = 0
	if _occupied_slots.has(req_id):
		slot_index = _occupied_slots[req_id]
	else:
		slot_index = _find_next_free_slot_index()
		if req_id != 0:
			_occupied_slots[req_id] = slot_index

	if work_points_parent and work_points_parent.get_child_count() > 0:
		var children = work_points_parent.get_children()
		var point_node = children[slot_index % children.size()] as Node3D
		if point_node:
			return point_node.global_position

	var angle: float = slot_index * (PI / 3.0)
	var offset = Vector3(cos(angle), 0.0, sin(angle)) * 1.0
	return global_position + offset

func release_work_point(requester: Node3D) -> void:
	if requester and _occupied_slots.has(requester.get_instance_id()):
		_occupied_slots.erase(requester.get_instance_id())

func _find_next_free_slot_index() -> int:
	var used_slots = _occupied_slots.values()
	var candidate: int = 0
	while candidate in used_slots:
		candidate += 1
	return candidate

func _update_dev_ui() -> void:
	if not dev_label:
		return
	if is_ripening:
		var progress: float = clamp((_ripen_timer / ripening_time) * 100.0, 0.0, 100.0)
		dev_label.text = "Berries: 0/%d\n[Ripening: %.0f%%]\nWork: %s" % [max_berries, progress, work_type]
	else:
		dev_label.text = "Berries: %d/%d (Nutr: +%.0f)\nWork: %s / %s" % [current_berries, max_berries, nutrition_value, work_type, skill]

func _ensure_dev_label_exists() -> void:
	if not dev_label:
		dev_label = get_node_or_null("DevLabel") as Label3D
		if not dev_label:
			dev_label = Label3D.new()
			dev_label.name = "DevLabel"
			dev_label.position = Vector3(0.0, 1.5, 0.0)
			dev_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			dev_label.no_depth_test = true
			dev_label.pixel_size = 0.005
			dev_label.modulate = Color(1.0, 0.8, 0.2)
			add_child(dev_label)

func _update_visuals() -> void:
	pass
