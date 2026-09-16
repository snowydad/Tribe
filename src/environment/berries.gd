# ==============================================================================
# ФАЙЛ: src/environment/Berries.gd
# НАЗНАЧЕНИЕ: Ягодный куст с точками взаимодействия для рабочих
# ==============================================================================
class_name Berries
extends Node3D

@export var resource_type: String = "berry"
@export var berries_available: int = 10
@export var nutrition_per_berry: float = 20.0

@onready var dev_label: Label3D = $DevLabel
@onready var work_points_container: Node3D = $WorkPoints

var _occupied_points: Dictionary = {}

func _ready() -> void:
	if work_points_container:
		for child in work_points_container.get_children():
			if child is Marker3D:
				_occupied_points[child] = null
	_update_dev_ui()

## Запросить свободную рабочую точку у куста
func get_free_work_point(requester: Node3D) -> Marker3D:
	for point in _occupied_points:
		if _occupied_points[point] == requester:
			return point
			
	for point in _occupied_points:
		if _occupied_points[point] == null or not is_instance_valid(_occupied_points[point]):
			_occupied_points[point] = requester
			return point
			
	return null

## Освободить точку работы
func release_work_point(requester: Node3D) -> void:
	for point in _occupied_points:
		if _occupied_points[point] == requester:
			_occupied_points[point] = null

## Сбор 1 ягоды
func harvest_berry() -> bool:
	if berries_available > 0:
		berries_available -= 1
		_update_dev_ui()
		return true
	return false

func _update_dev_ui() -> void:
	if not dev_label:
		return
	if berries_available > 0:
		dev_label.text = "BERRIES\nAvailable: %d" % berries_available
	else:
		dev_label.text = "BERRIES\n[EMPTY]"
