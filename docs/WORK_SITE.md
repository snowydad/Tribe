# WorkSite — universal work

## Идея
Логика «можно ли работать / сколько / что получилось» живёт **на объекте + ini**, не в `character.gd`.

## Контракт
| Метод | Смысл |
|-------|--------|
| `can_accept_work(worker)` | Сейчас можно работать? (ягоды есть, склад не полон…) |
| `get_work_time()` | Секунды одного цикла (из `[work] base_work_time`) |
| `get_work_skill()` | Навык (`forager`, `trader`…) |
| `get_work_type()` | Тип из ini (`foraging`, `delivering`…) |
| `do_work(worker)` | Выполнить цикл → Dictionary с `ok` / `give` / `take` / `xp_skill` |
| `get_free_work_point(worker)` | Точка стояния |
| `release_work_point(worker)` | Освободить слот |

Группа: `work_site` (+ `interactable`).

## ini-шаблон
```ini
[work]
work_type = "foraging"   ; или delivering / clear / build
skill = "forager"
base_work_time = 3.0

[output]                 ; для harvest
resource_type = "berry"
yield_amount = 1
