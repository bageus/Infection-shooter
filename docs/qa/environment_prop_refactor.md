# Декомпозиция EnvironmentProp — 09.10.2026

База: main 9ec40a8. Модуль: presentation.office_floor.

## Результат

- environment_prop.gd: 545 → 367 строк; адаптер публичной сцены,
  локальная композиция физического тела, команды попаданий и authored display config.
- environment_prop_geometry.gd: 124 строки; импортированный Visual,
  упорядоченные стадии/варианты и соответствие shape → mesh принадлежат одному экземпляру.
- environment_prop_breakup.gd: 108 строк; фасадные сколы, последовательные
  обломки и стекло. Геометрия и физическое тело передаются явно.
- Правила прочности остаются в features.combat.prop_damage_state.
- Public методы и exported поля сравнены с базой: без изменений.
  Наследники bathroom_fixture/paper_prop и диагностические поля совместимы.
  Сцены, ассеты, баланс, DTO, зависимости и policy не изменены.
- run_staged_glb_tests дополнен проверкой: разрушение первого шкафа не меняет
  стадии, состояние прочности и соответствие коллизий второго экземпляра.

## Проверки

Godot 4.7.2 stable, headless:

- `--headless --path . --editor --quit`: exit 0, без SCRIPT ERROR/ERROR.
- `--headless --path . --script <suite>`: 14 наборов PASS:
  office_floor: run_staged_glb_tests, run_display_tests, run_debris_tests,
  run_hit_effect_tests, run_prop_weight_tests, run_contact_shadow_tests,
  run_surface_decor_tests, run_sound_hook_tests;
  bootstrap: run_world_bindings_tests, run_world_surface_tests,
  run_model_texture_tests, run_layout_bake_tests, run_display_planner_tests;
  combat: run_prop_damage_state_tests.
- `--headless --path . res://game/bootstrap/app/main.tscn --quit-after 180`:
  exit 0, без SCRIPT ERROR/ERROR.
- Imported model audit: 257 active models, 184 textured, 0 failures.

Python и Git:

- validate_game_spec.py --ready, validate_workflow_state.py --ready,
  validate_project.py, validate_scene_resources.py, check_resource_paths.py,
  check_import_files.py, check_model_textures.py: PASS.
- test_architecture_scene_access.py, test_model_textures.py,
  test_workstation_templates.py, test_glass_openings.py: 12 tests PASS.
- git diff --check: PASS.

## Ограничения

Два тяжёлых теста полной сцены при параллельном запуске были завершены
с кодом -9 без ошибки Godot. Последовательно world_bindings и world_surface
прошли с exit 0; основной запуск также проверен отдельно. Причина -9
не измерена, нехватка памяти при параллельной загрузке остаётся предположением.
Предупреждение окружения об отсутствии /proc/self/exe не мешает запуску.

Рендерные снимки и FPS Windows/Web не измерялись. Root выше review-порога
300 строк: оставшиеся обязанности — публичная граница и композиция тела,
решение по дальнейшему разделению описано в docs/ARCHITECTURE.md.
Архитектурных исключений нет. Откат — revert коммита этого инкремента.
