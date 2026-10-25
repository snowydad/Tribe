# ==============================================================================
# TechTreePanel.gd — простая панель tech (текст + cost), позиции из JSON
# Toggle кнопкой Research (main).
# ОБНОВЛЕНО: 2026-10-24
# ==============================================================================
extends PanelContainer

const MARGIN := 16.0
const NODE_W := 140.0
const NODE_H := 36.0

var _canvas: Control
var _header: Label
var _scroll: ScrollContainer
var _map: Control
var _labels: Dictionary = {}  # id -> Label

var _refresh_timer: float = 0.0
var _full_refresh_timer: float = 0.0
const HEADER_REFRESH_SEC := 0.25
const FULL_REFRESH_SEC := 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	# только RP в шапке — полная пересборка кнопок жрёт FPS
	_refresh_timer += delta
	if _refresh_timer >= HEADER_REFRESH_SEC:
		_refresh_timer = 0.0
		_refresh_header()


func _refresh_header() -> void:
	if _header == null or TechTree == null:
		return
	_header.text = "Research  |  RP: %.0f  |  known: %d" % [
		TechTree.research_points,
		TechTree.get_known_ids().size()
	]




func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_top = 56
	offset_right = -40
	offset_bottom = -40
	_build()
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _build() -> void:
	# style
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	sb.border_color = Color(0.35, 0.4, 0.55, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)

	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.text = "Research"
	top.add_child(_header)

	var btn_kp := Button.new()
	btn_kp.text = "+50 RP"
	btn_kp.tooltip_text = "dev: add Research Points"
	btn_kp.pressed.connect(func ():
		if TechTree:
			TechTree.add_research_points(50.0)
			_refresh()
	)
	top.add_child(btn_kp)

	var btn_close := Button.new()
	btn_close.text = "Close"
	btn_close.pressed.connect(close)
	top.add_child(btn_close)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(_scroll)

	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_map)


func _refresh() -> void:
	if TechTree == null:
		if _header:
			_header.text = "TechTree missing"
		return
	_header.text = "Research  |  RP: %.0f  |  known: %d" % [
		TechTree.research_points,
		TechTree.get_known_ids().size()
	]
	# clear old labels
	for c in _map.get_children():
		c.queue_free()
	_labels.clear()

	var ids: PackedStringArray = TechTree.get_all_ids()
	if ids.is_empty():
		return

	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	for id in ids:
		var d: Dictionary = TechTree.get_def(id)
		var x: float = float(d.get("pos_x", 0))
		var y: float = float(d.get("pos_y", 0))
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)

	var span_x: float = maxf(max_x - min_x, 1.0)
	var span_y: float = maxf(max_y - min_y, 1.0)
	# map size: ~ scale so spacing readable left→right
	var scale := 0.22
	var map_w: float = span_x * scale + NODE_W + MARGIN * 2
	var map_h: float = span_y * scale + NODE_H + MARGIN * 2
	_map.custom_minimum_size = Vector2(map_w, map_h)

	for id in ids:
		var d: Dictionary = TechTree.get_def(id)
		var x: float = float(d.get("pos_x", 0))
		var y: float = float(d.get("pos_y", 0))
		var cost: float = float(d.get("research_cost", 0))
		var known: bool = TechTree.is_known(id)
		var avail: bool = TechTree.can_research(id)
		var afford: bool = TechTree.can_afford(id)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(NODE_W, NODE_H)
		btn.position = Vector2(
			MARGIN + (x - min_x) * scale,
			MARGIN + (y - min_y) * scale
		)
		var mark := ""
		if known:
			mark = "✓ "
			btn.disabled = true
			btn.modulate = Color(0.55, 0.9, 0.6)
		elif avail:
			mark = "○ "
			btn.disabled = false
			btn.modulate = Color(1.0, 0.95, 0.55) if afford else Color(0.85, 0.75, 0.4)
		else:
			mark = "· "
			btn.disabled = true
			btn.modulate = Color(0.55, 0.55, 0.6)

		btn.text = "%s%s  %d" % [mark, id, int(cost)]
		btn.tooltip_text = _tooltip(id, d, known, avail, afford)
		var tech_id: String = id
		btn.pressed.connect(func (): _on_tech_pressed(tech_id))
		_map.add_child(btn)
		_labels[id] = btn


func _tooltip(id: String, d: Dictionary, known: bool, avail: bool, afford: bool) -> String:
	var pr: Array = d.get("prerequisites", [])
	var lines: PackedStringArray = PackedStringArray([
		id,
		"category: %s" % str(d.get("category", "")),
		"cost: %d RP" % int(d.get("research_cost", 0)),
		"prereq: %s" % (", ".join(pr) if pr.size() else "—"),
	])
	if known:
		lines.append("status: known")
	elif avail and afford:
		lines.append("status: can research (click)")
	elif avail:
		lines.append("status: need more RP")
	else:
		lines.append("status: locked")
	return "\n".join(lines)


func _on_tech_pressed(id: String) -> void:
	if TechTree == null:
		return
	if TechTree.is_known(id):
		return
	if not TechTree.can_research(id):
		return
	if not TechTree.can_afford(id):
		print("[TechTreePanel] need RP for ", id, " have=", TechTree.research_points)
		_refresh()
		return
	TechTree.research(id, true)
	_refresh()
