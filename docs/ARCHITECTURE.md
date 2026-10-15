# Godot game architecture

ADR-0049: bootstrap.app хранит optional interface_v1.sunlight (default true).
Существующий GlobalOverheadLight видим при lighting && sunlight. Локальные
лампы, Environment и их бюджеты прежние; новых owners, API или зависимостей нет.

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

- searching the SceneTree for services or using `current_scene` from production features/presentation;
- resolving mission containers or impact budgets by parent-name conventions;
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

## Occlusion presentation (ADR-0023)

Bootstrap owns occlusion_mode and transient render copies/overrides, with actor, camera and world injected by main. Public structural and pickup roots expose versioned occlusion_visual_v1 classification groups, not service lookup. Gameplay never depends on this effect. Shared authored mesh/material resources remain immutable; skeletons are shared read-only. Planner commands temporarily suspend rendering without changing the persisted mode. No layer, dependency or policy exception is introduced; architecture/policy.json remains unchanged.

## Blast screen feedback (ADR-0024)

Player owns blast disorientation/audio recovery and reports typed blast_feedback_v1 facts. Bootstrap injects the public player root into a scene-local CanvasLayer that owns only the visual envelope; gameplay does not reference UI. Subscriptions disconnect on teardown. Authored damage/cover/radius and module dependency direction remain unchanged. No singleton, map schema change or policy exception.


Bootstrap settings and runtime diagnostics: ADR-0028 owns private controls_v1 keyboard/mouse bindings, additive interface_v1.test_mutagen (default false), four tab presentation and injected read-only F3 overlay. These do not change maps or dependency edges. The owner-requested surface_atlas_v1 helper is separately exposed by core.vfx for replacement bullet/scorch/glass materials.
## Display v1 (ADR-0026)

presentation.office_floor owns authored display power/content/seed and derived screen materials, glow and TV groups. Bootstrap injects a mission-local public/display_wall.gd through world_bindings; no service lookup. Layout DTO v8 adds optional display; exported fields preserve scene bake. Legacy records default to stable auto/static.

## Surface repair contracts (ADR-0027)

core.vfx surface_atlases_v1 supplies immutable atlas textures; features.combat impact_surface_v1 owns mission-local visible-triangle projection and injected visual registration. presentation.office_floor planner_decor_v2 owns blood surface normal and follows injected mesh anchors. bootstrap maps DTO v8 adds optional blood_normal, blood_attachment, object_id and rotation_x/z alongside display_v1. features.infected owns local bounded route caches. Retired distance visibility/chunk adapters never disable collision or hide world roots. Hole materials remain bootstrap-owned and cached with bounded installation.

## Оптимизации исполнения — ADR-0035

- bootstrap создаёт одну mission-local очередь полного поиска пути infected.
  `configure_chase_budget` внедряет её в начальных и призванных врагов.
  Priority heap, лимит двух завершений, мягкий бюджет 2000 мкс и 64 раскрытий за физический кадр принадлежат features.infected;
  глобальные счётчики/Autoload не добавлены.
- features.combat.public.prop_damage_state владеет здоровьем, индексом
  варианта, ожидающим переходом и одноразовыми флагами environment_prop.
  Presentation передаёт факты геометрии/крепления, отображает результат
  HitAction/Transition и управляет коллизиями/физикой/эффектами.
  Поле `_broken` сцены остаётся совместимым read-only представлением.
- Occlusion обновляет только добавленные/удалённые корни; полная пересборка
  нужна при старте, переключении режима или выходе из планировщика.
- Стриминг по дистанции не возвращается: WorldActivation лишь восстанавливает
  видимость/обработку корней и старые явно помеченные streamed-коллизии.

## Обновления представления — ADR-0036

Office-floor сохраняет владение визуальным полом и дисплеями: пространственные
MultiMesh-секции, локальный список включённых анимаций и исходные GIF-дедлайны.
Prototype HUD сравнивает снимки перед записями, фон радара имеет независимую
перерисовку. Infected владеет локальными expiry Timer частей; combat владеет
immutable cache физических ресурсов гильз. Публичные методы и DTO v8 прежние;
новых зависимостей, глобального clock/пула или политик дальних коллизий нет.

ADR-0037: core.vfx предоставляет opt-in surface_stamp_cache_v1; instance принадлежит существующему combat impact pool. Stateless v1 совместим; snapshots/indices ограничены 128 Mesh, invalidation Mesh.changed, teardown отключает observers. Новых зависимостей и глобального состояния нет.

## Локальная декомпозиция EnvironmentProp

presentation.office_floor сохраняет прежнего владельца состояния и публичную
сцену environment_prop. Root принимает команды попаданий, применяет результат
features.combat.prop_damage_state и конфигурирует своё RigidBody и дисплей.
EnvironmentPropGeometry владеет импортированным Visual, упорядоченными
вариантами/стадиями и соответствием collision shape → mesh.
EnvironmentPropBreakup отображает разрушение: фасадные сколы, последовательные
обломки и стекло; body и geometry передаются явно. Глобальных кэшей нет.

