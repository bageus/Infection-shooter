# N01 — сохранность записей недоступных объектов

25.10.2026. База main `6d3ff006becf34b3cbf51c8e8ade4b73fff44a4d`. Прямое поручение владельца «приступай» после [аудита PR470](https://github.com/bageus/Infection-shooter/pull/470). T004, Phase 1 / P1_LOGIC; задача не закрывается.

## Исправление

Раньше loader сохранял только путь missing scene и создавал только доступные nodes. Следующий capture писал только live placed nodes, поэтому load-save-load терял недоступные записи. Теперь planning_objects хранит отдельный Array[Dictionary] unresolved_records текущего документа. _stage делает глубокую копию всей валидной исходной записи (включая ID, transform и optional/неизвестные поля), а _begin публикует её лишь при успешной замене. Prepare/discard, invalid data, отмена до commit и прежний отказ карты без единого loadable object не меняют текущий документ.

Capture включает глубокие копии unresolved records один раз в заголовок полного снимка перед player/live records. В async-ветке batch-снимки не добавляют их повторно; порядок полного sync/async DTO одинаков. Это важно для snapshot equality, signature и отсутствия ложного restore. Исходный порядок missing records между собой и дублирующиеся scene paths с разными object_id сохраняются; общий порядок objects относительно live records может измениться. Existing v1–v8 readers работают, version/структура records прежние.

Explicit Clear Placed, пустая карта и успешная загрузка другой карты очищают прежние записи. При возвращении доступности asset/migration следующая загрузка создаёт объект из его сохранённой записи; он перестаёт находиться в unresolved и не дублируется. Статусы Save Map/Layout и named load сообщают, что записи недоступных объектов сохранены. Публичные API, сцены, физические правила, DTO, module graph и owners не менялись; архитектурного исключения нет.

## Проверка

Новый CI suite `game/bootstrap/app/tests/run_unresolved_map_records_tests.gd` использует настоящие planning_objects, loader, capture, storage.save_named_map, общий active _capture_save Save Map/Layout и атомарный map_file. Catalog fixture моделирует временно недоступную migration и настоящее отсутствие файла; создание использует настоящие PackedScene fixtures. Замены в тесте ограничены geometry/UI уведомлениями и автоматической расстановкой wall fixtures, не проверяемыми алгоритмами.

- На исходных четырёх production scripts из main: 18 assertion failures, exit1.
- С исправлением: 0 failures, exit0, без SCRIPT ERROR/ERROR/ObjectDB/resource leaks.
- Смешанная карта: 35 видимых + 3 недоступных записи; вложенная конфигурация/ID/transform, два одинаковых scene path, изменение исходного input и возвращённого capture не меняют сохранённые записи.
- Настоящий Save Map на диск, .bak и три последовательных load-save-load; общий active save capture, async snapshot и переход prepare→clear_async→commit_async сохраняют 38 records без дубликатов. Сравнение после JSON использует такой же wire roundtrip (integer literals читаются float), допуски не расширены.
- Редактирование доступного предмета сохраняется рядом с unresolved; возврат authored layout после его перемещения также сохраняет unresolved.
- Подготовка/discard другой карты, invalid scale, all-unavailable rejection и cancelled prepare не меняют исходные данные.
- Возвращённый asset получает прежний ID/transform; другая карта, explicit clear и empty-map очищают старые unresolved.
- Существующие run_layout_loading_tests, run_named_map_loading_tests и run_map_file_tests: exit0 / 0 failures без ошибок движка.
- Финальный editor headless import/open: exit0, без ERROR/SCRIPT ERROR/leaks после получения preload/import dependencies.
- Новый suite зарегистрирован в .github/runtime_suites.txt. Project gates: PASS, 232 registrations (224 runtime + 8 special). CI coverage — 11 Python tests PASS; runtime runner — 3 PASS. Diff check PASS.

Engine: pinned Godot 4.7.2 `ed1daf0bf`. Воспроизведение нового suite не требует полной карты: минимальный проект с game через symlink также прошёл. Рабочая копия частичная; для старых loader suites получены их preload/import зависимости. Промежуточные попытки до получения зависимостей содержали missing-asset errors и не засчитываются как PASS. Полный main-scene/native/Windows/Web прогон и FPS не заявляются; их проверяет CI/дальнейшая приёмка. Персональная карта владельца не использовалась.

Decomposition review: planning_objects 513 и planning_storage 492 строки остаются текущими scene/persistence adapters; здесь только поле/очистка и сообщение статуса. Loader301 остаётся единым staged transaction. Capture106 строк; collect меньше hard100. Новая ответственность/абстракция, ADR для смены owner, pass-through helper или policy exception не нужны.

Следующий шаг: PR/полный CI N01, затем отдельное исправление N02 (полный transform authored restore). Уже потерянные до исправления записи нужно восстанавливать из .bak/исходной карты; этот инкремент предотвращает дальнейшую потерю.

Отдельные disk-based check_resource_paths/validate_scene_resources в частичной копии не прошли из-за невыгруженных blood_decals_45 и 95 внешних scene resources. Эти проверки не считаются PASS и не ослаблялись; ссылки/ассеты не изменялись данным PR. Финальные targeted suites не содержат таких ошибок.
