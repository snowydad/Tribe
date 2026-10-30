# ==============================================================================
# ФАЙЛ: src/main/main.gd
# ОБНОВЛЕНО: 2026-10-29 — place campfire + shelter (step1)
# ==============================================================================
extends Node3D

const TechTreePanelScript = preload("res://src/ui/TechTreePanel.gd")
const ResourcesPanelScript = preload("res://src/ui/ResourcesPanel.gd")
const BuildPlacementScript = preload("res://src/main/BuildPlacement.gd")
const CampfireScene = preload("res://src/environment/campfire.tscn")
const ShelterScene = preload("res://src/environment/shelter.tscn")

@onready var player_input: Node3D = $PlayerInputManager
@onready var camera_anchor: Node3D = $CameraAnchor
@onready var ui_layer: CanvasLayer = $UI
@onready var char_panel: PanelContainer = $UI/CharacterInfoPanel
var _resources_panel: PanelContainer

var _tech_panel: PanelContainer
var _research_btn: Button
var _build_placement: Node3D


func _ready() -> void:
	print("[Main] World scene ready.")
	if player_input and player_input.has_signal("selection_changed"):
		player_input.selection_changed.connect(_on_selection_changed)
	_setup_resources_panel()
	_setup_research_ui()
	_setup_build_placement()


func _setup_resources_panel() -> void:
	if ui_layer == null:
		return
	var existing = ui_layer.get_node_or_null("ResourcesPanel")
	if existing:
		_resources_panel = existing as PanelContainer
		return
	_resources_panel = PanelContainer.new()
	_resources_panel.name = "ResourcesPanel"
	_resources_panel.set_script(ResourcesPanelScript)
	ui_layer.add_child(_resources_panel)


func _on_selection_changed(node) -> void:
	if char_panel == null:
		return
	if char_panel.has_method("set_selection"):
		char_panel.set_selection(node)
	elif char_panel.has_method("set_character"):
		char_panel.set_character(node)


func _setup_research_ui() -> void:
	if ui_layer == null:
		return
	_research_btn = Button.new()
	_research_btn.name = "ResearchButton"
	_research_btn.text = "Research"
	_research_btn.focus_mode = Control.FOCUS_NONE
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


func _setup_build_placement() -> void:
	_build_placement = Node3D.new()
	_build_placement.name = "BuildPlacement"
	_build_placement.set_script(BuildPlacementScript)
	add_child(_build_placement)
	var cam: Camera3D = null
	if camera_anchor:
		cam = camera_anchor.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if _build_placement.has_method("setup"):
		_build_placement.call("setup", cam, ui_layer)
	if _tech_panel and _tech_panel.has_signal("build_requested"):
		if not _tech_panel.is_connected("build_requested", _on_build_requested):
			_tech_panel.connect("build_requested", _on_build_requested)
	if _build_placement.has_signal("placement_confirmed"):
		if not _build_placement.is_connected("placement_confirmed", _on_placement_confirmed):
			_build_placement.connect("placement_confirmed", _on_placement_confirmed)


func _on_build_requested(tech_id: String) -> void:
	print("[Main] build_requested ", tech_id)
	if _tech_panel and _tech_panel.has_method("close"):
		_tech_panel.call("close")
	if _build_placement and _build_placement.has_method("start"):
		_build_placement.call("start", tech_id)


func _on_placement_confirmed(tech_id: String, world_pos: Vector3) -> void:
	print("[Main] place ", tech_id, " at ", world_pos)
	var scene: PackedScene = null
	match tech_id:
		"campfire":
			scene = CampfireScene
		"shelter":
			scene = ShelterScene
		_:
			push_warning("[Main] unknown build tech: " + tech_id)
			return
	var inst: Node3D = scene.instantiate() as Node3D
	if inst == null:
		return
	if inst.has_method("setup_as_construction"):
		inst.call("setup_as_construction")
	elif "under_construction" in inst:
		inst.set("under_construction", true)
	elif "is_built" in inst:
		inst.set("is_built", false)
	add_child(inst)
	inst.global_position = world_pos


func _on_research_pressed() -> void:
	if _tech_panel and _tech_panel.has_method("toggle"):
		_tech_panel.call("toggle")
