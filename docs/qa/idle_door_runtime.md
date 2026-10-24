# Двери: меньше работы в покое

Дата: 24.10.2026. T004 / Phase1 / P1_LOGIC, второй пункт FPS-диагностики.
База: main `5ee4e6ef3ac36d6f1b56cb7bb372179ec02dce06`. PR461 — отдельная
правка звуков спящей мебели; этот инкремент не требует её слияния.

## Поведение

Закрытая дверь после первой установки позы выполняет быстрый proximity guard,
если нет ожидания закрытия и request_open. За пределом
`max(3.0, trigger_distance + 0.5)` в исходных локальных XZ пропускаются
проверки ключа, звук и управление позой. Скрывается badge и возвращается
готовность locked cue. Для стеклянной створки сохраняется обновление стороны
открывания при обходе издалека. Координата local Y по-прежнему не ограничивает
старый trigger. Ближняя дверь, движение, задержка закрытия и remote request
обрабатываются каждый физический тик. Телепорт и быстрое приближение не ждут
таймера: proximity guard также выполняется каждый тик.

Обычная дверь не запускает glass collision check; незапертая не запрашивает
ключ. Private door_runtime_cache удерживает ссылки на glass Visual, GlassBody
и его CollisionShape children. Список обновляется по child enter/exit, а
подписки явно отключаются при выходе двери из дерева и восстанавливаются при
повторном входе. Координаты не замораживаются: используется native to_local
с живыми transforms/смещением Visual. Коллизии стеклянной двери проверяются
даже при idle guard, включая исправление внешней реактивации разбитой панели.

Новых Timer, Area3D, отключения/заморозки физики или distance streaming нет.
Владельцем locks/timers/motion остаётся interactive_door; cache содержит только
производные geometry bindings. Public API, сцены, ресурсы, карты/DTO, owners,
dependencies и policy не меняются. Root597строк reviewed: сохраняет door-only
управление, runtime bindings выделены по отдельной причине изменения.
Архитектурных исключений нет. Откат — отмена этого инкремента целиком.

## Изолированный CPU стенд

run_door_idle_tests создаёт 200 простых key-locked controllers, прогревает
первую позу и вручную вызывает 60 физических шагов с неподвижным дальним
игроком. Счётчик key queries принадлежит fixture player; glass_checks —
подклассу двери. Тесты проверяют результаты, а не текст реализации.
Пять отдельных процессов Godot4.7.2 на каждой версии; исходный root и
исправленный root запускают один и тот же окончательный suite.

| Показатель за 12000 callbacks | Исходный main | Исправление |
|---|---:|---:|
| Запросов ключа | 12000 | 0 |
| Вызовов glass check у обычных дверей | 12000 | 0 |
| Медиана времени всего цикла, мс | 16.962 | 7.216 |
| Минимум–максимум, мс | 16.274–17.398 | 6.848–7.704 |
| Failures окончательного suite | 2 | 0 |

Здесь около 57.5% меньше CPU-времени проверяемого цикла. Callback самой двери
по-прежнему вызывается каждый тик. Это НЕ измерение полного времени кадра,
GPU или FPS карты владельца; сцены моделей/анимации/отрисовка не входят в цикл.

## Регрессии

Новый suite: все четыре mode, подход/телепорт на первом тике, one-way wrong
side, увеличенный authored trigger, live key pickup без движения, sealed и
planner unlock, close delay и полное закрытие, request_open издалека,
rotation/scale/translation родителя и исходный local-Y trigger; смещённый и
двигаемый glass Visual, сторона hinge при обходе, broken collision repair,
late/free shapes, tree reentry и удаление GlassBody до двери.

Godot4.7.2 headless, все0failures без SCRIPT ERROR/ERROR/leaks:
- run_door_idle_tests
- run_door_runtime_tests
- run_planner_door_lock_tests
- run_key_door_hint_tests
- run_door_blood_attachment_tests
- run_glass_crack_tests
- run_sound_hook_tests
- run_darkness_room_tests

Editor import и validate_project PASS; suite зарегистрирован в runtime manifest,
impact_geometry paths учитывают новый private cache. Финальные project/editor/385 scene refs/resource paths/diff gates PASS. Windows/Web, ручная визуальная приёмка и FPS не проверены.
