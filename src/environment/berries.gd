# ==============================================================================
# ФАЙЛ: src/environment/Berries.gd
# НАЗНАЧЕНИЕ: Источник еды (Куст с ягодами / Ягодник)
# ==============================================================================
class_name Berries
extends Node3D

@export var resource_type: String = "berry"
@export var berries_available: int = 10
@export var nutrition_per_berry: float = 20.0
@export var gather_time: float = 1.5

@onready var dev_label: Label3D = $DevLabel

func _ready() -> void:
	_update_dev_ui()

## Забрать 1 ягоду (возвращает true, если ягода была успешно собрана)
func harvest_berry() -> bool:
	if berries_available > 0:
		berries_available -= 1
		_update_dev_ui()
		return true
	return false

## Отладочная плашка над объектом
func _update_dev_ui() -> void:
	if not dev_label:
		return
		
	if berries_available > 0:
		dev_label.text = "BERRIES\nAvailable: %d" % berries_available
	else:
		dev_label.text = "BERRIES\n[EMPTY]"
