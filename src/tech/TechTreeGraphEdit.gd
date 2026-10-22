# ==============================================================================
# TechTreeGraphEdit.gd — GraphEdit: connect/disconnect
# ОБНОВЛЕНО: 2026-10-22
# ==============================================================================
extends GraphEdit

func _ready() -> void:
	if not connection_request.is_connected(_on_connection_request):
		connection_request.connect(_on_connection_request)
	if not disconnection_request.is_connected(_on_disconnection_request):
		disconnection_request.connect(_on_disconnection_request)


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
