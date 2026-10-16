# O02 — поэтапная загрузка именованной карты

Область: bootstrap.app, инкремент T004. Предыдущая карта остаётся до успешной
валидации, загрузки ресурсов и создания всех новых узлов вне дерева. После этой
границы прежние заменяемые узлы освобождаются по кадрам, новые добавляются по
кадрам. Сбор authored DTO и структурных fingerprint также поэтапный. Публикация
снимка/имени происходит только после полного завершения.

## Реализация и сохранённые контракты

- `planning_storage.gd`: один busy guard для LOAD/SAVE MAP/SAVE LAYOUT; запуск
  внутренней транзакции и атомарная публикация готового snapshot.
- `planning_map_load.gd`: временный экран read/resources/prepare/free/objects/
  attachments/snapshot/ready, фокус и отключение planner UI; восстановление UI при ошибке.
- `planning_layout_loader.gd`: прежние prepare_async/commit_async с необязательной
  проверкой жизни владельца; staged clear сохраняет planning_existing/keep_on_clear.
  Startup не использует новый clear/attachments pass и сохраняет прежний порядок запуска.
- `planning_blood_placement.gd`: поэтапный preorder-обход для named load; прежняя
  синхронная функция и новая используют одну команду восстановления attachment.
- `planning_layout_capture.gd`: одна проекция всех прежних полей DTO для обычного
  SAVE и поэтапного снимка. Это перенос существующей записи, без миграции данных.
- `planning_mode.gd`: во время busy не двигает камеру/объекты и не выходит по Esc.

Public API модулей, сцены/ассеты/ресурсы/DTOv8/сеть/зависимости/owners прежние;
архитектурных исключений нет. Loader/storage/capture — private bootstrap.app.
Storage >300 строк: ответственность DTO выделена; режим остаётся владельцем
planner input. Лимиты не повышены. Журналы задачи дополнены в конце, без замены
записей параллельной работы.

Read/validation/instantiate failure сохраняет старую карту, selected, undo,
player spawn, authored snapshot и map name. Отсутствующие сцены пропускаются с
прежним отчётом; полностью ненагружаемая карта отклоняется, явно пустая допустима.
После успешной подготовки commit не предлагает пользовательскую отмену: иначе
потребовалось бы удерживать старые узлы и после границы освобождения. При уходе
миссии подготовленные/оставшиеся узлы освобождаются, результат не публикуется.
Выданные ResourceLoader jobs дренируются: API Godot не поддерживает их отмену.

## Воспроизводимые проверки

`run_named_map_loading_tests.gd` добавлен в mission_runtime CI:

- некорректные поля, all-missing, сломанный JSON, отсутствующий файл;
- отказ factory после 64 успешных созданий, освобождение staged узлов;
- неизменность layout/selection/history/spawn/authored/name при отказе;
- heartbeat при паузе, busy SAVE/reload, неизменность файла;
- mixed map, player spawn, сохранение порядка и retained/invalid старых узлов;
- равенство staged snapshot и обычной DTO projection, явно пустая карта;
- одинаковое разрешение duplicate owner ids в sync/staged blood attachment pass;
- уход сцены во время prepare, free, commit и snapshot; отсутствие частичного
  snapshot и освобождение всех отслеживаемых узлов.

Настоящий `run_planning_mode_tests.gd` ожидает coroutine, проверяет блокировку
exit/Delete, затем прежний round trip всех объектов. Целевые suites:
`named_map_loading`, `layout_loading`, `planning_mode`, `planner_persistence`,
`stair_planner`, `layout_bake`, `mission_loading`, `startup_resource_memory`;
также `blood_decor` и `surface_decor`.

## Измерение именно named load

Ручной стенд `game/bootstrap/app/tests/profile_named_map_loading.gd` создаёт
настоящий Main с существующей картой и загружает 5363 записи shipped map повторно.
`-- --sync` выполняет прежнее тело named load: read/apply/snapshot в одном вызове.
Без флага используется новый LOAD. Обе ветки используют ту же DTO projection и
те же ассеты. Начальная сборка, вход в planner и 5 прогревочных кадров вне таймера.

