# Проверка исправлений представления — 10.10.2026

Base: 33b7b1fe674d3c4b82d5ba8c02b6b7cefa22f03d. Scope: T002 / запрос владельца. Решение: ADR-0039.

## Результат

- HUD `sniper_scope.gd`: реальное увеличение 2.5× на экранный пиксель с учётом размера линзы и keep_aspect.
- Bootstrap `menu/mission_loader.gd`: start/restart не захватывает свободный курсор.
- Infection_source `mutagen_cloud.gd` / `.gdshader`: procedural green smoke, две частоты noise, 4–5 прозрачных слоёв вместо 7–9; нет ссылок на PNG-атласы и запуска GPU spores. Барьерная маска, absorption delay/refusal/non-stacking, lifetime/permanent/depleted и cap сохранены.
- Office_floor `city_facade.gdshader` / `public/city_backdrop.gd`: каждый третий блок — полностью стеклянная облицовка с тонкими перемычками. 144 здания, прежние batches, fog/no-collision/no-lights.
- Bootstrap `menu/menu_preferences.gd` / `settings_tabs.gd` и `assets/interface/translations.json`: Video → Освещение, persisted bool, лампы и global directional light. Ambient остаётся для видимости; authored lamp config прежний.

## Фактически выполненные проверки

Godot 4.7.2:

- Clean headless editor import: exit 0, без ERROR/SCRIPT ERROR; повторный итоговый import PASS.
- Headless suites PASS: mutagen_cloud, new_weapon, settings_tabs, mission_loading, city_backdrop, global_lighting, cursor_aim, lighting, menu.
- Native Compatibility (OpenGL Mesa llvmpipe): new_weapon, mutagen_cloud, city_backdrop PASS, без SCRIPT/SHADER ERROR. Scope включает pixel assertion реальной красной цели.
- Native Forward+ (Vulkan 1.4.318 Mesa lavapipe): те же три suites PASS, без ERROR. Первоначальная попытка без Vulkan driver переключилась на OpenGL и не считается Forward+; итоговая проверка использует настоящий Vulkan.
- `tools/capture_mutagen_cloud.gd`: Compatibility capture 0.4–10.0 секунд; кадр 2.4 с визуально проверен: мягкое полупрозрачное зелёное облако, без прямоугольной PNG-границы.
- `python tools/validate_game_spec.py --ready`, `validate_workflow_state.py --ready`, `validate_project.py` PASS. Project включает architecture/source-size gates; существующие size warnings не объявляются ошибками.
- `git diff --check` PASS.

## Ограничения

Полный общий runtime suite не выполнялся; существующий CI проверяет интеграцию после публикации. Число слоёв и shader workload уменьшены, но FPS на целевом Windows/Web не измерен и процент ускорения не заявляется. Software renderer не является пользовательским GPU. Старые PNG не удалены, поскольку это исходники владельца и другие ресурсы могут их использовать.

Public API, сцены, владельцы и зависимости прежние. Аддитивная приватная опция interface_v1.lighting=true совместима со старым конфигом; map/campaign/network DTO прежние. Архитектурных исключений нет.

Следующая целевая проверка: повторить start/restart, sniper на разных разрешениях, серию одновременных death clouds и light OFF→ON в Windows/Web; проверить CI draft PR.


## Исправление CI PR #85

Run 38073379819 (Architecture) и runtime job 114275213313 run 38073379826 остановились на `deduplicate_model_textures.py --check`: duplicate_files=1, externalized_images=13, changed_models=4. Эти модели пришли из base main 33b7b1f и не входили в исходные visual changes. Существующий deduplicator применён к четырём dented vending models группы 02; их semantic_digest (geometry/material/scene/image payload) до/после одинаков. 02_vending_automat_2_dented_Image_0.png заменён побайтно идентичным 02_vending_automat_1_dented_Image_0.png с тем же import profile. Удалены только заменённый дубль/import. Сэкономлено 5.54 МиБ embedded и 1.08 МиБ отдельного файла. Повторный dedup check: zero duplicates/externalized candidates/unmatched images.

Planner-rendering Forward+ job 114275213481 оборвал planner_extension на 180 сек, без ERROR/assertion failures; следующий occlusion suite прошёл. Отдельные weapon/effects и Compatibility planner прошли. На software Vulkan размер root viewport сам по себе не ограничивает rasterization directional shadow map 2048². Fixture сохраняет 320×180 viewport, всю сцену, источники/тени, capture lifecycle и все 90 physics ticks; только directional/positional shadow atlases ограничены 256². Pixel assertions в этом suite отсутствуют, отдельные shadow/render tests сохраняют реальные профили. Ни production renderer, ни тайм-ауты/assertions CI не ослаблены.

После исправления: Python Architecture block целиком PASS (включая profiles/atlases и unit tests), model audit 292/223/0 errors, semantic_digest четырёх GLB PASS, clean import без ERROR. Native Vulkan Forward+ planner_extension PASS за 89.19 с: все assertions, corpse/aim screenshots 320×180, прежний лимит 180 сек. Полный 73-suite и Compatibility завершаются; новая CI ревизия проверяется после публикации.
