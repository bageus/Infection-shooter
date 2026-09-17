---
task_version: 1
task_id: NONE
status: EMPTY
phase: 0
owner: NONE
updated: {{YYYY-MM-DD}}
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
- [ ] Working agreement is accepted.
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
- Discovery not started.

## Decisions made during this task

- None.

## Validation evidence

- Not run for this active discovery task.

## Blockers

- User answers are required.

## Next exact action

Ask the first unanswered questions from Group 0 in `docs/DISCOVERY_QUESTIONS.md`.

## Session handoff

At the end of every session replace this section with:

- what was completed;
- exact point where work stopped;
- files changed;
- checks run and results;
- unresolved blocker;
- one exact next action.
