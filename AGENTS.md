# Mandatory AI instructions for Godot

These rules apply to every AI agent and every file in this Godot 4.x repository. GDScript is the default implementation language.

Normative keywords **MUST**, **MUST NOT**, **SHOULD**, and **MAY** are intentional. The canonical architecture is `docs/ARCHITECTURE.md`; executable boundaries are in `architecture/policy.json`.

## Required reading order

Before changing code or project structure, the agent MUST read:

1. this file;
2. `GAME_SPEC.md` — product truth and current sequential phase;
3. `docs/ARCHITECTURE.md`;
4. `architecture/policy.json`;
5. all `module.json` files for modules touched by the task;
6. relevant ADRs under `docs/adr/`.

If these sources conflict or the requested work requires an exception, the agent MUST stop, describe the conflict, and request a decision. It MUST NOT silently invent a rule.

## Game specification gate

Before gameplay implementation, the agent MUST run:

```bash
python tools/validate_game_spec.py --ready
```

If `GAME_SPEC.md` has status `DRAFT`, contains placeholders, or contains `[BLOCKER]`, the agent MUST NOT implement gameplay. It may only help complete the specification.

When ready, the agent MUST work only on `current_phase` and the first unfinished task in section 25 whose dependencies are satisfied. It MUST NOT begin the next phase until the current phase exit criteria are met.

## Required workflow

Before editing, the agent MUST identify:

- requested outcome;
- affected modules and state owners;
- scenes, scripts, resources, save DTOs, and public contracts involved;
- expected files;
- architectural and migration risks.

During implementation, the agent MUST make the smallest coherent change, preserve unrelated files, and update manifests before adding cross-module dependencies.

Before completion it MUST run:

```bash
python tools/validate_game_spec.py
python tools/validate_architecture.py
```

When Godot is available it MUST also run:

```bash
godot --headless --path . --editor --quit
```

It MUST run relevant tests. It MUST NOT claim a check passed unless it actually ran successfully.

## Core architecture rules

1. The game is a modular monolith.
2. Every mutable state has exactly one owning module.
3. Other modules request state changes through commands or public interfaces.
4. Module internals are private; cross-module references target only `public/`.
5. Every dependency is declared in `module.json`.
6. Dependency cycles are forbidden.
7. Gameplay/domain code MUST NOT depend on UI, scenes, concrete storage, transport, analytics, or platform SDKs.
8. Third-party SDKs and Godot platform APIs with external side effects MUST be wrapped by infrastructure adapters.
9. Global mutable state, service locators, and untyped global event buses are forbidden.
10. Events report facts that already happened. Required work uses commands or direct typed interfaces.
11. New abstractions MUST solve a current demonstrated need.
12. Save formats, network protocols, and public contracts MUST be versioned when introduced.

## Godot-specific rules

### Scenes and nodes

- Scenes are composition and presentation boundaries, not domain databases.
- A scene root MAY wire child nodes belonging to the same module.
- A node MUST NOT search the SceneTree for a service or another module.
- Absolute `/root/` paths and `get_tree().root` are forbidden outside approved bootstrap/infrastructure code.
- Cross-module node references MUST be injected by the composition root or expressed through a declared public contract.
- `get_node()`, `$Node`, and `%UniqueNode` SHOULD remain local to the owning scene.
- Gameplay rules MUST be callable without instantiating a scene.

### Autoload

- Autoload is allowed only for bootstrap composition or infrastructure bridges explicitly approved by policy.
- Autoload MUST NOT own combat, inventory, quests, progression, world, or other gameplay state.
- A module MUST NOT use Autoload as a service locator.
- Adding an Autoload requires an ADR unless it is the single documented application composition root.

### Signals

- Signals MUST be typed where Godot permits.
- Signals are local by default.
- Cross-module signals must be listed in the producer's `public_api`.
- A global signal bus is forbidden.
- Signal connections MUST have an explicit lifecycle and be disconnected when the subscriber outlives its context.

### Resources

- `Resource` files are authored definitions/configuration by default, not mutable runtime state.
- Runtime state MUST be copied into module-owned runtime objects before mutation.
- Shared loaded resources MUST be treated as immutable.
- Durable identity uses stable IDs, never NodePath, instance ID, RID, or scene object reference.

### GDScript

- New GDScript SHOULD use static typing for parameters, returns, fields, arrays, and dictionaries when practical.
- `class_name` is part of the global namespace and MUST be unique.
- Cross-module scripts/scenes/resources are loaded only with explicit `res://` paths that the validator can inspect.
- Dynamic paths that hide module dependencies are forbidden.
- Engine callbacks should delegate quickly to application/domain methods.
- Heavy work MUST NOT be added to every node's `_process` or `_physics_process` without a measured need.

### Files and naming

- Files and directories use `snake_case`.
- Nodes use `PascalCase`.
- Signals use past-tense `snake_case` facts.
- Input actions use `snake_case`.
- Public cross-module files live under `public/`.

## Architecture changes

Changing layer direction, state ownership, public APIs, Autoloads, save/network formats, or shared abstractions requires:

1. an ADR copied from `docs/adr/0000-template.md`;
2. rejected alternatives;
3. migration and rollback plans;
4. documentation and policy updates;
5. explicit user or maintainer approval.

Without approval the agent may propose, but MUST NOT implement, the exception.

## Completion report

The final response MUST list:

- modules and files changed;
- public API, scene, resource, save, or network format changes;
- validation and tests actually run;
- assumptions and unresolved risks;
- any architecture exception, clearly marked.
