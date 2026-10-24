# ==============================================================================
# TechTree.gd — runtime tech tree from assets/data/tech_tree.json
# RP = Research Points (все персы вкладывают; пока 1 RP за полезную работу)
# known = techs with empty prerequisites at start
# ОБНОВЛЕНО: 2026-10-24 — KP → RP
# ==============================================================================
extends Node

const DATA_PATH: String = "res://assets/data/tech_tree.json"

## id -> { category, research_cost, pos_x, pos_y, prerequisites: Array }
var _defs: Dictionary = {}

## открытые технологии (id -> true)
var _known: Dictionary = {}

## Research Points (RP) — валюта research_cost
var research_points: float = 0.0


func _ready() -> void:
	reload()


func reload() -> void:
	_defs.clear()
	_known.clear()
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
		_defs[str(id)] = {
			"category": str(d.get("category", "")),
			"research_cost": float(d.get("research_cost", 0)),
			"pos_x": float(d.get("pos_x", 0)),
			"pos_y": float(d.get("pos_y", 0)),
			"prerequisites": prereq,
		}
	_init_roots_known()
	print("[TechTree] loaded %d techs, known roots: %s" % [_defs.size(), str(get_known_ids())])


func _init_roots_known() -> void:
	for id in _defs.keys():
		var prereq: Array = _defs[id].get("prerequisites", [])
		if prereq.is_empty():
			_known[id] = true


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


func can_research(id: String) -> bool:
	if not _defs.has(id):
		return false
	if is_known(id):
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


func can_unlock(id: String) -> bool:
	return can_research(id) and can_afford(id)


func research(id: String, spend_cost: bool = true) -> bool:
	if is_known(id):
		return false
	if not can_research(id):
		return false
	if spend_cost:
		if not can_afford(id):
			return false
		research_points -= float(_defs[id].get("research_cost", 0))
	_known[id] = true
	print("[TechTree] researched: %s (RP=%.0f)" % [id, research_points])
	return true


func force_know(id: String) -> void:
	if _defs.has(id):
		_known[id] = true


## +RP (полезный труд, dev-кнопка, later per-talent)
func add_research_points(amount: float) -> void:
	research_points += amount


## 1 RP за завершённый полезный цикл работы
func award_work_rp(amount: float = 1.0) -> void:
	add_research_points(amount)


func get_available_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		if can_research(str(id)):
			out.append(str(id))
	return out


func get_by_category(category: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _defs.keys():
		if str(_defs[id].get("category", "")) == category:
			out.append(str(id))
	return out
