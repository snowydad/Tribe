# ==============================================================================
# ФАЙЛ: src/autoload/ConfigLoader.gd
# ОБНОВЛЕНО: 2026-10-04 15:11 CEST — items.ini API
# НАЗНАЧЕНИЕ: Глобальный синглтон для чтения конфигурационных .ini файлов проекта.
#             Поддерживает автозагрузку всех конфигов из assets/config/,
#             универсальный метод get_config_value(config_name, section, key),
#             а также сохраняет полную обратную совместимость со всеми старыми геттерами.
# ==============================================================================
extends Node

const CONFIG_DIR_PATH: String = "res://assets/config/"

## Словарь всех загруженных файлов: { "character": ConfigFile, "storage": ConfigFile, ... }
var _configs: Dictionary = {}

## Псевдонимы имён конфигов для гибкого поиска
var _aliases: Dictionary = {
	"skills": "character_skills",
	"character_skills": "character_skills",
	"character": "character",
	"game": "game_config",
	"game_config": "game_config",
	"berries": "berries",
	"storage": "storage",
	"obstacle": "obstacle",
	"shelter": "shelter",
	"names": "names",
	"items": "items"
}

# Ссылки для 100% обратной совместимости
var _character_config: ConfigFile = ConfigFile.new()
var _skills_config: ConfigFile = ConfigFile.new()
var _game_config: ConfigFile = ConfigFile.new()
var _berries_config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	load_all_configs()

## Загружает или перезагружает все текстовые .ini конфигурации
func load_all_configs() -> void:
	_configs.clear()

	# 1. Автоматическое сканирование директории assets/config/
	var dir = DirAccess.open(CONFIG_DIR_PATH)
	if dir:
		for file_name in dir.get_files():
			if file_name.ends_with(".ini"):
				var cfg_key = file_name.get_basename().to_lower()
				var full_path = CONFIG_DIR_PATH.path_join(file_name)
				_load_single_config(cfg_key, full_path)
	else:
		push_warning("[ConfigLoader] Cannot open config directory: %s" % CONFIG_DIR_PATH)

	# 2. Гарантированная загрузка базовых конфигов (включая экспортные сборки)
	var fallback_configs = {
		"character": "res://assets/config/character.ini",
		"character_skills": "res://assets/config/character_skills.ini",
		"game_config": "res://assets/config/game_config.ini",
		"berries": "res://assets/config/berries.ini",
		"storage": "res://assets/config/storage.ini",
		"obstacle": "res://assets/config/obstacle.ini",
		"shelter": "res://assets/config/shelter.ini",
		"names": "res://assets/config/names.ini"
	}
	for cfg_name in fallback_configs.keys():
		if not _configs.has(cfg_name):
			_load_single_config(cfg_name, fallback_configs[cfg_name])

	# 3. Синхронизация старых ссылок для обратной совместимости
	_character_config = _configs.get("character", ConfigFile.new())
	_skills_config = _configs.get("character_skills", ConfigFile.new())
	_game_config = _configs.get("game_config", ConfigFile.new())
	_berries_config = _configs.get("berries", ConfigFile.new())

