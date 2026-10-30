# ==============================================================================
# Loc.gd — строки UI: ui_character.csv (+ позже ui.csv). Locale = OS, потом settings.
# Формат csv: id,comment,ru,en  (как names.csv)
# ОБНОВЛЕНО: 2026-10-30 — objects.csv
# ==============================================================================
extends Node

## en | ru (и др. → fallback en)
var locale: String = "en"

## file_key → { ID: { "ru": "...", "en": "..." } }
var _tables: Dictionary = {}


func _ready() -> void:
	_detect_system_locale()
	load_character_strings()
	load_object_strings()
	print("[Loc] locale=%s tables=%s" % [locale, str(_tables.keys())])


func _detect_system_locale() -> void:
	var sys: String = OS.get_locale_language().to_lower()
	# ru_RU → ru
	if sys.begins_with("ru"):
		locale = "ru"
	else:
		locale = "en"
	# Godot tr() для names.csv
	TranslationServer.set_locale(locale)


## Смена языка (настройки позже)
func set_locale(code: String) -> void:
	var c: String = code.strip_edges().to_lower()
	if c.begins_with("ru"):
		locale = "ru"
	else:
		locale = "en"
	TranslationServer.set_locale(locale)


func load_character_strings() -> void:
	_load_csv("res://assets/strings/ui_character.csv", "ui_character")


func load_object_strings() -> void:
	_load_csv("res://assets/strings/objects.csv", "objects")


## имя объекта: OBJ_CAMPFIRE / campfire / shelter → локализовано
func object_name(key: String) -> String:
	var k := str(key).strip_edges()
	if k == "":
		return t("OBJ_UNKNOWN", {}, "objects")
	var id := k
	if not id.begins_with("OBJ_"):
		id = "OBJ_%s" % k.to_upper()
	var s := t(id, {}, "objects")
	# t returns id if missing — try raw key
	if s == id:
		s = t(k, {}, "objects")
	if s == k or s == id:
		return k.capitalize().replace("_", " ")
	return s


func _load_csv(path: String, table_key: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("[Loc] missing %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var header: PackedStringArray = []
	var map: Dictionary = {}
	var line_i: int = 0
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var cols: PackedStringArray = _parse_csv_line(line)
		if line_i == 0:
			header = cols
			line_i += 1
			continue
		if cols.is_empty():
			continue
		var row: Dictionary = {}
		for i in range(mini(header.size(), cols.size())):
			row[header[i]] = cols[i]
		var id: String = str(row.get("id", "")).strip_edges()
		if id == "":
			continue
		map[id] = {
			"ru": str(row.get("ru", "")),
			"en": str(row.get("en", "")),
			"comment": str(row.get("comment", "")),
		}
		line_i += 1
	f.close()
	_tables[table_key] = map


## Простой CSV: учёт кавычек
func _parse_csv_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur: String = ""
	var in_q: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line[i]
		if ch == "\"":
			if in_q and i + 1 < line.length() and line[i + 1] == "\"":
				cur += "\""
				i += 2
				continue
			in_q = not in_q
			i += 1
			continue
		if ch == "," and not in_q:
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += ch
		i += 1
	out.append(cur)
	return out


## text by id; placeholders {name} → fmt["name"]
func t(id: String, fmt: Dictionary = {}, table: String = "ui_character") -> String:
	var tab: Dictionary = _tables.get(table, {})
	var row: Dictionary = tab.get(id, {})
	var s: String = ""
	if row is Dictionary:
		s = str(row.get(locale, ""))
		if s.strip_edges() == "":
			s = str(row.get("en", ""))
		if s.strip_edges() == "":
			s = str(row.get("ru", ""))
	if s.strip_edges() == "":
		s = id
	for k in fmt.keys():
		s = s.replace("{%s}" % str(k), str(fmt[k]))
	return s
