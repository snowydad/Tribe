# ==============================================================================
# ФАЙЛ: src/environment/berries.gd
# НАЗНАЧЕНИЕ: Контроллер куста ягод 'berries' с автораспределением свободных
#            WorkPoint для персонажей (исключает толкание и мерцание)
#            и полной загрузкой параметров из assets/config/berries.ini.
# ==============================================================================
extends Node3D

@export_group("Crop Settings")
@export var max_berries: int = 5           # Максимальный размер партии ягод (из [output] max_amount)
@export var yield_amount: int = 1          # Количество ягод за один сбор (из [output] yield_amount)
@export var ripening_time: float = 30.0    # Время созревания партии в секундах (из [output] ripening_time)
@export var work_time: float = 3.0         # Базовое время сбора 1 партии (из [work] base_work_time)
@export var resource_type: String = "berry"# Тип ресурса (из [output] resource_type)
@export var skill: String = "forager"      # Профильный навык (из [work] skill)
@export var work_type: String = "foraging" # Тип работы (из [work] work_type)

@export_group("Work Points")
@export var work_points_parent: Node3D     # Узел-родитель для точек WorkPoint
@export var procedural_radius: float = 1.0 # Радиус процедурных точек вокруг куста
@export var procedural_slots_count: int = 6# Количество процедурных слотов

@onready var dev_label: Label3D = $DevLabel

var current_berries: int = 5
var is_ripening: bool = false
var _ripen_timer: float = 0.0

# Словарь закрепления рабочих точек за персонажами: { instance_id: slot_index }
var _occupied_slots: Dictionary = {}

func _ready() -> void:
	add_to_group("berries")
	_ensure_dev_label_exists()
	
	# Считываем конфигурацию из res://assets/config/berries.ini
	if ConfigLoader:
		work_time = float(ConfigLoader.get_config_value("berries", "work", "base_work_time", 3.0))
		skill = str(ConfigLoader.get_config_value("berries", "work", "skill", "forager"))
		work_type = str(ConfigLoader.get_config_value("berries", "work", "work_type", "foraging"))
		resource_type = str(ConfigLoader.get_config_value("berries", "output", "resource_type", "berry"))
		yield_amount = int(ConfigLoader.get_config_value("berries", "output", "yield_amount", 1))
		max_berries = int(ConfigLoader.get_config_value("berries", "output", "max_amount", 5))
		ripening_time = float(ConfigLoader.get_config_value("berries", "output", "ripening_time", 30.0))
		print("[Berries] Config loaded: work_time=%.1fs, max_berries=%d, yield=%d, ripen=%.1fs" % [
			work_time, max_berries, yield_amount, ripening_time
		])
	
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
			current_berries = max_berries # Созревает вся партия
			_update_dev_ui()
			_update_visuals()
			print("[Berries] Crop fully ripe! All %d berries restored." % max_berries)

## Проверка наличия спелых ягод
func has_berries() -> bool:
	return current_berries > 0 and not is_ripening

## Время сбора
func get_work_time() -> float:
	return work_time

## Количество ресурса, собираемого за один подход
func get_yield_amount() -> int:
	return yield_amount

## Тип собираемого ресурса
func get_resource_type() -> String:
	return resource_type

## Сбор урожая персонажем (учитывает yield_amount из berries.ini)
func harvest_berry() -> bool:
	if current_berries > 0 and not is_ripening:
		var picked = min(yield_amount, current_berries)
		current_berries -= picked
		_update_dev_ui()
		_update_visuals()
		
		# Когда сорвали ПОСЛЕДНЮЮ ягоду — запускаем созревание всей партии
		if current_berries <= 0:
			current_berries = 0
			is_ripening = true
			_ripen_timer = 0.0
			_update_dev_ui()
			print("[Berries] All berries harvested! Starting ripening cycle (%.1fs)..." % ripening_time)
			
		return true
	return false

## Умный возврат свободной рабочей точки для персонажа
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

	# 1. Если есть дочерние WorkPoint в сцене
	if work_points_parent and work_points_parent.get_child_count() > 0:
		var children = work_points_parent.get_children()
		if slot_index < children.size():
			var wp_node = children[slot_index] as Node3D
			if wp_node:
				return wp_node.global_position

	# 2. Процедурные радиальные точки вокруг куста (если дочерних точек нет или их не хватает)
	var angle: float = slot_index * (TAU / float(max(1, procedural_slots_count)))
	var offset = Vector3(cos(angle) * procedural_radius, 0.0, sin(angle) * procedural_radius)
	
	return global_position + offset

## Освобождение слота персонажем при завершении или отмене работы
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

## Обновление отладочной плашки над кустом
func _update_dev_ui() -> void:
	if not dev_label:
		return
		
	if is_ripening:
		var progress: float = clamp((_ripen_timer / ripening_time) * 100.0, 0.0, 100.0)
		dev_label.text = "Berries: 0/%d\n[Ripening: %.0f%%]" % [max_berries, progress]
	else:
		dev_label.text = "Berries: %d/%d" % [current_berries, max_berries]

## Гарантия наличия DevLabel в сцене куста
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
