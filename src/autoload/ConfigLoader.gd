# ==============================================================================
# ФАЙЛ: src/autoload/ConfigLoader.gd
# НАЗНАЧЕНИЕ: Динамическое автоматическое сканирование и чтение ВСЕХ .ini
#            файлов из директории assets/config/
# ==============================================================================
extends Node

const CONFIG_DIR_PATH: String = "res://assets/config/"

# Словарь для хранения всех загруженных конфигураций:
# Имя файла без расширения -> ConfigFile (например: "berries" -> ConfigFile)
var _configs: Dictionary = {}

func _ready() -> void:
	load_all_configs()

## Автоматическое сканирование и загрузка всех .ini файлов из assets/config/
func load_all_configs() -> void:
	_configs.clear()
	var dir = DirAccess.open(CONFIG_DIR_PATH)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".ini"):
				var config_name = file_name.get_basename() # "berries.ini" -> "berries"
				var full_path = CONFIG_DIR_PATH + file_name
				var cfg = ConfigFile.new()
				var err = cfg.load(full_path)
				
				if err == OK:
					_configs[config_name] = cfg
					print("[ConfigLoader] Loaded config: ", file_name)
				else:
					push_error("[ConfigLoader] Failed to load %s (Error: %d)" % [full_path, err])
			file_name = dir.get_next()
		dir.list_dir_end()
		print(_configs)
	else:
		push_error("[ConfigLoader] Failed to open directory: " + CONFIG_DIR_PATH)

## Универсальный метод чтения любого ключа из любого .ini файла
## Пример: ConfigLoader.get_config_value("berries", "time", "work_time", 2.0)
func get_config_value(config_name: String, section: String, key: String, default_value: Variant = null) -> Variant:
	if _configs.has(config_name):
		return _configs[config_name].get_value(section, key, default_value)
	return default_value

# --- СОВМЕСТИМОСТЬ СО СТАРЫМИ ВЫЗОВАМИ ---

func get_game_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("game_config", section, key, default_value)

func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_game_value(section, key, default_value)

func get_character_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("character", section, key, default_value)
