# P2: ограничение пиков исполнения и аудит экспорта

Запрос владельца: реализовать четыре пункта P2 со скриншота и сразу создать PR.
База: `6e902feba4849cd230b632517ffca5308a050173`, T002, Phase 1.

## Реализация

| Пункт | Изменение | Ограничение |
|---|---|---|
| Подсветка за стенами | Приватная structural mask, один ray на точку, round robin | ≤8 subjects / ≤24 rays за physics tick |
| Загрузка | Очередь двух payload requests, main-thread Script preparation, discovery model_path | 128 МиБ мягкого allocator headroom; headless=1 |
| Обломки | Effects-root-local FIFO, reuse body/shape/mesh/material/watchers для generic chunks | 40 active, 40 dormant; ≤80 active/fading generic allocations |
| Экспорт | Явные исключения трёх authoring folders и аудит настоящего PCK | all_resources сохраняется ради string paths |

Подсветка использует physics layer 9 только как временный query bit. Furniture,
акторы и pickup не маркируются; при teardown снимается только этот бит.
Скрытие/разрушение structural root не воскресит отключённую collision.
При длинной очереди подсветка обновляется реже 10 Гц: верхняя оценка прохода
`ceil(subjects/8)` physics ticks, с прежними distance/viewport фильтрами.

Пул относится только к стандартным маленьким box chunks. Authored GLB fragments
сохраняют свои mesh/material/shape и освобождаются после fade. В начале fade
отключаются hit/world collisions, rigid physics, kick и impact-sound callbacks.
Дремлющие pooled nodes хранятся вне дерева и освобождаются при teardown root.
Счётчики и очереди не глобальны. Старые FIFO entries имеют отдельную WeakRef
identity: reused Node ID не удаляет новый фрагмент по старому entry.

Timings показывают ожидание payload jobs (сумма request→completion, включая
overlap), instantiate и main-thread add_child/_ready. Это не чистое время диска.
Allocator headroom — мягкая граница очереди, не полный RSS/VRAM лимит.
В Godot 4.7.2 Dummy renderer воспроизведены ошибочные mesh RID при двух
параллельных payloads; поэтому headless ограничен одним. Actual renderers
сохраняют concurrency=2, проверка добавлена в Compatibility/Forward+ CI.

## Экспорт

Authoring sources в трёх папках занимают около 68 МиБ, но уже имеют `.gdignore`.
Фактический baseline PCK не содержит этих ресурсов. Поэтому этот PR добавляет
защиту и проверки, без заявления о дополнительной экономии 68 МиБ.

`audit_export_pack.gd` использует собственный reader Godot, включая PCK v4,
и составляет inventory. `check_export_pack.py` проверяет явные exclusions,
отсутствие production ссылок на них, наличие конкретных string-path refs
и, при переданном baseline, отсутствие потерянных runtime files.

Локально Windows/Web PCK: 2500 файлов, 544 concrete runtime references,
0 runtime files lost относительно baseline. Packed mission smoke 180 кадров
для обоих preset проходит. Это проверка содержимого PCK движком native;
браузерный Web runtime и Windows GPU FPS требуют отдельной ручной проверки.

## Проверки и исходные ошибки

- Godot 4.7.2 clean import: без SCRIPT ERROR/ERROR.
- Новые mask/round-robin/queue и fragment-pool suites: PASS.
- Existing debris, occlusion, layout loading suites: PASS.
- Full map startup/restart: 1998 объектов, 1444 furniture проверены, 0 failures;
  после headless fallback нет RID ошибок. Peak allocator ~830.5 МиБ,
  RSS ~989.1 МиБ; это не GPU память и не обещание FPS.
- Project gates, import (849), scene refs (349), resource paths: PASS.
- Model textures: 292 GLB / 223 textured / 0 errors; dedup unchanged.
- Python architecture scene-access: 3 tests PASS.
- Полный headless набор: 74/77 PASS после повторного startup suite с Dummy
  fallback; три исходных failures ниже. Новые error-drain/recovery/dedup проверки
  очереди также PASS.
- Native Compatibility queue/mask PASS (concurrency=2); полный startup
  1998 объектов / 1444 furniture / 133 resources PASS без RID ошибок.
  Native Forward+ queue/mask/error-drain/recovery PASS на Vulkan 1.4.318
  llvmpipe (без fallback). Native Compatibility full-map startup/restart
  подтвердили 1998 объектов / 1444 furniture дважды, resources=133 и
  concurrency=2 без SCRIPT ERROR/ERROR. Startup 47.5 с, restart 90.1 с:
  оставшиеся 180 rendered frames превысили общий timeout 180 с на llvmpipe.
  Полный native memory suite поэтому не объявляется PASS; отдельный headless
  startup/restart suite PASS. Software-renderer время не является FPS замером
  Windows GPU.
- GitHub Architecture CI первой ревизии PR #89 PASS.

В исходном main воспроизведены:

1. `run_planner_extension_tests`: airborne corpse floor assertion.
2. `run_surface_pose_tests`: authored lamp count.
3. `run_gameplay_planner_repairs_tests`: blood mark without projected visual
   (первый baseline запуск PASS, повторный FAIL — нестабильность сохранена).

Assertions/таймауты не ослаблены. Эти старые проблемы не относятся к P2.
Для восстановления обязательного architecture gate удалены четыре redundant
назначения private infected Script в base_office_layout: наследуемая публичная
сцена уже назначает тот же Script, gameplay behavior прежний.

Public methods, map DTO, state owners и dependencies прежние. Архитектурных
исключений нет. Loader и queue остаются небольшими файлами одной обязанности;
их coroutine/_place выше мягкого порога 50 строк, но ниже hard limit 100.
Дополнительные pass-through helper ради длины не вводятся.

Следующее действие: CI PR и ручная приёмка Windows/Web с большим числом врагов,
серией разрушений и замером FPS/памяти на целевом устройстве.
