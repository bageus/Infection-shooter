---
task_version: 1
task_id: T001
status: READY
phase: 1
owner: AI
updated: 2026-09-17
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

READY; implementation not started.

## Decisions

Explicit domain state transitions; no scene-driven timers; no scope extension.

## Validation evidence

Not run.

## Blockers

None.

## Next exact action

Run readiness gates, then inspect architecture before creating feature files.

## Session handoff

This is the only active task. Work in main under the accepted agreement and stop for protected decisions.
