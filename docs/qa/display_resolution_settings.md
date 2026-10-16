# Разрешение и режим окна

Инкремент T004/Phase1/P1_LOGIC по прямому запросу владельца.
Owner bootstrap.app: private display catalog (presets/filter/fallback), display
adapter (native window + resize-driven render scale) и Video controls.
Preferences добавляет optional interface_v1.window_mode (0 windowed/1 fullscreen)
и resolution (строка). Legacy defaults: windowed1280x720, как до изменения.
Auto выбирает размер монитора; окно ограничено рабочей областью с учётом декораций.
720p/900p остаются для integrated GPU; 16:10/ultrawide/QHD/4K доступны по размеру
монитора. Fullscreen сохраняет native aspect, ограничивает3D выбранным budget;
UI остаётся native. Отдельный новый ползунок render scale не вводится.

Область: bootstrap menu_preferences/menu_dialog/settings_tabs, private helpers,
RU/EN translations, tests/CI, ADR/docs. Карты/gameplay saves/public API/module
edges/owners прежние; изменены только optional local interface preferences.
Menu dialog reviewed: platform calls вынесены в adapter, controls — в отдельную
presentation class; dialog только commits preferences. Все новые helpers<100строк.

## Проверки

READY spec/workflow и финальный validate_project PASS (466files/125advisory),
CI coverage164/164 (156runtime+8special), scene_resources392refs/diff PASS.
Первый editor import прервался из-за потери exec-server; после восстановления
полный final editor import exit0 и новый display suite PASS. Все6 целевых suites:
display_settings/settings_tabs/menu/walk_tuning/bullet_smoke/shooting_camera PASS.
Final import/runtime logs без SCRIPT ERROR/ERROR/ObjectDB/RID warnings.
Menu проверяет настоящий start/restart с сохранёнными mode1/resolution1600x900.
Новый suite включён также в существующий native weapon-rendering job (оба renderer),
с Xvfb1920x1080 и проверкой реального DisplayServer mode/placement/resize/3Dscale;
результат native CI пока ожидается.

Новый suite: размеры/aspect/без oversampling, 720p/900p, negative monitor origin,
уменьшившийся экран, invalid/legacy/types/roundtrip/reset; реальные Video controls,
RU/EN и сохранение; lifecycle одного adapter, renderer scale и canvas invariants.
Run_menu_tests проверяет сохранённые mode/resolution на реальном start/restart.

Native fullscreen здесь не запускался; CI добавлен. Pixels/FPS/Windows/Web не проверены.
Следующее действие: получить native CI results и проверить
переключение на обычном display backend. Нужна визуальная приёмка 720p/900p на
integrated GPU и native/ultrawide; выигрыш FPS не заявляется.
