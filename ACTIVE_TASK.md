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
- The project uses Godot 4.7.2.
- Ads are intended to be mandatory but must not block progress when unavailable; ad removal is paid.
- The stairwell shop uses real money for weapons, antidote, upgrades, and health ampoules.
- The player equips three of five weapon types, switches them with 1–3 in combat, and changes the loadout only on stairwell landings.
- Each weapon has separate ammo; ammo, health, and antidote drop from monsters or appear on levels.
- Weapons drop from bosses, appear on levels, or are sold in the shop.
- Advertising waits up to 10 seconds when unavailable, then progression continues without it.
- Pistol is accurate; Uzi and rifle spread; shotgun uses a triangular pellet spread; grenade launcher explodes on impact.
- Pickups are automatic, and found weapons remain in the current campaign collection.
- The first prototype enemy is faster than the player, permanently tracks the hero after line-of-sight detection, and deals 15 damage without causing infection.
- The player has 100 HP; a health ampoule restores 30 HP.
- Every killed infected creates a mutagen cloud.
- Grenade explosions damage the player and destroy eligible internal walls and partitions.
- Floors are procedurally assembled from authored modular maps/rooms.
- Early floors contain 5–10 infected; counts grow over the campaign.
- The first floor has no source and completes when all infected die; later floors include one or more stationary sources that spawn enemies.
- A floor seed is generated on first entry and reused after death.
- Provisional active-enemy limits are 10 for the prototype and 100 for the hardest full-game floors.
- The prototype uses a representative post-tutorial floor with one 500-HP source that spawns every 8 seconds.
- Any weapon damages the source; after it dies, the player must kill all remaining infected.
- Mutation uses a 0–100 scale; a full cloud gives +10 over 2 seconds.
- The first ability unlocks at 25 and disables only below 15.
- Critical control starts at 30; each control ampoule adds 5 up to 95.
- A normal antidote removes 10; staying above the critical line fills a 10-second instability timer.
- At 25, the player chooses reload -15%, movement +10%, or all-weapon damage +10%; selection pauses the game.
- Dropping below 15 removes the active choice. At the next 25, the player chooses again unless a priority ability is marked for automatic activation.
- Antidote has no overdose, toxicity meter, or separate debuff.
- Player speed is 6 m/s; fast infected speed is 7 m/s with 50 HP.
- Infected attack at 1.2 m once per second for 15 damage and route around obstacles.
- The first infected attacks a destructible object only if one hit would destroy it, so it does not attack partitions.
- Grenade radius is 3 m with up to 100 center damage and falloff, including player self-damage.

## Validation evidence

- Not run; this update records discovery decisions only.

## Blockers

- Weapon numbers, blocked-enemy fallback, technical budgets, and shop balance require owner answers.

## Next exact action

Define weapon magazines, damage, fire rates, reload times, reserves, and blocked-enemy fallback.

## Session handoff

Player/enemy speed, infected HP/attack, 3D navigation, obstacle rules, and grenade radius/falloff are recorded in `GAME_SPEC.md`. No validation was run. Continue with weapon numbers.
