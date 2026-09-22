---
task_version: 1
task_id: T002
status: IN_PROGRESS
phase: 1
owner: AI
updated: 2026-09-23
---

# Active task

## Goal
Build the first playable combat-slice foundation with an authored office floor, player, combat, infected enemies, infection source, and observable fail states.

## In scope
- hand-authored office floor from the newly grouped 01-16 object library;
- closed non-destructible perimeter with window/wall corner modules;
- expanded 80 x 60 m floor plan with elevator lobby, short connector corridor, small hall, broad left/right circulation, open combat areas and a small enclosed office;
- player defeat on zero health or falling below the floor;
- temporary defeat menu with restart and exit.

## Dependencies
READY game specification, accepted working agreement, architecture contract, and existing T001/T002 implementation.

## Affected modules
presentation.office_floor and bootstrap.app. Player health remains owned by features.player.

## Progress
Structural asset audit completed. `docs/ASSET_STANDARD.md` now defines the 0.25 m placement grid, canonical root pivots, the existing 2.25 m facade module, and identifies the 13_* glass kit plus the legacy 2.8 m cubicle partition as requiring dimensional correction/visual verification. All canonical public structural scenes are now declared in the module manifest. Source GLB/Blend geometry has not been destructively rescaled before Godot AABB verification.

The office-floor composition was rebuilt for the newly oriented grouped object library. Old public asset-wrapper usage was removed from the active scene, including the former -90 degree model compensation. The floor footprint is doubled from 40 x 30 to 80 x 60. The perimeter uses window corners at all four corners, mostly window modules along the facade, a solid elevator/emergency-exit block on the south facade, scene-authored perimeter collision, and a regular interior column grid. Interior architecture now provides an elevator lobby, short connector, small hall, wide circulation, open areas and a small enclosed office using explicit inner/outer corner modules. Bootstrap now detects zero health and falling below the floor and shows a temporary restart/exit defeat menu.

## Validation
Repository static validation still needs to run in CI. Godot runtime/import validation remains unavailable in this environment and is especially important because the new source assets are .blend files.

## Risks
Godot must be able to import the new .blend sources in the developer environment. Exact authored mesh extents still require visual snapping review in Godot; collision is deliberately scene-authored and continuous even if a visual module has small origin offsets.

## Next exact action
Run repository gates, then measure imported structural mesh AABBs in Godot against `docs/ASSET_STANDARD.md`; correct the 13_* glass connection span to 4.0 m and any retained legacy cubicle partition to 3.0 m only after confirming source mesh bounds.

## Out of scope
Procedural generation, save/checkpoints, final HUD, monetization, platform SDKs and campaign-wide content remain outside this T002 increment.

## Acceptance criteria
- Structural modules visually touch edge-to-edge with no visible gaps and no overlap beyond a tiny seam tolerance.\n- Exterior corners face inward correctly.\n- Perimeter and authored interior walls block the player.\n- The expanded floor and defeat menu remain functional.

## Validation evidence
User runtime screenshots exposed perimeter spacing, corner orientation and missing interior collision defects in the previous increment. This increment corrects those defects; repository CI must validate the static project gates.

## Blockers
No product blocker. Exact imported .blend bounds still require visual confirmation in Godot.

## Session handoff
T002 remains the only active task. After CI, visually verify seams and collision in Godot before adding furniture/content.
