# ==============================================================================
# ФАЙЛ: src/environment/Storage.gd
# НАЗНАЧЕНИЕ: Хранилище с рабочими точками разгрузки
# ==============================================================================
class_name Storage
extends Node3D

@export var stored_resources: Dictionary = {
	"berry": 0
}

@onready var dev_label: Label3D = $DevLabel
@onready var work_points_container: Node3D = $WorkPoints

var _occupied_points: Dictionary = {}

func _ready() -> void:
	if work_points_container:
		for child in work_points_container.get_children():
			if child is Marker3D:
				_occupied_points[child] = null
	_update_dev_ui()

## Запросить свободную точку разгрузки
func get_free_work_point(requester: Node3D) -> Marker3D:
	for point in _occupied_points:
		if _occupied_points[point] == requester:
			return point
			
	for point in _occupied_points:
		if _occupied_points[point] == null or not is_instance_valid(_occupied_points[point]):
			_occupied_points[point] = requester
			return point
			
	return null

## Освободить точку
func release_work_point(requester: Node3D) -> void:
	for point in _occupied_points:
		if _occupied_points[point] == requester:
			_occupied_points[point] = null

func deposit_food(food_type: String, amount: int) -> void:
	stored_resources[food_type] = stored_resources.get(food_type, 0) + amount
	print("[Storage] Deposited %d of %s. Total %s: %d" % [amount, food_type, food_type, stored_resources[food_type]])
	_update_dev_ui()

func withdraw_food(food_type: String, requested_amount: int) -> int:
	var current_amount: int = stored_resources.get(food_type, 0)
	var taken_amount: int = mini(current_amount, requested_amount)
	if taken_amount > 0:
		stored_resources[food_type] -= taken_amount
		_update_dev_ui()
	return taken_amount

func get_total_food_count() -> int:
	var total: int = 0
	for count in stored_resources.values():
		total += count
	return total

func _update_dev_ui() -> void:
	if not dev_label:
		return
	var text_info = "STORAGE\nTotal Food: %d\n" % get_total_food_count()
	for type_name in stored_resources:
		text_info += "%s: %d\n" % [type_name.capitalized(), stored_resources[type_name]]
	dev_label.text = text_info
