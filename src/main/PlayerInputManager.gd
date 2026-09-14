# ==============================================================================
# ФАЙЛ: src/main/PlayerInputManager.gd
# НАЗНАЧЕНИЕ: Менеджер ввода с мгновенным перехватом ЛКМ над персонажем
# ==============================================================================
extends Node3D

@export var camera: Camera3D
@export var drag_threshold: float = 10.0
@export var drag_height_offset: float = 2.0

var selected_character: CharacterBody3D = null
var is_dragging_character: bool = false

var _click_start_pos: Vector2 = Vector2.ZERO
var _is_pressing: bool = false
var _can_drag_selected: bool = false

func _process(_delta: float) -> void:
	if is_dragging_character and selected_character:
		_update_drag_position()

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return

	if is_dragging_character and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_click_start_pos = event.position
			_is_pressing = true
			
			# Проверяем клик по выделенному персонажу СРАЗУ при нажатии
			if selected_character and _is_mouse_over_character(event.position, selected_character):
				_can_drag_selected = true
				# Предотвращаем попадание события нажатия в camera_3d.gd (_unhandled_input)
				get_viewport().set_input_as_handled()
				_cancel_camera_drag()
			else:
				_can_drag_selected = false
		else:
			if _is_pressing:
				_is_pressing = false
				_can_drag_selected = false
				
				if is_dragging_character:
					is_dragging_character = false
					if selected_character:
						if "is_being_dragged" in selected_character:
							selected_character.is_being_dragged = false
						selected_character.move_to_position(selected_character.global_position)
					
					get_viewport().set_input_as_handled()
					_unlock_camera()
				else:
					var drag_distance = event.position.distance_to(_click_start_pos)
					if drag_distance < drag_threshold:
						_handle_click(event.position)

	elif event is InputEventMouseMotion and _is_pressing:
		var move_dist = event.position.distance_to(_click_start_pos)
		
		if _can_drag_selected and not is_dragging_character and move_dist > drag_threshold:
			is_dragging_character = true
			
			_cancel_camera_drag()
			_lock_camera()
			
			if "is_being_dragged" in selected_character:
				selected_character.is_being_dragged = true
			
			get_viewport().set_input_as_handled()

func _handle_click(mouse_position: Vector2) -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return

	var ray_origin = camera.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_position) * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.collision_mask = 0xFFFFFFFF
	
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		var hit_character: CharacterBody3D = null
		
		if collider is CharacterBody3D:
			hit_character = collider
		elif collider.get_parent() is CharacterBody3D:
			hit_character = collider.get_parent() as CharacterBody3D
		
		if hit_character and hit_character.has_method("set_selected"):
			if selected_character and selected_character != hit_character:
				selected_character.set_selected(false)
				
			selected_character = hit_character
			selected_character.set_selected(true)
		elif selected_character:
			selected_character.move_to_position(result.position)
	else:
		if selected_character:
			selected_character.set_selected(false)
			selected_character = null

func _update_drag_position() -> void:
	if not camera or not selected_character:
		return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.exclude = [selected_character.get_rid()]
	query.collision_mask = 0xFFFFFFFF
	
	var result = space_state.intersect_ray(query)
	if result:
		selected_character.global_position = result.position + Vector3(0, drag_height_offset, 0)

func _is_mouse_over_character(mouse_position: Vector2, character: CharacterBody3D) -> bool:
	if not camera:
		return false
	var ray_origin = camera.project_ray_origin(mouse_position)
	var ray_end = ray_origin + camera.project_ray_normal(mouse_position) * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		return collider == character or collider.get_parent() == character
	return false

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
