# Оставшийся тайм-аут planner light view — 26.10.2026

T004/Phase1/P1_LOGIC. База main60e0d3f после merge PR481.

## Подтверждённый результат предыдущего CI

Head636538ce: Architecture и Mission music transitions SUCCESS. Runtime job121544537818 SUCCESS: прежние biomass/UI failures устранены. Planner Forward+ job121544537672 и остальные renderer jobs также SUCCESS, кроме rendered-pixels Forward+ job121544537685.

Единственное оставшееся падение: `run_planner_light_view_tests.gd` завершён timeout124 после300с (run40314785374). В логе нет assertion/script/shader errors, видны3 checkpoints mission loading; затем завершение по внешнему лимиту. GL-вариант того же workflow прошёл.

## Изменение

Только test fixture `game/bootstrap/app/tests/run_planner_light_view_tests.gd`:

- Для native Forward+ выставляет 3D render scale0.25 и positional/directional shadow atlas256, как ограниченный raster budget программного Vulkan. Остальные renderers сохраняют прежние настройки.
- Сохраняет logical viewport/HUD размер; отдельная assertion проверяет это, поэтому мышь и camera projection используют прежние координаты.
- Полная авторская карта, реальные камеры/лампы, все mouse input, placement/selection/editor, undo, JSON/save-reload, overhead pan/zoom и planner lifecycle assertions остаются.
- Добавлены checkpoints после enter, placement/edit и reload, чтобы следующий timeout указывал фазу.

В этом suite нет pixel/shadow-quality assertions. Внешний timeout300 и прочие native pixel suites остаются. Production settings, renderer, lighting, API/DTO/scenes/owners/edges не меняются. Это исправление стоимости test rasterization, не измерение/обещание игрового FPS.

Decomposition review: небольшой test file; `_run` прежняя последовательность UI-сценария (98 строк, hard100), настройка native raster budget вынесена в отдельный helper. Новых module edges или policy exceptions нет.

## Проверки

Pinned Godot4.7.2 `ed1daf0bf`: `--headless --check-only --script ...run_planner_light_view_tests.gd` — exit0, без script/resource errors. Для проверки оригинальные недостающие sparse dependencies материализованы из git, файлы assets не менялись.

`validate_project.py` — PASS,238 suites/635 sources/177 size warnings.14 Python CI coverage/runner tests и diff check — PASS. Финальный headless editor import/open — exit0, без errors/leaks после материализации casing textures. Ранний import с отсутствующими локально textures не считается PASS.

Локальная sparse-копия не содержит все dynamic модели авторской карты и native software Vulkan/Xvfb, поэтому полный suite/время до-после здесь не заявляются пройденными. Проверка гипотезы о raster cost и результата при прежнем timeout — новый GitHub native Forward+ CI. Следующее действие — проверить новый PR/CI до перехода к Q02. T004 остаётся IN_PROGRESS.
