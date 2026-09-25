# ==============================================================================
# ФАЙЛ: src/objects/berries.gd
# НАЗНАЧЕНИЕ: Контроллер объекта 'berries' с чтением параметров из berries.ini
#            и партионным созреванием всей группы ягод.
# ==============================================================================
extends Node3D

@export_group("Work Settings")
@export var work_type: String = "foraging"
@export var skill: String = "forager"
@export var base_work_time: float = 3.0

@export_group("Output Settings")
@export var resource_type: String = "berry"
@export var yield_amount: int = 1
@export var max_amount: int = 5
@export var ripening_time: float = 15.0

@export_group("Work Points")
@export var work_points_parent: Node3D

var current_amount: int = 5
var is_ripening: bool = false
var _ripen_timer: float = 0.0

@onready var dev_label: Label3D = $DevLabel

func _ready() -> void:
	add_to_group("berries")
	_ensure_dev_label_exists()
	
	# Чтение параметров из res://assets/config/berries.ini
	if ConfigLoader and ConfigLoader.has_method("get_berries_value"):
		work_type = String(ConfigLoader.get_berries_value("work", "work_type", work_type))
		skill = String(ConfigLoader.get_berries_value("work", "skill", skill))
		base_work_time = float(ConfigLoader.get_berries_value("work", "base_work_time", base_work_time))
		
		resource_type = String(ConfigLoader.get_berries_value("output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_berries_value("output", "yield_amount", yield_amount))
		max_amount = int(ConfigLoader.get_berries_value("output", "max_amount", max_amount))
		ripening_time = float(ConfigLoader.get_berries_value("output", "ripening_time", ripening_time))
	
	if current_amount <= 0 and not is_ripening:
		current_amount = max_amount
		
	_update_visuals()

func _process(delta: float) -> void:
	if is_ripening:
		_ripen_timer += delta
		if _ripen_timer >= ripening_time:
			is_ripening = false
			_ripen_timer = 0.0
			current_amount = max_amount
			_update_visuals()
			print("[Berries] Crop fully ripe! All %d %s restored." % [max_amount, resource_type])
	
	_update_dev_ui()

## Проверка наличия спелых ягод для Character.gd
func has_berries() -> bool:
	return current_amount > 0 and not is_ripening

## Базовое время работы для Character.gd
func get_work_time() -> float:
	return base_work_time

## Сбор 1 ягоды персонажем
func harvest_berry() -> bool:
	if current_amount > 0 and not is_ripening:
		current_amount -= yield_amount
		if current_amount <= 0:
			current_amount = 0
			is_ripening = true
			_ripen_timer = 0.0
			print("[Berries] Harvested last berry. Starting ripening timer (%.1fs)..." % ripening_time)
		_update_visuals()
		return true
	return false

## Безопасный возврат точки WorkPoint для Context Drop
func get_free_work_point(_requester: Node3D = null) -> Vector3:
	if work_points_parent and work_points_parent.get_child_count() > 0:
		var children = work_points_parent.get_children()
		var random_point = children[randi() % children.size()] as Node3D
		if random_point:
			return random_point.global_position
	return global_position + Vector3(0.8, 0.0, 0.0)

func _ensure_dev_label_exists() -> void:
	if not dev_label:
		dev_label = get_node_or_null("DevLabel") as Label3D
	if not dev_label:
		dev_label = Label3D.new()
		dev_label.name = "DevLabel"
		dev_label.position = Vector3(0, 1.5, 0)
		dev_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dev_label.no_depth_test = true
		dev_label.pixel_size = 0.005
		dev_label.font_size = 32
		add_child(dev_label)

func _update_dev_ui() -> void:
	if not dev_label:
		return
	if is_ripening:
		var percent = int((_ripen_timer / max(ripening_time, 0.1)) * 100.0)
		dev_label.text = "Berries: 0/%d\n[Ripening: %d%%]" % [max_amount, clamp(percent, 0, 100)]
	else:
		dev_label.text = "Berries: %d/%d" % [current_amount, max_amount]

func _update_visuals() -> void:
	_update_dev_ui()
