# ==============================================================================
# ФАЙЛ: src/autoload/DevCheatManager.gd
# НАЗНАЧЕНИЕ: Отладочный менеджер чит-кодов и управления скоростью времени.
# ==============================================================================
extends Node

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed():
		return

	# Управление скоростью игры (Engine.time_scale)
	match event.keycode:
		KEY_0:
			Engine.time_scale = 0.0
			print("[DevCheat] Game paused (TimeScale: 0.0)")
		KEY_1:
			Engine.time_scale = 1.0
			print("[DevCheat] Normal speed (TimeScale: 1.0 - 24 hrs = 1 year)")
		KEY_2:
			Engine.time_scale = 2.0
			print("[DevCheat] Fast speed (TimeScale: 2.0) - 12 hrs = 1 year")
		KEY_3:
			Engine.time_scale = 24.0
			print("[DevCheat] Ultra speed (TimeScale: 24.0) - 1 hrs = 1 year")
		KEY_4:
			Engine.time_scale = 1440.0
			print("[DevCheat] Hyper speed (TimeScale: 1440.0) - 1 min = 1 year")
