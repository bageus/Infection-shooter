# Игровая камера: Alt

Запрос владельца: управление камерой во время игры аналогично планировщику,
запоминание выставленных углов, параметры под радаром для передачи разработчику.

## Поведение

Alt+ЛКМ drag: поворот/наклон 0.008 рад/пиксель, как в планировании.
Камера обходит персонажа и смотрит в его сторону. Колесо сохраняет прежний zoom,
Z/X — прежний поворот. Во время Alt обычная стрельба заблокирована.
Под радаром: наклон/поворот до 0.01°, базовая дистанция до 0.01 м, RU/EN.
Alt отпущен: панель скрывается, настройка сохраняется. При повторном Alt
параметры снова доступны. Пауза скрывает readout; планировщик не меняет preference.

Локальный cfg camera_v1.version=1, не gameplay save/map DTO. Нет файла — прежний
ракурс; malformed/NaN/Inf не применяются, числа clamp. Player владеет orbit,
bootstrap — локальной настройкой и readout. API описан в module.json/ADR0060.
Root player590/main>300 reviewed: только input/public adapters и composition;
обработка orbit и storage/UI в отдельных private components. Новый test _run>50
reviewed: один последовательный input/pause/persistence lifecycle fixture.

## Автоматические проверки

Godot4.7.2 final editor import: exit0 без ERROR/SCRIPT ERROR.
run_shooting_camera_tests: PASS (включая round-trip, malformed, clamp, focus,
normal update, существующие реальные shots/zoom/recoil).
run_gameplay_camera_tuning_tests: PASS (реальный Alt/LMB input, чувствительность,
readout, flush на паузе, восстановление в новом component).
run_radar_lifecycle_tests: PASS.
run_planning_mode_tests: PASS, полный named-map save/load.
Повтор gameplay_camera_tuning после добавления held-fire regression: PASS.
validate_project: PASS, CI188 suites; validate_scene_resources: PASS384 refs.

Первый ранний shooting run во время импорта ожидаемо не нашёл ещё не
импортированные GLB; после импорта повтор PASS. Initial input fixture требовал
Input.flush_buffered_events; после исправления fixture PASS, production без изменений.

## Ручная приёмка

Запустить миссию; зажать Alt, тянуть ЛКМ, убедиться, что нет выстрелов и персонаж
остаётся в центре. Отпустить Alt, проверить движение/прицеливание, Z/X и zoom.
Перезапустить миссию и игру, сверить углы. Открыть/закрыть planning, убедиться в
возврате игрового ракурса. Снять параметры под радаром и передать для нового default.
Native/Web pixels, удобство крайних углов и аппаратный FPS здесь не проверялись.
