# ==============================================================================
# ФАЙЛ: src/autoload/Logger.gd
# НАЗНАЧЕНИЕ: Глобальный синглтон логирования в текстовый файл.
#             Автоматически создаёт папку Documents/Tribe/ на Windows
#             и записывает подробный отладочный лог (конфиги, FSM, статы).
# ==============================================================================
extends Node

var log_file_path: String = ""
var _file_access: FileAccess = null

func _ready() -> void:
	_init_logger()

func _init_logger() -> void:
	var docs_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs_dir.is_empty():
		docs_dir = "user://"
		
	var tribe_dir = docs_dir.path_join("Tribe")
	
	var err = DirAccess.make_dir_recursive_absolute(tribe_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("[Logger] Failed to create directory: %s" % tribe_dir)
		
	log_file_path = tribe_dir.path_join("tribe_debug.log")
	
	# Перезаписываем лог при каждом новом запуске игры
	_file_access = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _file_access:
		log_info("==================================================")
		log_info("TRIBE GAME LOG SESSION STARTED: %s" % Time.get_datetime_string_from_system(false, true))
		log_info("Log Location: %s" % log_file_path)
		log_info("==================================================")
	else:
		push_error("[Logger] Could not open log file at: %s" % log_file_path)

## Общий информационный лог
func log_info(msg: String) -> void:
	_write_entry("INFO", msg)

## Логирование считывания параметров из .ini файлов
func log_config(config_name: String, section: String, key: String, value: Variant) -> void:
	_write_entry("CONFIG", "[%s.ini] [%s] %s = %s" % [config_name, section, key, str(value)])

## Логирование смены состояний FSM
func log_fsm(entity_name: String, old_state: String, new_state: String) -> void:
	_write_entry("FSM", "[%s] State: %s -> %s" % [entity_name, old_state, new_state])

## Запись строки в файл с мгновенным флашем на диск
func _write_entry(level: String, msg: String) -> void:
	var time_str = Time.get_time_string_from_system()
	var formatted = "[%s][%s] %s" % [time_str, level, msg]
	
	print(formatted) # Запись в консоль Godot
	
	if _file_access:
		_file_access.store_line(formatted)
		_file_access.flush() # Мгновенный сброс буфера на диск

func _exit_tree() -> void:
	if _file_access:
		log_info("TRIBE GAME LOG SESSION ENDED")
		_file_access.close()
