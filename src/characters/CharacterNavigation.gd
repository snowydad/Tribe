# ==============================================================================
# CharacterNavigation.gd — HOW: path / stuck / face / RVO
# WHAT — Decision / Task / character.start_* → go_to
# ОБНОВЛЕНО: 2026-10-17 — extract from character.gd (94a09ca + Nav fix)
# ==============================================================================
extends Node
class_name CharacterNavigation

signal arrived

var host: CharacterBody3D = null
var agent: NavigationAgent3D = null

var arrival_distance: float = 0.4
var max_step_distance: float = 0.3
var rotation_speed: float = 10.0
var stuck_time: float = 2.0
var stuck_max_cycles: int = 3
var stuck_side_distance: float = 1.0

## Цель A (WP) + текущая (может быть side B)
var goal_A: Vector3 = Vector3.ZERO
var goal: Vector3 = Vector3.ZERO

var _stuck_t: float = 0.0
var _stuck_cycles: int = 0
var _stuck_cd: float = 0.0
var _nav_side_step: bool = false
var _nav_direct_t: float = 0.0
var _nav_path: PackedVector3Array = PackedVector3Array()
var _nav_path_i: int = 0
var _last_pos_xz: Vector2 = Vector2.ZERO
var _active: bool = false


func setup(p_host: CharacterBody3D, p_agent: NavigationAgent3D) -> void:
	host = p_host
	agent = p_agent
	if agent:
		agent.target_desired_distance = arrival_distance
		agent.path_desired_distance = arrival_distance
		if not agent.velocity_computed.is_connected(_on_safe_velocity):
			agent.velocity_computed.connect(_on_safe_velocity)


func configure(
	p_arrival: float,
	p_max_step: float,
	p_rot: float,
	p_stuck_t: float,
	p_stuck_max: int,
	p_side: float
) -> void:
	arrival_distance = p_arrival
	max_step_distance = p_max_step
	rotation_speed = p_rot
	stuck_time = p_stuck_t
	stuck_max_cycles = p_stuck_max
	stuck_side_distance = p_side
	if agent:
		agent.target_desired_distance = arrival_distance
		agent.path_desired_distance = arrival_distance


func go_to(world_pos: Vector3) -> void:
	goal_A = world_pos
	goal = world_pos
	_nav_side_step = false
	_nav_direct_t = 0.0
	_stuck_t = 0.0
	_stuck_cycles = 0
	_stuck_cd = 0.0
	_nav_path = PackedVector3Array()
	_nav_path_i = 0
	_active = true
	if host:
		host.set("_current_target_pos", world_pos)
		_last_pos_xz = Vector2(host.global_position.x, host.global_position.z)
	if agent:
		agent.target_position = world_pos
		call_deferred("refresh_path")
		refresh_path()


func stop() -> void:
	_active = false
	_nav_direct_t = 0.0
	_stuck_t = 0.0


func is_active() -> bool:
	return _active


