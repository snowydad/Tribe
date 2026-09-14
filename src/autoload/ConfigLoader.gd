# ==============================================================================
# ФАЙЛ: src/autoload/ConfigLoader.gd
# НАЗНАЧЕНИЕ: Глобальный менеджер для чтения и хранения настроек из .ini файлов.
# ==============================================================================
extends Node

const GAME_CONFIG_PATH: String = "res://assets/config/game_config.ini"

var _game_config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	load_game_config()

## Загружает или перезагружает основной файл конфигурации
func load_game_config() -> void:
	var err = _game_config.load(GAME_CONFIG_PATH)
	if err == OK:
		print("[ConfigLoader] Конфигурация успешно загружена: ", GAME_CONFIG_PATH)
	else:
		push_error("[ConfigLoader] Не удалось загрузить конфиг! Код ошибки: %d" % err)

## Универсальный метод получения значений из game_config.ini
## Если секция или ключ не найдены, возвращает default_value
func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	return _game_config.get_value(section, key, default_value)
