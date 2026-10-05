# ADR-0028: Settings tabs, private controls and runtime diagnostics

- Status: accepted
- Date: 2026-10-05
- Owner: bageus (direct feature request)
- Related module: bootstrap.app

## Context
The owner requests four settings pages, editable controls, clearer menu copy, company history and diagnosis of lost control while walking with wall holes. Screenshots show a missing water-cooler texture; the gun smoke atlas moved. Normal main startup also enabled an infectious permanent test cloud at the player spawn.

## Decision
Bootstrap owns General, Controls, Video and Audio tabs and the binding editor. The private user configuration gains controls_v1: each of 22 gameplay actions stores {kind: key|mouse, code: integer}. Existing interface_v1 gains test_mutagen=false. Missing values use defaults; malformed/conflicting controls fall back atomically. Escape, Tab, Enter and F3 remain reserved. Mouse buttons 1–3 and single physical keys are supported; controllers/chords are deferred. Rebinding applies only owned gameplay InputMap actions; UI navigation remains unchanged. Mutation UI consumes the same actions as movement/combat. No map DTO, save format, dependency edge or architecture exception changes.

The infectious spawn cloud becomes an explicit General test setting, off by default; legitimate mutation loss and recovery remain. Bootstrap injects infection and occlusion collaborators into a read-only F3 overlay reporting frame time, mutation/control loss and hole material statistics. It does not locate services or mutate simulation state.

Hole material installation is queued (12 meshes per render frame), immutable source materials share replacements, and late actor registration preserves installed wall overrides. Original materials are restored on mode/planner teardown. This overlaps the material cache repair in PR #25, without importing its unrelated display or surface changes.

VECTRION history is proposed fiction except the owner-confirmed military-contractor origin. Exact dates, founders and incident cause are left open.

## Alternatives considered
Hardcoded labels without InputMap updates would not edit actual controls. Disabling mutation control loss would conceal the spawn-cloud problem. Per-mesh/per-spawn material recreation creates unnecessary GPU work.

## Migration and rollback
Old preference files load with default controls and test cloud off. Old readers ignore the additive fields. Revert bootstrap/config/UI changes to roll back; maps and authored materials are untouched. Asset repairs retain existing source texture identity and the water texture UID used by imported scenes.

## Validation
Settings tests cover page ownership, conflicts, persistence, reset, capture cancellation and mouse rebinding. Runtime debug tests cover saved hole startup, movement, late actor material reuse, read-only diagnostics, opt-in cloud, preserved mutation loss/recovery and four bottle placements. Existing pixel tests require Compatibility and Vulkan Forward+. Target-machine freeze/FPS acceptance remains manual.

## Asset compatibility follow-up
Deleted single decals also broke baseline tests. The already owner-requested surface_atlas_v1 helper from PR #25 is included: core.vfx exposes material(texture, cell), combat selects bullet cells 0–4 and scorch 5–7, glass selects 0–7. Existing module dependency edges suffice. Wood paths use wood_decals. No surface-projection/door/display features from PR #25 are implied by this narrow repair.
