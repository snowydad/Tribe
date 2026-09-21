# ==============================================================================
# ФАЙЛ: src/environment/Storage.gd
# НАЗНАЧЕНИЕ: Интерактивный склад/поляна с выведением отладочной инфы на DevLabel
#            и поддержкой параметров из assets/config/storage.ini
# ==============================================================================
extends Node3D

@export var stored_food: int = 0

var work_time: float = 1.0 # Время разгрузки (запасное значение)

@onready var work_points_container: Node3D = $WorkPoints
@onready var dev_label: Label3D = get_node_or_null("DevLabel")

func _ready() -> void:
	add_to_group("storage")
	add_to_group("interactable")
	
	# Читаем время работы из assets/config/storage.ini
	if ConfigLoader and ConfigLoader.has_method("get_config_value"):
		work_time = ConfigLoader.get_config_value("storage", "time", "work_time", 1.0)
		print("[Storage] Loaded work_time from storage.ini: ", work_time)

	_update_dev_ui()

## Возвращает время работы, требуемое для разгрузки еды на склад
func get_work_time() -> float:
	return work_time

## Приём еды на склад
func deposit_food(amount: int) -> void:
	stored_food += amount
	print("[Storage] Food deposited: +", amount, " | Total stored food: ", stored_food)
	_update_dev_ui()

## Возвращает координаты свободной точки WorkPoint рядом со складом
func get_free_work_point(_character: Node3D = null) -> Vector3:
	if work_points_container and work_points_container.get_child_count() > 0:
		var points = work_points_container.get_children()
		var random_point = points[randi() % points.size()] as Node3D
		if random_point:
			return random_point.global_position
	return global_position

## Обновление отладочной плашки над складом
func _update_dev_ui() -> void:
	if not dev_label:
		return
	dev_label.text = "Storage Food: %d\nWork: %.1fs" % [stored_food, work_time]
