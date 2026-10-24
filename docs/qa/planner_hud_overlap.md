# Планировщик: перекрытия HUD и предпросмотр затемнения

Запрос владельца25.10.2026. Фаза1/T004, модуль bootstrap.app.

## Изменения

- Панель SpawnWaves больше не плавает поверх информации о выбранном объекте:
  она находится перед списком палитры внутри левого ScrollContainer.
- Действия Undo/Duplicate и кнопка справки составляют одну строку. Под ними
  центральная панель выделения: название и статус, по одной строке, 12px.
  Длинный текст обрезается многоточием, полный доступен по наведению.
- Центральная колонка занимает доступное место между палитрой и ручкой
  правого меню, максимум400px; resize/collapse обновляют положение. Справка
  открывается ниже в собственной прокрутке и не накрывает соседние панели.
- Выключение затемнения действует только при видимом PlanningUI. Выход
  включает fog в игре; повторный вход применяет сохранённый preview.
  Поздние зоны получают актуальное разрешение, reveal/авторская видимость
  не меняются. Покадровых обходов не добавлено.
- Повторена минимальная декларация office_floor→features.spawning из
  исправления CI PR464: authored карта main уже содержит spawn_point.
  Карта сохранена, policy/validators не ослаблены.

## Проверки

run_planner_hud_tests: реальные прямоугольники действий, выделения, палитры,
правой панели/ручки и открытой справки не пересекаются при1024×600,1200×700,
1600×900; длинный статус не увеличивает панель выше44px. Сценарий Actors
проверяет размещение SpawnWaves внутри palette scroll. Прежние tab/input,
каталоги, atlas pixels и JSON/PackedScene roundtrip остаются.

run_planner_fog_tests: выключенный preview→выход→вход, поздняя зона в игре,
preference не меняется при выходе, restart/invalid/pause/material rebuild
и исследованные/скрытые зоны. Оба focused suite —0failures.

Также0failures: run_spawn_planner_tests, run_darkness_palette_tests,
run_planner_light_view_tests. validate_project PASS,387scene refs PASS,
resource paths/diff-check PASS, final editor import без ERROR.

Расширенный run_planning_mode_tests имеет один Named map round trip failure
(5003→5003records). Baseline с исходными HEAD planning_hud_layout/planning_fog
на той же карте повторяет тот же assertion, exit1. Исходники после сравнения
восстановлены. Различия transforms/decor_pose требуют отдельного расследования,
числовые допуски тестов не менялись. BACKLOG фиксирует baseline defect.
Ручная визуальная приёмка на Windows/Web и скриншот с native GPU не выполнены.
Публичные API/форматы карт/сцены/Autoload/owners прежние.

## Откат

Revert UI/fog commit; карты и CFG ключ view/fog_of_war совместимы.
При откате возвращается прежнее глобальное действие preview-переключателя.
