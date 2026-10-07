# ОБНОВЛЕНО: 2026-10-07 — talent XP/speed via talents_skills + xp_talent_multiplier
# ==============================================================================
# ОБНОВЛЕНО: 2026-10-05 12:05 CEST — hungry: no rest regen, only drain
# НАЗНАЧЕНИЕ: Ресурс хранения персональных данных, физических статов,
#             врождённых талантов, приобретаемых навыков и инвентаря.
# ==============================================================================
class_name CharacterData
extends Resource

enum Gender { MALE, FEMALE }

# ------------------------------------------------------------------------------
# 1. БАЗОВЫЕ ЛИЧНЫЕ ДАННЫЕ
# ------------------------------------------------------------------------------
@export var character_name: String = ""
@export var gender: Gender = Gender.MALE
@export var age: int = 18

# ------------------------------------------------------------------------------
# 2. ШКАЛЫ ПОТРЕБНОСТЕЙ И ЗДОРОВЬЯ
# ------------------------------------------------------------------------------
@export var death_cause: String = ""  # "", "starvation", "exhaustion", "old_age", "needs"
@export var health: float = 100.0   # 100.0 = здоров, 0.0 = смерть
@export var hunger: float = 0.0     # 0.0 = сыт, 100.0 = умирает от голода
@export var energy: float = 75.0    # бодрость 0..100; старт из character.ini [initial_stats] energy

# ------------------------------------------------------------------------------
# 3. ИНВЕНТАРЬ / ПЕРЕНОСИМЫЕ РЕСУРСЫ
# ------------------------------------------------------------------------------
@export var carried_item: String = "" # Идентификатор предмета (например "berry")
@export var item_amount: int = 0      # Количество предметов в руках

# ------------------------------------------------------------------------------
# 4. ТАЛАНТЫ, НАВЫКИ И ФИЗИЧЕСКИЕ ХАРАКТЕРИСТИКИ
# ------------------------------------------------------------------------------
## Врождённый генетический талант (Talent): "forager", "worker", "craftsman"
@export var talent: String = "forager"

## Физические и ментальные статы (из character.ini [initial_stats])
@export var stats: Dictionary = {}

## Приобретаемые ремесленные навыки (из character_skills.ini [initial_skills])
@export var skills: Dictionary = {}

# ------------------------------------------------------------------------------
# СИГНАЛЫ
# ------------------------------------------------------------------------------
signal data_changed
signal character_died(reason: String)

# ------------------------------------------------------------------------------
# ГЕНЕРАЦИЯ И ИНИЦИАЛИЗАЦИЯ
# ------------------------------------------------------------------------------

## Генерация личности (пол, имя, стартовый возраст и врождённый талант)
func generate_identity() -> void:
	gender = Gender.MALE if randf() > 0.5 else Gender.FEMALE

	var random_id_index: int = randi_range(1, 3)
	var name_id: String = "MALE_NAME_%d" % random_id_index if gender == Gender.MALE else "FEMALE_NAME_%d" % random_id_index
	character_name = tr(name_id)

	var min_age: int = ConfigLoader.get_character_value("age_ranges", "min_starting_age", 18) if ConfigLoader else 18
	var max_age: int = ConfigLoader.get_character_value("age_ranges", "max_starting_age", 35) if ConfigLoader else 35
	age = randi_range(min_age, max_age)

	var available_talents = ["forager", "worker", "craftsman"]
	talent = available_talents[randi() % available_talents.size()]

	load_all_stats_from_config()
	_connect_time_signals()

## Загружает физические статы и навыки из конфигурационных .ini файлов
func load_all_stats_from_config() -> void:
	if not ConfigLoader:
		push_warning("[CharacterData] ConfigLoader not available, using default stat values.")
		return

	health = ConfigLoader.get_character_value("base_stats", "max_health", 100.0)
	energy = float(ConfigLoader.get_character_value("initial_stats", "energy", 75.0))

	var default_strength = ConfigLoader.get_character_value("initial_stats", "strength", 10)
	var default_intelligence = ConfigLoader.get_character_value("initial_stats", "intelligence", 10)

	stats = {
		"strength": {"value": default_strength, "exp": 0.0},
		"intelligence": {"value": default_intelligence, "exp": 0.0},
	}

	var skill_list = ["forager", "worker", "builder", "trader", "lumberjack", "farmer"]
	skills.clear()
	for skill_key in skill_list:
		var init_lvl = ConfigLoader.get_skill_value("initial_skills", skill_key, 0)
		skills[skill_key] = {"level": init_lvl, "exp": 0.0}

