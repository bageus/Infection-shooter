---
task_version: 1
task_id: T002
status: IN_PROGRESS
phase: 1
owner: AI
updated: 2026-09-19
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
The office-floor composition was rebuilt for the newly oriented grouped object library. Old public asset-wrapper usage was removed from the active scene, including the former -90 degree model compensation. The floor footprint is doubled from 40 x 30 to 80 x 60. The perimeter uses window corners at all four corners, mostly window modules along the facade, a solid elevator/emergency-exit block on the south facade, scene-authored perimeter collision, and a regular interior column grid. Interior architecture now provides an elevator lobby, short connector, small hall, wide circulation, open areas and a small enclosed office using explicit inner/outer corner modules. Bootstrap now detects zero health and falling below the floor and shows a temporary restart/exit defeat menu.

## Validation
Repository static validation still needs to run in CI. Godot runtime/import validation remains unavailable in this environment and is especially important because the new source assets are .blend files.

## Risks
Godot must be able to import the new .blend sources in the developer environment. Exact authored mesh extents still require visual snapping review in Godot; collision is deliberately scene-authored and continuous even if a visual module has small origin offsets.

## Next exact action
Run repository gates, then open the rebuilt floor in Godot and visually verify model import orientation, corner seams, elevator facade alignment, player spawn and defeat menu.
