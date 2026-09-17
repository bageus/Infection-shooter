# Game architecture

## Goal

Keep a large game understandable and changeable as its team and content grow. The default is a **modular monolith**: one deployable game project with explicit module boundaries.

The architecture optimizes for local reasoning:

- one owner for each mutable state;
- small public module APIs;
- explicit dependency direction;
- engine and vendor isolation;
- data-driven content;
- automated boundary validation.

## Layers

| Layer | Responsibility | May depend on |
|---|---|---|
| `core` | Stable primitives, IDs, time abstractions, result types, contracts with no gameplay meaning | nothing |
| `features` | Gameplay rules and state: combat, inventory, quests, abilities, world simulation | `core`, public APIs of other `features` |
| `presentation` | UI, camera, animation, audio and VFX presentation | `core`, public `features` APIs |
| `infrastructure` | Save storage, network transport, asset loading, analytics and platform adapters | `core`, public `features` APIs |
| `bootstrap` | Composition root, startup, module wiring and top-level game states | all layers |

Dependencies point inward toward gameplay and stable contracts. Gameplay never imports concrete UI, storage, transport, analytics, or platform SDKs.

## Repository layout

```text
src/
  core/<module>/module.json
  features/<module>/module.json
  presentation/<module>/module.json
  infrastructure/<module>/module.json
  bootstrap/<module>/module.json

architecture/policy.json
docs/adr/
templates/module.json
tools/validate_architecture.py
```

Engine-specific folders MAY wrap this layout, but every architectural module still needs one discoverable `module.json`.

## Module contract

A module owns one coherent capability. Its manifest declares its identity, layer, state ownership, public API, and dependencies.

Recommended internal structure:

```text
<module>/
  Public/          cross-module interfaces, commands, queries and events
  Domain/          state and invariant rules
  Application/     use cases and orchestration
  Data/            immutable definitions and configuration
  Presentation/    optional module-owned views
  Infrastructure/  optional adapters
  Tests/
  module.json
```

Do not create empty directories merely to match the diagram.

### Public API

Only contracts named in `public_api` may be consumed from another module. A public API should expose intent, not internal collections or mutable fields.

Bad:

```text
questSystem.inventory.items.append(item)
```

Good:

```text
inventory.try_add(item_id, amount)
```

### State ownership

Every mutable state has exactly one owner. The owner validates commands and performs mutations. Other modules may query through read-only contracts or request a change.

Examples:

| State | Owner |
|---|---|
| health and alive/dead state | character or combat, chosen once |
| item stacks and equipment | inventory |
| quest progress | quests |
| persistent file representation | persistence adapter |
| authoritative multiplayer outcome | server simulation |

Duplicated read models and presentation caches are allowed when they are derived, disposable, and never treated as authoritative.

## Communication

Use the simplest explicit mechanism:

- **command**: requests a state-changing action and may fail;
- **query**: reads without changing state;
- **event**: announces a fact that already occurred.

Use direct calls for required synchronous work. Use typed events for optional reactions. Avoid global buses because they hide dependencies and execution order.

## Data boundaries

Keep these concepts separate:

- definition: immutable authored data, such as an item type;
- runtime state: a specific item stack or character instance;
- domain rule: how state may change;
- presentation: how state is shown;
- persistence DTO: versioned saved representation;
- network DTO: versioned transferred representation.

Never serialize engine object references as durable identity. Use stable IDs and explicit migrations.

## Runtime and update loop

Prefer a controlled phase order:

1. input collection;
2. command validation;
3. fixed-step simulation;
4. state publication;
5. presentation;
6. deferred cleanup.

Not every object should own a per-frame update. Batch or schedule high-volume work. Performance changes require profiler evidence and a stated budget.

## Multiplayer

For authoritative multiplayer:

```text
Input -> Command -> Server validation -> Simulation -> Replication -> Client presentation
```

The client may predict for responsiveness but cannot authoritatively decide combat, inventory, economy, or progression outcomes.

Transport code carries versioned commands and snapshots; it does not own game rules.

## Persistence

Modules expose serializable snapshots through contracts. Infrastructure performs atomic storage, backup, integrity checks, and cloud integration.

Every durable format requires:

- version number;
- stable IDs;
- migration path;
- interrupted-write recovery;
- tests using older fixtures.

## ECS policy

Use ECS selectively for measured high-volume, homogeneous simulation such as crowds, projectiles, or vegetation. Do not force UI, narrative orchestration, unique scripted actors, or platform integrations into ECS.

## Complexity limits

- No abstraction solely for hypothetical reuse.
- No generic framework before at least two concrete use cases reveal the stable common contract.
- No cross-module access to internals.
- No global mutable state.
- No service locator.
- No new third-party dependency without a documented need and isolation boundary.
- No architecture exception without an ADR.

## Definition of done

A change is complete only when:

- ownership and dependencies remain explicit;
- manifests are updated;
- public/data format changes are documented;
- tests cover success, boundary, and failure cases;
- architecture validation passes;
- build and relevant performance checks pass;
- rollback or migration exists where needed.
