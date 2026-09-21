# ==============================================================================
# ФАЙЛ: src/environment/Berries.gd
# НАЗНАЧЕНИЕ: Интерактивный куст ягод с выведением прогресса созревания в %
#            на отладочной плашке DevLabel
# ==============================================================================
extends Node3D

@export var max_berries: int = 5
@export var current_berries: int = 5

var work_time: float = 3.0   # Время сбора 1 ягоды (из berries.ini)
var ripen_time: float = 120.0 # Время созревания 1 новой ягоды (из berries.ini)
var _ripen_timer: float = 0.0

@onready var work_points_container: Node3D = $WorkPoints
@onready var dev_label: Label3D = get_node_or_null("DevLabel")

func _ready() -> void:
	add_to_group("interactable")
	current_berries = max_berries
	
	# Читаем параметры из assets/config/berries.ini
	if ConfigLoader and ConfigLoader.has_method("get_config_value"):
		work_time = ConfigLoader.get_config_value("berries", "time", "work_time", 3.0)
		ripen_time = ConfigLoader.get_config_value("berries", "time", "ripen_time", 120.0)
		print("[Berries] Loaded config -> work_time: %.1f, ripen_time: %.1f" % [work_time, ripen_time])

	_update_dev_ui()

func _process(delta: float) -> void:
	# Логика созревания ягод, если куст не заполнен до максимума
	if current_berries < max_berries:
		_ripen_timer += delta
		if _ripen_timer >= ripen_time:
			_ripen_timer = 0.0
			current_berries += 1
			print("[Berries] A new berry ripened! Total: ", current_berries, "/", max_berries)
		_update_dev_ui()

## Возвращает время работы, требуемое для сбора одной ягоды
func get_work_time() -> float:
	return work_time

## Проверка наличия ягод на кусте
func has_berries() -> bool:
	return current_berries > 0

## Сбор 1 ягоды с куста
func harvest_berry() -> bool:
	if current_berries > 0:
		current_berries -= 1
		print("[Berries] Berry harvested! Remaining: ", current_berries, "/", max_berries)
		_update_dev_ui()
		if current_berries <= 0:
			print("[Berries] Bush is now empty!")
		return true
	return false

## Возвращает координаты свободной точки WorkPoint рядом с кустом
func get_free_work_point(_character: Node3D = null) -> Vector3:
	if work_points_container and work_points_container.get_child_count() > 0:
		var points = work_points_container.get_children()
		var random_point = points[randi() % points.size()] as Node3D
		if random_point:
			return random_point.global_position
	return global_position

## Обновление отладочной плашки над кустом
func _update_dev_ui() -> void:
	if not dev_label:
		return
		
	if current_berries < max_berries:
		var ripen_pct: float = (_ripen_timer / ripen_time) * 100.0
		dev_label.text = "Berries: %d/%d\nWork: %.1fs\nRipen: %.0f%%" % [
			current_berries, max_berries, work_time, ripen_pct
		]
	else:
		dev_label.text = "Berries: %d/%d (Full)\nWork: %.1fs" % [
			current_berries, max_berries, work_time
		]
