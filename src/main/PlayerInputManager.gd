# ==============================================================================
# ФАЙЛ: src/main/PlayerInputManager.gd
# НАЗНАЧЕНИЕ: Контроллер ввода с мгновенным подхватом (Test Case 2),
#            плавным подъёмом (Test Case 3), фильтрацией слоёв (Test Case 5)
#            и блокировкой камеры (Test Case 4).
# ==============================================================================
extends Node3D

# character = CharacterBody3D или null (тип не указываем — emit(null) безопасен)
signal selection_changed(character)

@export var camera: Camera3D
@export var drag_threshold: float = 10.0
@export var drag_height_offset: float = 2.0
@export var lift_speed: float = 12.0

var selected_character: CharacterBody3D = null
var is_dragging_character: bool = false

var _click_start_pos: Vector2 = Vector2.ZERO
var _is_pressing: bool = false

func _process(delta: float) -> void:
	if is_dragging_character and selected_character:
		_update_drag_position(delta)

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
			
			# ✅ Мгновенный подхват персонажа под курсором (Test Case 2)
			var hit_char = _get_character_under_mouse(event.position)
			if hit_char:
				if selected_character and selected_character != hit_char:
					selected_character.set_selected(false)
				
				selected_character = hit_char
				selected_character.set_selected(true)
				selection_changed.emit(selected_character)
				
				is_dragging_character = true
				if "is_being_dragged" in selected_character:
					selected_character.is_being_dragged = true
				
				_cancel_camera_drag()
				_lock_camera()
				get_viewport().set_input_as_handled()
		else:
			if _is_pressing:
				_is_pressing = false
				
				if is_dragging_character:
					is_dragging_character = false
					_unlock_camera()
					# ✅ Сброс персонажа (Context Drop)
					_handle_character_drop(event.position)
					get_viewport().set_input_as_handled()
				else:
					var drag_distance = event.position.distance_to(_click_start_pos)
					if drag_distance < drag_threshold:
						_handle_click(event.position)

## Поиск персонажа под курсором (циклически пробивает коллизии объектов)
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

## Контекстная обработка сброса персонажа
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
		# Drop ≠ start_work: приземление + think + resolve
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

## Клик по interactable → go_work. Без знания harvest/storage/deliver.
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
		if selected_character and selected_character != hit_char:
			selected_character.set_selected(false)

		selected_character = hit_char
		selected_character.set_selected(true)
		selection_changed.emit(selected_character)
	else:
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
			var collider = result.collider
			var target_node = _find_interactable_node(collider)

			if target_node and selected_character:
				_assign_task_by_target(selected_character, target_node)
			elif selected_character:
				selected_character.move_to_position(result.position)
		else:
			if selected_character:
				selected_character.set_selected(false)
				selected_character = null
				selection_changed.emit(null)

## ✅ Плавный подъем и ведение над террейном (Test Case 3 и Test Case 5)
func _update_drag_position(delta: float) -> void:
	if not camera or not selected_character:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.exclude = [selected_character.get_rid()]

	# ✅ Test Case 5: Сканируем ТОЛЬКО Layer 1 (Террейн) и игнорируем Area3D/Layer 3
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
