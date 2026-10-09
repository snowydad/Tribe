# ==============================================================================
# WorkSite — контракт «универсальной работы» для интерактивных объектов мира.
#
# Объект (куст, склад, гриб, грядка, дом…) описывает работу сам + в .ini.
# Персонаж только: дойти → ждать get_work_time → do_work → применить результат.
#
# Обязательные методы на Node3D:
#   can_accept_work(worker: Node) -> bool
#   get_work_time() -> float
#   get_work_skill() -> String
#   get_work_type() -> String   # harvest | deposit | clear | build | ...
#   do_work(worker: Node) -> Dictionary
#   get_free_work_point(worker: Node) -> Vector3
#   release_work_point(worker: Node) -> void
#
# do_work() возвращает, например:
#   { "ok": true,  "give": {"item":"berry","amount":1}, "xp_skill":"forager", "nutrition":25.0 }
#   { "ok": true,  "take": {"item":"berry","amount":1}, "xp_skill":"trader" }
#   { "ok": false, "reason": "not_ready" }
# ==============================================================================
class_name WorkSite
extends RefCounted

const GROUP := "work_site"

## Узел реализует контракт WorkSite?
static func is_site(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_in_group(GROUP):
		return true
	return node.has_method("do_work") and node.has_method("can_accept_work")


static func can_accept(node: Node, worker: Node = null) -> bool:
	if not is_site(node):
		return false
	return bool(node.call("can_accept_work", worker))


static func get_time(node: Node, fallback: float = 1.0) -> float:
	if node and node.has_method("get_work_time"):
		return float(node.call("get_work_time"))
	return fallback


static func get_skill(node: Node, fallback: String = "worker") -> String:
	if node and node.has_method("get_work_skill"):
		return str(node.call("get_work_skill"))
	if node and "skill" in node:
		return str(node.skill)
	return fallback


static func get_anim(node: Node, fallback: String = "work") -> String:
	if node and node.has_method("get_work_anim"):
		var a := str(node.call("get_work_anim"))
		if a != "":
			return a
	if node and "work_anim" in node:
		var a2 := str(node.work_anim)
		if a2 != "":
			return a2
	return fallback


static func get_type(node: Node, fallback: String = "") -> String:
	if node and node.has_method("get_work_type"):
		return str(node.call("get_work_type"))
	if node and "work_type" in node:
		return str(node.work_type)
	return fallback


## Категория для маршрутизации FSM перса: harvest / deposit / clear / build / other
static func get_category(node: Node) -> String:
	var t := get_type(node).to_lower()
	match t:
		"foraging", "harvest", "gather", "mine", "chop":
			return "harvest"
		"delivering", "deposit", "store", "unload":
			return "deposit"
		"clear", "clearing", "demolish":
			return "clear"
		"build", "building", "construct":
			return "build"
		_:
			# эвристики по старым API
			if node and (node.has_method("deposit_food") or node.is_in_group("storage")):
				return "deposit"
			if node and (node.has_method("clear_obstacle") or node.is_in_group("obstacle")):
				return "clear"
			return "other"


static func do_work(node: Node, worker: Node) -> Dictionary:
	if not is_site(node):
		return {"ok": false, "reason": "not_a_work_site"}
	var result = node.call("do_work", worker)
	if result is Dictionary:
		return result
	return {"ok": false, "reason": "bad_result"}


static func xp_from_config() -> float:
	if ConfigLoader:
		if ConfigLoader.has_method("get_config_value"):
			return float(ConfigLoader.get_config_value("skills", "skill_progression", "xp_per_work_cycle", 10.0))
		if ConfigLoader.has_method("get_skill_value"):
			return float(ConfigLoader.get_skill_value("skill_progression", "xp_per_work_cycle", 10.0))
	return 10.0
