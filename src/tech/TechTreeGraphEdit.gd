# ==============================================================================
# TechTreeGraphEdit.gd — JSON source of truth (data/tech_tree.json)
# Кнопки Save / Load (Ctrl+S в Play часто перехватывает редактор)
# ОБНОВЛЕНО: 2026-10-22 — buttons, deferred edges, robust conn keys
# ==============================================================================
extends GraphEdit

const DEFAULT_PATH := "res://data/tech_tree.json"

@export var data_path: String = DEFAULT_PATH
@export var load_on_ready: bool = true

var _status: Label


func _ready() -> void:
	if not connection_request.is_connected(_on_connection_request):
		connection_request.connect(_on_connection_request)
	if not disconnection_request.is_connected(_on_disconnection_request):
		disconnection_request.connect(_on_disconnection_request)
	call_deferred("_make_toolbar")
	if load_on_ready:
		call_deferred("_deferred_load")


func _deferred_load() -> void:
	load_from_file()


func _make_toolbar() -> void:
	# панель поверх GraphEdit (не child GraphNode)
	var bar := HBoxContainer.new()
	bar.name = "TechToolbar"
	bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bar.position = Vector2(8, 8)
	bar.add_theme_constant_override("separation", 8)

	var b_save := Button.new()
	b_save.text = "Save JSON"
	b_save.pressed.connect(func (): save_to_file())
	bar.add_child(b_save)

	var b_load := Button.new()
	b_load.text = "Load JSON"
	b_load.pressed.connect(func (): load_from_file())
	bar.add_child(b_load)

	_status = Label.new()
	_status.text = data_path
	bar.add_child(_status)

	# toolbar не должен быть GraphNode-child логики — add as sibling overlay
	# GraphEdit is Control: add_child toolbar on parent if possible
	var host: Node = get_parent()
	if host:
		host.add_child.call_deferred(bar)
		bar.z_index = 100
	else:
		add_child.call_deferred(bar)


func _set_status(msg: String) -> void:
	print("[TechTree] ", msg)
	if _status:
		_status.text = msg


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)
	_set_status("connected %s → %s" % [from_node, to_node])


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)


func save_to_file(path: String = "") -> Error:
	if path.is_empty():
		path = data_path
	var data: Dictionary = export_data()
	var json_text: String = JSON.stringify(data, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err = FileAccess.get_open_error()
		_set_status("SAVE FAIL %s err=%s" % [path, err])
		return err
	f.store_string(json_text)
	f.close()
	var n: int = (data.get("nodes", []) as Array).size()
	var e: int = (data.get("edges", []) as Array).size()
	_set_status("SAVED %s  nodes=%d edges=%d" % [path, n, e])
	# debug dump
	print(json_text)
	return OK


func load_from_file(path: String = "") -> Error:
	if path.is_empty():
		path = data_path
	if not FileAccess.file_exists(path):
		_set_status("no file: " + path)
		return ERR_FILE_NOT_FOUND
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_set_status("LOAD FAIL open")
		return FileAccess.get_open_error()
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("LOAD FAIL json")
		return ERR_PARSE_ERROR
	import_data(parsed as Dictionary)
	var n: int = ((parsed as Dictionary).get("nodes", []) as Array).size()
	var e: int = ((parsed as Dictionary).get("edges", []) as Array).size()
	_set_status("LOADED %s  nodes=%d edges=%d" % [path, n, e])
	return OK


func export_data() -> Dictionary:
	var nodes: Array = []
	for c in get_children():
		if not (c is GraphNode):
			continue
		var gn: GraphNode = c
		var label_text: String = ""
		for ch in gn.get_children():
			if ch is Label:
				label_text = (ch as Label).text
				break
		var id: String = _node_id(gn)
		nodes.append({
			"id": id,
			"title": str(gn.title),
			"label": label_text if label_text != "" else str(gn.title),
			"pos": [gn.position_offset.x, gn.position_offset.y],
			"left": gn.is_slot_enabled_left(0),
			"right": gn.is_slot_enabled_right(0),
			"start_known": id == "campfire",
		})
	var edges: Array = []
	for conn in get_connection_list():
		print("[TechTree] raw conn: ", conn)
		var fro: String = ""
		var to: String = ""
		if conn is Dictionary:
			fro = str(conn.get("from_node", conn.get("from", "")))
			to = str(conn.get("to_node", conn.get("to", "")))
		if fro.is_empty() or to.is_empty():
			continue
		edges.append({
			"from": _id_from_graph_name(fro),
			"to": _id_from_graph_name(to),
		})
	return {"version": 1, "nodes": nodes, "edges": edges}


func import_data(data: Dictionary) -> void:
	clear_connections()
	var to_free: Array = []
	for c in get_children():
		if c is GraphNode:
			to_free.append(c)
	for c in to_free:
		remove_child(c)
		c.free()

	for n in data.get("nodes", []):
		if n is Dictionary:
			_spawn_node(n as Dictionary)

	# связи после кадра — слоты успевают
	var edges: Array = data.get("edges", [])
	call_deferred("_apply_edges", edges)


func _apply_edges(edges: Array) -> void:
	for e in edges:
		if not (e is Dictionary):
			continue
		var fro: String = _graph_name_from_id(str(e.get("from", "")))
		var to: String = _graph_name_from_id(str(e.get("to", "")))
		if not has_node(NodePath(fro)):
			push_warning("[TechTree] missing from: " + fro)
			continue
		if not has_node(NodePath(to)):
			push_warning("[TechTree] missing to: " + to)
			continue
		var err = connect_node(fro, 0, to, 0)
		print("[TechTree] connect ", fro, " → ", to, " err=", err)


func _spawn_node(n: Dictionary) -> void:
	var id: String = str(n.get("id", "tech")).to_lower()
	var gn := GraphNode.new()
	gn.name = _graph_name_from_id(id)
	gn.title = str(n.get("title", id))
	var pos = n.get("pos", [100.0, 100.0])
	if pos is Array and pos.size() >= 2:
		gn.position_offset = Vector2(float(pos[0]), float(pos[1]))
	gn.resizable = true
	var lab := Label.new()
	lab.text = str(n.get("label", n.get("title", id)))
	gn.add_child(lab)
	add_child(gn)
	var left_on: bool = bool(n.get("left", false))
	var right_on: bool = bool(n.get("right", false))
	# слот 0
	gn.set_slot_enabled_left(0, left_on)
	gn.set_slot_type_left(0, 0)
	gn.set_slot_enabled_right(0, right_on)
	gn.set_slot_type_right(0, 0)


func _node_id(gn: GraphNode) -> String:
	var n: String = str(gn.name)
	if n.begins_with("Tech_"):
		return n.substr(5).to_lower()
	return n.to_lower()


func _id_from_graph_name(graph_name: String) -> String:
	var g: String = graph_name
	if g.begins_with("Tech_"):
		return g.substr(5).to_lower()
	return g.to_lower()


func _graph_name_from_id(id: String) -> String:
	if id.is_empty():
		return "Tech_Unknown"
	var s: String = id.to_lower()
	return "Tech_" + s.substr(0, 1).to_upper() + s.substr(1)
