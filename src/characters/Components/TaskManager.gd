# ==============================================================================
# ФАЙЛ: src/characters/components/TaskManager.gd
# НАЗНАЧЕНИЕ: Менеджер задач и приоритетов персонажа (TaskManager).
#             Управляет стеком повседневных работ (сбор, доставка, расчистка)
#             и сценических прерываний (поедание еды, ожидания, ручные команды игрока).
# ==============================================================================
class_name TaskManager
extends Node

## Типы поддерживаемых задач
enum TaskType {
	NONE,          # Нет задачи
	MOVE_TO,       # Обычное перемещение в точку на земле
	WAIT_IDLE,     # Пауза/ожидание на месте
	GATHER,        # Сбор ягод/ресурсов с куста
	DELIVER,       # Доставка и разгрузка ресурса на склад
	EAT,           # Поедание имеющейся еды (из рук)
	CLEAR,         # Расчистка завала/сухостоя
	BUILD          # Строительство укрытия/шалаша
}

## Класс единичной задачи в стеке
class Task:
	var type: TaskType = TaskType.NONE
	var target_node: Node3D = null
	var target_pos: Vector3 = Vector3.ZERO
	var priority: int = 0             # Чем выше число, тем раньше выполняется
	var wait_timer: float = 0.0       # Длительность таймера ожидания
	var is_user_command: bool = false # Вызвана ли задача прямым действием игрока
	var is_persistent: bool = false   # Фоновая бессрочная задача (например, сбор ягод)

	func _init(p_type: TaskType = TaskType.NONE, p_pos: Vector3 = Vector3.ZERO, p_node: Node3D = null, p_priority: int = 0, p_persistent: bool = false) -> void:
		type = p_type
		target_pos = p_pos
		target_node = p_node
		priority = p_priority
		is_persistent = p_persistent

# --- СВОЙСТВА И СИГНАЛЫ ---
var _queue: Array[Task] = []
var _current_task: Task = null

signal task_started(task: Task)
signal task_completed(task: Task)
signal queue_changed

# ------------------------------------------------------------------------------
# МЕТОДЫ УПРАВЛЕНИЯ СТЕКОМ ЗАДАЧ
# ------------------------------------------------------------------------------

## Установить или заменить главную фоновую работу (например, сбор ягод у куста)
func set_persistent_task(task: Task) -> void:
	task.is_persistent = true
	# Очищаем старые фоновые задачи того же типа
	var filtered: Array[Task] = []
	for t in _queue:
		if not t.is_persistent:
			filtered.append(t)
	_queue = filtered
	_queue.push_back(task)
	_sort_tasks()
	queue_changed.emit()

## Добавить приоритетную субзадачу (например, поесть или отнести ресурс на склад)
func push_subtask(task: Task) -> void:
	if task.priority == 0:
		task.priority = 50
	_queue.push_front(task)
	_sort_tasks()
	queue_changed.emit()

## Установить прямую команду игрока (клик / Context Drop)
func set_user_override_task(task: Task) -> void:
	task.priority = 100
	task.is_user_command = true
	
	# Сохраняем текущую фоновую задачу, если она была
	if _current_task != null and _current_task.is_persistent:
		_queue.push_back(_current_task)
	
	_current_task = null
	
	# Оставляем в очереди только фоновые работы
	var persistent_tasks: Array[Task] = []
	for t in _queue:
		if t.is_persistent:
			persistent_tasks.append(t)
	_queue = persistent_tasks
	
	_queue.push_front(task)
	_sort_tasks()
	queue_changed.emit()

## Сортировка очереди по приоритету
func _sort_tasks() -> void:
	_queue.sort_custom(func(a: Task, b: Task) -> bool: return a.priority > b.priority)

## Запросить текущую активную задачу
func get_current_task() -> Task:
	if _current_task != null:
		return _current_task
		
	if _queue.size() > 0:
		_current_task = _queue.pop_front()
		task_started.emit(_current_task)
		queue_changed.emit()
		return _current_task
		
	return null

## Отметить текущую задачу как выполненную
func complete_current_task() -> void:
	if _current_task != null:
		task_completed.emit(_current_task)
		_current_task = null
		queue_changed.emit()

## Отменить текущую задачу и перейти к следующей
func cancel_current_task() -> void:
	_current_task = null
	queue_changed.emit()

## Очистить весь стек задач
func clear_all() -> void:
	_queue.clear()
	_current_task = null
	queue_changed.emit()

## Проверка наличия задач
func has_tasks() -> bool:
	return _current_task != null or _queue.size() > 0

## Название текущей активной задачи для UI
func get_current_task_debug_name() -> String:
	if _current_task == null:
		return "NONE"
	match _current_task.type:
		TaskType.MOVE_TO: return "MOVE_TO"
		TaskType.WAIT_IDLE: return "WAIT_IDLE"
		TaskType.GATHER: return "GATHER"
		TaskType.DELIVER: return "DELIVER"
		TaskType.EAT: return "EAT"
		TaskType.CLEAR: return "CLEAR"
		TaskType.BUILD: return "BUILD"
		_: return "UNKNOWN"
