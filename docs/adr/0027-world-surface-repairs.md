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
