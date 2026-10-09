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
| T002 | 1 | Minimal player, camera, weapons, infected enemy, and source | ACTIVE / IN_PROGRESS |

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
