# ==============================================================================
# CharacterInfoPanel.gd — простой HUD: FPS + игровое время
# ==============================================================================
extends PanelContainer

@export var refresh_interval: float = 0.25
@export var margin: Vector2 = Vector2(12, 12)
@export var panel_size: Vector2 = Vector2(200, 56)

var _label: Label
var _timer: float = 0.0

func _ready() -> void:
	_apply_top_right_layout()
	_build_style()
	_build_label()
	get_viewport().size_changed.connect(_apply_top_right_layout)

func _process(delta: float) -> void:
	_timer += delta
	if _timer < refresh_interval:
		return
	_timer = 0.0
	_update_text()

func _apply_top_right_layout() -> void:
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END

	offset_left = -panel_size.x - margin.x
	offset_top = margin.y
	offset_right = -margin.x
	offset_bottom = margin.y + panel_size.y

func _build_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
	style.border_color = Color(0.4, 0.75, 0.4, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)

func _build_label() -> void:
	_label = get_node_or_null("HudLabel") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "HudLabel"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 14)
		add_child(_label)
	_update_text()

func _update_text() -> void:
	if _label == null:
		return

	var fps := Engine.get_frames_per_second()

	var year_month := "1.1"
	var time_str := "0d0h0m"
	if TimeManager:
		if TimeManager.has_method("get_display_year_month"):
			year_month = TimeManager.get_display_year_month()
		else:
			year_month = str(TimeManager.current_year)
		time_str = _format_game_duration()

	# FPS:60
	# 11.1 / 0d0h33m
	_label.text = "FPS:%d\n%s / %s" % [fps, year_month, time_str]

	if fps < 30:
		_label.modulate = Color(1.0, 0.35, 0.35)
	elif fps < 50:
		_label.modulate = Color(1.0, 0.85, 0.3)
	else:
		_label.modulate = Color(0.7, 1.0, 0.7)

## Симулированное время → "XXdXXhXXm"
func _format_game_duration() -> String:
	var total_sec: float = 0.0
	if TimeManager:
		if TimeManager.has_method("get_total_game_seconds"):
			total_sec = TimeManager.get_total_game_seconds()
		elif TimeManager.has_method("get_total_game_minutes"):
			total_sec = float(TimeManager.get_total_game_minutes()) * 60.0
		else:
			var y: int = int(TimeManager.current_year) if "current_year" in TimeManager else 1
			var spy: float = float(TimeManager.seconds_per_year) if "seconds_per_year" in TimeManager else 86400.0
			total_sec = float(max(y - 1, 0)) * spy

	var sec_i: int = maxi(int(total_sec), 0)
	var days: int = sec_i / 86400
	var hours: int = (sec_i % 86400) / 3600
	var mins: int = (sec_i % 3600) / 60
	return "%dd%dh%dm" % [days, hours, mins]
