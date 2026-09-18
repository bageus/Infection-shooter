---
task_version: 1
task_id: T001
status: IN_PROGRESS
phase: 1
owner: AI
updated: 2026-09-18
---

# Active task

## Goal

Implement and test an engine-light infection, mutation-ability, antidote, critical-threshold, and control-loss domain.

## Why this task now

It is the defining mechanic and highest early timing and rollback risk.

## In scope

- mutation 0–100 and a full cloud adding 10 over 2 seconds;
- first ability at 25, disabled below 15, with priority reactivation;
- critical threshold 30, plus 5 per control ampule, capped at 95;
- ordinary antidote reducing mutation by 10;
- antidote in either risk window resetting escalation without mutation reduction;
- 10-second instability; 5-second then 7-second control loss; third trigger defeats;
- surviving a 30-second risk window resets to stage one;
- deterministic tests for every listed rule.

## Out of scope

Scenes, input, movement, camera, combat, enemies, procedural generation, destruction, saves, UI, assets, audio, ads, payments, SDKs, and campaign content.

## Dependencies

READY game specification, accepted working agreement, architecture contract, and repository validators.

## Affected modules

A feature-local module under `game/features/infection` with its manifest, domain implementation, and tests. No root gameplay manager or global mutable state.

## State ownership

Mutation amount, ability selection and priority, critical threshold, instability and risk-window timers, escalation stage, and terminal control-loss state.

## Expected files

Feature-local manifest, domain scripts, and tests; documentation only when validators require it.

## Acceptance criteria

- numeric, timing, hysteresis, antidote, escalation, reset, and defeat rules have deterministic tests;
- no scene, rendering, input, monetization, payment, or SDK dependency;
- feature manifest declares state ownership and dependencies;
- repository validation and available headless tests pass.

## Plan

1. Inspect architecture and project layout.
2. Add the smallest feature-local domain API and manifest.
3. Add deterministic rule tests.
4. Run validators and headless tests.
5. Record evidence and complete T001 only when all criteria pass.

## Progress

Domain implementation, feature manifest, and deterministic headless test runner are implemented on 2026-09-18. The implementation remains engine-light and contains no scene, rendering, input, or infrastructure dependency.

## Decisions

Explicit domain state transitions; no scene-driven timers; no scope extension. The module does not expose a cross-module public contract yet; T001 is self-contained and its domain implementation remains internal until a consuming module requires an approved contract.

## Validation evidence

GitHub Actions run 35360785260 passed the full repository gate on commit `fab04e62fa559d9e64dfb0d4e4afeda9b2194dbb`, including specification, workflow, architecture, and source-size validation. Godot headless execution is still pending because Godot is not installed in the current execution environment.

## Blockers

No product blocker. Completion evidence still requires an available Godot headless test run.

## Next exact action

Run `godot --headless --path . --script game/features/infection/tests/run_tests.gd` in an environment with Godot 4.7.2.

## Session handoff

T001 implementation exists in `game/features/infection`. Do not start T002 until T001 validation evidence is complete.
