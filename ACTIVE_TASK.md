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
- Camera, controls, browser-first platform, audience, localization, monetization intent, campaign length, checkpoint landings, mutation branches, control ampoules, antidote behavior, and the three-stage loss-of-control cycle are recorded.

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
- The camera rotates and follows the player; controls are WASD and mouse with no gamepad support.
- The campaign contains 20 floors, three tutorial levels, and checkpoints at floors 15, 10, and 5.
- Killed infected leave temporary mutagen clouds that feed a branching mutation meter.
- Loss of control escalates from 5 seconds to 7 seconds to defeat, with resettable 30-second risk windows.
- Browser release targets itch.io and Yandex Games, with a standalone launcher as an approved fallback requiring a later decision.
- Mutation branches cover passive utility, vitality/healing, and ammunition damage; control grows via one ampoule per level.
- Save buttons are placed on stairwell landings before floors 15, 10, and 5.
- Target audience is male teens and adults at 16+; English is primary and Russian secondary.
- The game is free with ads, paid packs, and paid ad removal; one developer has 48 hours for a full-mechanics vertical prototype.
- Ads and real payments are deferred until the core mechanics are complete.
- Stairwell shops offer weapons, antidote, upgrades, and health ampoules.
- Before the first checkpoint, death returns the player to the roof.
- Emergency antidote resets the risk window after either the first or second loss-of-control episode.

## Validation evidence

- Not run; this update records discovery decisions only.

## Blockers

- Ad gating, pack pricing/currency, exact Godot version, technical budgets, and shop balance require owner answers.

## Next exact action

Complete the remaining economy and core-flow questions, then prepare the 48-hour prototype task sequence.

## Session handoff

The 48-hour vertical prototype, stairwell shop, deferred monetization, roof respawn, and emergency-antidote rules are recorded in `GAME_SPEC.md`. No validation was run. Continue discovery.
