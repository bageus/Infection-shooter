# ADR-0027: Attached impact surfaces and persistent world collision

- Status: Accepted
- Date: 2026-10-05
- Approval: owner's direct request in this session for decals, door damage, blood placement, UI sounds, mutagen, enemy routing, removal of visibility downgrade and transparency crash repair.
- Related modules: core.vfx, features.combat, features.infected, features.infection_source, presentation.office_floor, bootstrap.app

## Context

Broad physics boxes produced floating marks. Moving glass lost collision while open; distance streaming disabled walls. Floor blood was below rendered tiles. Hole mode allocated repeated materials across authored geometry.

## Decision

core.vfx owns immutable 4x2 atlas definitions. Combat owns mission-local cached triangle projection and weak registered visual roots through impact_surface_v1. Impact marks attach to the hit visible mesh; glass cracks remain glass-owned, follow the door collision body and are removed on shattering. Open glass retains its moving physical leaf.

Distance chunk/visibility adapters keep existing composition interfaces but perform no runtime hiding, processing suspension or collider disabling. Destroyed collision is never restored. Infected owns bounded local A* route state, uses physics sphere sweeps, throttles replanning and retains body collision for movement; it never changes wall state. This improves local obstacle routing, not global navigation for arbitrary mazes.

Bootstrap blood placement probes floor/wall/object and calls planner_decor_v2. Optional layout v8 fields blood_normal, blood_attachment, object_id and rotation_x/z preserve surface alignment and mesh attachment; old maps default to floor/legacy wall. Office presentation owns the blood quad and follows an injected weak mesh anchor. Stable owner id plus authored mesh name identify durable attachments, never instance IDs/NodePaths. Bootstrap restores authored and loaded attachments. Damage hides attached marks with the mesh.

Hole materials are cached per original immutable material, culled shader variants reused, and installation limited to 12 meshes per frame. Mode transitions restore original materials; invalid viewport/behind-camera coordinates suppress the hole. This mitigates allocation bursts; native crash acceptance requires both GPU renderers and target device testing.

UI settings hover is restricted to the sound toggle; disabled mutation skills do not hover/click. Mutagen has no horizontal haze sheet: subdued upright billboards and lower glow remove the artificial floor reflection.

## Alternatives considered

- Marks on broad collision boxes: rejected because surfaces differ visibly.
- Reparent the entire glass body into visual hierarchy: rejected to preserve authored paths/public wiring.
- Keep distance collision disabling: rejected by owner and unsafe for enemy movement.
- Introduce a baked navigation map now: rejected because planner edits/destructible furniture require rebuild ownership beyond this repair.
- Discard hole mode: rejected; owner requested a repair.

## Migration and rollback

No existing DTO fields are renamed. Layout v8 additions are optional; v6/v7 remain readable. Regenerate display derivatives with the two tools. Rollback this commit restores previous rendering/AI and ignores new optional map fields; original supplied assets stay untouched. No architecture exception.

## Decomposition review

Files above 300 lines retain existing composition roles: planner storage/objects/history wire extracted placement/display helpers, interactive_door retains door-only behavior, infected_capsule delegates routing to chase_route. No production file exceeds 600 lines. New projection, blood probe, display content/geometry/layout and atlas rendering each have one responsibility.

## Validation

See DISPLAY_QA.md and WORLD_SURFACE_QA.md for executed checks and target-device acceptance.

## Уточнение реализации — issues234/235, 17.10.2026

По прямому запросу владельца moving door leaf явно регистрирует свой collider
и mesh через существующий impact_surface_v1. Bootstrap восстанавливает старую
unbound/frame blood по близкой реальной поверхности, в производный runtime anchor; authored
optional owner/mesh и object_id сохраняются без изменений при загрузке, другой
существующий saved owner не заменяется. Floor blood
и layout v8 прежние. Новый runtime контракт не вводится.

Office-floor освобождает все wall-mounted props при разрушении деревянной
перегородки через прежний fall_off_with_glass: классификация WallMountModels,
module-local group и private contact geometry в координатах опоры. Physics/damage
owners прежние; потеря крепления не ломает intact TV/шкаф/сантехнику.
Декомпозиция door587/prop564/main383 reviewed как scene composition; контакт
крепления выделен в отдельную private ответственность. Исключений нет.
Проверки/ограничения: docs/qa/door_blood_and_wall_support.md.
Откатить этот инкремент целиком; форматы и существующие сцены совместимы.


## Уточнение 24.10.2026 — idle door runtime

Closed/far guard пропускает key/sound/pose work только после начальной позы,
без close delay/request_open; proximity проверяется каждый physics tick,
поэтому приближение и teleport не ждут timer. Glass hinge side и defensive
broken collider repair сохраняются также вдали. Private door_runtime_cache
удерживает только geometry bindings; shape-list invalidation — по child events,
teardown отключает подписки. Transform/player/locks остаются живыми,
управление и mutable door state принадлежат прежнему root. Новых Timer/Area3D,
distance collision disabling, публичных API, DTO, owners/edges или исключений
policy нет. Root597строк reviewed; resource/scene изменения не нужны.
Проверки и CPU-ограничения: [QA](../qa/idle_door_runtime.md).
