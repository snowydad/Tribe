# ==============================================================================
# ФАЙЛ: src/environment/Storage.gd
# НАЗНАЧЕНИЕ: Хранилище ресурсов племени (Склад / Поляна)
# ==============================================================================
class_name Storage
extends Node3D

# Словарь хранимых ресурсов: {"berry": 12, "fish": 0}
@export var stored_resources: Dictionary = {
	"berry": 0
}

@onready var dev_label: Label3D = $DevLabel

func _ready() -> void:
	_update_dev_ui()

## Добавить еду на склад
func deposit_food(food_type: String, amount: int) -> void:
	stored_resources[food_type] = stored_resources.get(food_type, 0) + amount
	print("[Storage] Deposited %d of %s. Total %s: %d" % [amount, food_type, food_type, stored_resources[food_type]])
	_update_dev_ui()

## Забрать еду со склада (возвращает реально забранное количество)
func withdraw_food(food_type: String, requested_amount: int) -> int:
	var current_amount: int = stored_resources.get(food_type, 0)
	var taken_amount: int = mini(current_amount, requested_amount)
	
	if taken_amount > 0:
		stored_resources[food_type] -= taken_amount
		print("[Storage] Withdrawn %d of %s. Remaining: %d" % [taken_amount, food_type, stored_resources[food_type]])
		_update_dev_ui()
		
	return taken_amount

## Возвращает общее количество всей еды на складе
func get_total_food_count() -> int:
	var total: int = 0
	for count in stored_resources.values():
		total += count
	return total

## Отладочная плашка над складом
func _update_dev_ui() -> void:
	if not dev_label:
		return
		
	var text_info = "STORAGE\n"
	text_info += "Total Food: %d\n" % get_total_food_count()
	for type_name in stored_resources:
		text_info += "%s: %d\n" % [type_name.capitalized(), stored_resources[type_name]]
		
	dev_label.text = text_info
