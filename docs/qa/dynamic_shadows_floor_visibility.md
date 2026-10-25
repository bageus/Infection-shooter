# Dynamic shadow settings and floor decal visibility

Date: 2026-10-25. Scope: presentation and settings; T004 remains IN_PROGRESS.

## Behavior and diagnosis

The RU/EN toggle now reads “Динамические тени” / “Dynamic shadows”. Its tooltip distinguishes real-time light shadows from retained baked layers and contact shadows. The existing shadow quality slider retains its presets and controls dynamic shadow resolution/range. Existing preference keys, save data and public interfaces are unchanged.

The preservation test uses an actual baked biomass PNG/material and an actual prop contact-shadow quad, and checks both survive disabling dynamic shadows and changing quality. Main does not yet implement full static wall-shadow baking; this patch does not add that feature. The existing directional-light off-distance workaround remains intact.

The floor color blend already worked. Wood/plastic/fabric scatter instead placed many marks inside the source footprint, where retained geometry can hide them. Scatter now starts beyond the source edge, retaining the same recipes, obstacle checks, queue and density budgets.

The authored scuff mask peaked at alpha 144/255; default opacity and downsampling made small marks faint. A cached source copy normalizes mask coverage, preserving its shape and RGB; source PNG files remain unchanged. Footstep scuffs now use 0.35–0.6 m sizes and a 25% chance rather than 0.2–0.45 m and 12%. Opacity remains 0.18; zero still disables scuffs. Ground-contact checks and the two-mark frame cap remain.

## Evidence

The final focused suite against the original three production scripts fails 19 checks. With the candidate it passes:

| Check | Original | Candidate |
| --- | --- | --- |
| Wood marks outside 4×4 m source footprint | 8/30 | 30/30 |
| Plastic marks outside footprint | 11/30 | 30/30 |
| Fabric marks outside footprint | 9/24 | 24/24 |
| Minimum baked scuff peak alpha across frames | 0.02353 | 0.04314 |
| Scuffs from 120 confirmed foot contacts | 15 | 25 |

Eight headless suites pass: floor_decal_visibility, material_floor_debris, baked_surface_decal, glass_floor_debris, contact_shadow, floor_batch, glass_footstep and settings_tabs. Editor import succeeds. Project validation discovers 230 suites (222 runtime + 8 special). No FPS improvement is claimed.

The new optional native pixel checks are registered in CI for Compatibility and Forward+. They could not run locally because this environment cannot provide a usable X11 display; their result is pending CI. CPU image, distribution, grounding and idle/batch checks ran locally. This is not a hardware screenshot acceptance result or proof of every destruction asset's appearance.

## Limits and rollback

Scuffs retain existing base-floor receiver and footstep/blast event rules. Moving furniture alone does not introduce a new scuff event. No per-mark nodes, new draw-call layers, per-frame prop work, owner/dependency changes or data migration are added. Revert this patch to restore prior tuning and labels.
