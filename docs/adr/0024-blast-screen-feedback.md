# ADR-0024: Blast screen feedback lifecycle

- Status: accepted
- Date: 2026-10-05
- Owners: bageus
- Related modules: features.player, bootstrap.app

## Context

The owner requests tinnitus, blur, oscillating three/four-direction image ghosts and a slight glitch close to explosions. Player blast disorientation, sound ducking and proximity/cover rules already exist. Existing explosion damage and radius must remain consistent.

## Decision

Add blast_feedback_v1 public player facts: typed blast_stun_started(duration, intensity), blast_stun_ended(). They report accepted stun state, not a global bus or required gameplay command. Bootstrap injects the public player into a separate CanvasLayer owning only the screen envelope and shader. No player dependency on UI. Existing module dependencies suffice; no policy exception.

A single canvas pass samples the 3D screen: modest mip blur, four offsets that converge/diverge, slight RGB fringe and sparse short horizontal glitches. Layer -1 leaves HUD, mutations and menus sharp; invisible and unprocessed outside stun. Last second fades. Phase advances with gameplay, not shader TIME. Existing player cancellation on pause/planner/game over/exit hides the pass immediately. Source damage radius 5.5 m, cover test and 3–5 s stun remain unchanged. Existing looping tone is changed from 730 Hz to a restrained 2800/3200 Hz mixture and fades in the final 0.8 s; Sound/Master preferences remain in force.

## Alternatives considered

- Add UI/shader code to the 462-line player script: mixes presentation ownership and further bloats movement code.
- Poll private stun fields from UI: hides the contract and couples to implementation details.
- New global audio/effect singleton or renderer compositor: unnecessary dependency/ownership expansion.
- Flash/large brightness change: not requested and obscures the lighting test.

## Migration plan

Additive public signals; no scene path, input, map or preferences schema change. Composition subscribes/disconnects explicitly. The player remains stun/gameplay/audio recovery owner, bootstrap only owns temporary rendering.

## Rollback plan

Revert the commit to remove signal consumers, screen shader and tinnitus adjustment. Maps/materials/assets unchanged.

## Validation

Runtime tests must cover actual near/distant/sheltered blast dispatch, tone, fades, repeated hits, natural expiry/pause/exit and exact audio recovery. Actual rendered tests in Compatibility and Forward+ must check nonzero image differences, temporal ghost motion, unchanged HUD and recovery. Software rendering confirms behavior, not target FPS or subjective sound mix.
