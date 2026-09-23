# ==============================================================================
# ФАЙЛ: src/characters/CharacterData.gd
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
@export var health: float = 100.0   # 100.0 = здоров, 0.0 = смерть
@export var hunger: float = 0.0     # 0.0 = сыт, 100.0 = умирает от голода
@export var energy: float = 100.0   # 100.0 = бодр, 0.0 = вымотан

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
## Структура: {"strength": {"value": 10, "exp": 0.0}, ...}
@export var stats: Dictionary = {}

## Приобретаемые ремесленные навыки (из character_skills.ini [initial_skills])
## Структура: {"forager": {"level": 0, "exp": 0.0}, ...}
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
	# 1. Определение пола
	gender = Gender.MALE if randf() > 0.5 else Gender.FEMALE
	
	# 2. Выбор локализованного имени из CSV через TranslationServer
	var random_id_index: int = randi_range(1, 3)
	var name_id: String = "MALE_NAME_%d" % random_id_index if gender == Gender.MALE else "FEMALE_NAME_%d" % random_id_index
	character_name = tr(name_id)
	
	# 3. Стартовый возраст из character.ini [age_ranges]
	var min_age: int = ConfigLoader.get_character_value("age_ranges", "min_starting_age", 18) if ConfigLoader else 18
	var max_age: int = ConfigLoader.get_character_value("age_ranges", "max_starting_age", 35) if ConfigLoader else 35
	age = randi_range(min_age, max_age)
	
	# 4. Назначение врождённого таланта (forager, worker, craftsman)
	var available_talents = ["forager", "worker", "craftsman"]
	talent = available_talents[randi() % available_talents.size()]
	
	# 5. Загрузка параметров и подписка на сигналы времени
	load_all_stats_from_config()
	_connect_time_signals()

## Загружает физические статы и навыки из конфигурационных .ini файлов
func load_all_stats_from_config() -> void:
	if not ConfigLoader:
		push_warning("[CharacterData] ConfigLoader not available, using default stat values.")
		return

	# Базовые жизненные показатели из character.ini [base_stats]
	health = ConfigLoader.get_character_value("base_stats", "max_health", 100.0)
	
	# Физические статы из character.ini [initial_stats]
	var default_strength = ConfigLoader.get_character_value("initial_stats", "strength", 10)
	var default_intelligence = ConfigLoader.get_character_value("initial_stats", "intelligence", 10)
	var default_endurance = ConfigLoader.get_character_value("initial_stats", "endurance", 10)
	
	stats = {
		"strength": {"value": default_strength, "exp": 0.0},
		"intelligence": {"value": default_intelligence, "exp": 0.0},
		"endurance": {"value": default_endurance, "exp": 0.0}
	}
	
	# Ремесленные навыки из character_skills.ini [initial_skills]
	var skill_list = ["forager", "worker", "builder", "trader", "lumberjack", "farmer"]
	skills.clear()
	for skill_key in skill_list:
		var init_lvl = ConfigLoader.get_skill_value("initial_skills", skill_key, 0)
		skills[skill_key] = {"level": init_lvl, "exp": 0.0}

## Подписка на глобальные события времени
func _connect_time_signals() -> void:
	if Engine.has_singleton("TimeManager") or Node.new().get_node_or_null("/root/TimeManager") != null:
		var tm = Node.new().get_node_or_null("/root/TimeManager")
		if tm:
			if tm.has_signal("day_passed") and not tm.day_passed.is_connected(_on_day_passed):
				tm.day_passed.connect(_on_day_passed)
			if tm.has_signal("year_passed") and not tm.year_passed.is_connected(_on_year_passed):
				tm.year_passed.connect(_on_year_passed)

# ------------------------------------------------------------------------------
# РАСЧЁТ ЭФФЕКТИВНОСТИ И ПРОГРЕССИИ НАВЫКОВ
# ------------------------------------------------------------------------------

## Вычисляет итоговую скорость работы для заданного навыка (например, "forager")
## Формула: base_work_speed * talent_bonus * (1.0 + skill_level * speed_bonus_per_level)
func get_effective_work_speed(skill_name: String) -> float:
	var base_speed: float = ConfigLoader.get_character_value("base_stats", "work_speed", 1.0) if ConfigLoader else 1.0
	
	# Множитель врождённого таланта (если персонаж рождён с этим талантом)
	var talent_multiplier: float = 1.0
	if talent == skill_name and ConfigLoader:
		talent_multiplier = ConfigLoader.get_skill_value("talents", skill_name, 1.25)
		
	# Уровень приобретаемого навыка
	var skill_level: int = 0
	if skills.has(skill_name):
		skill_level = skills[skill_name].get("level", 0)
		
	var bonus_per_lvl: float = ConfigLoader.get_skill_value("skill_progression", "speed_bonus_per_level", 0.1) if ConfigLoader else 0.1
	
	var effective_speed = base_speed * talent_multiplier * (1.0 + float(skill_level) * bonus_per_lvl)
	return effective_speed

## Начисление опыта навыку за выполненный цикл работы
func add_skill_exp(skill_name: String, exp_amount: float) -> void:
	if not skills.has(skill_name):
		skills[skill_name] = {"level": 0, "exp": 0.0}
		
	var max_lvl: int = ConfigLoader.get_skill_value("skill_progression", "max_level", 10) if ConfigLoader else 10
	var exp_for_levelup: float = ConfigLoader.get_skill_value("skill_progression", "exp_for_level_up", 100.0) if ConfigLoader else 100.0
	
	var current_skill = skills[skill_name]
	if current_skill["level"] >= max_lvl:
		return
		
	current_skill["exp"] += exp_amount
	print("[CharacterData] %s gained %.1f XP in skill '%s' (Total XP: %.1f)" % [character_name, exp_amount, skill_name, current_skill["exp"]])
	
	# Повышение уровня при накоплении достаточного XP
	while current_skill["exp"] >= exp_for_levelup and current_skill["level"] < max_lvl:
		current_skill["exp"] -= exp_for_levelup
		current_skill["level"] += 1
		print("[CharacterData] LEVEL UP! %s reached level %d in '%s'!" % [character_name, current_skill["level"], skill_name])
		
	data_changed.emit()

# ------------------------------------------------------------------------------
# ОБРАБОТКА ВРЕМЕНИ И НУЖД
# ------------------------------------------------------------------------------

func _on_day_passed(_total_days: int) -> void:
	if health <= 0.0:
		return

	var hunger_rate: float = ConfigLoader.get_character_value("base_stats", "hunger_rate", 0.5) if ConfigLoader else 0.5
	hunger = clamp(hunger + hunger_rate * 20.0, 0.0, 100.0)
	energy = clamp(energy - 10.0, 0.0, 100.0)
	
	if hunger >= 100.0:
		health = clamp(health - 25.0, 0.0, 100.0)
		print("[CharacterData] %s is starving! Health: %.0f" % [character_name, health])
		
	if health <= 0.0:
		print("[CharacterData] %s died of starvation!" % character_name)
		character_died.emit("starvation")

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
			print("[CharacterData] %s died of old age at %d" % [character_name, age])
			character_died.emit("old_age")

	data_changed.emit()
