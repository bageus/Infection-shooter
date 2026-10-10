# P1 аудита — 10.10.2026

Исходная версия: main `5bd130a9`, уже содержит merge P0 / PR #84.
Scope T002 — четыре строки скриншота владельца. Новых зависимостей,
архитектурных исключений или save/public scene contracts нет.

## Запись карт

Named map, SAVE LAYOUT и editor shipped JSON используют planning_map_file.
JSON сначала пишется в соседний `.tmp`, flush/close и read-back проверяют
полные байты и schema. Предыдущая **валидная** карта аналогично готовится
в `.bak.tmp` и заменяет `.bak`; только затем заменяется основной JSON.
Ошибки открытия, записи, проверки, backup и replacement показываются в UI.
Если существующая карта недоступна для чтения, replacement отменяется: это
не трактуется как повреждённый JSON, который можно заменить без backup.
Authored snapshot меняется только после успешной записи. Временные файлы
не считаются картами, recovery copies не коммитятся.

Повреждённый основной JSON не заменяет последнюю рабочую резервную копию.
Наличие проверенного `.bak` позволяет восстановиться и при исчезнувшем
основном файле. Последний шаг использует DirAccess.rename_absolute в одном
каталоге; результат проверяется. Это защита от частичной записи приложения,
а не гарантия сохранности при аппаратном отказе или обесточивании файловой
системы; Windows/Web долговечность требует проверки на соответствующем runtime.

## Запуск и восстановление

Чтение проверяет JSON и schema до создания объектов карты. Ошибка оставляет
предыдущую сцену/камеру/паузу, освобождает pending mission и показывает причину.
В UI предлагаются только валидные кандидаты: предыдущая `.bak` и штатная карта.
Выбор запускает прежний staged/threaded pipeline, включая progress/snapshot и
активацию после всей карты. Исходное повреждённое сохранение не переписывается.
Back позволяет отказаться; повторный recovery click не запускает вторую миссию.
Fresh install без primary/backup по-прежнему загружает штатную карту.

## Поиск пути

Прежние cell 0.8м, radius 18 cells, максимум 192 раскрытий, восемь направлений,
physics cast layer 1, cooldown 45 + actor-id jitter и standalone search сохранены.
Frontier использует stable binary min-heap вместо линейного `_lowest`.
Mission queue тоже heap: ближайшие запросы идут раньше, возраст предотвращает
бесконечное вытеснение дальних. Ссылки слабые, повторные requests deduplicated;
cancel/expired/dead actors очищаются. Изменение цели/позиции перезапускает
устаревшую незавершённую порцию; heap tombstones периодически compacted.

Мягкий бюджет одного physics tick — **2000 мкс**, дополнительный safety cap
**64 раскрытия** и **2 завершения**. Состояние текущего узла и соседа позволяет
передать работу следующему кадру между cast_motion. Один physics cast и его
обработка не прерываются, поэтому возможен overshoot; это не жёсткая гарантия wall-clock кадра. Старый
проверенный путь используется во время ожидания, при отсутствии пути враг ждёт.
Clearance memoization не переживает физический кадр/порцию; открывшаяся дверь
и движущаяся преграда проверяются снова. Shortcuts ограничены четырьмя за запрос
направления; следующий сегмент проверяется перед движением.

CPU sample одинаковой стены и 32 route requests, Godot 4.7.2 headless:

| Метрика | Исходный main | P1 |
|---|---:|---:|
| Наибольшая порция поиска, мкс | 2432 (два целых A*) | 2189 |
| Завершение 32 запросов | 16 порций | 50 physics ticks |
| Незавершённых запросов в конце | 0 | 0 |

Это один локальный CPU sample, без оценки всего игрового кадра/FPS.
Стресс-стена 40м (192-expansion cap), 32 маршрута: baseline p95/peak 14,65мс;
P1 p95 4,31мс, peak 24,65мс. Повтор с probe instrumentation дал p95 2,117мс,
peak 2,419мс и max cast_motion 0,371мс. Причина разброса wall-clock timings не
установлена. Жёсткий предел 2мс не заявляется; оценивать надо весь игровой
кадр на целевом устройстве, включая задержку получения пути. Tradeoff —
меньше пиковых порций, больше задержка полного пути в толпе. Regression с
постоянными ближайшими запросами завершил дальний путь за 120 ticks при
намеренно сниженном cap 4 expansions. FPS Windows/Web не измерен.

## Свет экранов

Материал и animated/static content не меняются. Mission-local display_wall раз
в 0.2с выбирает ближайшие powered/visible screens в camera frustum: до **16**
SpotLight в **24м**, до **4** теней в **16м**. Без camera отдельные fixtures
сохраняют локальное свечение, но не запрашивают тени. Каждый экран больше не
включает shadow по умолчанию. Выключение, повреждение, hide и удаление сохраняют
прежний lifecycle. Общий свет видеостены не добавлен: bounded selection даёт
лимит стоимости без нового размещения light cone и риска свечения за стеной.

Native A/B profile теперь сравнивает все 24 света/тени с новой bounded policy
в ABBA порядке; sample удерживает policy, чтобы registry не отменял baseline
в середине измерения. Native цифры и визуальная приёмка ожидают CI; строгая величина FPS не заявляется.

## Проверки

Godot 4.7.2 clean import завершён, без ERROR/SCRIPT ERROR.
`validate_project.py` PASS; soft source-size warnings существующих файлов не
подавлялись. planning_storage >300 строк пересмотрен: DTO collection/scene bake
остаются его ответственностью, новое verified IO выделено отдельно. Ни один
production файл не пересекает hard limit. Новые tests включены в runtime CI.

Локально полный runtime loop **74/74 PASS** (386,81с), плюс 15 focused suites
и main 180 кадров PASS. Final IO guard проверен повторно map_file и
mission_loading; после интеграции main повторены ещё шесть affected suites. Основные 10: map_file, chase_route, display, layout_loading,
mission_loading, planner_persistence, display_planner, world_bindings,
planning_mode, menu. Map tests проверяют две записи/backup, invalid schema,
ошибку temporary/backup preparation, игнорирование interrupted temp, сохранность
corrupt evidence/last-good backup и fresh install. Mission tests проверяют
предложение обоих recovery вариантов, сохранность предыдущей сцены, запуск
64 записей из backup и повторный click. Route tests используют явный cap 8 для доказательства распределения по
кадрам, чтобы assertion не зависел от скорости CI-host. Проверяют collision clearance,
бюджеты, resumability, dedup/cancel/expired, priority/aging и открытие стены.
Display tests проверяют 24 экрана, лимиты, far/offscreen/power-off и сохранённую
emission. Дополнительно enemy_lod, horde_escalation, late_spawn_debris,
global_lighting и lighting PASS. Включён main `299f6961` (PR #85); новый
свободный курсор и все его assertions сохранены, интегрированный import и
project gate повторены. CI кода 804c600: Architecture, все 74 headless, main, weapon/planner в обоих
renderer и effects PASS. Общий native batch выполняется; финальный статус
GitHub CI фиксируется в PR, полный native PASS здесь не заявлен.

Откат — revert task commit: schema, authored models и карта не менялись;
пользовательские `.bak` не удалять.
