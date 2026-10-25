# ==============================================================================
# TechTree.gd — runtime tech tree (assets/data/tech_tree.json)
# RP + timed research: click starts → timer → known
# research_time (sec) in JSON; fallback = research_cost
# ОБНОВЛЕНО: 2026-10-25 — start_research + tick
# ==============================================================================
extends Node

const DATA_PATH: String = "res://assets/data/tech_tree.json"

signal research_started(id: String)
signal research_finished(id: String)
signal research_progress(id: String, progress: float, duration: float)

## id -> { category, research_cost, research_time, pos_x, pos_y, prerequisites }
var _defs: Dictionary = {}
var _known: Dictionary = {}

## Research Points
var research_points: float = 0.0

## текущее исследование (одно)
var researching_id: String = ""
var research_elapsed: float = 0.0
var research_duration: float = 0.0


func _ready() -> void:
	reload()


func _process(delta: float) -> void:
	if researching_id.is_empty():
		return
	research_elapsed += delta
	research_progress.emit(researching_id, research_elapsed, research_duration)
	if research_elapsed >= research_duration:
		_complete_research()


func reload() -> void:
	_defs.clear()
	_known.clear()
	_cancel_research_state()
	if not FileAccess.file_exists(DATA_PATH):
		push_error("[TechTree] missing: %s" % DATA_PATH)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("[TechTree] open fail: %s" % DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[TechTree] bad JSON root")
		return
	for id in parsed.keys():
		var raw: Variant = parsed[id]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var prereq: Array = []
		var pr = d.get("prerequisites", [])
		if pr is Array:
			for p in pr:
				prereq.append(str(p))
		var cost: float = float(d.get("research_cost", 0))
		# время: явное research_time, иначе research_cost как секунды
		var rtime: float = float(d.get("research_time", cost))
		if rtime <= 0.0:
			rtime = maxf(cost, 1.0)
		_defs[str(id)] = {
			"category": str(d.get("category", "")),
			"research_cost": cost,
			"research_time": rtime,
			"pos_x": float(d.get("pos_x", 0)),
			"pos_y": float(d.get("pos_y", 0)),
			"prerequisites": prereq,
		}
	_init_roots_known()
	print("[TechTree] loaded %d techs, known: %s" % [_defs.size(), str(get_known_ids())])


func _init_roots_known() -> void:
	for id in _defs.keys():
		var prereq: Array = _defs[id].get("prerequisites", [])
		if prereq.is_empty():
			_known[id] = true


func _cancel_research_state() -> void:
	researching_id = ""
	research_elapsed = 0.0
	research_duration = 0.0


func has_def(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> Dictionary:
	if not _defs.has(id):
		return {}
	return (_defs[id] as Dictionary).duplicate(true)


func get_all_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		out.append(str(id))
	return out


func get_known_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _known.keys():
		if _known[id]:
			out.append(str(id))
	return out


func is_known(id: String) -> bool:
	return bool(_known.get(id, false))


func is_researching(id: String = "") -> bool:
	if id.is_empty():
		return not researching_id.is_empty()
	return researching_id == id


func get_researching_id() -> String:
	return researching_id


## 0..1
func get_research_progress01() -> float:
	if researching_id.is_empty() or research_duration <= 0.0:
		return 0.0
	return clampf(research_elapsed / research_duration, 0.0, 1.0)


func get_research_remaining() -> float:
	if researching_id.is_empty():
		return 0.0
	return maxf(research_duration - research_elapsed, 0.0)


func can_research(id: String) -> bool:
	if not _defs.has(id):
		return false
	if is_known(id):
		return false
	if is_researching():  # занято другим
		return false
	var prereq: Array = _defs[id].get("prerequisites", [])
	for p in prereq:
		if not is_known(str(p)):
			return false
	return true


func can_afford(id: String) -> bool:
	if not _defs.has(id):
		return false
	return research_points >= float(_defs[id].get("research_cost", 0))


## prereq + RP + не идёт другое исследование
func can_start(id: String) -> bool:
	return can_research(id) and can_afford(id)


## Запуск по клику: списать RP, тикать research_time сек
func start_research(id: String) -> bool:
	if not can_start(id):
		return false
	var cost: float = float(_defs[id].get("research_cost", 0))
	research_points -= cost
	researching_id = id
	research_elapsed = 0.0
	research_duration = float(_defs[id].get("research_time", maxf(cost, 1.0)))
	print("[TechTree] start %s  time=%.1fs  RP left=%.0f" % [id, research_duration, research_points])
	research_started.emit(id)
	return true


func _complete_research() -> void:
	var id: String = researching_id
	if id.is_empty():
		return
	_known[id] = true
	print("[TechTree] finished: %s" % id)
	_cancel_research_state()
	research_finished.emit(id)


## Мгновенно (чит / legacy). spend_cost — списать RP
func research(id: String, spend_cost: bool = true) -> bool:
	if is_known(id):
		return false
	if not _defs.has(id):
		return false
	# prereq
	for p in _defs[id].get("prerequisites", []):
		if not is_known(str(p)):
			return false
	if spend_cost:
		if not can_afford(id):
			return false
		research_points -= float(_defs[id].get("research_cost", 0))
	if researching_id == id:
		_cancel_research_state()
	_known[id] = true
	print("[TechTree] instant: %s (RP=%.0f)" % [id, research_points])
	research_finished.emit(id)
	return true


func force_know(id: String) -> void:
	if _defs.has(id):
		_known[id] = true
		if researching_id == id:
			_cancel_research_state()


func add_research_points(amount: float) -> void:
	research_points += amount


func award_work_rp(amount: float = 1.0) -> void:
	add_research_points(amount)


func get_available_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		# available = prereq ok, not known (может не can_research если уже researching other)
		if is_known(str(id)):
			continue
		var ok := true
		for p in _defs[id].get("prerequisites", []):
			if not is_known(str(p)):
				ok = false
				break
		if ok:
			out.append(str(id))
	return out


func get_by_category(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		if str(_defs[id].get("category", "")) == category:
			out.append(str(id))
	return out
