# ==============================================================================
# ФАЙЛ: src/main/main.gd
# НАЗНАЧЕНИЕ: Корень игровой сцены. Сборка мира, не логика куста/персонажа.
# ОБНОВЛЕНО: 2026-10-24 — Research button + TechTreePanel
# ==============================================================================
extends Node3D

const TechTreePanelScript = preload("res://src/ui/TechTreePanel.gd")

@onready var player_input: Node3D = $PlayerInputManager
@onready var camera_anchor: Node3D = $CameraAnchor
@onready var ui_layer: CanvasLayer = $UI
@onready var char_panel: PanelContainer = $UI/CharacterInfoPanel

var _tech_panel: PanelContainer
var _research_btn: Button


func _ready() -> void:
	print("[Main] World scene ready.")
	if ui_layer:
		print("[Main] UI layer OK (layer=%d)" % ui_layer.layer)
	if char_panel:
		print("[Main] CharacterInfoPanel OK")
	else:
		push_warning("[Main] CharacterInfoPanel missing — add UI/CharacterInfoPanel in main.tscn")

	if player_input and player_input.has_signal("selection_changed"):
		player_input.selection_changed.connect(_on_selection_changed)

	_setup_research_ui()


func _on_selection_changed(character) -> void:
	if char_panel and char_panel.has_method("set_character"):
		char_panel.set_character(character)


func _setup_research_ui() -> void:
	if ui_layer == null:
		return

	_research_btn = Button.new()
	_research_btn.name = "ResearchButton"
	_research_btn.text = "Research"
	_research_btn.focus_mode = Control.FOCUS_NONE
	# top center
	_research_btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_research_btn.offset_left = -60
	_research_btn.offset_right = 60
	_research_btn.offset_top = 8
	_research_btn.offset_bottom = 40
	_research_btn.pressed.connect(_on_research_pressed)
	ui_layer.add_child(_research_btn)

	_tech_panel = PanelContainer.new()
	_tech_panel.name = "TechTreePanel"
	_tech_panel.set_script(TechTreePanelScript)
	ui_layer.add_child(_tech_panel)


func _on_research_pressed() -> void:
	if _tech_panel and _tech_panel.has_method("toggle"):
		_tech_panel.toggle()
