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

READY spec/workflow gates PASS до кода. Первый локальный validate_project PASS
(до добавления нового suite и последних изменений adapter). Во время импорта Godot
exec-server потерял соединение; финальные local import/runtime не заявляются PASS.
Исходники сохранены через GitHub, новый run_display_settings_tests зарегистрирован
в canonical runtime manifest. Итоговую проверку выполняет CI.

Новый suite: размеры/aspect/без oversampling, 720p/900p, negative monitor origin,
уменьшившийся экран, invalid/legacy/types/roundtrip/reset; реальные Video controls,
RU/EN и сохранение; lifecycle одного adapter, renderer scale и canvas invariants.
Run_menu_tests проверяет сохранённые mode/resolution на реальном start/restart.

Native fullscreen/Compatibility pixels/FPS/Windows/Web здесь не проверены.
Следующее действие: получить CI results, исправить найденные ошибки и проверить
переключение на обычном display backend. Нужна визуальная приёмка 720p/900p на
integrated GPU и native/ultrawide; выигрыш FPS не заявляется.
