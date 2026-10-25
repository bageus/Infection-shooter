# CI: планировщик и полная карта (PR467/468)

25.10.2026, T004/Phase1. Источник: runtime467 run40189025599/job121155857814; общая база main6b6d4b1. Новые проверки декалей/теней прошли headless и Compatibility; ошибка не в их pixel thresholds.

## Причины и правки

- Четыре Controls fixture не реализовали обновлённый collaborator hud_layout, поэтому layout loading/named maps/legacy paths/settle завершались exit0, но с SCRIPT ERROR. Fixtures теперь используют настоящий planning_hud_layout; отсутствие визуального setup корректно обрабатывается его существующим update_selection. Production guard не добавляется.
- Object-settings fixture размещал desk lamp/crate/enemy/plate под новым правым HUD. Точки перенесены в видимую область; `_input` и все проверки selection/edit/persistence сохранены.
- Одиннадцать focused suites загружали4997посторонних объектов до создания своих предметов. Используется существующий defer_layout_loading; реальный main/planner/world bindings и все явные fixtures/assertions сохраняются. Full-map startup/restart/memory, planning save/reload, authored occlusion, extension и light-view интеграции остаются полными.
- Три одновременно загруженные карты удерживают примерно по1ГиБ и конкурируют за Jolt threads. Семь известных full-map suites сериализуются flock в существующем runner;120с для обычных suites,300с для full-map, вместо прежних120/180. Время ожидания mutex не включается в время выполнения/timeout. Общий job budget остаётся45мин; ускорение focused fixtures освобождает время для native captures. Нет бесконечного ожидания теста, подавления ошибок или удаления assertions.
- Девять frameless TV bank в авторской карте стояли наx=-10.12049 за передней поверхностью стеныx=-10.15. Луч из фронта действительно упирался в StaticBody стены. Только эти9TV перенесены наружу наx=-10.20 в JSON и baked tscn вместе с settled transform. Все65TV снова доступны выстрелу, исходная проверка не меняется. Остальная расстановка сохранена. После редактирования карты её derived biomass cache пересчитывается штатным baker.

- Только в PR468: run_glass_cup_break_tests всё ещё требовал физические копии стакана и обращался к уже удалённым MeshInstance. Он обновлён под прямое правило владельца «только декали»: actual at_shape hit удаляет visual/body, не создаёт RigidBody и оставляет настоящий floor bake. В PR467 этот тест не меняется, потому что новое правило разрушения там не реализовано.

## Проверки

До исправления local object-settings воспроизводит16failures, CI summary обрезал их до первых3. После исправления16целевых suites проходят, focused fixtures6–15сек вместо120с timeout. Runtime runner probe проверяет serialization/isolation, SCRIPT ERROR при exit0, process exit3 и timeout exit124; все3теста PASS. CI suite coverage unit11PASS. Все7full-map интеграций через настоящий shell runner PASS: startup108с, menu101, planning111, occlusion56, extension49, light-view62, TV37. Полный startup/restart/memory budget и сохранение4997объектов проверены. Всего25runtime suites PASS; editor import, resource paths, scene387refs PASS. Штатный baker пересчитал5PNGpages; floor_biomass suite проверяет актуальный signature и идентичные PNG/cells JSON/tscn, не сравнивая различающиеся после JSON float/int типы.

Production scripts, API/DTO/owners/dependencies не меняются; только tests/runner/workflow и9authored positions с derived cache. Новых архитектурных исключений нет. Rollback: revert CI repair. Hardware FPS/Windows/Web и визуальная приёмка не заявлены.

PR467 слит владельцем в main a0cd5f0 во время работы. Общий fix теперь доставляется через PR468 вместе с интеграцией main; последующее обновление закрытой ветки467 само по себе не меняет main. Конфликт ADR0058 разрешён сохранением обоих принятых уточнений.

После интеграции main:11combined suites PASS, project gate231suites(223runtime+8special), import/resource paths/scene387 и runner3+coverage11unit PASS. Проверены одновременно оба набора изменений: тени/декали из467 и новые разрушения из468.
