# ==============================================================================
# ФАЙЛ: src/main/main.gd
# НАЗНАЧЕНИЕ: Корень игровой сцены. Сборка мира, не логика куста/персонажа.
# ==============================================================================
extends Node3D

@onready var player_input: Node3D = $PlayerInputManager
@onready var camera_anchor: Node3D = $CameraAnchor
@onready var ui_layer: CanvasLayer = $UI
@onready var char_panel: PanelContainer = $UI/CharacterInfoPanel

func _ready() -> void:
	print("[Main] World scene ready.")
	if ui_layer:
		print("[Main] UI layer OK (layer=%d)" % ui_layer.layer)
	if char_panel:
		print("[Main] CharacterInfoPanel OK")
	else:
		push_warning("[Main] CharacterInfoPanel missing — add UI/CharacterInfoPanel in main.tscn")
