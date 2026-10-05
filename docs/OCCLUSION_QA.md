# Occlusion modes: implementation and manual acceptance

Godot 4.7.2; switch in **Esc → Настройки → Перекрытие объектов**:

| Mode | Behavior |
| --- | --- |
| Цветные силуэты (default, 0) | Hidden hero cyan `0.2,0.85,1`; enemies red `1,0.24,0.28`; weapons, medkits, ammo amber `1,0.78,0.22`. Opacity 0.9. Visible fragments retain their authored color. |
| Отверстие вокруг героя (1) | Two-metre world radius projected into the camera, through opaque foreground walls/columns, with a narrow dithered transition and faint cyan halo. Floor/furniture remain visible; collisions remain active. |

Preference is additive interface_v1.occlusion_mode, persisted in user://interface_settings.cfg. Old/missing settings default to 0. Maps are not rewritten. Settings apply immediately while paused; planner suspends effects without changing the choice; map loads and late-spawned enemies/pickups are registered automatically. Ray classification runs at 10 Hz, screen/range culled (45 m). Cosmetic particles/blood spawns do not rebuild the registry. Shader reconstructs depth separately for Compatibility OpenGL and Forward+ Vulkan. Silhouette copies share the actor mesh/skin/live skeleton and update on replaced body meshes. Shared resources are never mutated. Hole shader copies structural PBR parameters/textures; transparent glass/custom shader surfaces stay authored, not converted. Original overrides are restored exactly. Source shadows are retained.

## Automated checks

run_occlusion_tests.gd checks blocker classification (furniture excluded), late spawn/removal, both modes, five override-restoration cycles including a pre-existing material_override and null surface override, saved preference/reload, three actual planner cycles and real player mesh/skin/skeleton binding. Rendered execution checks each color, exposed original hero color, wall outside the circle, and visible-fragment rejection even when silhouette copies are forcibly enabled. Optional OCCLUSION_CAPTURE_DIR exports PNGs. CI runs both real rendering methods; fallback errors fail CI.

These checks use an isolated synthetic scene and software llvmpipe. They confirm rendering, not final art direction, Windows/Web exports or target FPS. No new dependency is added to the game.

## Manual route

1. In the same map, put the hero behind a full wall and then a column; rotate the camera and use minimum/maximum zoom.
2. Silhouettes: verify hidden portions of the hero, all enemy species including Horde summons, a dropped weapon, a medkit and ammo. Visible portions retain their color; dead enemies do not reveal. Walk away from blockers and verify highlights disappear.
3. Hole: verify the hero and nearby floor are revealed; the rest of the wall remains solid, furniture is not cut, collisions and direct shadows are unchanged. Move around the column and corners; inspect the dithered edge at native resolution.
4. Switch while paused, resume, enter/exit Planning mode repeatedly; load/save a map and restart. Choice persists and materials do not remain cut in the planner.
5. Repeat in native Windows Forward+ and desktop browser Compatibility. Record resolution/device/CPU and GPU time for both modes in the same populated fight. 60 FPS remains a separate acceptance item.

Known boundaries: only opaque BaseMaterial3D structural surfaces are converted for the hole; custom shader/transparent glass surfaces retain their source materials. The first pass uses 10 Hz blocker checks (up to 100 ms activation delay) and a two-metre radius, subject to manual adjustment. No gameplay damage, targeting, picking or collision changes.

Changed files: bootstrap main/planning hooks, menu_preferences/menu_dialog, occlusion_effects/subject/wall_materials + two shaders, run_occlusion_tests; translations; classification groups in structural wall/column/door/window scenes and public health/ammo scenes; three module manifests; runtime workflow; ADR-0023, architecture and continuity docs. No architecture exception.
