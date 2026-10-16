# A07 — отказ подбора старых аптечек и патронов

Дата: 16.10.2026. База main `9449609f`, Godot4.7.2 stable, Linux headless.

## Результат

Исправлены только `features.pickups/health_pickup.gd` и `ammo_pickup.gd`.
Результат существующего collector command должен быть положительным:
`heal(...) > 0.0` или `add_ammo_to_current_weapon(...) > 0`.
При отказе `_consumed` сбрасывается, предмет остаётся, звуки не проигрываются.
При частичном положительном результате весь предмет расходуется, как в
`pickup_item.gd`; остаток не создаётся. Ранний `_consumed=true` остаётся
защитой на время синхронных collector signals: повторный вызов не выдаёт
вторую порцию. Удаление/звуки происходят только после подтверждения приёма.

Совместимость четырёх public сцен сохранена:

| Сцена | Прежнее количество | Получатель |
|---|---:|---|
| medkit_closed_pickup |35 здоровья|heal, source medkit|
| med_case_green_pickup |50 здоровья|heal, source medkit|
| ammo_red_pickup |36 патронов|текущее оружие|
| ammo_orange_pickup |60 патронов|текущее оружие|

Их PackedScene, Visual, shape/mask/groups, exports и публичные пути прежние.
Здоровьем/боезапасом по-прежнему владеет collector/player/combat; новых
зависимостей, публичных контрактов, DTO/форматов или архитектурных исключений нет.
Новый путь `pickup_item.gd` не изменён. Автопроверка стоящего collector не
добавлена: повтор старой сцены идёт через прежний body_entered (выйти и зайти).

## Доказательство и проверки

Новый `bootstrap/app/tests/run_legacy_pickup_tests.gd` загружает все четыре
публичные сцены и проверяет connected body_entered callbacks. Тот же suite
на исходных двух скриптах даёт **38 failures**, на исправленных —**0**,
без SCRIPT ERROR и ObjectDB warnings. Проверены:

- null/постороннее тело; два последовательных отказа и сохранность предмета;
- отсутствие звуков при отказе; повтор тем же предметом после изменения ёмкости;
- частичное принятие .25HP/2 патронов, исходные35/50/36/60 и medkit source;
- обычный успех, повтор из collector callback, повторный вход и второй collector;
- нулевое/отрицательное authored amount без награды или удаления;
- настоящий публичный Player: полное здоровье/текущее оружие с полным резервом,
  затем место для .25HP/2 патронов, успешный повтор и соблюдение caps.

Suite добавлен в Mission runtime regressions CI. Все8 целевых suites PASS:
legacy_pickup, pickup_floor, ammo_box, placed_ammo_pickup, enemy_loot,
item_palette_ammo, heal_feedback, sound_hook. В этих логах нет SCRIPT ERROR,
ERROR или ObjectDB warnings. `validate_project.py` PASS (включая READY
spec/workflow, architecture/scene/source-size);121 прежних size warnings,
новых превышений нет. Resource paths/diff check и Godot editor import PASS.

Windows/Web и физический проход персонажа через старые сцены вручную не
проверялись. Основная карта использует более новый pickup path; исправление
относится к сохранённым совместимым публичным сценам и не заявляется как
изменение стандартных аптечек текущей карты.
