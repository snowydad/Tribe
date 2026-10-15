# ==============================================================================
# SunPivot.gd — пустышка: крутим pivot, DirectionalLight — дочерний
# ОБНОВЛЕНО: 2026-10-15 — simple: rotation.x = day_x + (progress-noon)*360
# Полдень: world ≈ day_rotation (light local identity → pivot = day pose)
# ==============================================================================
extends Node3D

## Поза полудня (pivot в этот момент = эти углы; light child local 0)
@export var day_rotation_deg: Vector3 = Vector3(-45.0, 45.0, 0.0)
## Крутим вокруг локальной X pivot (полный оборот за сутки)
@export var spin_axis: Vector3 = Vector3(1, 0, 0)

@export var phase_dawn: float = 0.1
@export var phase_day: float = 0.7
@export var phase_dusk: float = 0.1
@export var phase_night: float = 0.1

@export_group("Light (child DirectionalLight3D)")
@export var energy_day: float = 1.15
@export var energy_night: float = 0.02
@export var color_day: Color = Color(1.0, 0.98, 0.92)
@export var color_dawn: Color = Color(1.0, 0.55, 0.35)
@export var color_dusk: Color = Color(1.0, 0.4, 0.25)
@export var color_night: Color = Color(0.35, 0.45, 0.7)

var _sun: DirectionalLight3D
var _progress: float = 0.0
var _phase: String = "day"
var _phase_t: float = 0.0


func _ready() -> void:
	_sun = _find_sun()
	_load_phases()
	if TimeManager and TimeManager.has_signal("day_night_cycle_updated"):
		if not TimeManager.day_night_cycle_updated.is_connected(_on_day_night):
			TimeManager.day_night_cycle_updated.connect(_on_day_night)
	_apply(0.0)
	print("[SunPivot] ready sun=%s day_pose=%s" % [_sun.name if _sun else "null", str(day_rotation_deg)])


func _find_sun() -> DirectionalLight3D:
	for c in get_children():
		if c is DirectionalLight3D:
			return c as DirectionalLight3D
	return get_node_or_null("DirectionalLight3D") as DirectionalLight3D


func _load_phases() -> void:
	if not ConfigLoader:
		return
	phase_dawn = float(ConfigLoader.get_value("day_night_phases", "dawn", phase_dawn))
	phase_day = float(ConfigLoader.get_value("day_night_phases", "day", phase_day))
	phase_dusk = float(ConfigLoader.get_value("day_night_phases", "dusk", phase_dusk))
	phase_night = float(ConfigLoader.get_value("day_night_phases", "night", phase_night))
	var s: float = phase_dawn + phase_day + phase_dusk + phase_night
	if s > 0.001 and absf(s - 1.0) > 0.02:
		phase_dawn /= s
		phase_day /= s
		phase_dusk /= s
		phase_night /= s


func _on_day_night(progress: float) -> void:
	_apply(clampf(progress, 0.0, 1.0))


func _apply(progress: float) -> void:
	_progress = progress
	_resolve_phase(progress)

	# Полный оборот за сутки вокруг оси; в полдень = day_rotation
	var noon: float = phase_dawn + phase_day * 0.5
	var turns: float = progress - noon  # 0 at noon
	# euler: базовая дневная поза + оборот вокруг X (восток-запад дуга)
	var spin: float = turns * -360.0
	rotation_degrees = Vector3(
		day_rotation_deg.x + spin,
		day_rotation_deg.y,
		day_rotation_deg.z
	)

	if _sun:
		# light local — identity (или как в сцене); energy/color
		_sun.light_energy = _energy()
		_sun.light_color = _color()


func _resolve_phase(p: float) -> void:
	var a1: float = phase_dawn
	var a2: float = a1 + phase_day
	var a3: float = a2 + phase_dusk
	if p < a1:
		_phase = "dawn"
		_phase_t = 0.0 if phase_dawn <= 0.0 else p / phase_dawn
	elif p < a2:
		_phase = "day"
		_phase_t = 0.0 if phase_day <= 0.0 else (p - a1) / phase_day
	elif p < a3:
		_phase = "dusk"
		_phase_t = 0.0 if phase_dusk <= 0.0 else (p - a2) / phase_dusk
	else:
		_phase = "night"
		_phase_t = 0.0 if phase_night <= 0.0 else (p - a3) / phase_night
	_phase_t = clampf(_phase_t, 0.0, 1.0)


func _day_amount() -> float:
	# 1 в полдень, 0 когда «солнце сзади/внизу» — по cos оборота
	var noon: float = phase_dawn + phase_day * 0.5
	var d: float = absf(_progress - noon)
	if d > 0.5:
		d = 1.0 - d
	return clampf(cos(d * PI), 0.0, 1.0)


func _energy() -> float:
	var a: float = _day_amount()
	var e: float = lerpf(energy_night, energy_day, smoothstep(0.0, 1.0, a))
	if _phase == "dawn":
		e = lerpf(energy_night, e, smoothstep(0.0, 1.0, _phase_t))
	elif _phase == "dusk":
		e = lerpf(e, energy_night, smoothstep(0.0, 1.0, _phase_t))
	elif _phase == "night":
		e = energy_night
	return e


func _color() -> Color:
	if _phase == "night":
		return color_night
	if _phase == "dawn":
		return color_dawn.lerp(color_day, smoothstep(0.0, 1.0, _phase_t))
	if _phase == "dusk":
		return color_day.lerp(color_dusk, smoothstep(0.0, 1.0, _phase_t))
	return color_day


func get_phase() -> String:
	return _phase


func is_night() -> bool:
	return _phase == "night"


func get_progress() -> float:
	return _progress
