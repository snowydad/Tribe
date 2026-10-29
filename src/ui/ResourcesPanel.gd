# ==============================================================================
# ResourcesPanel.gd — top-left: pop / food / wood / stone / RP + FPS + time
# ОБНОВЛЕНО: 2026-10-28 — split from CharacterInfoPanel
# ==============================================================================
extends PanelContainer

@export var refresh_interval: float = 0.35
@export var margin: Vector2 = Vector2(12, 12)
@export var panel_size: Vector2 = Vector2(280, 72)

var _label: Label
var _timer: float = 0.0


func _ready() -> void:
	_apply_layout()
	_build_style()
	_build_label()
	get_viewport().size_changed.connect(_apply_layout)
	_update_text()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < refresh_interval:
		return
	_timer = 0.0
	_update_text()


func _apply_layout() -> void:
	# top-left
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	offset_left = margin.x
	offset_top = margin.y
	offset_right = margin.x + panel_size.x
	offset_bottom = margin.y + panel_size.y


func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
	style.border_color = Color(0.55, 0.7, 0.9, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)


func _build_label() -> void:
	_label = get_node_or_null("ResLabel") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "ResLabel"
		add_child(_label)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _update_text() -> void:
	if _label == null:
		return
	var pop := _count_population()
	var food := 0
	var wood := 0
	var stone := 0
	var stocks := _sum_storage()
	food = int(stocks.get("food", 0))
	wood = int(stocks.get("wood", 0))
	stone = int(stocks.get("stone", 0))
	var rp: float = 0.0
	if TechTree:
		rp = float(TechTree.research_points)

	var fps := Engine.get_frames_per_second()
	var year_month := "1.1"
	var time_str := "0d0h0m"
	if TimeManager:
		if TimeManager.has_method("get_display_year_month"):
			year_month = TimeManager.get_display_year_month()
		else:
			year_month = str(TimeManager.current_year)
		time_str = _format_game_duration()

	# line1 resources, line2 time/fps
	_label.text = "FPS:%d  %s / %s\nPop:%d  Food:%d  Wood:%d  Stone:%d  RP:%.0f" % [
		fps, year_month, time_str, pop, food, wood, stone, rp
	]
	if fps < 30:
		_label.modulate = Color(1.0, 0.35, 0.35)
	elif fps < 50:
		_label.modulate = Color(1.0, 0.85, 0.3)
	else:
		_label.modulate = Color(0.75, 0.9, 1.0)


func _count_population() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var n: int = 0
	for c in tree.get_nodes_in_group("character"):
		if c == null or not is_instance_valid(c):
			continue
		# dead?
		if "current_state" in c and int(c.current_state) == 7:
			continue
		if "data" in c and c.data != null and "health" in c.data and float(c.data.health) <= 0.0:
			continue
		n += 1
	return n


func _sum_storage() -> Dictionary:
	var food := 0
	var wood := 0
	var stone := 0
	var tree := get_tree()
	if tree == null:
		return {"food": 0, "wood": 0, "stone": 0}
	for s in tree.get_nodes_in_group("storage"):
		if s == null or not is_instance_valid(s):
			continue
		if "stored_food" in s:
			food += int(s.stored_food)
		if "stored_wood" in s:
			wood += int(s.stored_wood)
		if "stored_stone" in s:
			stone += int(s.stored_stone)
	return {"food": food, "wood": wood, "stone": stone}


func _format_game_duration() -> String:
	var total_sec: float = 0.0
	if TimeManager:
		if TimeManager.has_method("get_total_game_seconds"):
			total_sec = TimeManager.get_total_game_seconds()
		elif TimeManager.has_method("get_total_game_minutes"):
			total_sec = float(TimeManager.get_total_game_minutes()) * 60.0
	var sec_i: int = maxi(int(total_sec), 0)
	return "%dd%dh%dm" % [sec_i / 86400, (sec_i % 86400) / 3600, (sec_i % 3600) / 60]
