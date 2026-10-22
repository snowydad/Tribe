# ==============================================================================
# TimeManager.gd — сутки: day_night_cycle_seconds = полная длина (день+ночь)
# ночь быстрее (night_time_mult), сумма реал. секунд всегда = cycle
# ОБНОВЛЕНО: 2026-10-16 — нормировка wall = cycle
# ==============================================================================
extends Node

signal year_passed(total_years: int)
signal day_night_cycle_updated(progress: float)

const SAVE_PATH: String = "user://time_data.json"

var seconds_per_year: float = 43200.0
## Полная длина суток в РЕАЛЬНЫХ секундах (день + ночь = это число)
var day_night_cycle_seconds: float = 900.0
var start_hour: float = 8.0
## Ночь в N раз быстрее дня (игровые часы ночи пролетают быстрее)
var night_time_mult: float = 3.0

var dawn_start: float = 5.0
var dawn_end: float = 8.0
var day_end: float = 18.0
var dusk_end: float = 21.0

var current_year: int = 1
var _year_timer: float = 0.0
## Игровой час 0…24 (дробный)
var _game_hour: float = 8.0


func _ready() -> void:
	_load_config()
	_game_hour = fposmod(start_hour, 24.0)
	print("[TimeManager] cycle=%.0fs (day+night real) start=%.1fh night_mult=%.1f | day_real≈%.0fs night_real≈%.0fs" % [
		day_night_cycle_seconds, start_hour, night_time_mult,
		_estimate_day_real(), _estimate_night_real()
	])
	_calculate_offline_time()
	day_night_cycle_updated.emit(get_day_progress())


func _load_config() -> void:
	if not ConfigLoader:
		return
	seconds_per_year = float(ConfigLoader.get_value("time_settings", "seconds_per_year", seconds_per_year))
	day_night_cycle_seconds = float(ConfigLoader.get_value("time_settings", "day_night_cycle_seconds", day_night_cycle_seconds))
	start_hour = float(ConfigLoader.get_value("time_settings", "start_hour", start_hour))
	night_time_mult = float(ConfigLoader.get_value("day_night_spin", "night_time_mult", night_time_mult))
	dawn_start = float(ConfigLoader.get_value("day_night_hours", "dawn_start", dawn_start))
	dawn_end = float(ConfigLoader.get_value("day_night_hours", "dawn_end", dawn_end))
	day_end = float(ConfigLoader.get_value("day_night_hours", "day_end", day_end))
	dusk_end = float(ConfigLoader.get_value("day_night_hours", "dusk_end", dusk_end))


## Часов «не-ночи» и «ночи» в сутках
func _day_hours() -> float:
	return 24.0 - _night_hours()


func _night_hours() -> float:
	# [dusk_end, 24) + [0, dawn_start)
	var n: float = (24.0 - dusk_end) + dawn_start
	return clampf(n, 0.0, 24.0)


## Игровых часов в 1 реальную секунду днём (ночь = × mult)
## так, что day_real + night_real = day_night_cycle_seconds
func _hour_rate_day() -> float:
	var T: float = maxf(day_night_cycle_seconds, 0.001)
	var M: float = maxf(night_time_mult, 0.001)
	var Hd: float = _day_hours()
	var Hn: float = _night_hours()
	# Hd/k + Hn/(k*M) = T  →  k = (Hd + Hn/M) / T
	return (Hd + Hn / M) / T


func _estimate_day_real() -> float:
	var k: float = _hour_rate_day()
	if k <= 0.0:
		return 0.0
	return _day_hours() / k


func _estimate_night_real() -> float:
	var k: float = _hour_rate_day()
	var M: float = maxf(night_time_mult, 0.001)
	if k <= 0.0:
		return 0.0
	return _night_hours() / (k * M)


func _process(delta: float) -> void:
	_year_timer += delta
	if _year_timer >= seconds_per_year:
		_year_timer -= seconds_per_year
		_advance_year(1)

	var k: float = _hour_rate_day()
	var rate: float = k
	if is_night_hour(_game_hour):
		rate = k * maxf(night_time_mult, 0.001)

	_game_hour += delta * rate
	_game_hour = fposmod(_game_hour, 24.0)
	day_night_cycle_updated.emit(get_day_progress())


func is_night_hour(hour: float) -> bool:
	var h: float = fposmod(hour, 24.0)
	return h >= dusk_end or h < dawn_start


func is_night() -> bool:
	return is_night_hour(get_game_hour())


## Вечер+ночь: [day_end … 24) + [0 … dawn_start)
func is_rest_time() -> bool:
	var h: float = fposmod(get_game_hour(), 24.0)
	return h >= day_end or h < dawn_start


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_current_timestamp()


func _advance_year(years_to_add: int) -> void:
	for i in range(years_to_add):
		current_year += 1
		year_passed.emit(current_year)
	_save_current_timestamp()


func _save_current_timestamp() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"last_timestamp": Time.get_unix_time_from_system(),
			"current_year": current_year,
			"year_timer": _year_timer
		}))


func _calculate_offline_time() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_save_current_timestamp()
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data = json.data
	current_year = int(data.get("current_year", 1))
	_year_timer = float(data.get("year_timer", 0.0))
	var elapsed: float = Time.get_unix_time_from_system() - float(data.get("last_timestamp", 0.0))
	if elapsed > 0.0 and seconds_per_year > 0.0:
		_year_timer += elapsed
		var passed: int = int(_year_timer / seconds_per_year)
		_year_timer = fmod(_year_timer, seconds_per_year)
		if passed > 0:
			_advance_year(passed)


func get_day_progress() -> float:
	return fposmod(_game_hour, 24.0) / 24.0


func get_game_hour() -> float:
	return fposmod(_game_hour, 24.0)


func get_display_year_month() -> String:
	return "%d.%d" % [current_year, get_month()]


func get_month() -> int:
	if seconds_per_year <= 0.0:
		return 1
	return int(clampf(_year_timer / seconds_per_year, 0.0, 0.9999) * 12.0) + 1


func get_total_game_seconds() -> float:
	return float(maxi(current_year - 1, 0)) * seconds_per_year + _year_timer


func get_total_game_minutes() -> int:
	return int(get_total_game_seconds() / 60.0)
