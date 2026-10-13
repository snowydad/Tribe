# ==============================================================================
# ФАЙЛ: src/autoload/DevCheatManager.gd
# НАЗНАЧЕНИЕ: Чит-коды: time_scale + полный toggle debug (Dev* + nav + coll)
# ОБНОВЛЕНО: 2026-10-13 — Ctrl+D: все видимые дебаги вкл/выкл
# ==============================================================================
extends Node

## Dev* узлы + nav paths + collisions + navmesh server debug
var dev_overlays_on: bool = true


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.echo:
		return

	# Ctrl+D — весь видимый debug
	if event.keycode == KEY_D and event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
		toggle_dev_overlays()
		get_viewport().set_input_as_handled()
		return

	match event.keycode:
		KEY_0:
			Engine.time_scale = 0.0
			print("[DevCheat] Game paused (TimeScale: 0.0)")
		KEY_1:
			Engine.time_scale = 1.0
			print("[DevCheat] Normal speed (TimeScale: 1.0)")
		KEY_2:
			Engine.time_scale = 2.0
			print("[DevCheat] Fast speed (TimeScale: 2.0)")
		KEY_3:
			Engine.time_scale = 24.0
			print("[DevCheat] Ultra speed (TimeScale: 24.0)")
		KEY_4:
			Engine.time_scale = 1440.0
			print("[DevCheat] Hyper speed (TimeScale: 1440.0)")


func toggle_dev_overlays() -> void:
	dev_overlays_on = not dev_overlays_on
	_apply_all_debug(dev_overlays_on)
	print("[DevCheat] Debug ALL: %s (Dev* / nav paths / collisions / navmesh)" % (
		"ON" if dev_overlays_on else "OFF"
	))


func is_dev_overlays_on() -> bool:
	return dev_overlays_on


func _apply_all_debug(on: bool) -> void:
	# 1) узлы Dev* / dev*
	_set_dev_nodes_visible(get_tree().root, on)
	# 2) пути NavigationAgent3D
	_set_nav_agents_debug(get_tree().root, on)
	# 3) SceneTree hints (коллизии, navigation wire)
	var tree := get_tree()
	if tree:
		tree.debug_collisions_hint = on
		if "debug_paths_hint" in tree:
			tree.debug_paths_hint = on
		if "debug_navigation_hint" in tree:
			tree.debug_navigation_hint = on
	# 4) NavigationServer debug (нав-сетка в рантайме, если проект позволяет)
	if ClassDB.class_has_method("NavigationServer3D", "set_debug_enabled"):
		NavigationServer3D.set_debug_enabled(on)
	elif NavigationServer3D.has_method("set_debug_enabled"):
		NavigationServer3D.call("set_debug_enabled", on)


func _is_dev_node(n: Node) -> bool:
	var nm := str(n.name)
	return nm.begins_with("Dev") or nm.begins_with("dev")


func _set_dev_nodes_visible(root: Node, on: bool) -> void:
	if root == null:
		return
	if _is_dev_node(root):
		if root is CanvasItem:
			(root as CanvasItem).visible = on
		elif root is Node3D:
			(root as Node3D).visible = on
	for c in root.get_children():
		_set_dev_nodes_visible(c, on)


func _set_nav_agents_debug(root: Node, on: bool) -> void:
	if root == null:
		return
	if root is NavigationAgent3D:
		var ag := root as NavigationAgent3D
		if "debug_enabled" in ag:
			ag.debug_enabled = on
	for c in root.get_children():
		_set_nav_agents_debug(c, on)
