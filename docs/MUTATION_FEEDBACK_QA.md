# Mutation, pickup art and blood feedback — 2026-09-30

## Behavior

- Paths fill through the furthest sequential reached circle, independently of
  whether another point is unspent. Purchase still requires points, mutation,
  stability and predecessors. `skill_requirements` is additive DTO v2.
- Closed stability gates darken branches; open gates stay gray until reached.
  Filled paths/glow use the HUD's lime `(0.3, 0.95, 0.1)`. The tree fits a
  1200×800 design, anchors left and scales to content without scroll.
- Each late passive has its own root. Locks sit to the right of circles.
  Five hybrid circles link adjacent passive branches, not the first/last.
  Retired Organic Ammo is removed from both learned and locked old state.
- Critical mutation retains its existing **10 seconds of instability** before
  control loss. Manual movement, aim, roll, reload, switching and casting are then
  blocked; the hero moves and fires autonomously, retaining gravity/collisions. Stage-one recovery takes five seconds,
  stage two seven; the existing third-stage defeat is connected to main.
  Opening the mutation menu still pauses all simulation/timers by design.
- DNA at `(-17.5, 0.5, -15)` near the launcher grants +5 stability through
  `add_control_ampule`, up to the existing 95 cap. It respawns after two seconds
  of unpaused game time. Only the injected player can collect it. A single
  node-owned Timer/visual is reused without SceneTree service searches.
- World pickups use pistol/uzi/shotgun/launcher GLBs; weapon index 1 is UZI,
  matching player slots. No generic boxes substitute those models.
- PNG blood marks are larger and near full opacity; three splatters per
  accepted hit. The 0.12-second throttle, 128 total marks, Mobile density cap,
  non-emission materials and oldest-first cleanup remain.
- HUD extracts six explicit artwork regions once, excludes broad atlas padding,
  preserves aspect and reuses textures. Main icon/name rectangles no longer
  overlap. The atlas's stable semantic indices are pistol=1, uzi=2,
  shotgun=3, syringe=4, launcher=5; `weapon_icon_cells` is author-configurable.

## Runtime suites

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script game/features/infection/tests/run_tests.gd
godot --headless --path . --script game/bootstrap/app/tests/run_mutation_feedback_tests.gd
godot --headless --path . --script game/features/player/tests/run_control_loss_tests.gd
godot --headless --path . --script game/presentation/prototype_hud/tests/run_weapon_icon_tests.gd
godot --headless --path . --script game/presentation/office_floor/tests/run_blood_effects_tests.gd
python tools/validate_project.py
```

Tests cover zero-spare-point path feedback, predecessor/stability gates,
retired locked IDs, loss/recovery cast gating, autonomous motion/fire and held-input override,
unique late roots, in-bounds circles/locks, adjacent hybrids, exclusive DNA
collection/2-second physics respawn while standing, pause/resume, all four GLB
models, and the real six-image atlas/HUD launcher swap without stretching.
The blood suite fixes splatters-per-hit to one for its pre-existing budget and
throttle assertions; production defaults to three.

## Verification status and exact limits

Повторная проверка полного checkout 30.09.2026: Godot 4.5.2 успешно выполнил
все пять runtime suites выше. Основная сцена отработала 180 кадров без игровых
ошибок. Проверки готовности, рабочего состояния, архитектуры и diff-check прошли.
Общий validator по-прежнему блокируется прежним planning_mode.gd (1629 строк).
Headless editor import завершился кодом 0, но две старые FBX-модели сообщили об
отсутствующих palette1.png и couches.png. Визуальная приёмка в целевой 4.7.2 остаётся.

Настоящий бинарный атлас доступен и просмотрен: launcher расположен вверху,
пять остальных иконок внизу имеют соединённые светлые ореолы. Поиск connected
components заменён явными границами рисунков. Файл PNG сохранён без изменений;
семантический порядок rifle/pistol/uzi/shotgun/syringe/launcher фиксирован. Тест
подтверждает шесть отдельных текстур, их aspect и реальную смену pistol →
launcher → pistol в основном HUD и слоте. ДНК проверена настоящим physics-overlap,
включая повторный подбор без выхода из области и остановку таймера паузой.

## Visual acceptance on installed Godot 4.7.2

1. Reach mutation 40 with stability 30, then raise stability to 45 with three
   DNA pickups. Closed branches darken; open branches gray; reachable first
   circles fill regardless of a spent point. Verify next circles still require
   predecessors. Check locked reactivation does not spuriously reopen menu.
2. Inspect a small and large window: ten distinct roots/circles fit, passive
   order stays intact, five hybrids lie between adjacent parents, `+` does not
   cover outgoing lines, and no divisions remain on the trunk.
3. Close the menu, stay critical for ten seconds, hold movement/fire/roll.
   Confirm loss notice, autonomous motion/fire, five-second recovery and repeat
   escalation. Antidote rules remain unchanged; third loss ends the mission.
4. Collect DNA repeatedly and stand within its area during respawn. Confirm one
   grant per two seconds, stability cap 95, and no duplicate nodes. Pause while
   hidden; the timer must resume with gameplay.
5. Exchange each weapon with the launcher. Check all four world models, slot
   identity, cropped main/slot icons, aspect and the **actual launcher cell**.
   The actual upper-row launcher crop is covered by the automated HUD swap test.
6. Shoot enemies near a wall/on floor, kill them and exceed mark budget. Check
   abundant larger blood, no emission, bounded density/fading and performance.

API references checked for image extraction and Timer lifecycle:
https://docs.godotengine.org/en/stable/classes/class_image.html
https://docs.godotengine.org/en/stable/classes/class_timer.html
These documentation checks do not establish a 4.7.2 runtime pass.
