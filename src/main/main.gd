# ==============================================================================
# ФАЙЛ: src/objects/berries.gd
# НАЗНАЧЕНИЕ: Контроллер куста ягод 'berries' с партионным созреванием 5 ягод.
# ==============================================================================
extends Node3D

@export var max_berries: int = 5        # Вся партия = 5 ягод
@export var ripening_time: float = 15.0   # Время полного созревания всей партии

var current_berries: int = 0
var is_ripening: bool = false
var _ripen_timer: float = 0.0

func _ready() -> void:
	current_berries = max_berries # На старте куст полностью спелый (5 ягод)
	_update_visuals()

## Проверка наличия ягод для сбора
func has_berries() -> bool:
	return current_berries > 0

## Сбор 1 ягоды персонажем
func harvest_berry() -> bool:
	if current_berries > 0:
		current_berries -= 1
		_update_visuals()
		
		# Когда сорвали ПОСЛЕДНЮЮ (5-ю) ягоду — куст запускает таймер созревания
		if current_berries == 0:
			is_ripening = true
			_ripen_timer = 0.0
			print("[Berries] All 5 berries harvested! Starting full crop ripening...")
		return true
	return false

func _process(delta: float) -> void:
	# Таймер тикает ТОЛЬКО когда куст полностью пуст (0 ягод)
	if is_ripening:
		_ripen_timer += delta
		if _ripen_timer >= ripening_time:
			is_ripening = false
			current_berries = max_berries # ВСЯ ПАРТИЯ (5 ЯГОД) СОЗРЕВАЕТ ОДНОВРЕМЕННО
			_update_visuals()
			print("[Berries] Crop is fully ripe! All 5 berries restored.")

func _update_visuals() -> void:
	# Логика скрытия/отображения мешей ягод на ветках
	pass
