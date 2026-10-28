# ==============================================================================
# PlayerInputManager.gd — ввод: тык = select/инфо, hold/сдвиг = drag
# ОБНОВЛЕНО: 2026-10-28 — select character OR worksite + object ring
# ==============================================================================
extends Node3D

signal selection_changed(node)  # Character or worksite or null

@export var camera: Camera3D
@export var object_ring_scale: float = 1.6
## сдвиг мыши (px) → начало drag
@export var drag_threshold: float = 10.0
## удержание (сек) → начало drag
@export var hold_to_drag_sec: float = 0.28
@export var drag_height_offset: float = 2.0
@export var lift_speed: float = 12.0

var selected_character: CharacterBody3D = null
var selected_object: Node3D = null
var is_dragging_character: bool = false
var _object_ring: MeshInstance3D = null

var _click_start_pos: Vector2 = Vector2.ZERO
var _is_pressing: bool = false
## перс под курсором на press (ещё не drag)
var _press_on_character: CharacterBody3D = null
var _press_time: float = 0.0


func _ready() -> void:
	_ensure_object_ring()


func _process(delta: float) -> void:
	_update_object_ring()
	if is_dragging_character and selected_character:
		_update_drag_position(delta)
		return

	# hold / сдвиг → drag (пока кнопка зажата на персе)
	if _is_pressing and _press_on_character and is_instance_valid(_press_on_character):
		_press_time += delta
		var mouse: Vector2 = get_viewport().get_mouse_position()
		var moved: float = mouse.distance_to(_click_start_pos)
		if _press_time >= hold_to_drag_sec or moved >= drag_threshold:
			_begin_drag(_press_on_character)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return

		# UI (Research, panels) first — иначе клик не доходит до Button
	if not is_dragging_character:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered != null:
			return

	if is_dragging_character and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_lmb_down(event.position)
		else:
			_on_lmb_up(event.position)


func _on_lmb_down(pos: Vector2) -> void:
	_click_start_pos = pos
	_is_pressing = true
	_press_time = 0.0
	_press_on_character = null

	var hit_char: CharacterBody3D = _get_character_under_mouse(pos)
	if hit_char:
		# только SELECT — не carried
		_select_character(hit_char)
		_press_on_character = hit_char
		get_viewport().set_input_as_handled()
	# иначе press на земле/объекте — обработаем на up (_handle_click)


func _on_lmb_up(pos: Vector2) -> void:
	if not _is_pressing and not is_dragging_character:
		_cancel_camera_drag()
		return
	_is_pressing = false
	_press_on_character = null

	var drag_distance: float = pos.distance_to(_click_start_pos)

	if is_dragging_character:
		is_dragging_character = false
		_unlock_camera()
		_cancel_camera_drag()
		_handle_character_drop(pos)
		get_viewport().set_input_as_handled()
		return

	# Сдвиг мыши = pan карты (или отмена) — НЕ приказ «иди сюда»
	if drag_distance >= drag_threshold:
		_cancel_camera_drag()
		get_viewport().set_input_as_handled()
		return

	# короткий тык: select / go_work / move
	_cancel_camera_drag()
	_handle_click(pos)
	get_viewport().set_input_as_handled()


func _begin_drag(ch: CharacterBody3D) -> void:
	if is_dragging_character or ch == null or not is_instance_valid(ch):
		return
	_select_character(ch)
	is_dragging_character = true
	_press_on_character = null
	if "is_being_dragged" in ch:
		ch.is_being_dragged = true
	_cancel_camera_drag()
	_lock_camera()
	get_viewport().set_input_as_handled()


func _select_character(hit_char: CharacterBody3D) -> void:
	_clear_object_selection(false)
	if selected_character and selected_character != hit_char and is_instance_valid(selected_character):
		if selected_character.has_method("set_selected"):
			selected_character.set_selected(false)
	selected_character = hit_char
	if selected_character and selected_character.has_method("set_selected"):
		selected_character.set_selected(true)
	selection_changed.emit(selected_character)


func _select_object(site: Node3D) -> void:
	if selected_character and is_instance_valid(selected_character):
		if selected_character.has_method("set_selected"):
			selected_character.set_selected(false)
		selected_character = null
	selected_object = site
	_ensure_object_ring()
	if _object_ring:
		_object_ring.visible = site != null
	selection_changed.emit(site)


func _clear_object_selection(emit_if_only_object: bool = true) -> void:
	if selected_object == null:
		return
	selected_object = null
	if _object_ring:
		_object_ring.visible = false
	if emit_if_only_object and selected_character == null:
		selection_changed.emit(null)


func _clear_all_selection() -> void:
	if selected_character and is_instance_valid(selected_character):
		if selected_character.has_method("set_selected"):
			selected_character.set_selected(false)
	selected_character = null
	_clear_object_selection(false)
	selection_changed.emit(null)


