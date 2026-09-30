# ==============================================================================
# ФАЙЛ: src/autoload/TimeManager.gd
# НАЗНАЧЕНИЕ: Менеджер времени (Биологический год + Визуальный день/ночь + Офлайн)
# ==============================================================================
extends Node

# Сигналы времени
signal year_passed(total_years: int)
signal day_night_cycle_updated(progress: float) # От 0.0 до 1.0 (для вращения солнца)

const SAVE_PATH: String = "user://time_data.json"

# Настройки из game_config.ini
var seconds_per_year: float = 86400.0
var day_night_cycle_seconds: float = 900.0

var current_year: int = 1

var _year_timer: float = 0.0
var _day_night_timer: float = 0.0

func _ready() -> void:
	# 1. Читаем параметры из секции [time_settings]
	seconds_per_year = ConfigLoader.get_value("time_settings", "seconds_per_year", 86400.0)
	day_night_cycle_seconds = ConfigLoader.get_value("time_settings", "day_night_cycle_seconds", 900.0)
	
	print("[TimeManager] Time initialized. 1 Year = ", seconds_per_year, "s | Day/Night cycle = ", day_night_cycle_seconds, "s")
	
	# 2. Считываем офлайн-прогресс
	_calculate_offline_time()

func _process(delta: float) -> void:
	# --- Биологический таймер (Год и Старение) ---
	_year_timer += delta
	if _year_timer >= seconds_per_year:
		_year_timer -= seconds_per_year
		_advance_year(1)
		
	# --- Визуальный таймер (День / Ночь) ---
	_day_night_timer += delta
	if _day_night_timer >= day_night_cycle_seconds:
		_day_night_timer = fmod(_day_night_timer, day_night_cycle_seconds)
		
	# Высылаем прогресс дня для вращения солнца (от 0.0 до 1.0)
	var cycle_progress: float = _day_night_timer / day_night_cycle_seconds
	day_night_cycle_updated.emit(cycle_progress)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_current_timestamp()

## Продвижение возраста на N лет
func _advance_year(years_to_add: int) -> void:
	for i in range(years_to_add):
		current_year += 1
		print("[TimeManager] Year passed! Current Year: ", current_year)
		year_passed.emit(current_year)
	
	_save_current_timestamp()

# ------------------------------------------------------------------------------
# ОФЛАЙН РАСЧЕТ
# ------------------------------------------------------------------------------

func _save_current_timestamp() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"last_timestamp": Time.get_unix_time_from_system(),
			"current_year": current_year,
			"year_timer": _year_timer
		}
		file.store_string(JSON.stringify(data))
		print("[TimeManager] Time state saved.")

func _calculate_offline_time() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_save_current_timestamp()
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
		
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		var last_time: float = data.get("last_timestamp", Time.get_unix_time_from_system())
		current_year = data.get("current_year", 1)
		_year_timer = data.get("year_timer", 0.0)
		
		var now: float = Time.get_unix_time_from_system()
		var elapsed_seconds: float = now - last_time
		
		if elapsed_seconds > 0:
			_year_timer += elapsed_seconds
			var passed_years: int = int(_year_timer / seconds_per_year)
			_year_timer = fmod(_year_timer, seconds_per_year)
			
			if passed_years > 0:
				print("[TimeManager] Offline progress: ", elapsed_seconds, "s passed (", passed_years, " years)")
				_advance_year(passed_years)


# ------------------------------------------------------------------------------
# ПУБЛИЧНОЕ API ДЛЯ UI
# ------------------------------------------------------------------------------

## Год.месяц, напр. "11.1" (месяц 1..12 из прогресса текущего года)
func get_display_year_month() -> String:
	var month := get_month()
	return "%d.%d" % [current_year, month]

## Месяц 1..12 (равномерные доли года)
func get_month() -> int:
	if seconds_per_year <= 0.0:
		return 1
	var frac: float = clampf(_year_timer / seconds_per_year, 0.0, 0.9999)
	return int(frac * 12.0) + 1

## Полное игровое время с старта мира (секунды симуляции)
func get_total_game_seconds() -> float:
	return float(max(current_year - 1, 0)) * seconds_per_year + _year_timer

func get_total_game_minutes() -> int:
	return int(get_total_game_seconds() / 60.0)
