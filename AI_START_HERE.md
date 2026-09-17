# AI Start Here

This file is a universal entry point for AI tools that do not automatically load `AGENTS.md`.

## Mandatory startup

Read in this exact order:

1. `AGENTS.md`
2. `GAME_SPEC.md`
3. `docs/WORKING_AGREEMENT.md`
4. `PROJECT_STATE.md`
5. `ACTIVE_TASK.md`
6. `BACKLOG.md`
7. `docs/GLOSSARY.md`
8. `docs/ARCHITECTURE.md`
9. relevant `module.json` files and ADRs

Do not change code before determining the operating mode.

## Mode selection

- If `GAME_SPEC.md` is `DRAFT`: use **Discovery** mode. Read `docs/DISCOVERY_QUESTIONS.md`, ask the next small group of unanswered high-impact questions, and update the specification. Do not implement gameplay.
- If the specification is ready but `ACTIVE_TASK.md` is `EMPTY`: use **Planning** mode. Create a small task from the current phase and backlog.
- If the active task is `READY` or `IN_PROGRESS`: use **Implementation** mode and work only inside its scope.
- If implementation criteria are met: use **Review** mode before marking the task complete.
- If the active task is `BLOCKED`: explain the blocker and ask only for the decision needed to continue.

## First response after repository study

Briefly report:

- recognized game/specification status;
- current phase and milestone;
- active task or lack of one;
- detected blockers or contradictions;
- the next questions or proposed next action.

Never pretend missing information is known.
