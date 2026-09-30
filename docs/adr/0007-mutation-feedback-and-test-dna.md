# ADR-0007: Mutation path feedback, control integration and test DNA

- Status: accepted
- Date: 2026-09-30
- Owners: bageus
- Related modules: features.infection, features.player, features.combat, bootstrap.app, presentation.prototype_hud, presentation.office_floor

## Context

The owner reported incomplete branch fills, indistinguishable stability gates,
shared late branch origins, missing control-loss behavior and incorrect pickup
art/atlas cropping. They requested a respawning DNA test pickup and removal of
the first-to-last passive hybrid.

## Decision

Infection retains mutation, stability, eligibility and all control-loss timers.
The read-only `skill_requirements` DTO is version 2 with additive `path_reached`:
mutation, stability and prerequisite requirements are met independently of
unspent points. Purchasing still needs a point. Bootstrap consumes this fact
for path fills; it does not derive game rules from drawing coordinates.

Player reads the existing `is_control_lost` query to block manual commands
and replace movement/aim/firing with autonomous mutation behavior. Its local
RefCounted movement phase changes direction every 0.65–1.1 seconds and resets
upon recovery. Rolling, weapon switching and manual reloading are blocked. Runtime rejects casts
during loss/defeat. Bootstrap handles the existing terminal defeat query. HUD
shows loss explicitly. The existing ten-second instability grace, five/seven
second losses, escalation, antidote rules and 95-point stability cap remain.

Bootstrap owns one injected test DNA pickup at (-17.5, 0.5, -15), near the test
launcher. It calls existing `add_control_ampule`, grants +5 stability and hides
for two seconds of game time. A node-owned one-shot Timer respawns the same
pickup; it stops with game pause and disappears with the level. No extra
progression state, enemy drops, reward probability or persistence DTO is added.

Organic Ammo (Metabolism + Arsenal) is removed from the catalog and parent map
at the owner's request. Five adjacent passive hybrids retain IDs and parents;
passive ordering and all other thresholds stay intact. Legacy effect methods
remain harmless for call compatibility; catalog checks disable the retired ID.

Combat exposes additive public `make_pickup_visual(index)` on launcher_visual
v1 to instantiate the four existing model paths. Existing launcher APIs stay
compatible. Bootstrap no longer requests generic non-launcher art. HUD reads
the updated atlas once, extracts six explicit artwork bounds, and reuses cropped
textures. The actual launcher is on the upper row; semantic index 5 selects
it while indices 0–4 preserve rifle/pistol/uzi/shotgun/syringe identity. The
PNG remains unchanged; explicit bounds avoid connected pale halos.

## Alternatives considered

- Advancing simulation while the mutation menu pauses was rejected: pause is
  explicitly requested by the owner.
- Repeating mutation rules in UI was rejected: it would desynchronize gates.
- A new XP/DNA progression system was rejected: the existing ampule command
  already owns the required +5 threshold progression.
- Rendering every weapon icon every frame was rejected: cached atlas artwork
  addresses visible-size loss directly.

## Migration and rollback

DTO v2 retains every v1 field; current consumers tolerate additive fields.
`reconcile` removes retired Organic Ammo on the next mutation change, including
stale lock flags, while all remaining IDs retain their meaning. Revert this
commit to restore v1 DTO/catalog/UI. No save/network schema migration or new
dependency direction is required.

## Validation and limitations

Use domain tests for point-independent path eligibility and cast gating; scene
tests for distinct roots, bounded UI positions, DNA ownership/respawn, cached
icon extraction, and actual player input blocking. Added functions belong to
their existing owners. The player movement file exceeds the 300-line review
threshold; this change adds only local control checks without unrelated moves.
Tree refresh is split by its existing layout lifecycle; no new state owner or
hard-limit exception is introduced.

Повторная проверка 30.09.2026: полный checkout содержит PNG и GLB. Атлас
просмотрен; шесть явных областей проверены настоящим HUD при замене оружия.
Godot 4.5.2 выполнил пять runtime suites без ошибок; основная сцена отработала
180 кадров. ДНК проверена physics-overlap, включая повторный подбор и паузу.
Импорт сообщает о двух старых отсутствующих FBX-текстурах; общий validator
блокируется прежним размером planning_mode.gd. Визуал целевой 4.7.2 ещё требует
приёмки. Повторная проверка не меняет API или архитектурные границы.

## Approval

Owner's direct 30.09.2026 request authorizes the tree layout, DNA test pickup,
control fix, retired wraparound hybrid, blood abundance and weapon art/atlas.
