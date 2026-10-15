# ==============================================================================
# SunPivot.gd — ТОЛЬКО вращение. Старт = как в сцене (не трогаем).
# ОБНОВЛЕНО: 2026-10-15 — strip energy/color/phases; base from scene
# ==============================================================================
extends Node3D

## −1 / +1 — направление
@export var spin_sign: float = -1.0
## Градусов за полный цикл progress 0→1
@export var degrees_per_cycle: float = 360.0

## Поза из сцены (снимок в _ready)
var _base_basis: Basis = Basis.IDENTITY
var _base_origin: Vector3 = Vector3.ZERO


func _ready() -> void:
	# как выставлено в редакторе — не сбрасываем в 0
	_base_basis = transform.basis
	_base_origin = transform.origin
	if TimeManager and TimeManager.has_signal("day_night_cycle_updated"):
		if not TimeManager.day_night_cycle_updated.is_connected(_on_day_night):
			TimeManager.day_night_cycle_updated.connect(_on_day_night)
	# progress 0 → ровно сцена
	_apply(0.0)
	print("[SunPivot] base from scene, spin_sign=%.1f deg/cycle=%.0f" % [spin_sign, degrees_per_cycle])


func _on_day_night(progress: float) -> void:
	_apply(clampf(progress, 0.0, 1.0))


func _apply(progress: float) -> void:
	# progress=0 → basis сцены; дальше доворот вокруг локального X базы
	var spin_rad: float = progress * deg_to_rad(degrees_per_cycle) * spin_sign
	transform.basis = _base_basis * Basis(Vector3.RIGHT, spin_rad)
	transform.origin = _base_origin
