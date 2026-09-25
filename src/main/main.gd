# ==============================================================================
# ФАЙЛ: src/main/main.gd
# НАЗНАЧЕНИЕ: Корень игровой сцены. Сборка мира, не логика куста/персонажа.
# ==============================================================================
extends Node3D

@onready var player_input: Node3D = $PlayerInputManager
@onready var camera_anchor: Node3D = $CameraAnchor

func _ready() -> void:
	print("[Main] World scene ready.")
