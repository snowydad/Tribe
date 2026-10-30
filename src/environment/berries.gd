# ОБНОВЛЕНО: 2026-10-14 — die wait from AnimationTree Die timeline_length (stretch)
# ОБНОВЛЕНО: 2026-10-09 — work_anim; nutrition из items.ini (fallback berries)
# ОБНОВЛЕНО: 2026-10-08 — WP: nearest free Marker3D (same as storage)
# ==============================================================================
# ОБНОВЛЕНО: 2026-10-06 — class_name BerriesSite; berry-логика только здесь
# berries.gd — куст ягод как WorkSite (данные из berries.ini)
# ОБНОВЛЕНО: 2026-10-04 21:22 CEST — life_cycles_max: после N полных сборов куст отмирает
# ==============================================================================
extends Node3D
class_name BerriesSite

@export_group("Crop Settings")
@export var max_berries: int = 5
@export var ripening_time: float = 15.0
@export var work_time: float = 3.0
@export var nutrition_value: float = 25.0
## Сколько раз можно обнулить урожай и снова созреть. 0 = бессрочно.
@export var life_cycles_max: int = 5

@export_group("Work (from ini)")
@export var work_type: String = "foraging"
@export var skill: String = "forager"
@export var work_anim: String = "gather_berries"
@export var resource_type: String = "berry"
@export var yield_amount: int = 1

@export_group("Work Points")
@export var work_points_parent: Node3D

@onready var dev_label: Label3D = $DevLabel

var current_berries: int = 5
var is_ripening: bool = false
var is_dead: bool = false
var _dying: bool = false  # die-anim in progress
## Сколько полных циклов (урожай снят до 0) уже прожито
var life_cycles_count: int = 0
var _ripen_timer: float = 0.0
var _occupied_slots: Dictionary = {}


func _ready() -> void:
	add_to_group("berries")
	add_to_group("interactable")
	add_to_group(WorkSite.GROUP)
	_ensure_dev_label_exists()
	_load_from_config()

	if not is_dead and current_berries <= 0 and not is_ripening:
		current_berries = max_berries

	_update_dev_ui()
	_update_visuals()