func tick(delta: float) -> void:
	if host == null or agent == null:
		_finish()
		return
	if not _active:
		return

	var current_pos: Vector3 = host.global_position
	var pos_xz := Vector2(current_pos.x, current_pos.z)
	var dist_to_final: float = pos_xz.distance_to(Vector2(goal.x, goal.z))

	# agent path + debug
	agent.target_position = goal
	var _agent_next: Vector3 = agent.get_next_path_position()

	if dist_to_final <= arrival_distance:
		_stop_h(delta)
		if _nav_side_step:
			_repath_A()
			host.move_and_slide()
			return
		_nav_direct_t = 0.0
		_stuck_t = 0.0
		_stuck_cycles = 0
		host.move_and_slide()
		_finish()
		return

	if _nav_direct_t > 0.0:
		_nav_direct_t -= delta
		_move_direct(delta, goal)
		return

	if agent.is_navigation_finished() and dist_to_final > arrival_distance:
		refresh_path()
		_nav_direct_t = 1.0
		_hard_nudge()
		_move_direct(delta, goal)
		return

	_stuck_cd = maxf(_stuck_cd - delta, 0.0)
	var hvel: float = Vector2(host.velocity.x, host.velocity.z).length()
	var moved: float = pos_xz.distance_to(_last_pos_xz)
	_last_pos_xz = pos_xz
	if _stuck_cd <= 0.0 and hvel < 0.1 and moved < 0.04:
		_stuck_t += delta
		var lim: float = minf(stuck_time, 1.0)
		if _stuck_t >= lim:
			_stuck_t = 0.0
			_stuck_cd = 0.4
			_stuck_cycles += 1
			if _stuck_cycles >= stuck_max_cycles:
				_hard_nudge()
				if pos_xz.distance_to(Vector2(goal.x, goal.z)) <= arrival_distance * 3.0:
					host.move_and_slide()
					_finish()
				else:
					_nav_direct_t = 1.2
					_move_direct(delta, goal)
				return
			var mode: int = _stuck_cycles % 3
			if mode == 0:
				if _nav_path_i < _nav_path.size() - 1:
					_nav_path_i += 1
				_nav_direct_t = 0.7
				_hard_nudge()
			elif mode == 1:
				refresh_path()
				_nav_direct_t = 1.0
				_hard_nudge()
			else:
				_step_aside()
			host.move_and_slide()
			return
	else:
		_stuck_t = 0.0

	var agent_path: PackedVector3Array = agent.get_current_navigation_path()
	if not agent_path.is_empty():
		if _nav_path.is_empty() or agent_path.size() != _nav_path.size():
			_nav_path = agent_path
			_nav_path_i = mini(_nav_path_i, maxi(_nav_path.size() - 1, 0))
	elif _nav_path.is_empty():
		refresh_path()

	var aim: Vector3 = goal
	if not _nav_path.is_empty():
		while _nav_path_i < _nav_path.size():
			var wp: Vector3 = _nav_path[_nav_path_i]
			var d_wp: float = Vector2(current_pos.x - wp.x, current_pos.z - wp.z).length()
			if d_wp <= maxf(arrival_distance, 0.35):
				_nav_path_i += 1
				continue
			aim = wp
			break
		if _nav_path_i >= _nav_path.size():
			aim = goal

	var dir: Vector3 = aim - current_pos
	dir.y = 0.0
	var next_dist: float = dir.length()
	if next_dist < 0.05:
		_nav_direct_t = 0.6
		_hard_nudge()
		_move_direct(delta, goal)
		return

	var move_dir: Vector3 = dir / next_dist
	var move_spd: float = _speed()
	var tvx: float = move_dir.x * move_spd
	var tvz: float = move_dir.z * move_spd
	var step_len2: float = Vector2(tvx * delta, tvz * delta).length()
	if step_len2 > max_step_distance and delta > 0.0:
		var cap2: float = max_step_distance / step_len2
		tvx *= cap2
		tvz *= cap2

	if agent.avoidance_enabled:
		agent.set_velocity(Vector3(tvx, host.velocity.y, tvz))
	else:
		host.velocity.x = tvx
		host.velocity.z = tvz
		face_dir(tvx, tvz, delta, 0.3)
		host.move_and_slide()


func refresh_path() -> void:
	if not agent or not host:
		return
	agent.target_position = goal
	var _poke: Vector3 = agent.get_next_path_position()
	_nav_path = agent.get_current_navigation_path()
	_nav_path_i = 0
	if _nav_path.is_empty():
		return
	var best_i: int = 0
	var best_d: float = INF
	for i in range(_nav_path.size()):
		var d: float = Vector2(
			host.global_position.x - _nav_path[i].x,
			host.global_position.z - _nav_path[i].z
		).length()
		if d < best_d:
			best_d = d
			best_i = i
	_nav_path_i = mini(best_i + 1, _nav_path.size() - 1)


func _move_direct(delta: float, to_goal: Vector3) -> void:
	var to := to_goal - host.global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= arrival_distance:
		_stop_h(delta)
		host.move_and_slide()
		return
	var move_dir := to / dist
	var move_spd: float = _speed()
	var vx: float = move_dir.x * move_spd
	var vz: float = move_dir.z * move_spd
	var step_len: float = Vector2(vx * delta, vz * delta).length()
	if step_len > max_step_distance and delta > 0.0:
		var cap: float = max_step_distance / step_len
		vx *= cap
		vz *= cap
	host.velocity.x = vx
	host.velocity.z = vz
	face_dir(vx, vz, delta, 0.25)
	host.move_and_slide()


