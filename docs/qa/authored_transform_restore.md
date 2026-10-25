# N02 — восстановление полного authored transform

25.10.2026. База main `6f76146c244a99f6ae273b765376e72db03191d7`, включает N01/PR471 и аудит PR470. Запрос владельца: следующий этап. T004 / Phase 1 / P1_LOGIC, Implementation.

## Проблема и исправление

planning_storage.restore_authored сравнивал scene/позицию/yaw, не учитывая наклоны X/Z и размер. Опрокинутый предмет на прежнем месте мог считаться неизменившимся. _put_back возвращал координаты/углы, но не scale: даже обнаруженный изменённый предмет мог остаться другого размера.

Fingerprint теперь учитывает три угла и три компонента масштаба. Существующая квантизация позиции0.05м и yaw2° сохранена; те же2° применяются к X/Z, scale квантуется до0.0001, чтобы числовой шум не вызывал лишнюю перестройку. Это частный runtime fingerprint, не persisted checksum cache биомассы. Reused node получает исходный scale (default1 по каждой оси старой карты), вместе с прежними позицией/углами; linear/angular velocity reused RigidBody по-прежнему обнуляются. Уцелевшие nodes переиспользуются по прежним правилам, игрок и его spawn не перемещаются командой восстановления.

## Совместимость с N01

При восстановлении authored layout все живые узлы могут оказаться в keep_on_clear, а в staged records остаться только недоступные модели. Прежний loader отвергал такой внутренний plan как полностью незагружаемый, поэтому лишние runtime nodes не удалялись. Теперь отсутствие новых loadable entries допустимо при непустом внутреннем keep_on_clear — уже существующая валидная композиция сохраняется, её unresolved records восстанавливаются и лишние узлы очищаются. Explicit load полностью недоступной карты с обычным пустым keep_on_clear по-прежнему отклоняется без изменения текущей карты. Внешние validation checks не ослаблялись.

DTO v1–v8, публичные API, сцены, dependency graph, владельцы, баланс и настройки не меняются. Архитектурного исключения или нового ADR для смены owner не требуется. Decomposition review: storage495 и loader302 строки — прежние persistence/transaction orchestration; изменения добавляют недостающие TRS-компоненты и совместимость сохранённых nodes, без новых обязанностей/глобальных кэшей/pass-through helpers. Лимиты600/100 соблюдены.

## Регрессии

Новый `game/bootstrap/app/tests/run_authored_transform_restore_tests.gd` выполняет настоящий loader→snapshot_authored→restore_authored→capture. Fixture подменяет только catalog создания простого Node3D/frozen RigidBody и несущественные UI/geometry callbacks. Алгоритмы capture, storage, keep/clear и loader используются production.

- На исходных storage/loader из main: **18 assertion failures, exit1**, без script errors.
- Исправленная версия: **0 failures, exit0**, без engine errors/утечек.
- Отдельные X/Y/Z повороты и X/Y/Z масштабы; combined tilt и nonuniform scale; JSON roundtrip snapshot; subsequent save получает исходный размер.
- Уцелевший node и сосед сохраняют identity/transform, create count не растёт; повторное восстановление — no-op.
- Nearby displaced rigid prop переиспользуется, возвращает TRS и нулевые скорости.
- Legacy v1 записи без углов/scale используют0°/1.0.
- Малая поза/scale погрешность внутри выбранных ячеек квантизации не запускает восстановление.
- Смешанная карта сохраняет полную unavailable record, удаляет лишний runtime-only node; explicit all-unavailable load остаётся non-destructive.

## Проверки

Pinned Godot 4.7.2 `ed1daf0bf`, headless:

- authored_transform_restore — PASS.
- unresolved_map_records (N01), layout_loading, named_map_loading, map_file — все PASS.
- Final error/leak scan пяти suites: нет ERROR/SCRIPT ERROR, leaked at exit или resources still in use.
- `--headless --path . --editor --quit`: exit0, error/leak scan PASS.
- `python tools/validate_project.py`: PASS, 233 registered suites (225 runtime +8 special).
- CI suite coverage —11 Python tests PASS; runtime runner —3 PASS.
- `git diff --check`: PASS.

Копия с выбранными assets/import dependencies из предыдущего этапа; полный main-scene suite, native GPU/Windows/Web/FPS не проверялись локально и не объявляются PASS. Пользовательская карта не использовалась. Full GitHub CI нового commit проверяется после публикации. N01 уже merged; его runtime CI на момент начала этапа ещё выполнялся.

Следующий шаг: отдельный N02 PR/полный CI; затем N03 — энергия многоточечных ламп в запекателе. T004 остаётся IN_PROGRESS.
