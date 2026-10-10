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
