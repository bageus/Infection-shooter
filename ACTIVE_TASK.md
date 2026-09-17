---
task_version: 1
task_id: NONE
status: EMPTY
phase: 0
owner: bageus
updated: 2026-09-17
---

# Active Task

There is no implementation task while the game specification is in `DRAFT`.

## Goal

Complete discovery and turn the concept into an approved specification.

## Why this matters

Implementation without an approved concept creates rework and uncontrolled scope.

## In scope

- Asking focused discovery questions.
- Recording confirmed answers.
- Identifying contradictions, assumptions, and blockers.
- Proposing options when the user is unsure.

## Out of scope

- Gameplay implementation.
- Production asset creation.
- New Godot plugins or external dependencies.
- Architecture exceptions.

## Dependencies

- `GAME_SPEC.md`
- `docs/DISCOVERY_QUESTIONS.md`
- `docs/WORKING_AGREEMENT.md`

## Affected modules

None.

## Expected files

- `GAME_SPEC.md`
- `docs/WORKING_AGREEMENT.md`
- `PROJECT_STATE.md`

## Acceptance criteria

- [ ] Required discovery sections are answered.
- [ ] Blocking questions are resolved or explicitly removed from MVP.
- [x] Working agreement is accepted.
- [ ] User approves the resulting concept and scope.
- [ ] `python tools/validate_game_spec.py --ready` passes.

## Plan

1. Establish working preferences.
2. Interview by priority.
3. Summarize and confirm each topic.
4. Resolve contradictions.
5. Define MVP and non-goals.
6. Run readiness validation.

## Progress

- Workflow prepared.
- Discovery Group 0 completed.
- Working agreement accepted.
- Core game identity and player promise recorded from Discovery Group 1.
- Remaining Group 1 details require clarification.

## Decisions made during this task

- AI autonomy: independent execution within an approved plan.
- Git workflow: direct commits to `main` until playable MVP, then branches and pull requests.
- Architecture, dependency, scope, format, destructive, publishing, release, and merge changes require confirmation.
- Completion reports should be concise.
- Conversation and documentation use Russian; code identifiers, code comments, and commits use English.
- The player is a special-forces operative descending through an infected skyscraper.
- Each floor is a level with combat, infection sources, destructible interiors, interactions, bosses, and multiple exit strategies.
- Infection grants mutation abilities but can cause loss of control; antidote reverses both infection and mutations.
- The game is single-player, uses 3D levels, and takes visual direction from a more colorful Alien Shooter 2.

## Validation evidence

- Not run; this update records discovery decisions only.

## Blockers

- Camera behavior, control scheme, run/checkpoint structure, mutation selection, and exact loss-of-control behavior require owner answers.

## Next exact action

Ask focused follow-up questions to complete Discovery Group 1.

## Session handoff

Group 0 is complete and the core Group 1 concept is recorded in `GAME_SPEC.md`. No validation was run. Continue with focused Group 1 questions.