func _load_from_config() -> void:
	if not ConfigLoader:
		return

	var nut_fallback: float = nutrition_value

	# [work]
	if ConfigLoader.has_method("get_berries_value"):
		work_time = float(ConfigLoader.get_berries_value("work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_berries_value("work", "work_type", work_type))
		skill = str(ConfigLoader.get_berries_value("work", "skill", skill))
		work_anim = str(ConfigLoader.get_berries_value("work", "work_anim", work_anim))
		max_berries = int(ConfigLoader.get_berries_value("output", "max_amount", max_berries))
		ripening_time = float(ConfigLoader.get_berries_value("output", "ripening_time", ripening_time))
		resource_type = str(ConfigLoader.get_berries_value("output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_berries_value("output", "yield_amount", yield_amount))
		life_cycles_max = int(ConfigLoader.get_berries_value("output", "life_cycles_max", life_cycles_max))
		nut_fallback = float(ConfigLoader.get_berries_value("nutrition", "nutrition_value", nutrition_value))
	elif ConfigLoader.has_method("get_config_value"):
		work_time = float(ConfigLoader.get_config_value("berries", "work", "base_work_time", work_time))
		work_type = str(ConfigLoader.get_config_value("berries", "work", "work_type", work_type))
		skill = str(ConfigLoader.get_config_value("berries", "work", "skill", skill))
		work_anim = str(ConfigLoader.get_config_value("berries", "work", "work_anim", work_anim))
		max_berries = int(ConfigLoader.get_config_value("berries", "output", "max_amount", max_berries))
		ripening_time = float(ConfigLoader.get_config_value("berries", "output", "ripening_time", ripening_time))
		resource_type = str(ConfigLoader.get_config_value("berries", "output", "resource_type", resource_type))
		yield_amount = int(ConfigLoader.get_config_value("berries", "output", "yield_amount", yield_amount))
		life_cycles_max = int(ConfigLoader.get_config_value("berries", "output", "life_cycles_max", life_cycles_max))
		nut_fallback = float(ConfigLoader.get_config_value("berries", "nutrition", "nutrition_value", nutrition_value))
	else:
		return

	# сытость: items.ini → resource_type; иначе berries [nutrition]
	if ConfigLoader.has_method("get_item_nutrition"):
		nutrition_value = float(ConfigLoader.get_item_nutrition(resource_type, nut_fallback))
	else:
		nutrition_value = nut_fallback

	print("[Berries] Config: work=%s anim=%s skill=%s time=%.1f item=%s nut=%.0f cycles=%d" % [
		work_type, work_anim, skill, work_time, resource_type, nutrition_value, life_cycles_max
	])



func _process(delta: float) -> void:
	if is_dead:
		return
	if is_ripening:
		_ripen_timer += delta
		_update_dev_ui()
		if _ripen_timer >= ripening_time:
			is_ripening = false
			_ripen_timer = 0.0
			current_berries = max_berries
			_update_dev_ui()
			_update_visuals()
			print("[Berries] Crop fully ripe! All %d berries restored (cycle %d/%d)." % [
				max_berries, life_cycles_count, life_cycles_max
			])


# --- legacy API (совместимость) ---
func has_berries() -> bool:
	return not is_dead and current_berries > 0 and not is_ripening


func get_work_time() -> float:
	return work_time


func get_nutrition_value() -> float:
	return nutrition_value


func get_resource_type() -> String:
	return resource_type


func get_yield_amount() -> int:
	return yield_amount


func harvest_berry() -> bool:
	if is_dead or current_berries <= 0 or is_ripening:
		return false
	current_berries -= 1
	_update_dev_ui()
	_update_visuals()
	if current_berries <= 0:
		current_berries = 0
		_on_crop_emptied()
	return true


## Урожай снят до 0: либо новый цикл созревания, либо отмирание куста
func _on_crop_emptied() -> void:
	life_cycles_count += 1
	# life_cycles_max <= 0 → бесконечно
	if life_cycles_max > 0 and life_cycles_count >= life_cycles_max:
		_die_bush()
		return
	is_ripening = true
	_ripen_timer = 0.0
	_update_dev_ui()
	_update_visuals()
	print("[Berries] Harvested out — ripening cycle %d/%d..." % [life_cycles_count, life_cycles_max])


func _die_bush() -> void:
	if _dying:
		return
	_dying = true
	is_dead = true
	is_ripening = false
	_ripen_timer = 0.0
	current_berries = 0
	# больше не interact / work (пока крутится Die)
	if is_in_group("interactable"):
		remove_from_group("interactable")
	if is_in_group("berries"):
		remove_from_group("berries")
	if WorkSite and is_in_group(WorkSite.GROUP):
		remove_from_group(WorkSite.GROUP)
	var ia := get_node_or_null("InteractiveArea") as Area3D
	if ia:
		ia.monitoring = false
		ia.monitorable = false
	_update_dev_ui()
	_update_visuals()
	var spawn_at: Vector3 = _respawn_anchor_position()
	print("[Berries] Bush dying after %d cycles — play Die, then free @ %s" % [
		life_cycles_count, str(global_position)
	])
	_play_die_then_free(spawn_at)


func _find_bush_anim_player() -> AnimationPlayer:
	var ap := get_node_or_null("berries/AnimationPlayer") as AnimationPlayer
	if ap:
		return ap
	ap = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		return ap
	return _find_anim_player_recursive(self)


func _find_anim_player_recursive(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_anim_player_recursive(c)
		if f:
			return f
	return null


func _play_die_then_free(spawn_at: Vector3) -> void:
	# Time Length + Stretch в AnimationTree (state Die) — вот это «20s», не glb length
	var tree := get_node_or_null("berries/AnimationTree") as AnimationTree
	if tree == null:
		tree = get_node_or_null("AnimationTree") as AnimationTree
	var ap := _find_bush_anim_player()
	var die_name := _die_anim_name(ap)
	var wait_sec: float = _get_die_timeline_length(tree, ap, die_name)
	if tree:
		tree.active = true
		var pb = tree.get("parameters/playback")
		if pb != null and pb.has_method("travel"):
			pb.travel("Die")
	elif ap and die_name != "":
		ap.play(die_name)
	await get_tree().process_frame
	wait_sec = maxf(wait_sec, _get_die_timeline_length(tree, ap, die_name))
	wait_sec = maxf(wait_sec, 0.3)
	# если Stretch в tree не тянет клип — дотягиваем speed_scale (2s → 20s)
	if ap and die_name != "" and wait_sec > 0.1:
		var clip: float = 0.0
		if ap.has_animation(die_name):
			var a: Animation = ap.get_animation(die_name)
			if a:
				clip = a.length
		if clip > 0.05 and wait_sec > clip * 1.05:
			ap.speed_scale = clip / wait_sec
	print("[Berries] Die wait %.2fs (tree timeline / clip, speed_scale=%.3f)" % [
		wait_sec, ap.speed_scale if ap else 1.0
	])
	if ap and die_name != "" and ap.has_signal("animation_finished"):
		var finished: bool = false
		var on_fin := func(anim_name: StringName):
			var s := str(anim_name)
			if s == die_name or s.ends_with(die_name):
				finished = true
		ap.animation_finished.connect(on_fin, CONNECT_ONE_SHOT)
		var t0: float = 0.0
		while is_instance_valid(self) and not finished and t0 < wait_sec + 0.25:
			await get_tree().process_frame
			t0 += get_process_delta_time()
		if not finished and is_instance_valid(self):
			await get_tree().create_timer(maxf(wait_sec - t0, 0.0)).timeout
	else:
		await get_tree().create_timer(wait_sec).timeout
	if not is_instance_valid(self):
		return
	if ap:
		ap.speed_scale = 1.0
	_request_respawn_near(spawn_at)
	queue_free()


## AnimationTree Die: timeline_length (stretch) → иначе Animation.length
func _get_die_timeline_length(tree: AnimationTree, ap: AnimationPlayer, die_name: String) -> float:
	var from_tree: float = _read_tree_die_timeline(tree)
	if from_tree > 0.05:
		return from_tree
	if ap:
		if "current_animation_length" in ap and float(ap.current_animation_length) > 0.1:
			return float(ap.current_animation_length)
		if die_name != "" and ap.has_animation(die_name):
			var anim: Animation = ap.get_animation(die_name)
			if anim:
				return maxf(anim.length, 0.1)
	return 2.0


func _read_tree_die_timeline(tree: AnimationTree) -> float:
	if tree == null or tree.tree_root == null:
		return 0.0
	var root = tree.tree_root
	# StateMachine → node "Die" (AnimationNodeAnimation)
	if root is AnimationNodeStateMachine:
		var sm := root as AnimationNodeStateMachine
		if sm.has_method("has_node") and sm.has_node("Die"):
			var die_n = sm.get_node("Die")
			return _anim_node_timeline_len(die_n)
		# fallback: walk child names
		if sm.has_method("get_node_list"):
			for nm in sm.get_node_list():
				if str(nm) == "Die":
					return _anim_node_timeline_len(sm.get_node(nm))
	return _anim_node_timeline_len(root)


func _anim_node_timeline_len(node) -> float:
	if node == null:
		return 0.0
	# Godot 4.x AnimationNodeAnimation: timeline_length + stretch_time_scale
	if "timeline_length" in node:
		var tl: float = float(node.timeline_length)
		var stretch: bool = true
		if "stretch_time_scale" in node:
			stretch = bool(node.stretch_time_scale)
		elif "use_custom_timeline" in node:
			stretch = bool(node.use_custom_timeline)
		if stretch and tl > 0.05:
			return tl
		if tl > 0.05:
			return tl
	# generic get
	if node.has_method("get"):
		var tl2 = node.get("timeline_length")
		if tl2 != null and float(tl2) > 0.05:
			return float(tl2)
	return 0.0


func _die_anim_name(ap: AnimationPlayer) -> String:
	if ap == null:
		return ""
	for n in ["Die", "die", "DIE"]:
		if ap.has_animation(n):
			return n
	return ""



## Точка, рядом с которой потом заспавнить новый куст (WP или своя позиция)
func _respawn_anchor_position() -> Vector3:
	var markers: Array = _work_markers()
	if markers.size() > 0 and markers[0] is Marker3D:
		return (markers[0] as Marker3D).global_position
	return global_position


## STUB: заспавнить новый куст у anchor (сейчас только лог / хук)
## Позже: instantiate berries.tscn, parent = get_parent(), position ≈ anchor
func _request_respawn_near(anchor: Vector3) -> void:
	# TODO: var scene = preload("res://src/environment/berries.tscn")
	# TODO: var bush = scene.instantiate()
	# TODO: get_parent().add_child(bush)
	# TODO: bush.global_position = anchor + offset
	print("[Berries] TODO respawn near WP/anchor %s" % str(anchor))


# --- WorkSite contract ---
func can_accept_work(_worker: Node = null) -> bool:
	return has_berries()


func get_work_skill() -> String:
	return skill


func get_work_type() -> String:
	return work_type


func get_work_anim() -> String:
	return work_anim


func do_work(_worker: Node = null) -> Dictionary:
	if not harvest_berry():
		return {"ok": false, "reason": "not_ready" if not is_dead else "dead"}
	var nut: float = nutrition_value
	if ConfigLoader and ConfigLoader.has_method("get_item_nutrition"):
		nut = float(ConfigLoader.get_item_nutrition(resource_type, nutrition_value))
	return {
		"ok": true,
		"give": {"item": resource_type, "amount": yield_amount},
		"xp_skill": skill,
		"work_type": work_type,
		"work_anim": work_anim,
		"nutrition": nut,
	}


func _work_markers() -> Array:
	var out: Array = []
	var container: Node3D = work_points_parent if work_points_parent else get_node_or_null("WorkPoints") as Node3D
	if container == null:
		return out
	for c in container.get_children():
		if c is Marker3D:
			out.append(c)
	return out


func get_free_work_point(requester: Node3D = null) -> Vector3:
	var markers: Array = _work_markers()
	var req_id: int = requester.get_instance_id() if requester else 0
	var from_pos: Vector3 = requester.global_position if requester != null and is_instance_valid(requester) else global_position

	var used_by_others: Dictionary = {}
	for rid in _occupied_slots.keys():
		if int(rid) == req_id:
			continue
		used_by_others[int(_occupied_slots[rid])] = true

	var best_i: int = -1
	var best_d: float = INF
	for i in range(markers.size()):
		if used_by_others.has(i):
			continue
		var m: Node3D = markers[i] as Node3D
		if m == null:
			continue
		var d: float = from_pos.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best_i = i

	if best_i >= 0:
		if req_id != 0:
			_occupied_slots[req_id] = best_i
		return (markers[best_i] as Node3D).global_position

	var slot_index: int = _find_next_free_slot_index()
	if req_id != 0:
		_occupied_slots[req_id] = slot_index
	var angle: float = float(slot_index) * (PI / 3.0)
	var offset = Vector3(cos(angle), 0.0, sin(angle)) * 1.0
	return global_position + offset


func release_work_point(requester: Node3D) -> void:
	if requester and _occupied_slots.has(requester.get_instance_id()):
		_occupied_slots.erase(requester.get_instance_id())


func _find_next_free_slot_index() -> int:
	var used_slots = _occupied_slots.values()
	var candidate: int = 0
	while candidate in used_slots:
		candidate += 1
	return candidate



func get_display_name() -> String:
	if Loc and Loc.has_method("object_name"):
		return Loc.object_name("berries")
	return "Berries"


func get_info_text() -> String:
	if has_method("_update_dev_ui"):
		_update_dev_ui()
	var dl = get_node_or_null("DevLabel") as Label3D
	if dl != null and str(dl.text).strip_edges() != "":
		return str(dl.text)
	return name


func _update_dev_ui() -> void:
	if not dev_label:
		return
	var show_dev := true
	if DevCheatManager and DevCheatManager.has_method("is_dev_overlays_on"):
		show_dev = DevCheatManager.is_dev_overlays_on()
	dev_label.visible = show_dev
	var life := "∞" if life_cycles_max <= 0 else "%d/%d" % [life_cycles_count, life_cycles_max]
	if is_dead:
		dev_label.text = "Berries: DEAD\nCycles: %s\nWork: %s" % [life, work_type]
	elif is_ripening:
		var progress: float = clampf((_ripen_timer / maxf(ripening_time, 0.001)) * 100.0, 0.0, 100.0)
		dev_label.text = "Berries: 0/%d\n[Ripening: %.0f%%]\nCycles: %s" % [max_berries, progress, life]
	else:
		dev_label.text = "Berries: %d/%d (Nutr: +%.0f)\nCycles: %s\n%s | %s\n%s" % [
			current_berries, max_berries, nutrition_value, life, work_type, skill, work_anim
		]


func _ensure_dev_label_exists() -> void:
	if not dev_label:
		dev_label = get_node_or_null("DevLabel") as Label3D
	if not dev_label:
		dev_label = Label3D.new()
		dev_label.name = "DevLabel"
		dev_label.position = Vector3(0.0, 1.5, 0.0)
		dev_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dev_label.no_depth_test = true
		dev_label.pixel_size = 0.005
		dev_label.modulate = Color(1.0, 0.8, 0.2)
		add_child(dev_label)


func _update_visuals() -> void:
	# AnimationTree (Wind/Still) читает current_berries; мёртвый куст = 0
	pass
