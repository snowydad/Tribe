# ==============================================================================
# TechTreePanel.gd — tech UI: start research (RP+prereq) → timer → known
# ОБНОВЛЕНО: 2026-10-28 — Build button for placeable known tech (step1)
# ==============================================================================
extends PanelContainer

## tech_id (e.g. "campfire") — placement later
signal build_requested(tech_id: String)

## known + can place in world
const BUILDABLE_TECHS: PackedStringArray = ["campfire"]

const MARGIN := 16.0
const NODE_W := 180.0
const NODE_H := 36.0

var _header: Label
var _scroll: ScrollContainer
var _map: Control
var _labels: Dictionary = {}

var _refresh_timer: float = 0.0
var _full_refresh_timer: float = 0.0
var _was_researching: bool = false
const HEADER_REFRESH_SEC := 0.25


func _process(_delta: float) -> void:
	if not visible:
		_was_researching = false
		return
	_refresh_timer += _delta
	if _refresh_timer < HEADER_REFRESH_SEC:
		return
	_refresh_timer = 0.0
	_refresh_header()
	if TechTree == null:
		return
	var now_r: bool = TechTree.is_researching()
	# research закончился при открытой панели → кнопки залипали на ~95%
	if _was_researching and not now_r:
		_was_researching = false
		_refresh()
		return
	_was_researching = now_r
	if now_r:
		_full_refresh_timer += HEADER_REFRESH_SEC
		if _full_refresh_timer >= 0.5:
			_full_refresh_timer = 0.0
			_refresh()


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 40
	offset_top = 56
	offset_right = -40
	offset_bottom = -40
	_build()
	if TechTree and TechTree.research_finished.is_connected(_on_research_finished) == false:
		TechTree.research_finished.connect(_on_research_finished)
	_refresh()


func _on_research_finished(_id: String) -> void:
	if visible:
		_was_researching = false
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


func _refresh_header() -> void:
	if _header == null or TechTree == null:
		return
	var extra := ""
	if TechTree.is_researching():
		var rid: String = TechTree.get_researching_id()
		var left: float = TechTree.get_research_remaining()
		var p01: float = TechTree.get_research_progress01()
		extra = "  |  %s %.0f%% (%.0fs)" % [rid, p01 * 100.0, left]
	_header.text = "Research  |  RP: %.0f  |  known: %d%s" % [
		TechTree.research_points,
		TechTree.get_known_ids().size(),
		extra,
	]


func _refresh() -> void:
	if TechTree == null:
		if _header:
			_header.text = "TechTree missing"
		return
	_refresh_header()
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
	var scale := 0.22
	_map.custom_minimum_size = Vector2(span_x * scale + NODE_W + MARGIN * 2, span_y * scale + NODE_H + MARGIN * 2)

	for id in ids:
		var d: Dictionary = TechTree.get_def(id)
		var x: float = float(d.get("pos_x", 0))
		var y: float = float(d.get("pos_y", 0))
		var cost: float = float(d.get("research_cost", 0))
		var rtime: float = float(d.get("research_time", cost))
		var known: bool = TechTree.is_known(id)
		var busy: bool = TechTree.is_researching(id)
		var prereq_ok: bool = _prereq_ok(id)
		var afford: bool = TechTree.can_afford(id)
		var can_start: bool = TechTree.can_start(id)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(NODE_W, NODE_H)
		btn.position = Vector2(MARGIN + (x - min_x) * scale, MARGIN + (y - min_y) * scale)

		if known:
			var can_build: bool = str(id) in BUILDABLE_TECHS
			if can_build:
				btn.disabled = false
				btn.modulate = Color(0.45, 0.85, 1.0)
				btn.text = "Build  %s" % id
				btn.tooltip_text = "Place %s in the world" % id
			else:
				btn.disabled = true
				btn.modulate = Color(0.55, 0.9, 0.6)
				btn.text = "✓ %s  %d" % [id, int(cost)]
		elif busy:
			var p01: float = TechTree.get_research_progress01()
			btn.disabled = true
			btn.modulate = Color(0.55, 0.75, 1.0)
			btn.text = "… %s  %d%%" % [id, int(p01 * 100.0)]
		elif prereq_ok:
			btn.disabled = not can_start
			btn.modulate = Color(1.0, 0.95, 0.55) if can_start else Color(0.85, 0.75, 0.4)
			btn.text = "○ %s  %dRP/%.0fs" % [id, int(cost), rtime]
		else:
			btn.disabled = true
			btn.modulate = Color(0.55, 0.55, 0.6)
			btn.text = "· %s  %d" % [id, int(cost)]

		if not (known and str(id) in BUILDABLE_TECHS):
			btn.tooltip_text = _tooltip(id, d, known, prereq_ok, afford, busy, can_start, rtime)
		var tech_id: String = id
		btn.pressed.connect(func (): _on_tech_pressed(tech_id))
		_map.add_child(btn)
		_labels[id] = btn


func _prereq_ok(id: String) -> bool:
	if TechTree == null or TechTree.is_known(id):
		return false
	var d: Dictionary = TechTree.get_def(id)
	for p in d.get("prerequisites", []):
		if not TechTree.is_known(str(p)):
			return false
	return true


func _tooltip(id: String, d: Dictionary, known: bool, prereq_ok: bool, afford: bool, busy: bool, can_start: bool, rtime: float) -> String:
	var pr: Array = d.get("prerequisites", [])
	var lines: PackedStringArray = PackedStringArray([
		id,
		"category: %s" % str(d.get("category", "")),
		"cost: %d RP" % int(d.get("research_cost", 0)),
		"time: %.0f s" % rtime,
		"prereq: %s" % (", ".join(pr) if pr.size() else "—"),
	])
	if known:
		lines.append("status: known")
	elif busy:
		lines.append("status: researching…")
	elif can_start:
		lines.append("status: click to start")
	elif prereq_ok and not afford:
		lines.append("status: need more RP")
	elif TechTree and TechTree.is_researching():
		lines.append("status: wait — other research")
	else:
		lines.append("status: locked")
	return "\n".join(lines)


func _on_tech_pressed(id: String) -> void:
	if TechTree == null:
		return
	# step1: known + buildable → signal only (placement later)
	if TechTree.is_known(id) and str(id) in BUILDABLE_TECHS:
		print("[TechTreePanel] Build requested: ", id)
		build_requested.emit(id)
		return
	if TechTree.is_known(id) or TechTree.is_researching():
		return
	if not TechTree.can_start(id):
		print("[TechTreePanel] cannot start ", id, " RP=", TechTree.research_points)
		_refresh()
		return
	TechTree.start_research(id)
	_refresh()
