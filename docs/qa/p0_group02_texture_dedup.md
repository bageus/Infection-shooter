# P0: дедупликация текстур группы 02

## Причина

В main `33b7b1fe674d3c4b82d5ba8c02b6b7cefa22f03d` Architecture run
38071648160 завершился с exit 1 на `deduplicate_model_textures.py --check`.
План миграции: один внешний дубликат, 13 встроенных изображений, четыре GLB.
Проверки project gates, scene resources и resource paths прошли до этого шага.

## Изменение

Применён существующий `tools/deduplicate_model_textures.py --apply`.
Изображения не перекодированы и не уменьшены. GLB import profiles прежние.
Удалён byte-identical `02_vending_automat_2_dented_Image_0.png` и его `.import`;
оба автомата используют `02_vending_automat_1_dented_Image_0.png` с совместимым
профилем импорта. Остальные изображения уже существовали в той же группе.

| GLB | Узлы до/после | Вынесено изображений | Сокращение, байт |
|---|---:|---:|---:|
| 02_coffee_vending_1_dented | 11 | 7 | 2 825 956 |
| 02_vending_automat_1_dented | 28 | 1 | 1 131 948 |
| 02_vending_automat_2_dented | 31 | 1 | 1 131 900 |
| 02_vending_machine_fantas_dented | 44 | 4 | 724 052 |

GLB сокращены на 5 813 856 байт; удалённый PNG — 1 131 845 байт.
Итого payload — 6 945 701 байт (6,624 МиБ), плюс удалённый `.import`.
`semantic_digest` исходного Git blob и результата совпал для каждой модели;
геометрия, UV, индексы, структура сцен и узлов, материалы и содержимое изображений сохранены.

## Проверки

Локально PASS:
- `python tools/validate_project.py` (включая ready, workflow, architecture и source-size);
- `python tools/validate_scene_resources.py`;
- `python tools/check_resource_paths.py`;
- `python tools/check_import_files.py`;
- `python tools/deduplicate_model_textures.py --check`: 0 aliases, 0 embedded replacements, 0 changes;
- `python tools/test_texture_deduplication.py`: 10 тестов;
- `python tools/build_display_surfaces.py --check` и `test_display_surfaces.py`;
- `python tools/check_model_textures.py`: 292 модели, 223 textured, 0 errors;
- `python tools/check_group01_atlas.py`, `check_group03_atlas.py`, `check_group04_atlas.py`;
- `python tools/test_group03_atlas.py`, `test_model_textures.py`;
- `python tools/test_destruction_mesh_audit.py`, `test_workstation_templates.py`, `test_architecture_scene_access.py`.

Godot 4.7.2: первый запуск с пустым кешем завершился с exit 0, но лог
остановился на reimport 61%; повторный import завершил импорт и загрузку
editor layout с exit 0. Оба лога без ERROR/SCRIPT ERROR. Финальный импорт PASS.

Runtime PASS (exit 0, без ERROR/SCRIPT ERROR):
- `game/bootstrap/app/tests/run_model_texture_tests.gd`: 292 модели, 223 textured,
  0 failures; 1318 references, 10 shared updated maps, 10,7 МиБ;
- `game/presentation/office_floor/tests/run_staged_glb_tests.gd`: 0 failures;
- `game/presentation/office_floor/tests/run_debris_tests.gd`: 0 failures;
- `game/presentation/office_floor/tests/run_display_tests.gd`: 0 failures.
GitHub CI исправления: ожидает публикации.

## Границы

Затронуты только ресурсы группы 02 и документация текущего T002.
Код, публичные API, scene paths, DTO v8, владельцы состояния и зависимости прежние.
Новых архитектурных исключений нет. FPS и внешний вид Windows/Web не измерялись.