Команды, каждая с отдельным пустым XDG_DATA_HOME, запускаются последовательно:

```bash
godot --headless --path . --script game/bootstrap/app/tests/profile_named_map_loading.gd -- --sync
godot --headless --path . --script game/bootstrap/app/tests/profile_named_map_loading.gd
```

`named_map_loading_metrics.json` содержит фактические интервалы process_frame,
время операции и память. Allocator/RSS наблюдаются на кадрах и границах factory/
bind; phase logs показывают память на границах prepare/free/commit/snapshot.
Это sampled peak, не доказанный абсолютный пик. Чтение /proc входит в стенд и
увеличивает его время. В синхронном варианте одна длинная frame sample, поэтому
его p95 не описывает распределение. Headless/Dummy не измеряет FPS, GPU, draw calls
или native responsiveness; physics paused как в настоящем planner.

## Фактический результат 16.10.2026

Одна последовательная пара на окончательном коде, без параллельного Godot;
filesystem cache прогрет. Синхронная ветка не использует новый async pass.

| Метрика | Прежний sync route | Поэтапный named LOAD |
|---|---:|---:|
| Полное время операции | 11,535 с | 27,264 с |
| Самый длинный process_frame interval | 11,810 с | 0,417 с |
| Mean / p95 интервала | одна sample, 11,810 с | 8,671 / 12,057 мс |
| Число интервалов | 1 | 3151 |
| Sampled allocator peak | 1049,618 МиБ | 1050,373 МиБ |
| Sampled RSS peak | 1234,988 МиБ | 1237,309 МиБ |

Allocator candidate: read951,526 → resources974,751 → prepare976,74 →
free1050,373 → objects711,238 → attachments965,015 → snapshot978,468 →
ready973,162 МиБ (точные phase значения — в JSON). Удержание старой композиции
до успешной подготовки даёт почти тот же пик. Полное время выше из-за отдачи
кадров; уменьшение длительности загрузки не заявляется. Пробный cap64 для обхода
attachments давал33,004с; cap256 с прежним мягким4мс сократил лишние уступки.
Самый длинный оставшийся интервал относится к чтению/началу resources, отдельные
паузы free/attachments118–289мс также остаются; hard frame guarantee нет.

Все10 целевых suites PASS:8 основных и2 blood/surface. После изменения только
cap64→256 повторно named_map_loading/planning_mode PASS (2/47с). Ни SCRIPT ERROR,
ERROR, ObjectDB/RID leak warnings в этих проверках нет. Full startup/restart:
5363 placed/3953 furniture, failures0, peak allocator975,709МиБ/RSS1246,430МиБ;
это отдельный сценарий, не результат named load. Editor import exit0 без ошибок;
project/spec/workflow/architecture/scene/resources/diff PASS, source-size439 файлов,
122 рекомендательных warnings, без изменения лимитов. DTO projection отдельно
сверена с исходным телом после замены только сигнатуры и источника обхода.
Native capture не выполнен: в этом окружении отсутствует Xvfb; Forward+/Windows/
Web не проверены. Видимый progress проверен структурно, пиксели не засчитаны.

## Ограничения

Пик удержания старой карты и prepared nodes сохраняется ради защиты от ошибки
factory. Освобождение старых узлов до массового add_child уменьшает перекрытие
ready-композиций, но не гарантирует меньший общий пик. Уменьшение RAM не заявлено.
Пакеты ограничены 16 объектами (обход attachment tree — 256 узлами)
или мягким бюджетом 4мс; отдельный instantiate/
_ready/free, JSON parse/validation и отдельный поиск mesh anchor могут
превысить бюджет. Ошибка preparation освобождает prepared nodes синхронно.
Это поэтапная загрузка, не гарантия кадра ≤4мс. Рендерерные/Windows/Web замеры и
ручная приёмка полной карты остаются отдельными; параметры игры не менялись.
