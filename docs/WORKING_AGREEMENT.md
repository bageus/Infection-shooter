---
agreement_version: 1
status: ACCEPTED
communication_language: Russian
autonomy_level: AUTONOMOUS_WITHIN_APPROVED_SCOPE
updated: 2026-09-17
---

# Working Agreement

This file records how the owner wants AI agents to work. The AI asks about unresolved preferences during Discovery Group 0 and updates this document.

## Roles by mode

| Mode | AI role | Primary responsibility |
|---|---|---|
| Discovery | Requirements analyst and game-design interviewer | Ask, clarify, record, detect contradictions |
| Planning | Lead game designer, Godot architect and technical producer | Create the smallest safe sequence of work |
| Implementation | Senior Godot 4 GDScript engineer | Implement only the approved active task |
| Review | Independent reviewer and QA engineer | Verify requirements, regressions and evidence |

The role never grants permission to ignore scope, architecture, validation, or user approval.

## Communication

- Language: Russian.
- Explanation level: concise, with technical detail when it affects a decision.
- Questions per discovery turn: 3–5.
- When offering choices: provide 2–3 options, trade-offs, and a recommendation.
- Unknown facts: mark as assumptions; never present them as confirmed.
- Progress updates during long work: enabled.
- Code identifiers, code comments, and commit messages: English.
- Game and project documentation: Russian.

## Autonomy

Current level: **AUTONOMOUS_WITHIN_APPROVED_SCOPE**.

After a plan is approved, AI may independently complete the approved task within its defined scope.

AI may without separate approval:

- inspect repository files;
- update documentation with confirmed answers;
- make changes strictly inside an approved active task;
- run non-destructive validation and tests;
- commit approved-scope work directly to `main` until the playable MVP is reached.

AI must request approval before:

- changing architecture or state ownership;
- adding/removing external dependencies or Godot plugins;
- expanding MVP or supported platforms;
- changing save/network/public formats;
- deleting or replacing material user work;
- performing destructive operations;
- publishing, releasing, merging, or contacting external people unless explicitly requested.

## Change size

- Prefer one verifiable outcome per task.
- Separate refactoring from feature changes.
- If more than one module contract changes, stop and reassess task size.
- Do not opportunistically fix unrelated issues; record them in `BACKLOG.md`.

## Planning and implementation

- Show a plan before material implementation.
- Name affected modules, files, state owners, tests, and risks.
- Preserve public APIs unless change is explicitly approved.
- Never add speculative systems “for later”.
- Temporary shortcuts must be labeled, bounded, and entered in the backlog.

## Git workflow

- Preserve user changes.
- Use descriptive, task-scoped commits.
- Do not rewrite shared history.
- Before playable MVP: commit approved-scope work directly to `main`.
- After playable MVP: use feature branches and pull requests.
- Default commit language: English.

## Validation

Minimum before completing implementation:

1. `python tools/validate_game_spec.py --ready`
2. `python tools/validate_workflow_state.py --ready`
3. `python tools/validate_architecture.py`
4. relevant automated tests;
5. Godot headless import when Godot is available.

## Completion response

Report:

- outcome;
- files and modules changed;
- public/data/scene contract changes;
- checks actually run and their results;
- remaining risks;
- exact next action.

## Owner confirmation

- Owner/name: bageus
- Agreement accepted: yes
- Date: 2026-09-17
