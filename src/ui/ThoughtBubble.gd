# ==============================================================================
# ThoughtBubble.gd — follow + размеры. Icon.pos масштабируется с width.
# billboard/rotation/offset детей не трогаем.
# ОБНОВЛЕНО: 2026-10-20 — size without breaking icon offset
# ==============================================================================
extends Node3D

@export var height_m: float = 2.2
@export var offset_x: float = 0.0
@export var width_m: float = 0.55
@export var height_size_m: float = 0.0
@export_range(0.1, 3.0, 0.05) var icon_scale: float = 1.0

@export_group("Textures")
@export var bubble_texture: Texture2D
@export var icon_food: Texture2D
@export var icon_shelter: Texture2D
@export var icon_campfire: Texture2D

@onready var _bubble: Sprite3D = $Bubble
@onready var _icon: Sprite3D = $Icon

var _current_id: String = ""
var _host: Node3D = null

## из сцены (до _apply_sizes)
var _base_icon_pos: Vector3 = Vector3.ZERO
var _base_bubble_ps: float = 0.0015
var _base_icon_ps: float = 0.0015
var _got_base: bool = false


func _ready() -> void:
	_bubble = get_node_or_null("Bubble") as Sprite3D
	_icon = get_node_or_null("Icon") as Sprite3D
	_host = get_parent() as Node3D
	_capture_base()
	_apply_sizes()
	if Engine.is_editor_hint():
		set_process(false)
		position = Vector3(offset_x, height_m, 0.0)
		return
	top_level = true
	visible = false
	set_process(true)
	_follow_host()


func _capture_base() -> void:
	if _got_base:
		return
	if _icon:
		_base_icon_pos = _icon.position
		_base_icon_ps = _icon.pixel_size
	if _bubble:
		_base_bubble_ps = maxf(_bubble.pixel_size, 0.0000001)
	_got_base = true


func _process(_delta: float) -> void:
	_follow_host()


func _follow_host() -> void:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	if _host == null:
		return
	var p: Vector3 = _host.global_position
	global_position = Vector3(p.x + offset_x, p.y + height_m, p.z)


func _apply_sizes() -> void:
	if _bubble == null:
		_bubble = get_node_or_null("Bubble") as Sprite3D
	if _icon == null:
		_icon = get_node_or_null("Icon") as Sprite3D
	if _bubble == null:
		return
	_capture_base()

	var tw: float = 256.0
	var th: float = 256.0
	if _bubble.texture:
		tw = maxf(float(_bubble.texture.get_width()), 1.0)
		th = maxf(float(_bubble.texture.get_height()), 1.0)

	var mpp: float = width_m / tw
	_bubble.pixel_size = mpp

	# высота: только scale.y, центр не смещаем
	if height_size_m > 0.0:
		var nat_h: float = th * mpp
		_bubble.scale = Vector3(1.0, height_size_m / maxf(nat_h, 0.0001), 1.0)
	else:
		_bubble.scale = Vector3.ONE

	if _icon:
		# иконка: тот же «мир/пиксель», что bubble × icon_scale
		_icon.pixel_size = mpp * icon_scale
		# сдвиг из сцены масштабируем вместе с width (иначе «уезжает» вниз)
		var ratio: float = mpp / _base_bubble_ps
		_icon.position = _base_icon_pos * ratio


func set_thought(id: String) -> void:
	if _icon == null:
		_icon = get_node_or_null("Icon") as Sprite3D
	id = id.strip_edges()
	if id.is_empty():
		clear()
		return
	visible = true
	var tex: Texture2D = null
	match id:
		"need_food":
			tex = icon_food
		"need_campfire":
			tex = icon_campfire
		"need_shelter":
			tex = icon_shelter
		_:
			tex = icon_food
	if tex == null:
		var path := ""
		match id:
			"need_food":
				path = "res://assets/ui/icon_food.png"
			"need_campfire":
				path = "res://assets/ui/icon_campfire.png"
			"need_shelter":
				path = "res://assets/ui/icon_shelter.png"
		if path != "" and ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	if _icon and tex:
		_icon.texture = tex
	_current_id = id
	_apply_sizes()
	_follow_host()


func clear() -> void:
	_current_id = ""
	visible = false
