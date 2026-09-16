# ==============================================================================
# ФАЙЛ: src/main/PlayerInputManager.gd
# НАЗНАЧЕНИЕ: Мгновенный подхват любого персонажа + полная изоляция ввода от камеры
# ==============================================================================
extends Node3D

@export var camera: Camera3D
@export var drag_threshold: float = 10.0 # Порог сдвига мыши для подхвата (в пикселях)
@export var drag_height_offset: float = 2.0 # Высота парения юнита в воздухе

var selected_character: CharacterBody3D = null
var is_dragging_character: bool = false

var _click_start_pos: Vector2 = Vector2.ZERO
var _is_pressing: bool = false
var _pressed_character: CharacterBody3D = null
var _drag_xz_offset: Vector3 = Vector3.ZERO

func _process(_delta: float) -> void:
	if is_dragging_character and selected_character:
		_update_drag_position()

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return

	# Если тащим персонажа — полностью поглощаем движение мыши
	if is_dragging_character and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return

	# 1. НАЖАТИЕ ЛКМ (Press)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_click_start_pos = event.position
		_is_pressing = true
		
		# Сканируем: есть ли персонаж прямо под курсором
		_pressed_character = _get_character_at_pos(event.position)
		
		if _pressed_character:
			# Мгновенно блокируем карту и поглощаем событие, чтобы она ДАЖЕ НЕ НАЧИНАЛА двигаться!
			_lock_camera()
			get_viewport().set_input_as_handled()

	# 2. ДВИЖЕНИЕ МЫШИ ПРИ ЗАЖАТОЙ ЛКМ (Motion)
	elif event is InputEventMouseMotion and _is_pressing:
		var move_dist = event.position.distance_to(_click_start_pos)
		
		# Если тыкнули в персонажа и потянули дальше порога — МГНОВЕННО ПОДХВАТЫВАЕМ
		if _pressed_character and not is_dragging_character and move_dist > drag_threshold:
			if selected_character and selected_character != _pressed_character:
				selected_character.set_selected(false)
				
			selected_character = _pressed_character
			selected_character.set_selected(true)
			
			is_dragging_character = true
			_calculate_drag_offset(event.position)
			
			if "is_being_dragged" in selected_character:
				selected_character.is_being_dragged = true
			
			_lock_camera()
			get_viewport().set_input_as_handled()

	# 3. ОТПУСКАНИЕ ЛКМ (Release)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _is_pressing:
			_is_pressing = false
			
			if is_dragging_character:
				is_dragging_character = false
				if selected_character:
					if "is_being_dragged" in selected_character:
						selected_character.is_being_dragged = false
					selected_character.move_to_position(selected_character.global_position)
				
				_unlock_camera()
				get_viewport().set_input_as_handled()
			else:
				# Короткий клик без таскания
				var drag_distance = event.position.distance_to(_click_start_pos)
				if drag_distance < drag_threshold:
					_handle_click(event.position)
				
				if _pressed_character:
					_unlock_camera()
					get_viewport().set_input_as_handled()
			
			_pressed_character = null

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
			print("[PlayerInputManager] Selected character: ", selected_character.data.character_name)
			
		elif selected_character:
			selected_character.move_to_position(result.position)
			print("[PlayerInputManager] Moving to: ", result.position)
	else:
		if selected_character:
			selected_character.set_selected(false)
			selected_character = null

func _calculate_drag_offset(mouse_pos: Vector2) -> void:
	if not camera or not selected_character:
		return
		
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_dir * 1000.0)
	query.exclude = [selected_character.get_rid()]
	query.collision_mask = 0xFFFFFFFF
	
	var result = space_state.intersect_ray(query)
	if result:
		var hit_ground = result.position
		var char_pos = selected_character.global_position
		_drag_xz_offset = Vector3(char_pos.x - hit_ground.x, 0, char_pos.z - hit_ground.z)
	else:
		_drag_xz_offset = Vector3.ZERO

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
		var terrain_point = result.position
		selected_character.global_position = Vector3(
			terrain_point.x + _drag_xz_offset.x,
			terrain_point.y + drag_height_offset,
			terrain_point.z + _drag_xz_offset.z
		)

func _get_character_at_pos(mouse_position: Vector2) -> CharacterBody3D:
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
	query.collision_mask = 0xFFFFFFFF
	
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider is CharacterBody3D:
			return collider
		elif collider.get_parent() is CharacterBody3D:
			return collider.get_parent() as CharacterBody3D
	return null

func _get_camera_controller() -> Node:
	if not camera:
		return null
	if camera.has_method("cancel_drag") or "is_locked" in camera:
		return camera
	var parent = camera.get_parent()
	if parent and (parent.has_method("cancel_drag") or "is_locked" in parent):
		return parent
	return null

func _lock_camera() -> void:
	var ctrl = _get_camera_controller()
	if ctrl:
		if ctrl.has_method("cancel_drag"):
			ctrl.cancel_drag()
		if ctrl.has_method("force_reset_drag"):
			ctrl.force_reset_drag()
		if "is_locked" in ctrl:
			ctrl.is_locked = true

func _unlock_camera() -> void:
	var ctrl = _get_camera_controller()
	if ctrl:
		if ctrl.has_method("cancel_drag"):
			ctrl.cancel_drag()
		if ctrl.has_method("force_reset_drag"):
			ctrl.force_reset_drag()
		if "is_locked" in ctrl:
			ctrl.is_locked = false
