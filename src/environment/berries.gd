# ==============================================================================
# ФАЙЛ: src/objects/berries.gd
# НАЗНАЧЕНИЕ: Контроллер куста ягод 'berries' с считыванием [work], [output] и [nutrition] из berries.ini
# ==============================================================================
extends Node3D

@export_group("Crop Settings")
@export var max_berries: int = 5           # Максимальный размер партии ягод (из [output] max_amount)
@export var ripening_time: float = 15.0      # Время созревания партии в секундах (из [output] ripening_time)
@export var work_time: float = 3.0           # Базовое время сбора 1 ягоды (из [work] base_work_time)
@export var nutrition_value: float = 25.0    # Восстановление сытости (из [nutrition] nutrition_value)

@export_group("Work Points")
@export var work_points_parent: Node3D       # Узел-родитель для точек WorkPoint

@onready var dev_label: Label3D = $DevLabel

var current_berries: int = 5
var is_ripening: bool = false
var _ripen_timer: float = 0.0

# Трекинг занятых слотов вокруг куста { character_instance_id: slot_index }
var _occupied_slots: Dictionary = {}

func _ready() -> void:
	add_to_group("berries")
	_ensure_dev_label_exists()
	
	# Считываем конфигурацию из res://assets/config/berries.ini
	if ConfigLoader and ConfigLoader.has_method("get_berries_value"):
		work_time = float(ConfigLoader.get_berries_value("work", "base_work_time", 3.0))
		max_berries = int(ConfigLoader.get_berries_value("output", "max_amount", 5))
		ripening_time = float(ConfigLoader.get_berries_value("output", "ripening_time", 15.0))
		nutrition_value = float(ConfigLoader.get_berries_value("nutrition", "nutrition_value", 25.0))
	
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

## Время сбора 1 ягоды
func get_work_time() -> float:
	return work_time

## Питательная ценность 1 ягоды
func get_nutrition_value() -> float:
	return nutrition_value

## Сбор 1 ягоды персонажем
func harvest_berry() -> bool:
	if current_berries > 0 and not is_ripening:
		current_berries -= 1
		_update_dev_ui()
		_update_visuals()
		
		# Когда сорвали ПОСЛЕДНЮЮ ягоду — запускаем созревание всей партии
		if current_berries <= 0:
			current_berries = 0
			is_ripening = true
			_ripen_timer = 0.0
			_update_dev_ui()
			print("[Berries] All berries harvested! Starting ripening cycle...")
			
		return true
	return false

## Возврат персональной рабочей точки для персонажа
func get_free_work_point(requester: Node3D = null) -> Vector3:
	var req_id: int = requester.get_instance_id() if requester else 0
	
	# Выделяем или берем существующий слот для этого персонажа
	var slot_index: int = 0
	if _occupied_slots.has(req_id):
		slot_index = _occupied_slots[req_id]
	else:
		slot_index = _find_next_free_slot_index()
		if req_id != 0:
			_occupied_slots[req_id] = slot_index

	# Если есть узлы WorkPoint в сцене — привязываем к ним
	if work_points_parent and work_points_parent.get_child_count() > 0:
		var children = work_points_parent.get_children()
		var point_node = children[slot_index % children.size()] as Node3D
		if point_node:
			return point_node.global_position

	# Иначе генерируем точки по кругу с радиусом 1.0м
	var angle: float = slot_index * (PI / 3.0) # Шаг 60 градусов
	var offset = Vector3(cos(angle), 0.0, sin(angle)) * 1.0
	return global_position + offset

## Освобождение точки при уходе персонажа
func release_work_point(requester: Node3D) -> void:
	if requester and _occupied_slots.has(requester.get_instance_id()):
		_occupied_slots.erase(requester.get_instance_id())

func _find_next_free_slot_index() -> int:
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
		dev_label.text = "Berries: %d/%d (Nutr: +%.0f)" % [current_berries, max_berries, nutrition_value]

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
