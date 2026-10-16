# D01 — потребители и безопасная очистка

Обновление16.10: четыре cabinet mappings из baseline ниже восстановлены отдельным
инкрементом [D01_LEGACY_PROP_PATHS](legacy_cabinet_paths.md). Старые результаты
здесь и в JSON остаются историческими; legacy scenes/scripts сохраняются.

База main `e4af46b075ec38b4eca29f7098c114a342f0267d` после PR228,
Godot 4.7.2, Linux headless. Это проверка кандидатов аудита, а не разрешение
удалять любой файл без ссылки из main. [Машинные результаты](cleanup_candidate_inventory.json).
Пути в JSON относительно корня репозитория; исторические пути не являются loads.

## Выполненный перенос

`game/bootstrap/app/test_dna_pickup.gd` и `.uid` перенесены в
`game/bootstrap/app/tests/fixtures/`. Исходник и UID `uid://ckertdsya4jja`
побайтно прежние. После editor import ResourceUID разрешает его в новый путь;
новый Script загружается. Прямых code consumers два, их preload обновлены:
`run_mutation_feedback_tests.gd` и `tools/capture_pickup_beacons.gd`.
Main использует TEST_CLOUD, а не этот генератор тестовой двойной спирали.
Изменения конфигурации fixture не меняют его выдачу, respawn, звук или визуал.