## Подписка на глобальные события времени
func _connect_time_signals() -> void:
	if TimeManager == null:
		return
	# day_passed в TimeManager пока нет — _on_day_passed не вешаем
	if TimeManager.has_signal("year_passed"):
		if not TimeManager.year_passed.is_connected(_on_year_passed):
			TimeManager.year_passed.connect(_on_year_passed)

# ------------------------------------------------------------------------------
# РАСЧЁТ ЭФФЕКТИВНОСТИ И ПРОГРЕССИИ НАВЫКОВ
# ------------------------------------------------------------------------------

## skill входит в талант? (talents_skills.ini: forager = "forager, farmer, ...")
func talent_covers_skill(skill_name: String) -> bool:
	var sk := str(skill_name).strip_edges().to_lower()
	if sk.is_empty():
		return false
	var tal := str(talent).strip_edges().to_lower()
	if tal.is_empty():
		return false
	if tal == sk:
		return true
	if not ConfigLoader or not ConfigLoader.has_method("get_skill_value"):
		return false
	var raw := str(ConfigLoader.get_skill_value("talents_skills", tal, ""))
	raw = raw.replace('"', "").replace("'", "")
	for part in raw.split(","):
		if part.strip_edges().to_lower() == sk:
			return true
	return false


func get_effective_work_speed(skill_name: String) -> float:
	var base_speed: float = ConfigLoader.get_character_value("base_stats", "work_speed", 1.0) if ConfigLoader else 1.0

	var talent_multiplier: float = 1.0
	if talent_covers_skill(skill_name) and ConfigLoader:
		# множитель по имени таланта (forager=1.25), не по skill
		talent_multiplier = float(ConfigLoader.get_skill_value("talents", str(talent).strip_edges().to_lower(), 1.25))

	var skill_level: int = 0
	if skills.has(skill_name):
		skill_level = skills[skill_name].get("level", 0)

	var bonus_per_lvl: float = ConfigLoader.get_skill_value("skill_progression", "speed_bonus_per_level", 0.1) if ConfigLoader else 0.1

	var effective_speed = base_speed * talent_multiplier * (1.0 + float(skill_level) * bonus_per_lvl)
	return effective_speed


func add_skill_xp(skill_name: String, exp_amount: float) -> void:
	add_skill_exp(skill_name, exp_amount)


func add_skill_exp(skill_name: String, exp_amount: float) -> void:
	if not skills.has(skill_name):
		skills[skill_name] = {"level": 0, "exp": 0.0}

	var max_lvl: int = ConfigLoader.get_skill_value("skill_progression", "max_level", 10) if ConfigLoader else 10
	var exp_for_levelup: float = ConfigLoader.get_skill_value("skill_progression", "exp_for_level_up", 100.0) if ConfigLoader else 100.0

	var current_skill = skills[skill_name]
	if current_skill["level"] >= max_lvl:
		return

	var gained: float = exp_amount
	if talent_covers_skill(skill_name) and ConfigLoader:
		var xp_mult: float = float(ConfigLoader.get_skill_value("skill_progression", "xp_talent_multiplier", 2.0))
		gained *= xp_mult

	current_skill["exp"] += gained
	print("[CharacterData] %s gained %.1f XP in skill '%s' (Total XP: %.1f)%s" % [
		character_name, gained, skill_name, current_skill["exp"],
		" [talent x%.1f]" % (gained / exp_amount if exp_amount > 0.0 else 1.0) if talent_covers_skill(skill_name) else ""
	])

	while current_skill["exp"] >= exp_for_levelup and current_skill["level"] < max_lvl:
		current_skill["exp"] -= exp_for_levelup
		current_skill["level"] += 1
		print("[CharacterData] LEVEL UP! %s reached level %d in '%s'!" % [character_name, current_skill["level"], skill_name])

	data_changed.emit()

# ------------------------------------------------------------------------------
# ОБРАБОТКА ВРЕМЕНИ И НУЖД
# ------------------------------------------------------------------------------
# hunger += hunger_rate  (всегда)
# energy += work_rate | rest_rate (rest только если hunger <= thr)
# energy += energy_drain_rate  если hunger > thr  (rest не перекрывает)
# health += health_drain_rate  если energy < thr ИЛИ hunger > thr  (один раз)
# energy → move/work mult: get_energy_speed_mult()
# ------------------------------------------------------------------------------