Root остаётся выше порога 300 строк: его оставшиеся методы являются адаптерами
публичной сцены и локальной композицией физического тела. Декомпозиция выполнена
по причинам изменения, не по числу строк; наследники и диагностические поля
сохранены. Дополнительные pass-through классы для лимита не вводятся.
Контракты, DTO, балансы, модульные зависимости и policy не меняются.

## Группа 03: ресурсы стадий по требованию

Office-floor Geometry сохраняет владение visual/stages/collision и удерживает immutable PackedScene стадий в течение жизни объекта. Post-import добавляет пустые именованные группы с lazy_stage_path; Geometry наполняет группу при переходе. ResourceLoader разделяет ресурсы, scene nodes остаются локальными. Manifest относится к assets, не DTO сохранений. Глобальный cache, новый owner, dependency или публичный API не добавлены.


## P1 аудита — безопасная запись и ограничение кадра

bootstrap.app сохраняет владение картой и стартом миссии. Приватный
planning_map_file записывает JSON во временный соседний файл, проверяет байты
и прежнюю schema v1–v8, готовит проверенную .bak предыдущей валидной карты,
затем заменяет основной файл. mission_loader предлагает backup/default при
повреждении, не исправляя пользовательский файл без команды сохранения.

features.infected сохраняет route/budget_v1: A* frontier и очередь порций
используют приватный stable binary heap, ожидание повышает приоритет дальних
запросов. Physics cast не прерывается посередине: 2000 мкс — мягкая граница,
дополненная лимитом 64 раскрытий и прежними 192 раскрытиями на поиск.
Clearance memoization ограничена кадром/порцией; после изменений препятствий
в следующем физическом кадре запрос выполняется снова. Пройденный путь
проверяется перед движением, движение через коллизии не разрешается.

office_floor/display_wall сохраняет derived lighting: до 16 видимых близких
screen lights и 4 shadow lights; emission/content независимы от этого лимита.
DTO, методы публичных сцен, зависимости и владельцы состояния прежние.

ADR-0039: bootstrap interface_v1.lighting — optional bool с default true, применяемый к существующим лампам и global overhead; layout DTO прежний. HUD корректирует покрытие линзы на экранный пиксель; infection_source рисует ограниченный procedural smoke; office_floor владеет glass facade variant. Владельцы и зависимости прежние.


Стыки планировщика (T002, 10.10.2026): bootstrap planning_edge_snap владеет только производным расчётом позиции по геометрии; состояния/DTO прежние. Render helper ContactShadowQuad помечается planning_bounds_excluded для пропуска в существующем geometry probe. Import extension восстанавливает известные flattened-stage exports, без изменения исходных GLB; office_floor Geometry и staged_table сохраняют свои обязанности. Public методы, зависимости, policy и owners прежние; исключений нет.


## P2: ограниченные очереди представления и загрузки

bootstrap.app сохраняет владельца occlusion visuals и загрузки карт. Приватная
occlusion_query_layer добавляет/снимает только бит layer 9 на structural bodies;
исходные gameplay bits не заменяются. Round robin ограничен 8 subjects/24 rays
за physics tick. scene_resource_queue удерживает не более двух background
requests, с мягким allocator headroom 128 МиБ и headless Dummy fallback=1;
Script preparation остаётся на main thread. Loader освобождает payload refs
после commit/discard и отдельно измеряет instantiate/add_child.

presentation.office_floor сохраняет владельца физических визуальных фрагментов:
FragmentRuntime является дочерним private узлом явно переданного effects root,
без Autoload, глобального пула или поиска сервиса по SceneTree. FIFO содержит
WeakRef и generation identity, чтобы повторное использование Node не совпадало
со старым tombstone. Generic pool живёт/освобождается вместе с контейнером.
Fade снимает collision mask/layer, freeze и callbacks до анимации.
Public API, layout DTO v8, balance, dependency edges и policy прежние.

ADR-0044: features.character_animation владеет отретаргеченными клипами таза и ног игрока (SkeletonModifier3D leg_clip_motion, play_dodge, leg_clips) вместо процедурной походки игрока; features.player вызывает play_dodge при перекате, меню хранит dodge_animation. Новых зависимостей и изменений DTO нет.
ADR-0040: features.character_animation владеет аддитивной реакцией корпуса на попадание (SkeletonModifier3D hit_reaction: позвоночник, грудь, запаздывающая голова; бёдра и ноги не трогаются) и выпрямлением колена в процедурной походке; notify_hit аддитивно принимает точку, направление и силу. features.infected владеет темпом погони chase_pace (рывки бега и шаг между ними, ускорение без скачков). Новых зависимостей, глобального состояния и изменений DTO нет.

ADR-0048: bootstrap owns scene-local menu/mission music and derived aggression intensity; office_floor owns native positional fan loops; infected owns species/action voice profiles. Existing public perception query and sound_events_v1 are reused. interface_v1 adds optional menu_music/menu_music_volume; defaults preserve older settings. No new dependency edge, Autoload or policy exception.
