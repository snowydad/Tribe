# ==============================================================================
# SunPivot.gd — Pivot X: 12:00 = поза сцены (зенит), 15°/час, spin_sign=-1
# ОБНОВЛЕНО: 2026-10-16 — clock model; start via TimeManager hour
# ==============================================================================
extends Node3D

## −1 по X (как договорились)
@export var spin_sign: float = -1.0
## 360° / 24 ч = 15° на игровой час
@export var degrees_per_hour: float = 15.0

@export_group("Light")
@export var energy_day: float = 1.15
@export var energy_night: float = 0.05
@export var color_day: Color = Color(1.0, 0.98, 0.92)
@export var color_dawn: Color = Color(1.0, 0.55, 0.35)
@export var color_dusk: Color = Color(1.0, 0.45, 0.28)
@export var color_night: Color = Color(0.4, 0.5, 0.75)

## Часовые границы фаз [start, end) — 24h
@export var dawn_start: float = 5.0
@export var dawn_end: float = 8.0
@export var day_end: float = 18.0
@export var dusk_end: float = 21.0

var _sun: DirectionalLight3D
var _base_basis: Basis = Basis.IDENTITY
var _base_origin: Vector3 = Vector3.ZERO
var _hour: float = 12.0
var _phase: String = "day"


func _ready() -> void:
	_base_basis = transform.basis
	_base_origin = transform.origin
	_sun = _find_sun()
	_load_hours_from_config()
	if TimeManager and TimeManager.has_signal("day_night_cycle_updated"):
		if not TimeManager.day_night_cycle_updated.is_connected(_on_day_night):
			TimeManager.day_night_cycle_updated.connect(_on_day_night)
	# сразу час из TimeManager (после его _ready start_hour)
	var h: float = 12.0
	if TimeManager and TimeManager.has_method("get_game_hour"):
		h = float(TimeManager.get_game_hour())
	_apply_hour(h)
	print("[SunPivot] zenith=12:00 scene base, sign=%.1f °/h=%.1f hour=%.1f" % [
		spin_sign, degrees_per_hour, _hour
	])


func _load_hours_from_config() -> void:
	if not ConfigLoader:
		return
	dawn_start = float(ConfigLoader.get_value("day_night_hours", "dawn_start", dawn_start))
	dawn_end = float(ConfigLoader.get_value("day_night_hours", "dawn_end", dawn_end))
	day_end = float(ConfigLoader.get_value("day_night_hours", "day_end", day_end))
	dusk_end = float(ConfigLoader.get_value("day_night_hours", "dusk_end", dusk_end))


func _find_sun() -> DirectionalLight3D:
	for c in get_children():
		if c is DirectionalLight3D:
			return c as DirectionalLight3D
	return get_node_or_null("Sun") as DirectionalLight3D


func _on_day_night(progress: float) -> void:
	# progress 0 = 00:00, 0.5 = 12:00, 1 = 24:00
	var hour: float = clampf(progress, 0.0, 1.0) * 24.0
	_apply_hour(hour)


func _apply_hour(hour: float) -> void:
	_hour = fposmod(hour, 24.0)
	# 12:00 → 0° от позы сцены; 8:00 → (8-12)*15 = −60°; * spin_sign
	var spin_deg: float = (_hour - 12.0) * degrees_per_hour * spin_sign
	var spin_rad: float = deg_to_rad(spin_deg)
	transform.basis = _base_basis * Basis(Vector3.RIGHT, spin_rad)
	transform.origin = _base_origin
	_phase = _phase_for_hour(_hour)
	_apply_light()


func _phase_for_hour(h: float) -> String:
	if h >= dawn_start and h < dawn_end:
		return "dawn"
	if h >= dawn_end and h < day_end:
		return "day"
	if h >= day_end and h < dusk_end:
		return "dusk"
	return "night"


func _phase_t() -> float:
	# 0…1 внутри текущей фазы
	match _phase:
		"dawn":
			var L: float = dawn_end - dawn_start
			return 0.0 if L <= 0.0 else clampf((_hour - dawn_start) / L, 0.0, 1.0)
		"day":
			var L2: float = day_end - dawn_end
			return 0.0 if L2 <= 0.0 else clampf((_hour - dawn_end) / L2, 0.0, 1.0)
		"dusk":
			var L3: float = dusk_end - day_end
			return 0.0 if L3 <= 0.0 else clampf((_hour - day_end) / L3, 0.0, 1.0)
		_:
			# night: dusk_end → 24 и 0 → dawn_start
			if _hour >= dusk_end:
				var Ln: float = (24.0 - dusk_end) + dawn_start
				return 0.0 if Ln <= 0.0 else clampf((_hour - dusk_end) / Ln, 0.0, 1.0)
			var Ln2: float = (24.0 - dusk_end) + dawn_start
			return 0.0 if Ln2 <= 0.0 else clampf((_hour + (24.0 - dusk_end)) / Ln2, 0.0, 1.0)


func _apply_light() -> void:
	if _sun == null:
		return
	var t: float = _phase_t()
	match _phase:
		"dawn":
			_sun.light_energy = lerpf(energy_night, energy_day, t)
			_sun.light_color = color_dawn.lerp(color_day, t)
		"day":
			_sun.light_energy = energy_day
			_sun.light_color = color_day
		"dusk":
			_sun.light_energy = lerpf(energy_day, energy_night, t)
			_sun.light_color = color_day.lerp(color_dusk, t)
		_:
			_sun.light_energy = energy_night
			_sun.light_color = color_night


func get_phase() -> String:
	return _phase


func get_game_hour() -> float:
	return _hour


func is_night() -> bool:
	return _phase == "night"
