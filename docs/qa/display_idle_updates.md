# Экранные обновления и подсветка: этап FPS4

Запрос владельца25.10.2026, T004/Phase1. Владелец состояния/представления —
presentation.office_floor. Это CPU-оптимизация контроллера, не измерение FPS.

## Изменение

Прежний controller каждые0.2с читал global_transform/visibility/powered и
положения светильников всех дисплеев для проверки уже сохранённого snapshot.
DisplayView теперь сообщает изменения native transform/visibility notifications,
setter powered и configure/build hooks. Private display_glow — тот же SpotLight3D
со скриптом native transform observer, без нового узла или _process. Он сообщает
также независимое перемещение света и выход из дерева. Сам display регистрируется
при повторном входе в дерево; rebind/unregister сохраняют lifecycle.

Controller не хранит/не сканирует полные snapshots для managed DisplayView.
Прежний polling сохранён для произвольных legacy/custom Node3D adapters.
Проверка камеры и native сравнение состава registry остаются. Camera motion
всё ещё требует полного ранжирования; правила/сортировка кандидатов прежние.

Animation tick обходит только видимый powered subset прежнего animated list.
Если список пуст, timeline frames не рассчитываются; elapsed продолжает идти,
возвращённый экран получает текущий GIF frame. Материалы/атласы/интервалы GIF
и 0.15с layout debounce не меняются. Бюджеты с камерой16glow/4shadow, дистанции
24/16/8м и no-camera fallback прежние. Обычное движение только ставит dirty:
refresh остаётся не чаще прежнего0.2с, не превращается в покадровый обход.
Configure/register сохраняют прежний prompt refresh.

Новые API/DTO/owners/Autoload/Timer/Viewport, материалы или ассеты не вводятся.
Файл public/display_wall остаётся прежним injected registry; новый метод
_invalidate_lighting — приватное взаимодействие компонентов этого модуля.
Повторена отсутствовавшая декларация существующей office_floor→spawning из
CI-фикса PR464: authored main уже содержит публичную spawn_point. Карта
сохранена, policy не ослаблена.

## Проверка поведения

Окончательный run_display_idle_tests на исходных production scripts даёт
4failures: snapshots180, расчёт180timeline frames вне обзора, нерегистрируемый
reentry и связанный с ним лишний свет. Candidate0failures: snapshots0,
offscreen frame reads0, корректные reentry/budgets. На60simulated ticks движения
оба варианта выполняют4budget refresh, а не60. Тест проверяет также реальные
meshes/materials, непрерывную анимацию, точный кадр после возврата, родителя,
видимость и движение во время pause/planning, powered direct assignment,
configure, независимое смещение glow, topology rebuild, shadow permission,
rebind и освобождение.

run_light_budget_cache_tests: 36последовательных legacy changes; полный trace
решений ламп/экранов visible/shadow совпадает до/после. Camera identity,
projection, near/far/FOV/offset/aspect, no-camera, прямое powered/screens
редактирование adapters сохранены. Это независимая регрессия старого polling.

PASS0failures: display_idle, light_budget_cache, display, display_planner.
Display suite покрывает все профили моделей, двухэкранные мониторы, power/auto,
короткое замыкание, PackedScene, общую TV-стену/UV, удаление соседа, анимацию
и standalone/registry rebind. Проверки GPU pixels в headless не выполняются.

## CPU microbenchmark

180реальных DisplayView без GLB мебели, со screen mesh/material/SpotLight3D.
Setup/два warmup callbacks исключены. Один процесс на пробу, пять проб на
версию,200controller callbacks по0.2с simulated delta. Это не200render frames,
не wall-clock40секунд игры и не hardware GPU measurement. Raw данные и
production blob hashes: display_idle_metrics.json.

| Сценарий | Исходник, медиана200callbacks | Candidate | Диапазоны |
|---|---:|---:|---|
| Камера и экраны неподвижны | 34.680мс | 1.168мс | 32.963–39.493 / 1.070–1.308мс |
| Камера двигается | 128.561мс | 134.758мс | 123.417–147.622 / 126.944–144.000мс |

Idle callback cost снизился примерно96.6% (173.4→5.84мкс за один poll).
В moving-сценарии итоговая медиана на4.8% выше, диапазоны сильно перекрываются;
улучшение этого пути не заявляется. Полный расчёт кандидатов сохранён.
Устранение периодического CPU poll не устраняет расходы отрисовки экранов,
динамического света/теней и остальных объектов и не обещает исправить10–12FPS.

## Ограничения и откат

Нативные Windows/Web, visual pixels, полный FPS/RAM/VRAM карты не измерены.
Снимки исходных поверхностей/контент и качество света не упрощались.
Откат — revert инкремента, миграции карт не требуется.