func _load_single_config(config_name: String, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var config_file = ConfigFile.new()
	var err = config_file.load(path)
	if err == OK:
		_configs[config_name] = config_file
		print("[ConfigLoader] %s config loaded successfully: %s" % [config_name, path])
	else:
		push_warning("[ConfigLoader] Failed to load %s config from %s (Error code: %d)" % [config_name, path, err])

## Нормализация имени конфига с учётом расширения и алиасов
func _resolve_config_name(config_name: String) -> String:
	var clean_name = config_name.strip_edges().to_lower()
	if clean_name.ends_with(".ini"):
		clean_name = clean_name.trim_suffix(".ini")
	return _aliases.get(clean_name, clean_name)

## Возвращает объект ConfigFile по имени конфига
func get_config_file(config_name: String) -> ConfigFile:
	var resolved = _resolve_config_name(config_name)
	return _configs.get(resolved, null)

## Проверяет существование секции и ключа в указанном конфиге
func has_config_key(config_name: String, section: String, key: String) -> bool:
	var cfg = get_config_file(config_name)
	if cfg:
		return cfg.has_section_key(section, key)
	return false

# ==============================================================================
# ОСНОВНОЙ УНИВЕРСАЛЬНЫЙ API ЧТЕНИЯ
# ==============================================================================

## Универсальное безопасное чтение значения из конкретного .ini файла
## Пример: ConfigLoader.get_config_value("storage", "work", "base_work_time", 1.0)
func get_config_value(config_name: String, section: String, key: String, default_value: Variant = null) -> Variant:
	var cfg = get_config_file(config_name)
	if cfg and cfg.has_section_key(section, key):
		return cfg.get_value(section, key, default_value)
	return default_value

## Возвращает список всех секций конфига
func get_sections(config_name: String) -> PackedStringArray:
	var cfg = get_config_file(config_name)
	if cfg:
		return cfg.get_sections()
	return PackedStringArray()

## Возвращает список всех ключей заданной секции
func get_section_keys(config_name: String, section: String) -> PackedStringArray:
	var cfg = get_config_file(config_name)
	if cfg and cfg.has_section(section):
		return cfg.get_section_keys(section)
	return PackedStringArray()

# ==============================================================================
# МЕТОДЫ ОБРАТНОЙ СОВМЕСТИМОСТИ И БЫСТРЫЕ ГЕТТЕРЫ
# ==============================================================================

## Универсальный метод сквозного поиска по базовым конфигам (для TimeManager и др.)
func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	var search_order = ["game_config", "character", "character_skills", "items", "berries", "storage", "obstacle", "shelter"]
	for cfg_name in search_order:
		var cfg = get_config_file(cfg_name)
		if cfg and cfg.has_section_key(section, key):
			return cfg.get_value(section, key, default_value)
	return default_value

## Получение значений из character.ini
func get_character_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("character", section, key, default_value)

## Получение значений из character_skills.ini
func get_skill_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("character_skills", section, key, default_value)

## Получение значений из game_config.ini
func get_game_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("game_config", section, key, default_value)

## Получение значений из berries.ini
func get_berries_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("berries", section, key, default_value)

## Получение значений из storage.ini
func get_storage_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("storage", section, key, default_value)

## Получение значений из obstacle.ini
func get_obstacle_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("obstacle", section, key, default_value)

## Получение значений из shelter.ini
func get_shelter_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("shelter", section, key, default_value)

# ==============================================================================
# ITEMS.INI — edible / nutrition (новые продукты — в items.ini, не в character)
# ==============================================================================

func resolve_item_id(raw_id: String) -> String:
	var id := str(raw_id).strip_edges().to_lower()
	if id.is_empty():
		return "food"
	var alias = get_config_value("items", "aliases", id, null)
	if alias != null and str(alias).strip_edges() != "":
		return str(alias).strip_edges().to_lower()
	if has_config_key("items", id, "edible") or has_config_key("items", id, "nutrition"):
		return id
	if id.ends_with("s") and id.length() > 1:
		var singular := id.substr(0, id.length() - 1)
		if has_config_key("items", singular, "edible") or has_config_key("items", singular, "nutrition"):
			return singular
	return id


func get_item_value(item_id: String, key: String, default_value: Variant = null) -> Variant:
	return get_config_value("items", resolve_item_id(item_id), key, default_value)


func is_item_edible(item_id: String, default_if_unknown: bool = false) -> bool:
	if str(item_id).strip_edges().is_empty():
		return bool(get_item_value("food", "edible", true))
	var id := resolve_item_id(item_id)
	if has_config_key("items", id, "edible"):
		return bool(get_item_value(id, "edible", default_if_unknown))
	return default_if_unknown


func get_item_nutrition(item_id: String, default_value: float = 25.0) -> float:
	var id := resolve_item_id(item_id)
	if str(item_id).strip_edges().is_empty():
		id = "food"
	return float(get_item_value(id, "nutrition", default_value))


func get_item_display_name(item_id: String) -> String:
	var id := resolve_item_id(item_id)
	return str(get_item_value(id, "display_name", id))
