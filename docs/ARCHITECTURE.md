# Godot game architecture

## Target

This template targets **Godot 4.x with GDScript**. It uses a modular monolith so a large game remains understandable without introducing unnecessary frameworks.

## Layers

| Layer | Godot responsibility | Allowed dependencies |
|---|---|---|
| `core` | Engine-light primitives, IDs, time abstractions, result types | none |
| `features` | Gameplay rules and owned state: combat, inventory, quests, abilities, world | `core`, public APIs of `features` |
| `presentation` | UI scenes, camera, animation, audio and VFX | `core`, public `features` |
| `infrastructure` | Save files, transport, asset/platform adapters, analytics | `core`, public `features` |
| `bootstrap` | Main scene, game states, dependency composition and module wiring | all layers |

## Project layout

```text
project.godot
game/
  core/<module>/
  features/<module>/
  presentation/<module>/
  infrastructure/<module>/
  bootstrap/<module>/
content/                  authored .tres resources and data
assets/                   imported art, audio and fonts
addons/                   isolated third-party Godot plugins
docs/adr/
architecture/policy.json
tools/validate_architecture.py
```

Every module directory contains `module.json`.

Recommended module anatomy:

```text
inventory/
  public/                 cross-module interfaces, commands, DTOs and signals
  domain/                 state and invariant rules
  application/            use cases and orchestration
  data/                   definitions and configuration
  presentation/           optional module-owned scenes/views
  infrastructure/         optional adapters
  tests/
  module.json
```

Create only directories the module actually needs.

## Dependency enforcement

Godot paths are architectural imports. References found in `.gd`, `.tscn`, and `.tres` are mapped to their owning module.

A cross-module reference is legal only when:

1. the target module appears in the source module's `dependencies`;
2. the target layer is allowed by policy;
3. the referenced file is inside the target module's `public/`.

References to `assets/`, `content/`, and approved `addons/` are data/plugin references rather than module dependencies. Wrappers around addon APIs belong in infrastructure.

Dynamic construction of cross-module paths is forbidden because it bypasses static validation.

## State and domain logic

Each mutable state has one authoritative owner. Nodes and scenes may display or cache derived state but do not become authoritative merely because they contain a script.

Domain logic should be plain `RefCounted` objects or similarly engine-light classes when possible. It must be testable without loading a scene.

Separate:

- authored `Resource` definition;
- mutable runtime state;
- domain rules;
- Node-based presentation;
- versioned persistence DTO;
- versioned network DTO.

Loaded resources are shared by Godot. Treat definition resources as immutable; copy values into runtime state before mutation.

## Scene rules

A scene is a local composition boundary. Its root owns the lifecycle of children it creates.

Allowed:

- local `$Child` or `%UniqueNode` access;
- exported references wired in the editor;
- instantiating another module's explicitly public scene through a declared dependency;
- bootstrap composing top-level modules.

Forbidden:

- searching the SceneTree for services;
- absolute `/root/` lookups from gameplay;
- embedding domain rules only in button handlers or animation callbacks;
- using node groups as a hidden global dependency container;
- reaching into another module's internal child nodes.

Keep reusable scene APIs on their root script. External code must not depend on internal node layout.

## Autoload policy

Autoload is not a general dependency injection mechanism. It is limited to:

- the application composition root;
- narrow infrastructure bridges whose engine lifecycle truly requires it.

Autoload never owns gameplay state. Adding one requires review and normally an ADR. The validator reads `project.godot` and rejects Autoloads from disallowed layers.

## Signals, commands, and queries

Use:

- command for a requested state change that may fail;
- query for a read with no state change;
- signal/event for a fact that already happened.

Prefer direct typed calls when an operation is required synchronously. Signals are best for local optional reactions. Cross-module signals are public contracts and must have explicit connection/disconnection lifecycles.

A global signal bus is forbidden because it hides dependencies, ordering, and ownership.

## Runtime loop

Do not give every node an update callback.

Preferred phases:

1. input collection;
2. command validation;
3. fixed-step simulation in `_physics_process`;
4. state publication;
5. frame presentation in `_process`;
6. deferred cleanup.

Use timers, events, batching, visibility callbacks, and central scheduling to avoid thousands of idle callbacks. Performance changes require profiler evidence and a target budget.

## Persistence

Feature modules expose versioned snapshots. Infrastructure writes them atomically and handles backup, integrity, and cloud/platform APIs.

Persistent data must not contain:

- Node references;
- NodePath as durable identity;
- instance IDs;
- RID values;
- resource memory identity.

Use stable string/integer IDs and explicit migrations with old-save fixtures.

## Multiplayer

For authoritative multiplayer:

```text
input -> command -> server validation -> simulation -> replication -> presentation
```

Godot RPC annotations describe transport, not game authority. Server-side feature modules validate combat, inventory, economy, and progression. Network DTOs and RPC contracts are versioned.

## Source decomposition and size guardrails

Line count is a warning signal, not the definition of architecture. Split code by ownership and reason to change:

- `public/`: small cross-module contracts, commands, queries, DTOs and events;
- `domain/`: authoritative state and invariant rules;
- `application/`: one use case or orchestration flow;
- `presentation/`: Nodes, scenes and player feedback;
- `infrastructure/`: persistence, network, platform and SDK adapters;
- `tests/`: behavior and regression evidence.

Do not create empty pass-through files, one-line wrappers, or vague shared helpers merely to reduce line counts.

Default GDScript guardrails:

| Scope | Review threshold | Hard limit |
|---|---:|---:|
| Production file | 300 lines | 600 lines |
| Test file | 500 lines | 900 lines |
| Function | 50 lines | 100 lines |

Physical lines are counted deliberately so comments and whitespace cannot hide an oversized unit. Scene and Resource serialization are editor-managed data and are not subject to handwritten-code limits.

Files above a review threshold require a responsibility review. Files above a hard limit fail validation. A justified exception must be exact-path, finite, recorded in policy, and backed by an approved ADR.

Good reasons to split:

- different state owners;
- domain rules mixed with Node/UI behavior;
- persistence or network details mixed with gameplay;
- functions that change for unrelated reasons;
- independent lifecycles or testing boundaries.

Bad reasons to split:

- reaching an arbitrary line number;
- creating generic `utils.gd`;
- moving code into helpers that still mutate foreign state;
- hiding a dependency behind signals or a service locator.

## Testing

- Domain tests instantiate engine-light classes without scenes.
- Integration tests load one module boundary.
- Scene tests verify wiring and lifecycle.
- Persistence tests load old fixtures.
- Performance tests measure representative object counts.
- Headless project import catches missing resources and broken scene paths.

## Definition of done

A change is complete when manifests are accurate, ownership remains unique, public paths are respected, tests pass, the project imports headlessly, and:

```bash
python tools/validate_architecture.py
```

passes without exceptions.
