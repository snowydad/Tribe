# ==============================================================================
# SunPivot.gd — вращение от позы сцены + доли фаз; ночь крутится быстрее
# ОБНОВЛЕНО: 2026-10-16 — spin 0 at noon (scene pose), not at progress 0
# ==============================================================================
extends Node3D

@export var spin_sign: float = -1.0
@export var degrees_per_cycle: float = 360.0

## Доли ВРЕМЕНИ (сумма 1) — из ini
@export var phase_dawn: float = 0.1
@export var phase_day: float = 0.7
@export var phase_dusk: float = 0.1
@export var phase_night: float = 0.1

## Множители угловой скорости (ночь > 1 → быстрее доворачивается)
@export var mult_dawn: float = 1.0
@export var mult_day: float = 1.0
@export var mult_dusk: float = 1.0
@export var mult_night: float = 3.0

@export_group("Light color / energy")
@export var energy_day: float = 1.15
@export var energy_night: float = 0.05
@export var color_day: Color = Color(1.0, 0.98, 0.92)
@export var color_dawn: Color = Color(1.0, 0.55, 0.35)
@export var color_dusk: Color = Color(1.0, 0.45, 0.28)
@export var color_night: Color = Color(0.4, 0.5, 0.75)

var _sun: DirectionalLight3D
var _base_basis: Basis = Basis.IDENTITY
var _base_origin: Vector3 = Vector3.ZERO
var _phase: String = "day"
var _phase_t: float = 0.0
var _progress: float = 0.0


func _ready() -> void:
	_base_basis = transform.basis
	_base_origin = transform.origin
	_sun = _find_sun()
	_load_config()
	if TimeManager and TimeManager.has_signal("day_night_cycle_updated"):
		if not TimeManager.day_night_cycle_updated.is_connected(_on_day_night):
			TimeManager.day_night_cycle_updated.connect(_on_day_night)
	_apply(0.0)
	print("[SunPivot] phases d/d/d/n=%.2f/%.2f/%.2f/%.2f night_mult=%.1f" % [
		phase_dawn, phase_day, phase_dusk, phase_night, mult_night
	])


func _load_config() -> void:
	if not ConfigLoader:
		return
	phase_dawn = float(ConfigLoader.get_value("day_night_phases", "dawn", phase_dawn))
	phase_day = float(ConfigLoader.get_value("day_night_phases", "day", phase_day))
	phase_dusk = float(ConfigLoader.get_value("day_night_phases", "dusk", phase_dusk))
	phase_night = float(ConfigLoader.get_value("day_night_phases", "night", phase_night))
	mult_dawn = float(ConfigLoader.get_value("day_night_spin", "dawn_mult", mult_dawn))
	mult_day = float(ConfigLoader.get_value("day_night_spin", "day_mult", mult_day))
	mult_dusk = float(ConfigLoader.get_value("day_night_spin", "dusk_mult", mult_dusk))
	mult_night = float(ConfigLoader.get_value("day_night_spin", "night_mult", mult_night))
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
	# Поза сцены = ПОЛДЕНЬ (середина day), не progress=0
	# spin_p: 0…1 за сутки; ноль угла когда progress == noon
	var noon: float = phase_dawn + phase_day * 0.5
	var spin_p: float = _time_to_spin_progress(progress)
	var noon_p: float = _time_to_spin_progress(noon)
	var spin_delta: float = spin_p - noon_p
	# wrap −0.5…0.5 чтобы путь был кратчайший от полудня
	if spin_delta > 0.5:
		spin_delta -= 1.0
	if spin_delta < -0.5:
		spin_delta += 1.0
	var spin_rad: float = spin_delta * deg_to_rad(degrees_per_cycle) * spin_sign
	transform.basis = _base_basis * Basis(Vector3.RIGHT, spin_rad)
	transform.origin = _base_origin
	_apply_light()


func _find_sun() -> DirectionalLight3D:
	for c in get_children():
		if c is DirectionalLight3D:
			return c as DirectionalLight3D
	return get_node_or_null("DirectionalLight3D") as DirectionalLight3D


func _apply_light() -> void:
	if _sun == null:
		return
	_sun.light_energy = _energy_for_phase()
	_sun.light_color = _color_for_phase()


func _energy_for_phase() -> float:
	match _phase:
		"dawn":
			return lerpf(energy_night, energy_day, _phase_t)
		"day":
			return energy_day
		"dusk":
			return lerpf(energy_day, energy_night, _phase_t)
		_:
			return energy_night


func _color_for_phase() -> Color:
	match _phase:
		"dawn":
			return color_dawn.lerp(color_day, _phase_t)
		"day":
			return color_day
		"dusk":
			return color_day.lerp(color_dusk, _phase_t)
		_:
			return color_night


## Кусок [start, start+len), rate mult → вклад в «угол»
func _time_to_spin_progress(p: float) -> float:
	var segs: Array = [
		{"len": phase_dawn, "mult": maxf(mult_dawn, 0.001)},
		{"len": phase_day, "mult": maxf(mult_day, 0.001)},
		{"len": phase_dusk, "mult": maxf(mult_dusk, 0.001)},
		{"len": phase_night, "mult": maxf(mult_night, 0.001)},
	]
	var total_w: float = 0.0
	for s in segs:
		total_w += float(s["len"]) * float(s["mult"])
	if total_w < 0.0001:
		return p
	var acc_t: float = 0.0
	var acc_w: float = 0.0
	for s in segs:
		var L: float = float(s["len"])
		var M: float = float(s["mult"])
		var w: float = L * M
		if p <= acc_t + L + 0.0000001:
			var local_t: float = 0.0 if L <= 0.0 else (p - acc_t) / L
			local_t = clampf(local_t, 0.0, 1.0)
			return (acc_w + local_t * w) / total_w
		acc_t += L
		acc_w += w
	return 1.0


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


func get_phase() -> String:
	return _phase


func get_phase_t() -> float:
	return _phase_t


func get_progress() -> float:
	return _progress


func is_night() -> bool:
	return _phase == "night"
