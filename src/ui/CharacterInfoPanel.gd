# ==============================================================================
# CharacterInfoPanel.gd — HUD: FPS + время + инфо выбранного перса
# res://src/ui/CharacterInfoPanel.gd
# ==============================================================================
extends PanelContainer

@export var refresh_interval: float = 0.25
@export var margin: Vector2 = Vector2(12, 12)
@export var panel_size_compact: Vector2 = Vector2(200, 56)
@export var panel_size_expanded: Vector2 = Vector2(320, 200)

var _label: Label
var _timer: float = 0.0
var _selected: Node = null

func _ready() -> void:
	_apply_top_right_layout()
	_build_style()
	_build_label()
	get_viewport().size_changed.connect(_apply_top_right_layout)

func set_character(character: Node) -> void:
	if character != null and is_instance_valid(character):
		_selected = character
	else:
		_selected = null
	_apply_top_right_layout()
	_update_text()

func _process(delta: float) -> void:
	_timer += delta
	if _timer < refresh_interval:
		return
	_timer = 0.0
	if _selected != null and not is_instance_valid(_selected):
		_selected = null
		_apply_top_right_layout()
	_update_text()

func _apply_top_right_layout() -> void:
	var panel_size: Vector2 = panel_size_expanded if _selected != null else panel_size_compact
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
		_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_label.add_theme_font_size_override("font_size", 13)
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
	var text := "FPS:%d\n%s / %s" % [fps, year_month, time_str]
	var char_block := _format_character_block()
	if char_block != "":
		text += "\n" + char_block
	_label.text = text
	if fps < 30:
		_label.modulate = Color(1.0, 0.35, 0.35)
	elif fps < 50:
		_label.modulate = Color(1.0, 0.85, 0.3)
	else:
		_label.modulate = Color(0.7, 1.0, 0.7)

func _format_character_block() -> String:
	if _selected == null or not is_instance_valid(_selected):
		return ""
	var d = _selected.get("data")
	if d == null:
		return ""

	var name_str: String = str(d.character_name) if "character_name" in d else "?"
	var age: int = int(d.age) if "age" in d else 0
	var gender_letter := "M"
	if "gender" in d:
		gender_letter = "F" if int(d.gender) == 1 else "M"
	var talent: String = str(d.talent) if "talent" in d else "-"
	var hp: float = float(d.health) if "health" in d else 0.0
	var hunger: float = float(d.hunger) if "hunger" in d else 0.0
	var energy: float = float(d.energy) if "energy" in d else 0.0

	var lines: PackedStringArray = []
	# Name. 24yrs. M. forager
	lines.append("%s. %dyrs. %s. %s" % [name_str, age, gender_letter, talent])
	# HP / Hunger / Energy
	lines.append("HP:%.0f Hunger:%.0f Energy:%.0f" % [hp, hunger, energy])
	# forager:2 | worker:1 | …
	lines.append(_format_skills_line(d))
	# action: gathering | walk | carry:berry3 | delivering:berry3 | idle
	lines.append("action: %s" % _format_current_action())
	# speed / work / velocity
	lines.append(_format_speeds_line())
	return "\n".join(lines)

## Навыки, которые перс реально качал (level>0 или exp>0)
func _format_skills_line(d) -> String:
	var skills = d.get("skills") if d is Object else null
	if skills == null or not (skills is Dictionary) or skills.is_empty():
		return "skills: -"
	var parts: PackedStringArray = []
	for key in skills.keys():
		var entry = skills[key]
		var lvl: int = 0
		var exp_v: float = 0.0
		if entry is Dictionary:
			lvl = int(entry.get("level", 0))
			exp_v = float(entry.get("exp", 0.0))
		if lvl > 0 or exp_v > 0.0:
			parts.append("%s:%d" % [str(key), lvl])
	if parts.is_empty():
		return "skills: -"
	return " | ".join(parts)

## Текущее действие из current_state + инвентарь
func _format_current_action() -> String:
	var ch = _selected
	var state_val = ch.get("current_state")
	var state_name := "idle"
	# enum State { IDLE, MOVING, CARRIED, GATHERING, DELIVERING, CLEARING, EATING }
	if state_val != null:
		match int(state_val):
			0: state_name = "idle"
			1: state_name = "walk"
			2: state_name = "carried"
			3: state_name = "gather"
			4: state_name = "deliver"
			5: state_name = "clear"
			6: state_name = "eat"
			_:
				state_name = str(state_val)

	var d = ch.get("data")
	var item := ""
	var amount := 0
	if d != null:
		if "carried_item" in d:
			item = str(d.carried_item)
		if "item_amount" in d:
			amount = int(d.item_amount)

	var cargo := ""
	if item != "" and amount > 0:
		cargo = "%s%d" % [item, amount]

	if state_name == "walk" and cargo != "":
		return "carry: %s" % cargo
	if state_name == "deliver":
		if cargo != "":
			return "delivering: %s" % cargo
		return "delivering"
	if state_name == "gather":
		return "gather"
	if state_name == "eat":
		return "eat"
	if state_name == "clear":
		return "clear"
	if state_name == "carried":
		return "carried"
	if state_name == "idle":
		if cargo != "":
			return "idle (hold: %s)" % cargo
		return "idle"
	return state_name

func _format_speeds_line() -> String:
	var ch = _selected
	var move_spd: float = float(ch.get("speed")) if ch.get("speed") != null else 0.0
	var work_spd: float = float(ch.get("work_speed")) if ch.get("work_speed") != null else 0.0
	# effective work speed if available (talent/skill)
	var d = ch.get("data")
	if d != null and d.has_method("get_effective_work_speed"):
		# для отображения — talent или forager как типичный рабочий skill
		var skill_key: String = "forager"
		if "talent" in d and str(d.talent) != "":
			skill_key = str(d.talent)
		work_spd = float(d.get_effective_work_speed(skill_key))
	var vel: float = 0.0
	if "velocity" in ch:
		var v = ch.velocity
		if v is Vector3:
			vel = Vector2(v.x, v.z).length()
	return "spd:%.1f work:%.2f vel:%.2f" % [move_spd, work_spd, vel]

func _format_game_duration() -> String:
	var total_sec: float = 0.0
	if TimeManager:
		if TimeManager.has_method("get_total_game_seconds"):
			total_sec = TimeManager.get_total_game_seconds()
		elif TimeManager.has_method("get_total_game_minutes"):
			total_sec = float(TimeManager.get_total_game_minutes()) * 60.0
	var sec_i: int = maxi(int(total_sec), 0)
	return "%dd%dh%dm" % [sec_i / 86400, (sec_i % 86400) / 3600, (sec_i % 3600) / 60]
