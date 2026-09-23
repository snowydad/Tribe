# ==============================================================================
# ФАЙЛ: src/autoload/ConfigLoader.gd
# НАЗНАЧЕНИЕ: Глобальный синглтон для чтения конфигурационных .ini файлов проекта.
#             Загружает базовые параметры персонажа (character.ini),
#             систему навыков/талантов (character_skills.ini) и
#             глобальные настройки игры (game_config.ini).
# ==============================================================================
extends Node

const CHARACTER_CONFIG_PATH: String = "res://assets/config/character.ini"
const SKILLS_CONFIG_PATH: String = "res://assets/config/character_skills.ini"
const GAME_CONFIG_PATH: String = "res://assets/config/game_config.ini"

var _character_config: ConfigFile = ConfigFile.new()
var _skills_config: ConfigFile = ConfigFile.new()
var _game_config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	load_all_configs()

## Загружает или перезагружает все текстовые .ini конфигурации
func load_all_configs() -> void:
	_load_single_config(_character_config, CHARACTER_CONFIG_PATH, "Character")
	_load_single_config(_skills_config, SKILLS_CONFIG_PATH, "Skills")
	_load_single_config(_game_config, GAME_CONFIG_PATH, "Game")

func _load_single_config(config_file: ConfigFile, path: String, config_name: String) -> void:
	var err = config_file.load(path)
	if err == OK:
		print("[ConfigLoader] %s config loaded successfully: %s" % [config_name, path])
	else:
		push_warning("[ConfigLoader] Failed to load %s config from %s (Error code: %d)" % [config_name, path, err])

## Универсальный метод получения значений для обратной совместимости (используется в TimeManager и др.)
func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	if _game_config.has_section_key(section, key):
		return _game_config.get_value(section, key, default_value)
	if _character_config.has_section_key(section, key):
		return _character_config.get_value(section, key, default_value)
	if _skills_config.has_section_key(section, key):
		return _skills_config.get_value(section, key, default_value)
	return default_value

## Безопасное получение значений из character.ini (базовые статы, навигация, возраст)
func get_character_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return _character_config.get_value(section, key, default_value)

## Безопасное получение значений из character_skills.ini (таланты, начальные навыки, прогрессия)
func get_skill_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return _skills_config.get_value(section, key, default_value)

## Безопасное получение значений из game_config.ini (глобальные настройки)
func get_game_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return _game_config.get_value(section, key, default_value)
