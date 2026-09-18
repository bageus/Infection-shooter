---
task_version: 1
task_id: T002
status: IN_PROGRESS
phase: 1
owner: AI
updated: 2026-09-18
---

# Active task

## Goal

Build the first playable combat-slice foundation: a hand-authored office floor, movable player, camera, then minimal weapons, infected enemy, and infection source.

## Why this task now

The owner explicitly requested moving to T002 on 2026-09-18 and supplied a visual reference for the office scene.

## In scope

- hand-authored office floor assembled from scenes under `models/objects`;
- closed perimeter using wall/window model scenes plus scene-authored collision;
- separate capsule player scene with WASD movement;
- isometric follow camera authored in the player scene;
- next increments: minimal weapon, infected enemy, infection source, and T001 integration required by T002.

## Out of scope

Procedural generation, save/checkpoints, final HUD, monetization, platform SDKs, campaign content, and runtime generation of environment objects from code.

## Dependencies

READY game specification, accepted working agreement, architecture contract, existing T001 implementation, and repository validators. T001 Godot headless execution remains deferred by explicit owner instruction to proceed.

## Affected modules

`features.player`, `presentation.office_floor`, and `bootstrap.app`. Existing `features.infection` is not modified in this first T002 increment.

## State ownership

The player module owns movement velocity. The office-floor presentation module owns no mutable gameplay state; it only authors scene composition.

## Expected files

Player module manifest, player scene and movement script, office-floor presentation manifest and public scene, bootstrap composition update, Input Map update, and continuity documentation.

## Acceptance criteria

- project starts into the office-floor scene;
- all environment props are instantiated as scenes, not spawned from code;
- walls/windows visibly surround the level and scene-authored collision prevents leaving the floor;
- the player is a capsule scene and moves with WASD;
- camera follows the player from an isometric angle;
- repository validators pass after each coherent increment;
- T002 remains open until minimal weapon, infected enemy, and source are also implemented and tested.

## Plan

1. Author the office floor and capsule player as scenes.
2. Wire bootstrap and WASD Input Map.
3. Validate architecture and scene references.
4. Add minimal weapon and aiming.
5. Add infected enemy and infection source.
6. Connect T001 infection behavior and perform playable review.

## Progress

Owner override accepted: T002 started before the pending Godot headless execution of T001. The scene/player increment passed repository validation. Red capsule enemies, elongated capsule weapon, aiming/fire, infection source, enemy-death mutagen cloud, and T001 infection integration are implemented. A prototype HUD is now added as a separate presentation scene so HP and mutation behavior are directly observable during play.

## Decisions

The visual reference is used for layout direction, not copied literally. Imported GLB files are treated as PackedScene content. Perimeter gameplay collision is authored directly in the level scene so imported models do not need runtime collision generation.

## Validation evidence

GitHub Actions runs 35362345864, 35369496353, and 35371501101 passed the scene/player, combat, and infection-integration repository gates. The current increment adds a scene-authored prototype HUD for HP, mutation, critical threshold, control state, and controls. Godot runtime/import testing is unavailable in the current environment.

## Blockers

No product blocker. Runtime visual scale and imported-model transforms require Godot review because the current environment cannot open the project.

## Next exact action

Verify repository gates for the prototype HUD increment, then perform a Godot playable review when runtime access is available.

## Session handoff

T002 is the only active task by explicit owner instruction. T001 implementation remains present, with its Godot headless execution still unverified.
