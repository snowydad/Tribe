# ==============================================================================
# ФАЙЛ: src/characters/CharacterData.gd
# НАЗНАЧЕНИЕ: Ресурс хранения данных, характеристик и инвентаря персонажа
# ==============================================================================
class_name CharacterData
extends Resource

enum Gender { MALE, FEMALE }

# ------------------------------------------------------------------------------
# ПОЛЯ ДАННЫХ ПЕРСОНАЖА
# ------------------------------------------------------------------------------
@export var character_name: String = ""
@export var gender: Gender = Gender.MALE
@export var age: int = 18

# ------------------------------------------------------------------------------
# ШКАЛЫ ПОТРЕБНОСТЕЙ И ЗДОРОВЬЯ
# ------------------------------------------------------------------------------
@export var health: float = 100.0   # 100.0 = здоров, 0.0 = смерть
@export var hunger: float = 0.0     # 0.0 = сыт, 100.0 = умирает от голода
@export var energy: float = 100.0   # 100.0 = бодр, 0.0 = вымотан

# ------------------------------------------------------------------------------
# ИНВЕНТАРЬ / ПЕРЕНОСИМЫЕ ПРЕДМЕТЫ
# ------------------------------------------------------------------------------
@export var carried_item: String = "" # Название предмета (например "berry")
@export var item_amount: int = 0      # Количество

# Сигналы для системы UI и событий
signal data_changed
signal character_died(reason: String)

# ------------------------------------------------------------------------------
# ГЕНЕРАЦИЯ И ИНИЦИАЛИЗАЦИЯ
# ------------------------------------------------------------------------------

## Генерирует имя, пол и стартовый возраст
func generate_identity() -> void:
	gender = Gender.MALE if randf() > 0.5 else Gender.FEMALE
	
	var random_id_index: int = randi_range(1, 3)
	var name_id: String = ""
	
	if gender == Gender.MALE:
		name_id = "MALE_NAME_%d" % random_id_index
	else:
		name_id = "FEMALE_NAME_%d" % random_id_index
		
	character_name = tr(name_id)
	
	# Чтение возраста из character.ini
	var min_age: int = ConfigLoader.get_character_value("age_ranges", "min_starting_age", 18)
	var max_age: int = ConfigLoader.get_character_value("age_ranges", "max_starting_age", 35)
	age = randi_range(min_age, max_age)
	
	if TimeManager:
		if not TimeManager.year_passed.is_connected(_on_year_passed):
			TimeManager.year_passed.connect(_on_year_passed)

# ------------------------------------------------------------------------------
# ЛОГИКА ИЗМЕНЕНИЯ НУЖД
# ------------------------------------------------------------------------------

func _on_year_passed(_total_years: int) -> void:
	if health <= 0.0:
		return

	age += 1
	
	hunger = clamp(hunger + 25.0, 0.0, 100.0)
	energy = clamp(energy - 15.0, 0.0, 100.0)
	
	if hunger >= 100.0:
		health = clamp(health - 35.0, 0.0, 100.0)
		print("[CharacterData] ", character_name, " is starving! Health: ", health)
	
	if age > 60:
		var old_age_death_chance = (age - 60) * 0.05
		if randf() < old_age_death_chance:
			health = 0.0
			print("[CharacterData] ", character_name, " died of old age at ", age)
			character_died.emit("old_age")

	if health <= 0.0:
		print("[CharacterData] ", character_name, " died!")
		character_died.emit("starvation_or_disease")

	data_changed.emit()
