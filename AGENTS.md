# Mandatory AI instructions

These rules apply to every AI agent and every file in this repository.

Normative keywords **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are intentional. The canonical human-readable architecture is `docs/ARCHITECTURE.md`; the executable dependency policy is `architecture/policy.json`.

## Required reading order

Before changing code or project structure, the agent MUST read:

1. this file;
2. `docs/ARCHITECTURE.md`;
3. `architecture/policy.json`;
4. all `module.json` files for modules touched by the task;
5. relevant ADRs under `docs/adr/`.

If any required file is missing, contradictory, or unclear, the agent MUST stop and ask for clarification instead of inventing a rule.

## Mandatory workflow

Before editing, the agent MUST:

1. restate the requested outcome;
2. identify affected modules and state owners;
3. list files expected to change;
4. identify architectural risks;
5. keep the change within the requested scope.

While editing, the agent MUST:

- make the smallest coherent change;
- preserve public APIs unless the task explicitly requires changing them;
- access another module only through its declared public API;
- declare every module dependency in that module's `module.json`;
- keep domain logic independent from UI, engine objects, persistence, networking, analytics, and platform SDKs;
- keep configuration data separate from runtime state;
- leave unrelated files unchanged.

Before finishing, the agent MUST run:

```bash
python tools/validate_architecture.py
```

It MUST also run project tests and builds when they exist. A task is not complete while validation fails.

## Non-negotiable architecture rules

1. The project is a modular monolith.
2. Each mutable state has exactly one owning module.
3. Other modules request changes through commands or public interfaces; they MUST NOT mutate foreign state.
4. Module internals are private. Only items listed in `public_api` are cross-module contracts.
5. Dependency cycles are forbidden.
6. Hidden dependency lookup, global mutable state, and service locator patterns are forbidden.
7. Global event buses are forbidden. Cross-module events MUST be typed, documented public contracts.
8. Events describe facts that already happened. Required actions use commands or direct public interfaces.
9. Gameplay/domain code MUST NOT depend on presentation or concrete infrastructure.
10. Third-party SDKs MUST be wrapped by infrastructure adapters.
11. Save formats, network protocols, and public contracts MUST be versioned when introduced.
12. A new abstraction MUST solve a current demonstrated need; speculative frameworks are forbidden.
13. ECS MAY be used only for measured high-volume simulation. UI, orchestration, and unique scripted objects SHOULD remain conventional objects.
14. Refactoring and feature work SHOULD be separate changes.
15. Generated code MUST NOT be trusted without validation and tests.

## Architecture changes

The agent MUST NOT silently bypass a rule.

A change to layer directions, state ownership, public contracts, persistence format, network authority, or a shared abstraction requires:

1. an ADR copied from `docs/adr/0000-template.md`;
2. explicit rationale and rejected alternatives;
3. migration and rollback plans;
4. corresponding updates to documentation and policy;
5. explicit approval from the user or maintainer.

Without approval, the agent MUST propose the change but not implement the architectural exception.

## Module creation

A new module MUST have a `module.json` based on `templates/module.json`. Its ID MUST be stable and unique. The manifest MUST name:

- layer;
- purpose;
- state owner;
- public API;
- dependencies.

A module MUST NOT be split merely to reduce file size. Split only when ownership, lifecycle, scaling, or dependency boundaries are genuinely different.

## Completion report

The final response MUST include:

- changed modules and files;
- public API or data-format changes;
- tests and validators run;
- unresolved risks or assumptions;
- any architecture deviation, clearly marked.

The agent MUST never claim a check passed unless it actually ran successfully.
