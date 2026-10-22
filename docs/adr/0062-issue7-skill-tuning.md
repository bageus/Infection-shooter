# ADR-0062: Shared mutation tuning and issue #7 skill effects

- Status: accepted — owner requested implementation, branch and PR on 22.10.2026
- Date: 2026-10-22
- Owners: features.infection (definitions/progression), features.player (effects), features.combat (ammo), features.pickups (drop probabilities), features.infected (damage receiver), bootstrap.app (cards)
- Related modules: features.infection, features.player, features.combat, features.pickups, features.infected, bootstrap.app

## Context

The accepted top section of issue #7 specifies 40 skill variants. Previous effects
and vague RU/EN cards disagreed on thresholds, quantities, triggers and ammunition
sources. The sixth passive hybrid was absent. Player and infected host scripts
already approach the 600-line limit.

## Decision

Expose immutable `features.infection/public/mutation_balance.gd` as the common
numeric definition for localized templates and gameplay. Add the declared
`features.infected -> features.infection` dependency for those read-only values.
Existing dependency direction and all mutable state owners remain unchanged.

Keep hybrid clocks/absorption in private player `passive_hybrid_effects.gd` and
consumable application in `player_consumables.gd`. The existing infected
`mutation_status.gd` applies the wounded-target bonus. Player and enemy hosts
retain their existing public methods. No singleton, save field or scene is added.

Combat adds `refill_magazine_from_reserve() -> int` on existing weapon scenes:
it transfers only available reserve and cancels pending reload; belt-fed weapons
return zero. Organic Ammo uses the existing explicit magazine creation command;
weapons without a magazine are excluded. It never creates reserve ammo.

Loot `release_enemy`/`drop_for_enemy` accept optional `ammo_multiplier=1.0`.
Recycling multiplies automatic ammo drop probabilities by1.3, using otherwise
empty probability mass; non-ammo probabilities and authored manual/empty loot
are unchanged. Legacy callers keep their default behavior.

`skill_requirements.cooldown` now includes active Neurostimulation. Cards retain
fractional recovery values. Assimilation enhances medkits/ammo supplies and the
mutation reduction of an antidote at use. It does not multiply passive healing,
DNA progression, or the discrete number of antidote charges.

Devourer refreshes one absorption reserve to50 for5seconds while at full health
in a cloud; it does not stack above50 or modify normal armor. Hyperactive starts
on the first kill; gaps of exactly1second are allowed; larger gaps start10seconds
of recovery that kills cannot bypass. Disabled branch effects stop immediately.
Damage accumulation retains the existing incoming-damage accounting after
mutation absorption and before resistance/ordinary armor; Evolution now only
counts physical hits. Existing additive resistance and75% cap remain.

## Alternatives considered

- Editing only descriptions would leave incorrect promises in the UI.
- Keeping copied constants in translations and each effect would drift again.
- A global effects service or new cross-feature state owner would introduce
  unnecessary lifetime and dependency changes. Private player helpers preserve ownership.

## Consequences

Numeric text and effects share definitions; display-only rounding does not alter
Bone Armor's division by1.3. Organic Ammo closes the passive ring with a bottom
connector lane, without consuming a point. Active families and Q/E remain intact.
The read-only tuning contract is an additional public dependency to maintain.

## Migration plan

1. Preserve existing IDs and add `organic_ammo` with two complete parent branches.
2. Reconcile old purchased/locked hybrid state through existing refund logic.
3. Keep optional arguments backward compatible; register new tuning API and edge.
4. Update RU/EN cards, spec and CI suites together.

## Rollback plan

Revert this change as one commit; no persisted schema migration is needed. The
previous reconciliation discards unrecognized Organic Ammo learned/locked state.

## Validation

Pinned Godot4.7.2 headless import;22 related suites, including numeric boundaries,
ammo conservation, protection expiry, series/cooldowns, consumable effectiveness,
deterministic loot probability integration and all40 RU/EN templates. Project,
architecture, workflow, source-size and CI coverage gates. Native visual review
of the sixth hybrid and full gameplay balance are outside headless verification.

## Approval

Owner's accepted decisions in issue #7 and explicit request: «теперь реализуй в
коде, создай ветку и PR». Additive commands/data contracts implement that scope;
no architectural policy exception is introduced.
