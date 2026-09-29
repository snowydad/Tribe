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
	EAT,           # Поедание имеющейся еды (из рук или со склада)
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
	var is_user_command: bool = false # Вызвана ли задача прямым действием игрока (Drag & Drop)
	var is_persistent: bool = false   # Фоновая бессрочная задача (например, цикл работы у куста)

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

## Добавить фоновую/обычную задачу в стек
func push_task(task: Task) -> void:
	# Избегаем дублирования одинаковой задачи на тот же объект
	for existing in _queue:
		if existing.type == task.type and existing.target_node == task.target_node and task.target_node != null:
			return
			
	_queue.append(task)
	sort_tasks()
	queue_changed.emit()

## Добавить приоритетную задачу (например, поесть при голоде или доставить при полном инвентаре)
func push_subtask(task: Task) -> void:
	# Субзадача ставится поверх текущей очереди
	if task.priority == 0:
		task.priority = 50
	_queue.push_front(task)
	sort_tasks()
	queue_changed.emit()

## Назначить прямую ручную команду игрока (Drag & Drop / клик).
## Перекрывает текущую деятельность, но сохраняет фоновую работу на дне стека.
func set_user_override_task(task: Task) -> void:
	task.priority = 100
	task.is_user_command = true
	
	# Если сейчас выполнялась фоновая работа — сохраняем её обратно в стек
	if _current_task != null and not _current_task.is_user_command:
		_queue.push_back(_current_task)
		_current_task = null
		
	# Очищаем временные субзадачи, оставляя только фоновые
	var persistent_tasks: Array[Task] = []
	for t in _queue:
		if t.is_persistent:
			persistent_tasks.append(t)
	_queue = persistent_tasks
	
	_queue.push_front(task)
	queue_changed.emit()

## Сортировка очереди по приоритету
func sort_tasks() -> void:
	_queue.sort_custom(func(a: Task, b: Task) -> bool: return a.priority > b.priority)

## Запросить и активировать следующую главную задачу из стека
func get_current_task() -> Task:
	if _current_task != null:
		return _current_task
		
	if _queue.size() > 0:
		_current_task = _queue.pop_front()
		task_started.emit(_current_task)
		queue_changed.emit()
		return _current_task
		
	return null

## Завершить текущую активную задачу (например, доставку или поедание)
func complete_current_task() -> void:
	if _current_task != null:
		task_completed.emit(_current_task)
		_current_task = null
		queue_changed.emit()

## Принудительно отменить текущую задачу и вернуться к предыдущей
func cancel_current_task() -> void:
	_current_task = null
	queue_changed.emit()

## Очистить всю очередь задач
func clear_all() -> void:
	_queue.clear()
	_current_task = null
	queue_changed.emit()

## Проверка наличия задач
func has_tasks() -> bool:
	return _current_task != null or _queue.size() > 0

## Название текущей активной задачи для отладки
func get_current_task_debug_name() -> String:
	if _current_task == null:
		return "NONE"
	match _current_task.type:
		TaskType.MOVE_TO: return "MOVE_TO"
		TaskType.WAIT_IDLE: return "WAIT_IDLE"
		TaskType.GATHER: return "GATHER"
		TaskType.DELIVER: return "DELIVER"
		TaskType.EAT: return "EATING"
		TaskType.CLEAR: return "CLEAR"
		TaskType.BUILD: return "BUILD"
		_: return "UNKNOWN"
