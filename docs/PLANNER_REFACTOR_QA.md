# Проверка CI освещения на актуальном планировщике

Первый CI PR #17 (run 36773694786) проходил validate_architecture.py, но падал в validate_source_size.py: planning_mode.gd 1627 > 600 строк. В main коммит b9533c8 разделил планировщик по обязанностям и удалил неиспользуемые сцены. PR согласован с этим коммитом: его компоненты, владельцы состояния, удалённые сцены и дополнительные проверки сохранены.

Изменения освещения перенесены в актуальные компоненты: planning_controls.gd редактирует авторскую энергию и показывает её в UI, planning_objects.gd загружает авторскую энергию/коэффициент, planning_storage.gd сохраняет коэффициент и экспортирует сцену. planning_mode.gd и разделение из main не заменяются повторной реализацией. Все производственные файлы укладываются в жёсткий лимит 600 строк; исключения лимита и ослабление CI не добавлены.

| Компонент | Строк |
|---|---:|
| planning_mode.gd | 431 |
| planning_catalog.gd | 135 |
| planning_controls.gd | 261 |
| planning_objects.gd | 443 |
| planning_geometry.gd | 335 |
| planning_storage.gd | 222 |

Проверки итогового сочетания:

- python tools/validate_project.py — PASS, включая readiness/workflow/architecture/source-size.
- python tools/validate_scene_resources.py — PASS, 254 ссылки.
- python tools/test_workstation_templates.py — PASS, 3 теста.
- Godot 4.5.2 run_lighting_tests.gd — 0 failures, включая пять циклов реального планировщика, мерцание, восстановление, JSON round-trip, Undo/Duplicate и restart.
- Godot 4.5.2 run_planning_mode_tests.gd из актуального main — PASS: размещение, поворот, Undo, desk setup, управление лампой, запись и загрузка настоящего временного JSON-файла карты.
- git diff --check — PASS.
- Headless editor import exit 0 с прежними ошибками FBX-текстур palette1.png/couches.png; импорт не чистый. Основная сцена — 180 headless-кадров без SCRIPT ERROR/ERROR.

Документация контракта освещения: ADR-0010 (номер ADR-0009 занят разделением планировщика в main). Целевая Godot 4.7.2, графический Windows/Web и FPS по-прежнему требуют визуальной приёмки по LIGHTING_QA.md. Унаследованные динамические маршруты каталога этим исправлением не переработаны.
