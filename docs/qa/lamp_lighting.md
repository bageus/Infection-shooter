# Lamp lighting (12.10.2026)

Owner request: lamps sometimes do not light; narrow and rectangular lamps shine from one point; no lamp above the elevator doors; fixtures cast shadows; the desk lamp gives no light; light passes through walls and columns.

## Causes and changes

- **Lamps that do not light.** Compatibility renders at most `max_renderable_lights` (default 32) lights per frame and `max_lights_per_object` (default 8) per mesh, and drops the rest without a message. `PlanningLighting` now keeps a light budget: every 0.15 s the lamps nearest to the camera focus are lit until 28 spot lights are used (`MAX_LIGHTS`); the rest stay off. Project limits are raised to 40 / 12.
- **Narrow and rectangular lamps.** A linear fixture now has two spot lights at ±0.4 m, a rectangle four at its corners; they share the authored energy (0.7 / n each) and follow the cone angle of the main `Light` node. Planner values (energy, color, angle, height) and saved layouts are unchanged.
- **Shadows from fixtures.** The housing and diffuser meshes no longer cast shadows (nothing lights a ceiling fixture from above).
- **Light through walls and columns.** The six lamps nearest to the camera (`MAX_SHADOW_LIGHTS`) cast spot shadows. The Shadows setting (PR #97) switches them off through `PlanningLighting.set_shadows_allowed`, next to the overhead light and display wall.
- **Elevator indicator.** `interactive_door.gd` only handled `StandardMaterial3D`, but the model uses `ORMMaterial3D`, so the lens never glowed. It now accepts any `BaseMaterial3D`, lights only the smallest (lens) surface, and adds an omni light in front of the housing while the doors are open.
- **Desk lamp.** `05_lamp.glb` props carry a warm omni light (range 2.8 m, no shadow).
- Omni lights of props use `budget_omni_light.gd` and join the same budget (group `budget_lights`).
- **Lamps in view past the budget (#236).** Lamps inside the camera view that the budget leaves dark get a flat additive floor pool (one `MultiMeshInstance3D`, no light node). Measured at the start camera: 238 lamps in view, light cost 603, against a budget of 28, so most in-view lamps still have no real light.

## Notes

- In Compatibility, once any light in the scene casts a shadow, overlapping lights add up brighter than with no shadow casters at all (checked with two overlapping spots: 0.79 vs 1.0). With the Shadows setting off, lamp pools look as before.
- Frames: `/mnt/project-files/lighting_review/*_before_after.png`, made with `tools/capture_lighting_review.gd`.
- Regression suite: `game/bootstrap/app/tests/run_lamp_lighting_tests.gd`.
