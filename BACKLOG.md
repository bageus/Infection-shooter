---
backlog_version: 1
status: ACTIVE
current_milestone: P1_LOGIC
updated: 2026-09-18
---

# Backlog

## Ready queue

| ID | Phase | Outcome | Status |
|---|---:|---|---|
| T004 | 1 | Blood sprays onto walls and objects beside a hit | ACTIVE / IN_PROGRESS |

## Planned

| ID | Phase | Outcome | Depends on |
|---|---:|---|---|
| T003 | 1 | Procedural floor, destruction, save, bilingual HUD, and Web build | T002 |

## Icebox


- CI_WORLD_BINDINGS_CLEANUP: existing main 26a819a run 37148645355 fails after world bindings assertions pass because one resource remains in use at exit (2 ObjectDB instances). Reproduced before menu integration; investigate the existing mission/debris cleanup separately. No test error is suppressed by the menu change.

Platform monetization and SDKs; full campaign content; cloud saves; window exits; gamepad; multiplayer; launcher; final rating and certification.

T001 implementation is retained with repository gates passed. Its Godot headless test execution is still pending; the owner explicitly instructed work to continue with T002 before that runtime check.

## Completed

| ID | Outcome | Completed |
|---|---|---|
| SETUP-001 | Workflow, architecture guardrails, and validators | Before 2026-09-17 |
| DISC-001 | Owner-approved discovery specification | 2026-09-17 |

- PLANNER_BASELINE_8A8E527: при проверке Lights исходный main воспроизводит run_planning_mode_tests: число сохранённых lamps > 1 и строгая dictionary equality после round-trip (разница rotation_y ~8e-6); run_planner_extension_tests: падение airborne part и четыре torso/barrel aim assertions. Те же ошибки до/после Lights; исправить отдельно, тесты не ослаблять.


## Threaded ResourceLoader: обход worker-side compilation (09.10.2026)

WORKAROUND_IMPLEMENTED: ранние Godot 4.7.2 threaded probes воспроизводили
RefCounted=0 при выходе и промежуточные stalls. scene_resource_preparation
компилирует зависимости Script на основном потоке и удерживает их, пока payloads
сцен/моделей читаются в фоне; финальные mission/menu suites прошли без этих
warnings и preload errors. Похожая upstream issue:
https://github.com/godotengine/godot/issues/120661; совпадение причины не доказано.
Проверить loading/restart и память с длинной серией переходов на native Windows/Web.
Движок/зависимости не менять в этом инкременте. Подробности
в docs/qa/map_loading_and_mission_startup.md.


## PR #191: Web instance uniforms и corpse capture (15.10.2026)

- BLOCKER T004/общие материалы: Godot4.7.2 Web теряет instance uniform values
  на129 объектах, pixel clean neighbor FAIL. Upstream112674/fix124336 (4.8).
  PR191 не объединять без повторного зелёного Web CI. Владелец выбирает
  engine update либо Web fallback; исключение Web-sharing не согласовано.
  Доказательства: docs/qa/audit_2026-10-14_enemy_skin_appendix.md.
- DEFERRED: Jolt ERROR на non-uniform scale corpse bullet hitboxes при death
  clip fallback. Native capture убирает hitboxes только в стенде; игровую
  причину исправлять отдельно с corpse/ragdoll collision regression.


## PR #198 follow-ups: белые серверы и монитор на столе (15.10.2026)

- BUG серверы: 03_server_rack*.glb при включённом свечении рендерятся полностью белыми.
  Воспроизведено headless xvfb (gl_compatibility): материал Group03Emission,
  emission_energy 2.5 при emission_texture (group03_emission.png, в среднем тёмный).
  Со свечением выключено стойка чёрная с деталями; при energy 0.3 серая. Причина
  в связке emission-текстуры и энергии, не в albedo. Не исправлено: нужен разбор
  группы 03 (tools/build_group03_atlas.py) или понижение emission для стоек.
  Скрин до: /tmp/claude-0/-home-claude-infection-shooter/e2eb0ce6-afbf-5459-b58c-fbcf7a112618/scratchpad/server_rack_before.png
- BUG монитор на столе: в headless-проверке монитор на замороженном столе
  08_office_desk_2 стоит на высоте столешницы, искры при попадании пистолетом
  появляются, после выстрела не проваливается. Не воспроизведено. Подозрение:
  динамический (незамороженный) стол падает сквозь пол в тестовом стенде, это
  может быть артефакт стенда (слой/маска пола), а не игры. Нужна проверка
  реальной карты и коллизии столов.


## D01 — совместимость перед дальнейшей очисткой (16.10.2026)

IMPLEMENTED / инкремент T004: D01_LEGACY_PROP_PATHS (16.10.2026).
Четыре identity mappings восстановлены; sync/async load-save-load regression
добавлен в CI, исходное описание проблемы ниже сохранено как история.
QA: docs/qa/legacy_cabinet_paths.md; следующая основная задача аудита D02. На main e4af46b
PlanningCatalog._migrate_scene_path возвращает пустой путь для публичных
03_drawer_cabinet/03_drawer_cabinet_mobile/03_file_cabinet_tall/03_locker_tall.tscn,
хотя PackedScene загружается. Loader._stage добавляет их в missing; смешанная карта
может загрузиться без этих объектов, карта только из них отклоняется как no loadable
objects. До удаления legacy scripts/scenes нужны явный alias/fallback без подмены
модели на похожую по имени и load-save-load regression с transforms/metadata.
14 props и4 старых pickup scenes сохранены; публичный fog_overlay также сохранён.
Инвентаризация/ограничения: docs/qa/cleanup_candidates.md и JSON рядом. Это не
новая активная задача и не разрешение менять public API; T004 остаётся единственной.


- PLANNER_FULL_MAP_ROUNDTRIP_FB6C79A (25.10.2026): run_planning_mode_tests
  на mainfb6c79a с5003records даёт Named map round trip preserves all object
  records FAIL. Воспроизведено с исходными planning_hud_layout/planning_fog
  и с HUD candidate; численность5003→5003, различия transforms/decor_pose.
  Расследовать сохранение/восстановление отдельно; UI/fog правки не меняют DTO
  или числовые допуски теста. Evidence: docs/qa/planner_hud_overlap.md.

- RESOLVED25.10.2026 — PLANNER_FULL_MAP_ROUNDTRIP_FB6C79A, PR465 CI repair.
  Все5003object records сохранялись; различалась только optional cache
  floor_biomass_v1. SHA256 native -0.0 отличалась от JSON0.0. Нормализация
  signed zero устраняет отказ cache; исходный planning_mode suite теперь
  PASS без изменения assertions/tolerances. Новая regression до2failures,
  после0; реальные правки координат по-прежнему инвалидируют cache.


## N01 — сохранность missing records (25.10.2026)

IMPLEMENTED / CI_PENDING в рамках T004 по прямому поручению владельца после [аудита PR470](https://github.com/bageus/Infection-shooter/pull/470). Deep-copy records сохраняются в существующем objects DTO при sync/async load-save-load; clear/replacement и восстановление модели проверены. QA: [unresolved_map_records](docs/qa/unresolved_map_records.md). Следующее действие — полный CI N01, затем N02 (полное восстановление authored transform); T004 остаётся единственной активной задачей.


## N02 — authored transform (25.10.2026)

IMPLEMENTED / CI_PENDING внутри T004: исходные наклоны/масштаб восстанавливаются, reuse и N01 сохранены; [QA](docs/qa/authored_transform_restore.md). Следующий этап после проверки N02 CI — N03, неверная энергия многоточечных ламп при bake. Новая параллельная активная задача не создаётся.