func _step_aside() -> void:
	if not agent or not host:
		return
	if not _nav_side_step:
		goal_A = goal
	var side: Vector3 = _side_dir()
	var raw: Vector3 = host.global_position + side * stuck_side_distance
	var map_rid: RID = agent.get_navigation_map()
	var b: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, raw)
	_nav_side_step = true
	_stuck_t = 0.0
	_stuck_cd = stuck_time
	goal = b
	host.set("_current_target_pos", b)
	agent.target_position = b


func _repath_A() -> void:
	_nav_side_step = false
	_stuck_t = 0.0
	_stuck_cd = stuck_time
	_stuck_cycles += 1
	if _stuck_cycles >= stuck_max_cycles:
		_finish()
		return
	goal = goal_A
	host.set("_current_target_pos", goal_A)
	if agent:
		agent.target_position = goal_A


func _side_dir() -> Vector3:
	var away := _away_peer()
	if away.length_squared() > 0.01:
		return away.normalized()
	var to_a := goal_A - host.global_position
	to_a.y = 0.0
	if to_a.length_squared() > 0.01:
		var f := to_a.normalized()
		var side := Vector3(-f.z, 0.0, f.x)
		if (_stuck_cycles % 2) == 1:
			side = -side
		return side
	return Vector3(1.0, 0.0, 0.0)


func _away_peer() -> Vector3:
	if host == null:
		return Vector3.ZERO
	var tree := host.get_tree()
	if tree == null:
		return Vector3.ZERO
	var best_d := 2.5
	var best := Vector3.ZERO
	for n in tree.get_nodes_in_group("character"):
		if n == host or not (n is Node3D) or not is_instance_valid(n):
			continue
		var o: Node3D = n as Node3D
		var d: float = host.global_position.distance_to(o.global_position)
		if d < best_d and d > 0.01:
			best_d = d
			var v: Vector3 = host.global_position - o.global_position
			v.y = 0.0
			best = v
	return best


func _hard_nudge() -> void:
	if host == null:
		return
	var g: Vector3 = goal_A if goal_A != Vector3.ZERO else goal
	var to: Vector3 = g - host.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var raw: Vector3 = host.global_position + to.normalized() * 0.45
	if agent:
		var map_rid: RID = agent.get_navigation_map()
		raw = NavigationServer3D.map_get_closest_point(map_rid, raw)
	host.global_position.x = raw.x
	host.global_position.z = raw.z


func face_dir(dir_x: float, dir_z: float, delta: float, min_speed: float = 0.35) -> void:
	if host == null:
		return
	var dlen := Vector2(dir_x, dir_z).length()
	if dlen < min_speed:
		return
	var target_angle := atan2(-dir_x, -dir_z)
	var diff := absf(angle_difference(host.rotation.y, target_angle))
	if diff < 0.14:
		return
	var turn := rotation_speed * delta
	if diff < 0.5:
		turn *= 0.35
	host.rotation.y = lerp_angle(host.rotation.y, target_angle, clampf(turn, 0.0, 1.0))


func _on_safe_velocity(safe_velocity: Vector3) -> void:
	if host == null:
		return
	if host.get("is_being_dragged") == true:
		return
	if not host.is_on_floor():
		return
	# Nav fix: хотим velocity только в walk; иначе всё равно slide (гравитация)
	if host.has_method("nav_wants_safe_velocity") and host.nav_wants_safe_velocity():
		host.velocity.x = safe_velocity.x
		host.velocity.z = safe_velocity.z
		face_dir(safe_velocity.x, safe_velocity.z, host.get_physics_process_delta_time(), 0.4)
		host.move_and_slide()
	else:
		# state сменился, RVO всё равно пришёл
		host.move_and_slide()


func _speed() -> float:
	if host and host.has_method("get_current_move_speed"):
		return float(host.get_current_move_speed())
	return 5.0


func _stop_h(delta: float) -> void:
	if host == null:
		return
	if host.has_method("_stop_horizontal_movement"):
		host._stop_horizontal_movement(delta)
	else:
		host.velocity.x = move_toward(host.velocity.x, 0.0, 20.0 * delta)
		host.velocity.z = move_toward(host.velocity.z, 0.0, 20.0 * delta)


func _finish() -> void:
	if not _active:
		return
	_active = false
	arrived.emit()