Экспорт использует all_resources с исключением */tests/*. Поэтому перенос
реально исключает тестовый код из игрового пакета, сохраняя его для разработки.
Это не удаление авторского ассета и не ускорение runtime-кода.

## Решения по кандидатам

| Кандидат | Подтверждённые потребители/контракт | Решение |
|---|---|---|
| Test DNA | Один bootstrap test и один capture tool | Перенесён в fixtures, UID и поведение сохранены |
| fog_overlay.gd | Остаётся в prototype_hud public_api; иных code/scene подключений в repo не найдено | Сохранён: отсутствие внутренних ссылок не доказывает отсутствие внешнего потребителя; public API не меняется этим PR |
| physical_prop.gd | Базовый класс physical_table/pushable_chair;8 старых cabinet/desk/plant scenes; debris и destruction_sound tests | Сохранён |
| physical_table.gd | 07_table_longest.tscn | Сохранён |
| pushable_chair.gd | Пять публичных chair scenes | Сохранён |
| scaled_destructible.gd | Те же8 cabinet/desk/plant scenes, дочерние старые collision nodes | Сохранён |
| health_pickup/ammo_pickup | Четыре объявленных public pickup scenes; A07 regression | Сохранены: их контракт отличается от pickup_item |
| Генераторы SFX | Offline build tools и audio_generation_manifest,253 owned OGG | Владение исправлено A08; повторное удаление/переписывание не требуется |
| build_added_audio.py | Historical import, shared convert/import_settings для refresh importer | Уже явно помечен historical и закрыт guard; сохранён |

Подтверждение legacy:22 literal script references в14 props (8 с двумя scripts,
5 chair и1 table). Static reachability не покрывает пользовательские сохранённые
карты, прямые загрузки публичных сцен и инструменты. Новые карты могут выбирать
сцену environment_prop, пока старые публичные сцены всё ещё нужны.

## Миграции старых props

Префикс старых сцен: `game/presentation/office_floor/public/props/`.
Снято настоящим PlanningCatalog после `_build_environment_catalogs()`:
`_migrate_scene_path(old)`, затем `_create_asset(target)`. Все14 исходных
PackedScene успешно instantiate; это проверка создания до add_child/_ready,
а не доказательство эквивалентности физики/разрушения двух реализаций.

| Старый файл | Текущий результат миграции |
|---|---|
| 03_drawer_cabinet.tscn | **Пусто** |
| 03_drawer_cabinet_mobile.tscn | **Пусто** |
| 03_file_cabinet_tall.tscn | **Пусто** |
| 03_locker_tall.tscn | **Пусто** |
| 06_office_chair.tscn | enviroments/06/06_office_chair.glb |
| 06_office_chair_2.tscn | enviroments/06/06_office_chair_2.glb |
| 06_office_chair_2_fell.tscn | enviroments/06/06_office_chair_2_fell.glb |
| 06_simple_chair.tscn | enviroments/06/06_simple_chair.glb |
| 06_simple_chair_fell.tscn | enviroments/06/06_simple_chair_fell.glb |
| 07_table_longest.tscn | enviroments/07/07_table_longest.glb |
| 08_office_desk_2.tscn | enviroments/08/08_office_desk_2.glb |
| 11_plant_large.tscn | enviroments/11/11_plant_large.glb |
| 11_plant_medium.tscn | enviroments/11/11_plant_medium.glb |
| 11_plant_small.tscn | enviroments/11/11_plant_small.glb |

Все10 непустых targets создаются. Текущая миграция сравнивает нормализованные
имена с каталогом, а не гарантирует alias каждой исторической сцены. Например,
старый locker использует существующий 03_locker_tall_dented.glb, но его прежнее
имя каталогу не соответствует. У двух drawer scenes общий прежний GLB, но это
не доказывает одинаковую физику неподвижного/мобильного шкафа.

`planning_layout_loader._stage` добавляет пустой/неизвестный путь в missing.
По коду смешанная карта может загрузиться без четырёх старых cabinets; карта
только из них получает no loadable objects. Это подтверждённые пустые mappings
и следствие веток loader, **не выполненный round-trip таких четырёх карт**.
Следующий отдельный инкремент D01_LEGACY_PROP_PATHS записан в BACKLOG: явный
alias/fallback с сохранением модели, load-save-load/transform/metadata проверки.
Удалять старые реализации до этого рано. Сами mappings в данном PR не изменены.

## Почему старые pickups нельзя заменить механически

Health scenes дают35/50 HP через heal(amount, medkit), играют pickup/use и
потребляются при любом положительном принятом количестве. Старые ammo дают36/60
**текущему оружию** через add_ammo_to_current_weapon. Отказ оставляет предмет,
повтор происходит через прежний body_entered; latch защищает reentrant calls.

PickupItem выбирает конкретный вид боеприпасов/PISTOL/UZI/SHOTGUN и новые классы,
имеет другую default amount и периодический повтор для стоящего collector.
Подмена скрипта поменяет баланс/получателя/повторный подбор и звуки. A07 сохранил
эти различия намеренно. Для унификации нужны explicit legacy modes и отдельные
regressions, а не удаление четырёх публичных сцен.

## Проверка пакетов и ограничения

Windows Desktop PCK до/после:2842→2840 entries,332427176→332422612 байт
(**−4564 байта**, без заявления о заметном FPS/памяти). Удалены только:
`game/bootstrap/app/test_dna_pickup.gdc` и `.gd.remap`. Новых entries нет.
Web PCK после имеет тот же набор2840 файлов; сравнение выполнено с Windows
baseline (исключения/all_resources одинаковы), отдельный Web before не снимался.

В обоих after inventories сохранены14 legacy scenes,4 scripts,4 старых pickups
и fog overlay. Вложенного tests/fixtures/test_dna_pickup в игровых PCK нет.
`check_export_pack --inventory` PASS для обоих,697 concrete runtime refs.
Это генерация/чтение PCK штатным Godot на Linux, **не запуск Windows exe или WebGL**.

Семь штатных suites PASS: mutation_feedback, legacy_pickup, pickup_floor,
layout_loading, planner_persistence, debris, destruction_sound. Старые проверки
не ослаблены; полный round-trip всех исторических пользовательских карт не
проводился. Capture tool прошёл --check-only; его PNG не перерисовывались,
сам DNA source неизменён. Массовое удаление/public API retirement не выполнено.

validate_project/spec/workflow/architecture/source-size PASS (452 GDScript,
122 прежних advisory warnings), CI registry157/157 PASS, resource paths PASS,
scene resources392 PASS, headless editor import и git diff --check PASS.
В итоговых import/export/probe/runtime логах ERROR/ObjectDB/RID leak нет.

Изменены только расположение bootstrap fixture,2 его потребителя и документация.
Публичные API/сцены/ассеты/save-network форматы/владельцы/dependency edges/policy
прежние, архитектурных исключений нет. D02 и Q02 остаются отдельными задачами.
