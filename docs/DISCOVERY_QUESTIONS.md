# Discovery Questions

Use this interview only while `GAME_SPEC.md` is `DRAFT`.

## Interview protocol

1. Read existing answers first; never ask an answered question again.
2. Ask 3–5 related questions per turn.
3. Start with decisions that can invalidate later answers.
4. Explain why a question matters only when it is not obvious.
5. If the owner does not know, offer 2–3 concrete options with trade-offs and a recommendation.
6. Record confirmed answers immediately in the correct file.
7. Distinguish:
   - **BLOCKER** — implementation cannot safely begin;
   - **ASSUMPTION** — temporary proposal requiring confirmation;
   - **DEFERRED** — can be decided in a later phase.
8. After every group, summarize confirmed decisions, contradictions, and the next group.
9. Do not force irrelevant questions; use `N/A — reason`.
10. Do not mark the specification ready without explicit owner approval.

## Group 0 — Working relationship

Ask first:

1. How independently may the AI modify files after a plan is approved?
2. Should changes go directly to `main` or through pull requests?
3. Which actions always require confirmation?
4. How much explanation is preferred?
5. What language should code comments, documentation, commits, and conversation use?

Record answers in `docs/WORKING_AGREEMENT.md`.

## Group 1 — Identity and player promise

Determine:

- who the player is;
- primary repeated activity;
- immediate and long-term goals;
- unique hook;
- genre, camera, pace and session length;
- reference games and explicit non-goals.

Required output: one-sentence concept and 3–5 experience pillars.

## Group 2 — Audience and product constraints

Determine:

- target audience and expected skill;
- target platforms and input devices;
- distribution/monetization;
- age rating, regions and languages;
- team, budget and time constraints;
- measurable definition of product success.

## Group 3 — Core loop and game flow

Determine:

- minute-to-minute loop;
- session loop;
- long-term loop;
- meaningful player decisions;
- launch-to-control flow;
- win, failure, restart and completion behavior.

Ask for observable examples, not abstract adjectives.

## Group 4 — Mechanics and ownership

For every MVP mechanic determine:

- stable mechanic ID;
- player purpose;
- inputs, rules, outputs and feedback;
- authoritative state owner;
- failures and edge cases;
- saving/network implications;
- acceptance criteria.

Reject mechanics that support no experience pillar.

## Group 5 — World, content and progression

Determine:

- world/level structure;
- authored vs procedural content;
- content unit and estimated volume;
- progression and economy;
- anti-softlock rules;
- replayability;
- content production ownership and validation.

## Group 6 — Presentation and accessibility

Determine:

- required screens and HUD;
- tutorial/onboarding;
- visual and audio direction;
- readability;
- remapping, subtitles, text scale, contrast, motion and audio accessibility.

## Group 7 — Technical foundation

Determine:

- exact Godot version and language;
- 2D/3D model;
- minimum hardware and performance budgets;
- save/version/migration strategy;
- multiplayer authority if applicable;
- localization;
- plugins, SDKs and external services;
- build, export and test platforms.

## Group 8 — Scope, quality and risk

Determine:

- must-have MVP;
- desirable post-MVP;
- explicit exclusions;
- release-blocking defects;
- legal/licensing/privacy requirements;
- highest technical and production risks;
- rollback and dependency fallback expectations.

## Final synthesis

Before requesting `READY` status:

1. show the concept in one paragraph;
2. show the core loop;
3. list pillars and non-goals;
4. show MVP and exclusions;
5. show platforms and technical constraints;
6. list unresolved blockers and assumptions;
7. propose Phase 1 milestone and first three candidate tasks;
8. ask for explicit approval.

After approval:

- replace placeholders;
- remove resolved `[BLOCKER]` markers;
- set the working agreement to `ACCEPTED`;
- set `GAME_SPEC.md` to `READY`;
- update `PROJECT_STATE.md`, `BACKLOG.md`, and `ACTIVE_TASK.md`;
- run all readiness validators.
