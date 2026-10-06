# BloodEffects3D v1 — configuration and verification

## Integration

`bootstrap.app/main.gd` composes the public scene
`presentation/office_floor/public/blood_effects_3d.tscn` and connects the public
infected-scene events. Damage, AI, loot, mutation and death cleanup retain their
existing owners. No save format changes and no renderer changes.

The five methods `splatter_hit`, `small_stain`, `drops_trail`, `smear_drag` and
`death_pool` enqueue value-only requests for the physics phase. `clear_marks`
clears pending requests, pools and active marks. `diagnostics()` returns a copy
of contract version, actual engine version, renderer and ClassDB API check;
`statistics()` reports marks, pending work and pending pools.

The 44 marks are five atlases in `models/objects/textures/blood_decals_45`
(3×3 per category, pool 4×2; frames numbered row by row). The cache loads once,
slices evenly sized cells, preserves RGBA, crops transparent padding (ignoring
faint alpha noise below 6/255 after box averaging) and retains the visible
rectangle's aspect. Copies are limited to 512 pixels with mipmaps;
source PNGs are untouched. Empty/missing assets warn and produce no mark.

Defaults: 128 marks, 90-second lifetime, 1.2-second fade; 0.08m projection
depth; 24–36m distance fade; hit interval 0.12s; wounded movement spacing
0.4–0.8m; pool delay 0.3–0.8s and growth 1–3s. See the public scene's exported
properties for category sizes and tuning. Decal alpha fades without emission.
Compatibility uses opaque-facing transparent quads with no billboard, shadow
or collision. Its 0.018m offset clears the existing floor tile's visual top.

Physics layer 8 and render layer 8 are independently assigned to injected
environment roots and future children. Existing bits remain intact. Actor and
effect subtrees are skipped. New actors are wired by the enemy container.
Marks retain local position/rotation through a RemoteTransform3D anchor.

## Engine API references

- https://docs.godotengine.org/en/stable/classes/class_decal.html
- https://docs.godotengine.org/en/stable/classes/class_remotetransform3d.html
- https://docs.godotengine.org/en/stable/classes/class_physicsrayqueryparameters3d.html
- https://docs.godotengine.org/en/stable/classes/class_renderingserver.html

These are documentation checks, not evidence of a successful Godot 4.7.2 run.
`diagnostics().api_valid` checks the actual engine's required properties/methods
on startup. Forward+/Mobile use Decal; `gl_compatibility` uses QuadMesh.

## Automated checks

Run with the owner's installed Godot executable:

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script game/presentation/office_floor/tests/run_blood_effects_tests.gd
godot --headless --path . --script game/features/infected/tests/run_blood_events_tests.gd
godot --headless --path . --script game/features/pickups/tests/run_pickup_floor_tests.gd
python tools/validate_project.py
```

The surface/effect suite uses synthetic transparent texture fixtures, so it
checks logic independently of asset appearance. It covers floor/wall/slope,
no-surface rejection, actor exclusions, orthonormal normal basis, repeated
texture avoidance, platform movement, delayed single pools after enemy
deletion, growing X/Z with constant depth, hit throttle, lifetime, strict
budget/local density, no emission and clearing. The infected suite covers
unchanged damage, first wound, distance-dependent drops, no stationary drops,
one death and actual dead-body displacement.

Execution in this workspace on 2026-09-30:

| Check | Result |
|---|---|
| gdtoolkit syntax parser for changed/new scripts | Passed |
| Specification/readiness/workflow and architecture | Passed |
| `git diff --check` | Passed |
| Aggregate project validator | Failed: existing `planning_mode.gd`, 1629 lines > 600; untouched |
| Available Godot 4.5.2 headless import | Exit 139 before output |
| Both Godot test suites | Exit 139 before output; not passed |
| Godot 4.7.2 API/runtime and visual check | Pending: no 4.7.2 executable available here |

## Visual and performance acceptance — pending

1. On the actual 4.7.2 renderer, shoot enemies beside a wall and in an open
   area. Verify transparent backgrounds, visible PNG shapes, no glow, no marks
   in midair and no projection onto the player/enemies or adjacent wall faces.
2. Place a receiver on a slope and move/rotate a platform. Confirm stable
   orientation without camera following and no relative slide.
3. Move a wounded enemy, stop it, then kill/remove it. Check distance-based
   drops and one delayed pool growing only horizontally.
4. Invoke `smear_drag` along a long actual movement path and observe several
   short directed smears. The existing enemy death hides its mesh; this change
   does not introduce a visible corpse or a new dragging interaction.
5. Create more than 128 marks. Check oldest marks fade, the count never exceeds
   the cap, surface deletion cleans anchors, and level restart clears all work.
6. On Mobile, create dense hits on one floor mesh and profile frame time.
   The manager keeps at most six active/fading marks per collider, below
   Mobile's eight-Decal-per-mesh budget. Other decal systems can consume slots;
   lower this setting when they overlap. Multiple colliders sharing one visual
   mesh need a correspondingly stricter setting or receiver partitioning.
   A large merged floor using one collider may remove distant marks early.
7. Profile texture memory and frame time at 128 marks on target hardware.
   No GPU timing or visual-performance pass is claimed by this commit.

## Dropped supplies follow-up

`drop_table` now requests `pickup_item.settle_on_floor()` after setting the
spawn position. One physics-phase ray finds the floor, excludes actors/areas,
and places the lowest visible mesh bound 0.018m above its collision surface
to clear the existing tile. This fixes model origins and removes the old
+0.18m hover offset without changing rewards or collection. No floor means
no floating drop. The pickup suite checks three different mesh origins and
missing floor; its engine execution remains blocked by exit 139.
