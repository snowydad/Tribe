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

func get_effective_work_speed(skill_name: String) -> float:
	var base_speed: float = ConfigLoader.get_character_value("base_stats", "work_speed", 1.0) if ConfigLoader else 1.0
	
	var talent_multiplier: float = 1.0
	if talent == skill_name and ConfigLoader:
		talent_multiplier = ConfigLoader.get_skill_value("talents", skill_name, 1.25)
		
	var skill_level: int = 0
	if skills.has(skill_name):
		skill_level = skills[skill_name].get("level", 0)
		
	var bonus_per_lvl: float = ConfigLoader.get_skill_value("skill_progression", "speed_bonus_per_level", 0.1) if ConfigLoader else 0.1
	
	var effective_speed = base_speed * talent_multiplier * (1.0 + float(skill_level) * bonus_per_lvl)
	return effective_speed

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
	
	while current_skill["exp"] >= exp_for_levelup and current_skill["level"] < max_lvl:
		current_skill["exp"] -= exp_for_levelup
		current_skill["level"] += 1
		print("[CharacterData] LEVEL UP! %s reached level %d in '%s'!" % [character_name, current_skill["level"], skill_name])
		
	data_changed.emit()

# ------------------------------------------------------------------------------
# ОБРАБОТКА ВРЕМЕНИ И НУЖД
# ------------------------------------------------------------------------------

## Непрерывное обновление нужд (голод) в реальном времени
func update_needs(delta: float) -> void:
	if health <= 0.0:
		return

	var hunger_rate: float = float(ConfigLoader.get_character_value("base_stats", "hunger_rate", 0.048)) if ConfigLoader else 0.048
	hunger = clamp(hunger + hunger_rate * delta, 0.0, 100.0)

	if hunger >= 100.0:
		health = clamp(health - 2.0 * delta, 0.0, 100.0)
		if health <= 0.0:
			print("[CharacterData] %s died of starvation!" % character_name)
			character_died.emit("starvation")

	data_changed.emit()

## Прием пищи (снижение уровня голода)
func eat_food(nutrition_value: float) -> void:
	hunger = clamp(hunger - nutrition_value, 0.0, 100.0)
	print("[CharacterData] %s ate food! Hunger level: %.1f%%" % [character_name, hunger])
	data_changed.emit()

func _on_day_passed(_total_days: int) -> void:
	if health <= 0.0:
		return
	energy = clamp(energy - 10.0, 0.0, 100.0)
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
