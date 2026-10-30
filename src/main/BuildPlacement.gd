# ==============================================================================
# BuildPlacement.gd — ghost + valid/invalid + Confirm
# ОБНОВЛЕНО: 2026-10-28 — _load_place_rules fixed; show ground Y on button
# ==============================================================================
extends Node3D

signal placement_cancelled
signal placement_confirmed(tech_id: String, world_pos: Vector3)

var clear_radius: float = 2.5
var min_ground_y: float = 0.0

var active: bool = false
var tech_id: String = ""
var ghost: MeshInstance3D = null
var _cam: Camera3D = null
var _mat: StandardMaterial3D = null
var _ui: CanvasLayer = null
var _btn_confirm: Button = null
var _btn_cancel: Button = null
var _valid: bool = true
var _last_ground: Vector3 = Vector3.ZERO

const GROUPS_BLOCK := [
	"interactable",
	"campfire",
	"storage",
	"berries",
	"debris",
	"obstacle",
	"shelter",
	"character",
]


func setup(camera: Camera3D, ui_layer: CanvasLayer = null) -> void:
	_cam = camera
	_ui = ui_layer
	_ensure_ui()


func start(p_tech_id: String) -> void:
	tech_id = p_tech_id
	active = true
	_load_place_rules(p_tech_id)
	_ensure_ghost()
	ghost.visible = true
	_set_ui_visible(true)
	print("[BuildPlacement] start ", tech_id, " min_y=", min_ground_y, " clear=", clear_radius)
	_refresh_validity(_last_ground)


func _load_place_rules(p_tech_id: String) -> void:
	min_ground_y = 0.0
	clear_radius = 2.5
	if ConfigLoader == null:
		push_warning("[BuildPlacement] ConfigLoader missing")
		return
	var y_val = null
	var r_val = null
	var cfg := p_tech_id  # campfire / shelter / …
	# getters: get_campfire_value / get_shelter_value / get_config_value
	var getter := "get_%s_value" % cfg
	if ConfigLoader.has_method(getter):
		y_val = ConfigLoader.call(getter, "build", "place_min_y", null)
		r_val = ConfigLoader.call(getter, "build", "place_clear_radius", null)
	elif ConfigLoader.has_method("get_config_value"):
		y_val = ConfigLoader.get_config_value(cfg, "build", "place_min_y", null)
		r_val = ConfigLoader.get_config_value(cfg, "build", "place_clear_radius", null)
	if y_val != null:
		min_ground_y = float(y_val)
	if r_val != null:
		clear_radius = float(r_val)
	print("[BuildPlacement] ", cfg, " min_y=", min_ground_y, " clear=", clear_radius)


func cancel() -> void:
	active = false
	tech_id = ""
	if ghost:
		ghost.visible = false
	_set_ui_visible(false)
	print("[BuildPlacement] cancel")
	placement_cancelled.emit()


func confirm() -> void:
	if not active or ghost == null:
		return
	_refresh_validity(_last_ground)
	if not _valid:
		print("[BuildPlacement] blocked ground_y=", _last_ground.y, " min=", min_ground_y)
		return
	var pos := ghost.global_position
	var id := tech_id
	active = false
	tech_id = ""
	if ghost:
		ghost.visible = false
	_set_ui_visible(false)
	print("[BuildPlacement] confirm ", id, " @ ", pos)
	placement_confirmed.emit(id, pos)


func _ensure_ui() -> void:
	if _btn_confirm or _ui == null:
		return
	_btn_confirm = Button.new()
	_btn_confirm.name = "BuildConfirmButton"
	_btn_confirm.text = "Build here"
	_btn_confirm.focus_mode = Control.FOCUS_NONE
	_btn_confirm.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_btn_confirm.offset_left = -100
	_btn_confirm.offset_right = 100
	_btn_confirm.offset_top = -72
	_btn_confirm.offset_bottom = -36
	_btn_confirm.pressed.connect(confirm)
	_ui.add_child(_btn_confirm)

	_btn_cancel = Button.new()
	_btn_cancel.name = "BuildCancelButton"
	_btn_cancel.text = "Cancel"
	_btn_cancel.focus_mode = Control.FOCUS_NONE
	_btn_cancel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_btn_cancel.offset_left = -80
	_btn_cancel.offset_right = 80
	_btn_cancel.offset_top = -110
	_btn_cancel.offset_bottom = -78
	_btn_cancel.pressed.connect(cancel)
	_ui.add_child(_btn_cancel)
	_set_ui_visible(false)


func _set_ui_visible(on: bool) -> void:
	if _btn_confirm:
		_btn_confirm.visible = on
	if _btn_cancel:
		_btn_cancel.visible = on


func _ensure_ghost() -> void:
	if ghost and is_instance_valid(ghost):
		return
	ghost = MeshInstance3D.new()
	ghost.name = "BuildGhost"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.1
	mesh.height = 0.4
	mesh.radial_segments = 16
	ghost.mesh = mesh
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(0.2, 1.0, 0.35, 0.45)
	ghost.material_override = _mat
	add_child(ghost)
	ghost.visible = false


func _set_ghost_color(c: Color) -> void:
	if _mat:
		_mat.albedo_color = c


func _process(_delta: float) -> void:
	if not active or ghost == null or _cam == null:
		return
	var pos := _screen_center_on_ground()
	_last_ground = pos
	ghost.global_position = Vector3(pos.x, pos.y + 0.12, pos.z)
	_refresh_validity(pos)


func _refresh_validity(ground_pos: Vector3) -> void:
	if ghost == null:
		return
	_valid = _is_spot_valid(ground_pos)
	if _valid:
		_set_ghost_color(Color(0.2, 1.0, 0.35, 0.45))
	else:
		_set_ghost_color(Color(1.0, 0.25, 0.2, 0.5))
	if _btn_confirm:
		_btn_confirm.disabled = not _valid
		# live debug: ground Y vs min from ini
		if _valid:
			_btn_confirm.text = "Build here  y=%.1f" % ground_pos.y
		else:
			_btn_confirm.text = "Blocked  y=%.1f < min %.1f" % [ground_pos.y, min_ground_y]


func _is_spot_valid(pos: Vector3) -> bool:
	# place_min_y from campfire.ini [build] — ground at or below = water/low
	if pos.y <= min_ground_y:
		return false
	var tree := get_tree()
	if tree == null:
		return true
	var seen: Dictionary = {}
	for gname in GROUPS_BLOCK:
		for n in tree.get_nodes_in_group(gname):
			if n == null or not is_instance_valid(n):
				continue
			var iid: int = n.get_instance_id()
			if seen.has(iid):
				continue
			seen[iid] = true
			if not (n is Node3D):
				continue
			var other: Node3D = n as Node3D
			if other == ghost:
				continue
			var d: float = Vector3(other.global_position.x, 0.0, other.global_position.z).distance_to(
				Vector3(pos.x, 0.0, pos.z)
			)
			if d < clear_radius:
				return false
	return true


func _screen_center_on_ground() -> Vector3:
	var vp := get_viewport()
	if vp == null or _cam == null:
		return global_position
	var size: Vector2 = vp.get_visible_rect().size
	var from: Vector3 = _cam.project_ray_origin(size * 0.5)
	var dir: Vector3 = _cam.project_ray_normal(size * 0.5)
	var to: Vector3 = from + dir * 500.0
	var space := get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit:
			return hit.position
	if absf(dir.y) > 0.001:
		var t: float = -from.y / dir.y
		if t > 0.0:
			return from + dir * t
	return Vector3(from.x, 0.0, from.z)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel()
			get_viewport().set_input_as_handled()
