# Tribe — структура проекта

Симулятор племени на **Godot 4.7** (рендер Mobile, физика Jolt, 120 тиков/с).  
Сейчас это одна сцена-песочница: один персонаж, куст ягод, склад, препятствие, RTS-камера. Игрок хватает перса мышью и бросает на объект — тот сам идёт собирать / нести / расчищать.

Главная сцена в редакторе: `src/main/main.tscn` (в `project.godot` стартовая сцена не прописана — открывать вручную).

Черновик идей и дневник — в `README.md`. Этот файл — карта кода.

---

## Папки

```
Tribe/
├── project.godot          # имя, автолоады, физика, переводы имён
├── icon.svg
├── src/
│   ├── autoload/          # глобальные синглтоны (живут всегда)
│   ├── main/              # мир, камера, ввод игрока
│   ├── characters/        # персонаж + данные (Resource)
│   └── environment/       # куст, склад, препятствие, террейн
├── assets/
│   ├── config/            # балансные .ini (не сцены)
│   ├── materials/         # материалы Godot (.tres)
│   ├── models/            # glb: террейн, море, куст ягод
│   └── strings/           # имена (CSV → переводы ru/en)
└── .tmp.driveupload/      # мусор синка, не часть игры
```

Логика только в `src/`. Баланс и тексты — в `assets/`. Модели не трогать из кода без нужды.

---

## Автолоады (порядок в `project.godot`)

| Имя в дереве     | Скрипт                         | Зачем |
|------------------|--------------------------------|--------|
| `ConfigLoader`   | `src/autoload/ConfigLoader.gd` | Читает `.ini` при старте |
| `DevCheatManager`| `src/autoload/DevCheatManager.gd` | Клавиши `0–4`: пауза и ускорение времени |
| `TimeManager`    | `src/autoload/TimeManager.gd`  | Год жизни + цикл день/ночь + офлайн |
| `LoggerGlobal`   | `src/autoload/Logger.gd`       | Файл лога: `Документы/Tribe/tribe_debug.log` |

`ConfigLoader` реально грузит только четыре файла:

- `assets/config/game_config.ini`
- `assets/config/character.ini`
- `assets/config/character_skills.ini`
- `assets/config/berries.ini`

Лежат, но **не подключены** к лоадеру: `storage.ini`, `obstacle.ini`, `shelter.ini`, `names.ini`. Имена берутся из `assets/strings/names.csv` через `tr()`, не из `names.ini`.

---

## Сцена `Main`

```
Main                    ← main.gd (корень мира)
├── PlayerInputManager  ← мышь: выбор, drag, context drop
├── Terrain             ← res://src/environment/terrain.tscn (файла в репо нет)
├── WorldEnvironment
├── DirectionalLight3D
├── CameraAnchor        ← camera_3d.gd (RTS)
│   ├── SpringArm3D
│   │   └── Camera3D
│   └── CameraTarget
├── Character           ← character.tscn
├── DevBox / DevSphere  ← отладочные CSG
├── Island / Island2    ← заглушки островов
├── Storage
├── Berries
└── DevObstacle
```

### Камера (`camera_3d.gd`)

- ЛКМ по земле (слой 1) — пан карты с инерцией и «резинкой» границ.
- Колесо — зум, наклон pitch.
- СКМ — орбита вокруг якоря.
- Якорь садится по лучу вниз на слой 1 (террейн / уровень моря).
- Пока перса тащат, камера `is_locked`.

### Ввод (`PlayerInputManager.gd`)

1. ЛКМ на персонажа — сразу захват (`CARRIED`), камера стоп.
2. Везём над землёй (луч только слой 1).
3. Отпустили:
   - на куст (`harvest_berry`) → сбор;
   - на склад (`deposit_food` / группа `storage`) → сдача;
   - на препятствие (`clear_obstacle` / группа `obstacle`) → расчистка;
   - иначе → идти в точку.

Клик без драга: выбрать перса или дать ту же задачу выбранному.

---

## Персонаж

**Сцена** `src/characters/character.tscn` — `CharacterBody3D`, слой коллизии **2**, маска **1+4** (земля + интерактивы). Прокси-меш (коробка + «лицо»), `NavigationAgent3D` с RVO avoidance, кольцо выбора, `Label3D` со статами.

**Контроллер** `character.gd` — конечный автомат:

| Состояние    | Смысл |
|--------------|--------|
| `IDLE`       | Стоит; если в руках ресурс — идёт на склад; если куст снова спелый — возвращается собирать |
| `MOVING`     | Идёт по навмешу (или дугой в воздухе после броска) |
| `CARRIED`    | Игрок держит в воздухе |
| `GATHERING`  | Таймер работы у куста → 1 ягода в руки → склад |
| `DELIVERING` | Путь к складу, потом разгрузка |
| `CLEARING`   | Таймер у препятствия |
| `EATING`     | Зарезервировано, не используется |

