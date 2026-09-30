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
- Mutation strictly above the critical boundary starts control loss immediately.
  First loss lasts five seconds; recovery immediately starts the seven-second
  second loss if still critical, then the third crossing ends the mission.
  DNA raising the threshold can allow recovery; equality is safe.
- Hybrids activate automatically after all three circles in each of the two
  adjacent passive parent branches are learned and mutation/stability gates pass.
  They cost no extra point and cannot be individually locked.
- Central trunk darkens from the first closed stability gate onward.
- HUD key buttons sit inside the left of each cell; selection fills their frame
  and reverses the number color. Antidote quantity is upper right in its cell.
  Weapon names/GL letters behind icons are hidden. The new atlas is tightly
  cropped; neighboring disconnected artwork is removed from each extracted copy.
- Renamed elevator door instances build their static Wall collider from actual
  mesh triangles, preserving the opening and blocking both visible side walls.
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
godot --headless --path . --script game/presentation/office_floor/tests/run_elevator_collision_tests.gd
python tools/validate_project.py
```

Tests cover zero-spare-point path feedback, predecessor/stability gates,
retired locked IDs, loss/recovery cast gating, autonomous motion/fire and held-input override,
unique late roots, in-bounds circles/locks, adjacent hybrids, exclusive DNA
collection/2-second physics respawn while standing, pause/resume, all four GLB
models, and the real six-image atlas/HUD launcher swap without stretching.
The blood suite fixes splatters-per-hit to one for its pre-existing budget and
throttle assertions; production defaults to three.

## Previous verification status and exact limits

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
3. Cross the threshold: loss starts in the same update. Keep mutation critical:
   after five seconds second loss starts immediately; seven seconds later the
   mission ends. Collect DNA during loss to verify safe recovery when its raised
   threshold catches mutation. Full hybrid parent paths activate their hybrid.
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

Current follow-up verification is pending; prior runtime results above describe the preceding commit, not this follow-up. Check renamed neighboring elevators from both sides, their wall seams and open doorway after syncing.
