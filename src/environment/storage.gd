# ==============================================================================
# ФАЙЛ: src/environment/Storage.gd
# НАЗНАЧЕНИЕ: Интерактивный склад/поляна с выведением отладочной инфы на DevLabel
#            и поддержкой параметров из assets/config/storage.ini
# ==============================================================================
extends Node3D

@export var stored_food: int = 0
@export var max_storage: int = 500

@export_group("Work Points")
@export var procedural_radius: float = 2.0   # Радиус процедурных слотов вокруг склада
@export var procedural_slots_count: int = 8  # Количество процедурных слотов

var work_time: float = 1.0 # Время разгрузки (из storage.ini [work] base_work_time)
var skill: String = "trader" # Навык разгрузки (из storage.ini [work] skill)
var work_type: String = "delivering"

@onready var work_points_container: Node3D = $WorkPoints
@onready var dev_label: Label3D = get_node_or_null("DevLabel")

# Словарь закрепления рабочих точек за персонажами: { instance_id: slot_index }
var _occupied_slots: Dictionary = {}

func _ready() -> void:
	add_to_group("storage")
	add_to_group("interactable")
	
	# Читаем параметры из assets/config/storage.ini
	if ConfigLoader:
		work_time = float(ConfigLoader.get_config_value("storage", "work", "base_work_time", 1.0))
		skill = str(ConfigLoader.get_config_value("storage", "work", "skill", "trader"))
		work_type = str(ConfigLoader.get_config_value("storage", "work", "work_type", "delivering"))
		max_storage = int(ConfigLoader.get_config_value("storage", "capacity", "max_storage", 500))
		print("[Storage] Config loaded: work_time=%.1fs, max_storage=%d, skill=%s" % [work_time, max_storage, skill])

	_update_dev_ui()

## Возвращает время работы, требуемое для разгрузки еды на склад
func get_work_time() -> float:
	return work_time

## Проверка наличия свободного места на складе
func has_space() -> bool:
	return max_storage <= 0 or stored_food < max_storage

## Приём еды на склад (с учётом лимита вместимости)
func deposit_food(amount: int) -> void:
	var prev_food = stored_food
	if max_storage > 0:
		stored_food = min(stored_food + amount, max_storage)
	else:
		stored_food += amount
	var actual_deposited = stored_food - prev_food
	print("[Storage] Food deposited: +%d | Total stored food: %d/%d" % [actual_deposited, stored_food, max_storage])
	_update_dev_ui()

## Умный возврат свободной рабочей точки рядом со складом (исключает выбор занятой точки)
func get_free_work_point(requester: Node3D = null) -> Vector3:
	_cleanup_slots()

	var requester_id: int = requester.get_instance_id() if requester else 0

	# Если за этим персонажем уже закреплен слот — возвращаем его
	var slot_index: int = 0
	if requester_id != 0 and _occupied_slots.has(requester_id):
		slot_index = _occupied_slots[requester_id]
	else:
		# Находим минимальный свободный индекс слота
		slot_index = _find_first_free_slot()
		if requester_id != 0:
			_occupied_slots[requester_id] = slot_index

	# 1. Если есть дочерние Marker3D (N/S/E/W) в WorkPoints
	if work_points_container and work_points_container.get_child_count() > 0:
		var children = work_points_container.get_children()
		if slot_index < children.size():
			var wp_node = children[slot_index] as Node3D
			if wp_node:
				return wp_node.global_position

	# 2. Процедурные радиальные точки вокруг склада (если маркеров не хватает)
	var angle: float = slot_index * (TAU / float(max(1, procedural_slots_count)))
	var offset = Vector3(cos(angle) * procedural_radius, 0.0, sin(angle) * procedural_radius)
	return global_position + offset

## Освобождение слота персонажем при завершении разгрузки или смене задачи
func release_work_point(requester: Node3D) -> void:
	if requester and is_instance_valid(requester):
		_occupied_slots.erase(requester.get_instance_id())

## Очистка утекших ID персонажей
func _cleanup_slots() -> void:
	var to_remove: Array = []
	for req_id in _occupied_slots.keys():
		var obj = instance_from_id(req_id)
		if not obj or not is_instance_valid(obj):
			to_remove.append(req_id)
	for req_id in to_remove:
		_occupied_slots.erase(req_id)

## Поиск первого свободного слота
func _find_first_free_slot() -> int:
	var used_slots = _occupied_slots.values()
	var candidate: int = 0
	while candidate in used_slots:
		candidate += 1
	return candidate

## Обновление отладочной плашки над складом
func _update_dev_ui() -> void:
	if not dev_label:
		return
	dev_label.text = "Storage Food: %d/%d\nWork: %.1fs" % [stored_food, max_storage, work_time]
