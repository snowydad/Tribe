# ==============================================================================
# SunController.gd — день/ночь на DirectionalLight3D
# ОБНОВЛЕНО: 2026-10-15 — only X rotates; day pose x=-45,y=45,z=0; continuous
# ==============================================================================
extends DirectionalLight3D

## Опорная дневная поза (должна проходить через неё в «полдень»)
@export var day_rotation_deg: Vector3 = Vector3(-45.0, 45.0, 0.0)
## X ночью (солнце «под горизонтом» — слабый/нулевой свет)
@export var night_x_deg: float = 25.0

## Доли фаз (из ini)
@export var phase_dawn: float = 0.1
@export var phase_day: float = 0.7
@export var phase_dusk: float = 0.1
@export var phase_night: float = 0.1

@export_group("Energy")
@export var energy_day: float = 1.15
@export var energy_night: float = 0.02
@export var energy_dawn_min: float = 0.2
@export var energy_dusk_min: float = 0.15

@export_group("Color")
@export var color_day: Color = Color(1.0, 0.98, 0.92)
@export var color_dawn: Color = Color(1.0, 0.55, 0.35)
@export var color_dusk: Color = Color(1.0, 0.4, 0.25)
@export var color_night: Color = Color(0.35, 0.45, 0.7)

var _progress: float = 0.0
var _phase: String = "day"
var _phase_t: float = 0.0
## 1 = полдень (day pose), 0 = глубокая ночь — непрерывный
var _day_factor: float = 1.0


func _ready() -> void:
	_load_phases()
	# зафиксировать Y/Z из day pose
	rotation_degrees = day_rotation_deg
	if TimeManager and TimeManager.has_signal("day_night_cycle_updated"):
		if not TimeManager.day_night_cycle_updated.is_connected(_on_day_night):
			TimeManager.day_night_cycle_updated.connect(_on_day_night)
	_apply(0.0)


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
	print("[Sun] X-only day_pose=%s night_x=%.1f phases d/d/d/n=%.2f/%.2f/%.2f/%.2f" % [
		str(day_rotation_deg), night_x_deg, phase_dawn, phase_day, phase_dusk, phase_night
	])


func _on_day_night(progress: float) -> void:
	_apply(clampf(progress, 0.0, 1.0))


func _apply(progress: float) -> void:
	_progress = progress
	_resolve_phase(progress)
	_day_factor = _compute_day_factor(progress)

	# --- rotation: Y/Z фиксированы, только X ---
	# day_factor=1 → day_rotation.x (−45); day_factor=0 → night_x
	var x: float = lerpf(night_x_deg, day_rotation_deg.x, _day_factor)
	rotation_degrees = Vector3(x, day_rotation_deg.y, day_rotation_deg.z)

	light_energy = _energy_smooth()
	light_color = _color_smooth()


## Непрерывный 0…1: 1 в середине дня, 0 в середине ночи (без скачков)
func _compute_day_factor(p: float) -> float:
	# полдень = середина фазы day
	var noon: float = phase_dawn + phase_day * 0.5
	var d: float = absf(p - noon)
	if d > 0.5:
		d = 1.0 - d
	# d=0 → noon, d=0.5 → opposite (night mid)
	# cos: 1 at noon, 0 at midnight
	var f: float = cos(d * PI) # d/0.5 * (PI/2) → cos(d*PI) when d in 0..0.5 → 1..0
	# d=0 → cos0=1; d=0.5 → cos(π/2)=0 — wait cos(0.5*π)=0 yes if d*PI and d=0.5 → 0.5*PI
	return clampf(f, 0.0, 1.0)


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


func _energy_smooth() -> float:
	# база от day_factor (главный анти-прыжок)
	var e: float = lerpf(energy_night, energy_day, smoothstep(0.0, 1.0, _day_factor))
	# лёгкий tint по фазе без скачка: подмешиваем min на краях
	match _phase:
		"dawn":
			var edge: float = lerpf(energy_dawn_min, energy_day, _phase_t)
			e = minf(e, edge) if _phase_t < 0.5 else e
			e = lerpf(energy_dawn_min, e, clampf(_phase_t * 2.0, 0.0, 1.0))
		"dusk":
			e = lerpf(e, energy_dusk_min, _phase_t)
		"night":
			e = energy_night
		_:
			pass
	return e


func _color_smooth() -> Color:
	# смесь day↔night по day_factor + лёгкий dawn/dusk
	var c: Color = color_night.lerp(color_day, smoothstep(0.0, 1.0, _day_factor))
	match _phase:
		"dawn":
			c = color_dawn.lerp(c, _phase_t)
		"dusk":
			c = c.lerp(color_dusk, _phase_t)
		"night":
			c = color_night
		_:
			pass
	return c


func get_phase() -> String:
	return _phase


func get_phase_t() -> float:
	return _phase_t


func get_progress() -> float:
	return _progress


func get_day_factor() -> float:
	return _day_factor


func is_night() -> bool:
	return _phase == "night"
