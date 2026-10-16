# O01 — обновление лестничных проёмов без обхода мебели

Дата: 16.10.2026. Исходная A/B база `12d2570`; перед публикацией принята main `014c546`
после A08, затем main `242616e` после PR217/218 (стрельба/камера и shelter
Colossus). Godot4.7.2, Linux headless. Код лестничной геометрии в этих PR не менялся.

## Изменение

MissionLayout выполняет один начальный поиск в переданном PlanningObjects.
Затем child_entered/exiting_tree поддерживают mission-local weak registry
лестничных корней. Добавление проверяется deferred: placement/loader назначают
metadata после add_child. Удалённый до регистрации узел игнорируется.
Ссылки/наблюдатели очищаются при teardown; новая сцена миссии создаёт свой cache.

Раз0.35с проверяются global_transform и visual AABB только известных лестниц.
Сами отверстия переиспользуются, пока эти inputs прежние. Проверка bounds
сохранена, поэтому изменения дочернего Visual или общего Mesh также видны.
Порядок opening arrays соответствует текущему порядку детей, включая reorder.
Без лестниц _process отключён; последнее удаление сначала закрывает проёмы.

Геометрические функции, пороги расположения этажей, шаг сетки0.5м, floor region
partition, физические формы пола и goal_reached не изменены. Перемещения/поворот/
масштаб/ancestor transform, поздняя metadata, удаление/undo/reload дают те же
проёмы. Сохраняется прежний pause contract: во время paused planner processing
MissionLayout приостановлен; после resume изменения подхватываются.
Asset identity задаётся factory при создании корня; превращение произвольного
старого Node3D в лестницу одной поздней правкой metadata не является путём
редактирования проекта. Замена asset в существующих командах создаёт новый root.

Изменения внутри bootstrap.app: mission_layout.gd, две регрессии и CI.
Публичные API, owners, зависимости, PackedScene/ресурсы, DTO/map formats прежние.
Новых архитектурных исключений нет; production файл221 строк, функций за
порогами не добавлено.

## Регрессии

`run_stair_refresh_tests.gd` сравнивает точные ordered arrays с прежним полным
обходом, используя неизменённые geometric functions. На исходном production —
**6 failures**, на исправленном —**0**, без SCRIPT ERROR/ERROR/ObjectDB warnings.
Это проверки отсутствия повторных чтений мебели, отключения пустого polling,
reuse геометрии и игнорирования selection highlight.

Функциональные случаи: настоящий descending staircase, перенос/upstairs,
поворот и равномерный масштаб, ancestor transform, legacy path, два пролёта,
reorder, metadata/Visual после add_child, перенос Visual/смена Mesh bounds,
selection overlay, detach/reattach, clear, удаление до deferred registration,
reload и initial discovery уже существующей лестницы. Для каждого состояния
проверяются floor visual, original floor collision mode, реальные ray queries
в проёмах и на сплошном полу, положительный/отрицательный goal и порог y=-1.3.
Неравномерный scale проверен на geometry-only fixture: Jolt не поддерживает
его для некоторых walkable shapes настоящей модели (ограничение движка).

`run_stair_planner_tests.gd`: настоящая main scene, загрузчик canonical/legacy
records, pause/resume, planner rotate/scale/nudge, undo, delete/undo с новым root,
реальный collect/JSON/reload, clear и восстановление сплошного пола —0 failures.
Оба suite добавлены в Mission runtime CI.

## Измерение

Данные: [stair_refresh_metrics.json](stair_refresh_metrics.json). По три отдельных
процесса каждой ревизии, по5 warmup и100 вызовов;5424 Node3D без лестниц/мебельных meshes.
Population и initial discovery вне таймера. Медиана средних трёх прогонов:

| Метрика | Прежний код | Исправленный |
|---|---:|---:|
| Среднее время проверки, мкс |3443.89|0.76|
| Медиана p95 трёх прогонов, мкс |4336|1|
| Чтения model_path мебели за100 проверок |542400|0|

Команда воспроизведения на нужной ревизии, с тем же новым test script:

```bash
godot --headless --path . --script game/bootstrap/app/tests/run_stair_refresh_tests.gd -- --benchmark
```

Это цена конкретной функции, а не всего кадра: прежняя работа была периодической,
не каждый кадр. В сцене с лестницами остаётся проверка их bounds/transform.
Результат пустого cache находится около разрешения1мкс таймера; отсутствие
обхода отдельно подтверждено точным счётчиком чтений. Измерение не является
обещанием прироста игрового FPS или бюджетом GPU.

## Приёмка

Все8 целевых suites прошли assertions: stair_refresh, stair_planner,
group01_asset, planning_mode, layout_bake, world_bindings, planner_persistence,
startup_resource_memory. В первом параллельном прогоне startup после успешных
assertions сообщил об одном неосвобождённом RendererDummy Mesh RID; runner
правильно пометил набор failed. Это не скрывалось и teardown/assertions не
менялись. Отдельные повторные startup/restart на исходном и исправленном
production прошли без ERROR/WARNING/ObjectDB/RID. Причина одиночного сообщения
не установлена, его связь с этим изменением не доказана. Остальные7 наборов
чистые с первого запуска. Peak allocator935.43MiB, RSS1207.30MiB на повторном
candidate startup; video0, не GPU-измерение.

После принятия main242616e дополнительно повторены stair_refresh, stair_planner,
shooting_camera, new_weapon и colossus_shelter:5 suites PASS, без warnings/errors.
Все чужие изменения сохранены.

Project/spec/workflow/architecture/scene/resources/diff gates и editor import
PASS;121 прежних source-size warnings, новых превышений нет.
Windows/Web и визуальный проход персонажа по лестнице вручную не проверены.