func _ensure_object_ring() -> void:
	if _object_ring and is_instance_valid(_object_ring):
		return
	_object_ring = MeshInstance3D.new()
	_object_ring.name = "ObjectSelectionRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8 * object_ring_scale
	torus.outer_radius = 1.0 * object_ring_scale
	_object_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.95, 0.4, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_object_ring.material_override = mat
	_object_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_object_ring.visible = false
	add_child(_object_ring)


func _update_object_ring() -> void:
	if _object_ring == null or not _object_ring.visible:
		return
	if selected_object == null or not is_instance_valid(selected_object):
		_object_ring.visible = false
		selected_object = null
		return
	var p: Vector3 = selected_object.global_position
	_object_ring.global_position = Vector3(p.x, p.y + 0.05, p.z)


## Поиск персонажа под курсором
func _get_character_under_mouse(mouse_position: Vector2) -> CharacterBody3D:
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return null

	var ray_origin = camera.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_position) * 1000.0

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var exclude_list: Array[RID] = []

	while true:
		query.exclude = exclude_list
		var result = space_state.intersect_ray(query)
		if not result:
			break

		var collider = result.collider
		var hit_char: CharacterBody3D = null

		if collider is CharacterBody3D:
			hit_char = collider as CharacterBody3D
		elif collider.get_parent() is CharacterBody3D:
			hit_char = collider.get_parent() as CharacterBody3D

		if hit_char:
			return hit_char

		exclude_list.append(result.rid)

	return null


func _handle_character_drop(mouse_position: Vector2) -> void:
	if not camera or not selected_character:
		return

	var ray_origin = camera.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_position) * 1000.0

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [selected_character.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = true

	var result = space_state.intersect_ray(query)

	if result:
		var target_node = _find_interactable_node(result.collider)
		var land_pos: Vector3 = result.position
		if selected_character.has_method("on_context_drop"):
			selected_character.on_context_drop(target_node, land_pos)
		elif target_node:
			_assign_task_by_target(selected_character, target_node)
		else:
			selected_character.move_to_position(land_pos)
	else:
		if selected_character.has_method("on_context_drop"):
			selected_character.on_context_drop(null, selected_character.global_position)
		else:
			selected_character.move_to_position(selected_character.global_position)


func _find_interactable_node(collider: Node) -> Node3D:
	if not collider:
		return null
	if collider.is_in_group("interactable") or collider.is_in_group("work_site") or collider.has_method("get_free_work_point") or collider.has_method("do_work"):
		return collider as Node3D
	var p = collider.get_parent()
	if p and (p.is_in_group("interactable") or p.is_in_group("work_site") or p.has_method("get_free_work_point") or p.has_method("do_work")):
		return p as Node3D
	return null


func _assign_task_by_target(character: CharacterBody3D, target: Node3D) -> void:
	if character.has_method("go_work"):
		character.go_work(target)
		return
	if character.has_method("start_work_at"):
		character.start_work_at(target)
		return
	character.move_to_position(target.global_position)


func _handle_click(mouse_position: Vector2) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return

	var hit_char = _get_character_under_mouse(mouse_position)
	if hit_char:
		_select_character(hit_char)
		return

	var ray_origin = camera.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_position) * 1000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	if selected_character:
		query.exclude = [selected_character.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)

	if result:
		var target_node = _find_interactable_node(result.collider)
		if target_node:
			var ch: CharacterBody3D = selected_character
			if ch and is_instance_valid(ch):
				_assign_task_by_target(ch, target_node)
			_select_object(target_node as Node3D)
		elif selected_character:
			selected_character.move_to_position(result.position)
			_clear_object_selection(true)
		else:
			_clear_all_selection()
	else:
		_clear_all_selection()


func _update_drag_position(delta: float) -> void:
	if not camera or not selected_character:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.exclude = [selected_character.get_rid()]
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)
	if result:
		var target_air_pos = result.position + Vector3(0, drag_height_offset, 0)
		selected_character.global_position = selected_character.global_position.lerp(target_air_pos, lift_speed * delta)


func _get_camera_controller() -> Node:
	if not camera:
		return null
	if camera.has_method("cancel_drag") or "is_locked" in camera:
		return camera
	var parent = camera.get_parent()
	if parent and (parent.has_method("cancel_drag") or "is_locked" in parent):
		return parent
	return null


func _cancel_camera_drag() -> void:
	var ctrl = _get_camera_controller()
	if ctrl and ctrl.has_method("cancel_drag"):
		ctrl.cancel_drag()


func _lock_camera() -> void:
	var ctrl = _get_camera_controller()
	if ctrl:
		if ctrl.has_method("cancel_drag"):
			ctrl.cancel_drag()
		if "is_locked" in ctrl:
			ctrl.is_locked = true


func _unlock_camera() -> void:
	var ctrl = _get_camera_controller()
	if ctrl:
		if ctrl.has_method("cancel_drag"):
			ctrl.cancel_drag()
		if "is_locked" in ctrl:
			ctrl.is_locked = false
