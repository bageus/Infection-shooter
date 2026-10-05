# ADR-0023: Two testable occlusion visualization modes

- Status: accepted
- Date: 2026-10-05
- Owners: bageus
- Related modules: bootstrap.app, presentation.office_floor, features.pickups

## Context

The owner requests in-game switching between hidden hero/enemy/item silhouettes and a localized hole through walls/columns around the hero. Main updates are authorized by the working agreement. This is visual presentation within T002, without changing combat, collision or authored materials.

## Decision

Bootstrap owns the mode, transient mesh copies and material overrides. An additive integer occlusion_mode in interface_v1 defaults to 0 (silhouettes), 1 selects the hole; invalid values clamp. No map DTO changes. Settings apply immediately while paused and persist through restart. Planner suspends effects without changing the preference.

Public structural roots gain occlusion_visual_v1 classification group camera_occluder; public health/ammo roots gain occlusion_items. Existing infected and weapon_pickups classifications remain. These identify injected composition descendants, never locate services. No new dependencies, singleton or architecture exception.

A single controller checks camera rays at 10 Hz, excluding actors/furniture; only structural blockers activate effects. Silhouette copies share live meshes, skins and skeletons, cast no shadows and compare reconstructed scene depth to color only hidden fragments. Colors: cyan hero, red enemies, amber items. Hole radius is 2 world metres projected around the hero; only front structural surfaces are cut. Its dithered edge has a faint cyan ring. Runtime PBR shader copies leave shared resources untouched and restore original overrides exactly on mode switch/planner/teardown. Floor and furniture never get hole materials. Shadow passes preserve wall geometry.

## Alternatives considered

- Hide whole walls: loses the local opening and causes large pops.
- Disable depth globally on actors: colors visible parts and draws through unrelated geometry.
- Modify imported models or shared materials: violates scope and contaminates later scenes.
- Renderer-specific compositor/stencil extension: unnecessary platform dependency.

## Migration plan

Absent interface_v1 field uses mode 0; maps remain unchanged. Existing scenes instantiate the public roots with their groups automatically. No user map rewrite.

## Rollback plan

Revert the commit to remove the effects/UI/classifications. Unrecognized config fields are ignored by the old preferences reader. Authored material resources and colliders are unchanged.

## Validation

Runtime tests exercise modes, blockers, dynamically added subjects, restoration, persistence and planner cycles. Rendered tests must exercise hidden versus visible fragments and the opening in actual Compatibility and Forward+; headless does not validate shader output. Windows/browser gameplay acceptance and frame budget in the fully furnished level remain manual.
