# ==============================================================================
# ФАЙЛ: src/objects/berries.gd
# НАЗНАЧЕНИЕ: Контроллер куста ягод 'berries' с партионным созреванием 5 ягод
#            и отображением прогресса созревания в процентах на DevLabel.
# ==============================================================================
extends Node3D

@export_group("Crop Settings")
@export var max_berries: int = 5           # Вся партия = 5 ягод
@export var ripening_time: float = 15.0      # Время созревания всей партии (в секундах)
@export var work_time: float = 2.0           # Время сбора 1 ягоды

@export_group("Work Points")
@export var work_points_parent: Node3D       # Узел-родитель для точек WorkPoint (необязательно)

@onready var dev_label: Label3D = $DevLabel

var current_berries: int = 5
var is_ripening: bool = false
var _ripen_timer: float = 0.0

func _ready() -> void:
	add_to_group("berries")
	_ensure_dev_label_exists()
	
	# При старте куст гарантированно полон спелых ягод
	if current_berries <= 0 and not is_ripening:
		current_berries = max_berries
	
	_update_dev_ui()

func _process(delta: float) -> void:
	# Таймер созревания тикает ТОЛЬКО когда куст полностью опустел (0 ягод)
	if is_ripening:
		_ripen_timer += delta
		if _ripen_timer >= ripening_time:
			is_ripening = false
			_ripen_timer = 0.0
			current_berries = max_berries # ВЕСЬ УРОЖАЙ (5 ЯГОД) СОЗРЕВАЕТ ОДНОВРЕМЕННО!
			print("[Berries] Crop fully ripe! All %d berries restored." % max_berries)
		_update_dev_ui()

## Проверка наличия спелых ягод для Character.gd
func has_berries() -> bool:
	return current_berries > 0 and not is_ripening

## Время сбора 1 ягоды для Character.gd
func get_work_time() -> float:
	return work_time

## Сбор 1 ягоды персонажем. ОБЯЗАТЕЛЬНО возвращает bool (true = успешно)
func harvest_berry() -> bool:
	if current_berries > 0 and not is_ripening:
		current_berries -= 1
		_update_dev_ui()
		
		# Когда сорвали ПОСЛЕДНЮЮ (5-ю) ягоду — куст запускает таймер созревания партии
		if current_berries <= 0:
			current_berries = 0
			is_ripening = true
			_ripen_timer = 0.0
			print("[Berries] All 5 berries harvested! Starting ripening timer (%.1f s)..." % ripening_time)
			_update_dev_ui()
			
		return true # КРИТИЧЕСКИ ВАЖНО для Character.gd!
	
	return false

## Безопасный возврат рабочей точки для Context Drop
func get_free_work_point(_requester: Node3D = null) -> Vector3:
	if work_points_parent and work_points_parent.get_child_count() > 0:
		var children = work_points_parent.get_children()
		var random_point = children[randi() % children.size()] as Node3D
		if random_point:
			return random_point.global_position
			
	# Дефолтная точка рядом с кустом
	return global_position + Vector3(0.8, 0.0, 0.0)

## Автоматическое создание/поиск плашки DevLabel над кустом
func _ensure_dev_label_exists() -> void:
	if not dev_label:
		dev_label = get_node_or_null("DevLabel") as Label3D
	if not dev_label:
		dev_label = Label3D.new()
		dev_label.name = "DevLabel"
		dev_label.position = Vector3(0, 1.5, 0)
		dev_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dev_label.no_depth_test = true
		dev_label.pixel_size = 0.005
		dev_label.modulate = Color(1.0, 0.85, 0.2) # Желтый оттенок для ресурса
		add_child(dev_label)

## Вывод количества ягод и прогресса созревания в процентах
func _update_dev_ui() -> void:
	if not dev_label:
		_ensure_dev_label_exists()
	if not dev_label:
		return
		
	if is_ripening:
		var pct: int = int(clamp((_ripen_timer / ripening_time) * 100.0, 0.0, 100.0))
		dev_label.text = "Berries: 0/%d\n[Ripening: %d%%]" % [max_berries, pct]
	else:
		dev_label.text = "Berries: %d/%d" % [current_berries, max_berries]
