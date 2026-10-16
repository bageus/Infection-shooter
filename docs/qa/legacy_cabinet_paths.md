# D01_LEGACY_PROP_PATHS — старые шкафы сохраняются в картах

База main `b0b6a21` после PR229, Godot4.7.2, Linux headless. Bootstrap.app
сохраняет владельца миграции/загрузки/сохранения. В planning_catalog добавлены
четыре известных identity mappings: возвращается исходная публичная .tscn,
вместо пустой строки из неудачного сопоставления имени с нынешним каталогом.

| Историческая сцена в office_floor/public/props | Модель сохранена | Масса/пуля/толчок персонажа |
|---|---|---|
| 03_drawer_cabinet.tscn | models/objects/03_drawer_cabinet.glb | 18 /0,75 /1,5 |
| 03_drawer_cabinet_mobile.tscn | Та же модель, отдельная физическая конфигурация | 14 /0,9 /1,8 |
| 03_file_cabinet_tall.tscn | models/objects/03_file_cabinet_tall.glb | 55 /0,25 /0,45 |
| 03_locker_tall.tscn | enviroments/03/03_locker_tall_dented.glb | 55 /0,25 /0,45 |

Это совместимость сохранённых сцен, не перевод на environment_prop и не
удаление legacy-кода. Подмена ближайшей по имени GLB потеряла бы часть настроек.
Сохранённый scene path остаётся тем же после повторной записи; DTOv8 не меняется.
Неизвестные legacy имена/retired Office_Set не получили общий fallback.
Десять остальных миграций из D01 inventory остались прежними; все14 targets
теперь существуют и instantiate. Исходный JSON D01 сохраняется как baseline.

## Воспроизведение и регрессия

`run_legacy_cabinet_paths_tests.gd` на прежнем production даёт10 failures:
4 неверных mappings,4 отклонённых cabinet-only maps, mixed map теряет4 объекта
и mixed unknown case не может загрузить единственный известный cabinet.
Тот же исправленный test fixture на новом production даёт0 failures.

Каждый из4 cabinet-only maps проходит настоящий synchronous loader, capture,
MAP.write/read через user:// и повторный loader/capture. Смешанная карта4 cabinets
+ неизменённый07_table проходит prepare_async/commit_async до и после записи.
По каждому объекту проверяются exact scene/model path, порядок, object_id,
desk/attachment/zone/auto_fixture metadata, все углы, координаты и неравномерный
масштаб. Числовые поля двух DTO сравниваются с absolute tolerance0,0001
единицы/градуса из-за Euler/JSON round-off; строки/metadata — точно.

Настоящие _ready/deferred collision builders выполняются: проверяются исходный
physical_prop script, RigidBody3D, authored mass/impulses и созданные CollisionShape3D.
Родитель fixture отключает process/physics, чтобы гравитация не двигала шкаф во
время persistence-проверки; поведение толкания/разрушения здесь не симулируется.
Соседние существующие debris/destruction_sound suites проверяются отдельно.
Unknown legacy path продолжает давать skipped1, известный cabinet — loaded1.

Новый suite внесён в .github/runtime_suites.txt. Публичные API/сцены/ассеты,
формат сохранений, владельцы/dependency edges и policy прежние, ADR/исключений нет.
Production catalog281 строк; _migrate_scene_path как ordered migration flow
остаётся выше мягкого50, но ниже hard100. Отдельный pass-through helper не добавлен.

Итоговая валидация:7 suites PASS (legacy_cabinet_paths, layout_loading,
named_map_loading, planner_persistence, map_file, debris, destruction_sound),
11 Python CI registry regressions PASS. validate_project PASS:453 GDScript,
122 прежних advisory warnings,158 suites registered (150 runtime +8 jobs).
Headless editor import/resource paths/scene resources/git diff --check PASS;
итоговые runtime/import логи без ERROR/ObjectDB/RID leaks. Сравнение body script
в regression идёт через исходную публичную PackedScene, без private path dependency.

Ограничения: Windows/Web gameplay, native pixels и пользовательские карты вне
репозитория не проверены. Не заявляется FPS/память-выигрыш или совместимость
всех когда-либо существовавших имён props. Старые сцены/скрипты ещё нужны.

Следующий основной пункт аудита — D02. Остальная очередь и условные продолжения:
[оставшиеся задачи](../audits/infection_shooter_audit_remaining.md).