Цикл фуражира: куст → руки `berry` ×1 → ближайший узел группы `storage` → если на кусте ещё есть ягоды, снова туда. Отдельной очереди задач (стек из README) **нет**: новая команда затирает цели.

Точка подхода — `get_free_work_point()` у объекта (маркеры N/S/E/W).

**Данные** `CharacterData.gd` (`class_name CharacterData`, Resource):

- имя, пол, возраст, HP / голод / энергия;
- руки: `carried_item`, `item_amount`;
- талант (`forager` / `worker` / `craftsman`);
- статы и навыки из `.ini`;
- скорость работы: база × бонус таланта × (1 + уровень × 0.1);
- опыт `forager` за сбор; старение по сигналу `year_passed`.

Голод завязан на сигнал `day_passed`, которого у `TimeManager` нет — шкала голода сейчас не тикает.

---

## Окружение

| Объект | Сцена / скрипт | Группы | Поведение |
|--------|----------------|--------|-----------|
| Куст   | `berries.tscn` / `berries.gd` | `berries` | Партия ягод; после 0 — таймер созревания всей партии. Модель `assets/models/environment/berries.glb`. Интерактив — `Area3D` слой **4**. |
| Склад  | `storage.tscn` / `storage.gd` | `storage`, `interactable` | `deposit_food`, счётчик еды на `DevLabel`. |
| Препятствие | `dev_obstacle.tscn` (скрипта нет) | — | Меш + `NavigationObstacle3D`. Нет `clear_obstacle` и группы `obstacle` — расчистка из ввода не цепляется. |
| Террейн | `terrain.tscn` | — | Ссылка из Main есть, файла в репозитории нет. Модель `assets/models/terrain00.glb` есть. |

Контракт объекта для работы: `get_work_time()`, `get_free_work_point()`, плюс метод задачи (`harvest_berry` / `deposit_food` / `clear_obstacle`).

---

## Конфиги (`assets/config/`)

| Файл | Кто читает | Содержание |
|------|------------|------------|
| `game_config.ini` | TimeManager | секунд на год жизни, длина суток |
| `character.ini` | персонаж, CharacterData | возраст, HP, скорость, статы |
| `character_skills.ini` | CharacterData | таланты, стартовые навыки, XP |
| `berries.ini` | berries.gd | время сбора, урожай, созревание |
| `storage.ini` | задумано складом | время сдачи, вместимость |
| `obstacle.ini` | нигде | расчистка, дроп дерева |
| `shelter.ini` | нигде | стройка, дрова |
| `names.ini` | нигде | черновик имён |

Склад вызывает `ConfigLoader.get_config_value(...)`, такого метода **нет** — остаётся `work_time = 1.0` из скрипта.

---

## Время и читы

- **Год жизни:** `seconds_per_year` (по умолчанию 86400 с = 1 реальный день). Сигнал `year_passed` → возраст.
- **День/ночь:** отдельный таймер, сигнал `day_night_cycle_updated(0…1)` (солнце пока не подписано).
- **Офлайн:** `user://time_data.json` при паузе/закрытии.
- **Читы:** `0` пауза, `1` ×1, `2` ×2, `3` ×24, `4` ×1440 (`Engine.time_scale`).

---

## Слои коллизии (как задумано)

| Слой | Кто |
|------|-----|
| 1 | земля / террейн (камера и drag перса) |
| 2 | персонаж |
| 4 | зоны куста и склада |

---

## Поток данных (фураж)

```
Игрок бросает перса на куст
        ↓
GATHERING ← work_time из berries.ini, скорость из CharacterData
        ↓
harvest_berry() → руки berry
        ↓
ближайший storage
        ↓
deposit_food()
        ↓
если куст не пуст → снова GATHERING, иначе IDLE (ждёт созревания)
```

---

## Дыры и рассинхрон (на момент разбора)

1. **`terrain.tscn` отсутствует** — сломанная ссылка в Main.
2. **`storage.ini` / `obstacle.ini` / `shelter.ini` не в ConfigLoader.**
3. **`DevObstacle`** не интерактивен для AI (нет скрипта/группы).
4. **`LoggerGlobal`** почти не вызывается из геймплея (`print` вместо него).
5. **Голод/энергия** ждут `day_passed`.
6. **Стек задач** из README не реализован.
7. **`.tmp.driveupload/`** и `*.tmp` у сцен — не игровой код.

---

## Куда смотреть, если править

| Задача | Файлы |
|--------|--------|
| Поведение перса | `src/characters/character.gd` |
| Статы, навыки, смерть | `src/characters/CharacterData.gd`, `character.ini`, `character_skills.ini` |
| Сбор / созревание | `src/environment/berries.gd`, `berries.ini` |
| Склад | `src/environment/storage.gd`, позже `storage.ini` |
| Мышь и бросок | `src/main/PlayerInputManager.gd` |
| Камера | `src/main/camera_3d.gd` |
| Год / скорость времени | `TimeManager.gd`, `game_config.ini`, `DevCheatManager.gd` |
| Состав мира | `src/main/main.tscn` |