func _cfg(key: String, default: float) -> float:
	if ConfigLoader:
		return float(ConfigLoader.get_character_value("base_stats", key, default))
	return default

## activity: "work" | "rest"
func update_needs(delta: float, activity: String = "rest") -> void:
	if health <= 0.0:
		return

	var prev_h: int = int(health)
	var prev_g: int = int(hunger)
	var prev_e: int = int(energy)

	var max_hp: float = _cfg("max_health", 100.0)
	var hunger_rate: float = _cfg("hunger_rate", 0.048)
	var energy_work_rate: float = _cfg("energy_work_rate", -0.08)
	var energy_rest_rate: float = _cfg("energy_rest_rate", 0.04)
	var energy_drain_rate: float = _cfg("energy_drain_rate", -0.03)
	var energy_drain_hunger_thr: float = _cfg("energy_drain_hunger_threshold", 50.0)
	var health_drain_rate: float = _cfg("health_drain_rate", -0.5)
	var thr_energy: float = _cfg("health_energy_threshold", 10.0)
	var thr_hunger: float = _cfg("health_hunger_threshold", 90.0)

	# 1) голод
	hunger = clampf(hunger + hunger_rate * delta, 0.0, 100.0)

	# 2) energy: work / rest
	# При hunger > threshold rest-реген НЕ идёт (иначе +rest сильнее drain → energy=100).
	if activity == "work":
		energy = clampf(energy + energy_work_rate * delta, 0.0, 100.0)
	elif hunger <= energy_drain_hunger_thr:
		energy = clampf(energy + energy_rest_rate * delta, 0.0, 100.0)

	# 2b) drain при голоде (и idle, и work)
	if hunger > energy_drain_hunger_thr:
		energy = clampf(energy + energy_drain_rate * delta, 0.0, 100.0)

	# 3) health: один drain, если хотя бы одно условие
	if energy < thr_energy or hunger > thr_hunger:
		health = clampf(health + health_drain_rate * delta, 0.0, max_hp)

	if health <= 0.0:
		health = 0.0
		if death_cause == "":
			# причина по доминирующему порогу
			if hunger > thr_hunger and energy < thr_energy:
				death_cause = "starvation+exhaustion"
			elif hunger > thr_hunger:
				death_cause = "starvation"
			elif energy < thr_energy:
				death_cause = "exhaustion"
			else:
				death_cause = "needs"
		print("[CharacterData] %s died (%s). hunger=%.0f energy=%.0f" % [character_name, death_cause, hunger, energy])
		character_died.emit(death_cause)
		data_changed.emit()
		return

	if int(health) != prev_h or int(hunger) != prev_g or int(energy) != prev_e:
		data_changed.emit()

## Еда: −hunger, +energy (energy_eat_ratio)
func eat_food(nutrition_value: float) -> void:
	var n: float = maxf(nutrition_value, 0.0)
	hunger = clampf(hunger - n, 0.0, 100.0)
	var ratio: float = _cfg("energy_eat_ratio", 1.0)
	energy = clampf(energy + n * ratio, 0.0, 100.0)
	print("[CharacterData] %s ate food! hunger=%.1f energy=%.1f (+%.1f)" % [character_name, hunger, energy, n * ratio])
	data_changed.emit()

## Множитель move/work от energy
##  >=90 → 1.1 | 75..90 → 1.0 | 10 → 0.25 | <10 → 0.25
func get_energy_speed_mult() -> float:
	if energy >= 90.0:
		return 1.1
	if energy >= 75.0:
		return 1.0
	if energy <= 10.0:
		return 0.25
	return lerpf(0.25, 1.0, (energy - 10.0) / 65.0)

func spend_energy(amount: float) -> void:
	if amount == 0.0:
		return
	# amount > 0 = расход; можно передать и отрицательное для хила
	energy = clampf(energy - amount, 0.0, 100.0)
	data_changed.emit()

func _on_year_passed(_total_years: int) -> void:
	if health <= 0.0:
		return

	age += 1
	print("[CharacterData] %s aged up! New age: %d" % [character_name, age])

	if age > 60:
		var death_chance = (age - 60) * 0.05
		if randf() < death_chance:
			health = 0.0
			death_cause = "old_age"
			print("[CharacterData] %s died of old age at %d" % [character_name, age])
			character_died.emit("old_age")

	data_changed.emit()
