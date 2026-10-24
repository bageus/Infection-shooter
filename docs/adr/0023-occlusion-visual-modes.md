# ADR-0023: Two testable occlusion visualization modes

- Status: accepted
- Date: 2026-10-05
- Owners: bageus
- Related modules: bootstrap.app, presentation.office_floor, features.pickups

## Context

The owner requests in-game switching between hidden hero/enemy/item silhouettes and a localized hole through walls/columns around the hero. Main updates are authorized by the working agreement. This is visual presentation within T002, without changing combat, collision or authored materials.

## Decision

Bootstrap owns the mode, transient mesh copies and material overrides. An additive integer occlusion_mode in interface_v1 defaults to 0 (silhouettes), 1 selects the hole; invalid values clamp. No map DTO changes. Settings apply immediately while paused and persist through restart. Planner suspends effects without changing the preference.

Public structural roots gain occlusion_visual_v1 classification group camera_occluder; public health/ammo roots gain occlusion_items. Existing infected and weapon_pickups classifications remain. These identify injected composition descendants, never locate services. No new dependencies, singleton or architecture exception.

A single controller checks camera rays at 10 Hz, excluding actors/furniture; only structural blockers activate effects. Silhouette copies share live meshes, skins and skeletons, cast no shadows and compare reconstructed scene depth to color only hidden fragments. Colors: cyan hero, red enemies, amber items. Hole radius is 2 world metres projected around the hero; only front structural surfaces are cut. Its dithered edge has a faint cyan ring. Runtime PBR shader copies leave shared resources untouched and restore original overrides exactly on mode switch/planner/teardown. Floor and furniture never get hole materials. Shadow passes preserve wall geometry.

## Alternatives considered

- Hide whole walls: loses the local opening and causes large pops.
- Disable depth globally on actors: colors visible parts and draws through unrelated geometry.
- Modify imported models or shared materials: violates scope and contaminates later scenes.
- Renderer-specific compositor/stencil extension: unnecessary platform dependency.

## Migration plan

Absent interface_v1 field uses mode 0; maps remain unchanged. Existing scenes instantiate the public roots with their groups automatically. No user map rewrite.

## Rollback plan

Revert the commit to remove the effects/UI/classifications. Unrecognized config fields are ignored by the old preferences reader. Authored material resources and colliders are unchanged.

## Validation

Runtime tests exercise modes, blockers, dynamically added subjects, restoration, persistence and planner cycles. Rendered tests must exercise hidden versus visible fragments and the opening in actual Compatibility and Forward+; headless does not validate shader output. Windows/browser gameplay acceptance and frame budget in the fully furnished level remain manual.


## Уточнение владельца: просвет только для героя — 24.10.2026

Реальное вырезание стены/крышки тумана открывало раковины и потолочные
светильники. В mode=1 геометрия стен сохраняет непрозрачность и depth;
локальная линза только затемняет стену. Отдельная копия героя разделяет mesh,
skin, skeleton и morph weights, копирует стандартные PBR параметры/текстуры,
проверяет исходный scene depth и рисует перекрытые фрагменты перед преградой.
Clip-space depth сжат к ближней плоскости с сохранением относительной глубины
частей героя; LIGHT_VERTEX сохраняет авторское положение для освещения.
Проход ограничен основной камерой и не отбрасывает тени.

Туман не вырезается: в пределах активной линзы depth test его маски
перекрывает также потолочные элементы выше самой плоскости тумана.
Маска depth не записывает; настоящий проход через дверь/стекло остаётся.
У героя есть force flag для покрытия туманом, не пишущим scene depth.
Mode=0 сохраняет прежние цветные силуэты; mode=1 не создаёт копий врагов,
предметов или потолочных объектов. При нормальном обзоре копия героя скрыта.

Новых viewport/обхода мебели/коллизий/DTO/зависимостей нет. Изменяется только
визуальный контракт уже согласованного режима; запрос владельца разрешает
ограничить просвет героем. Откат — revert PR, настройки 0/1 совместимы.
Шесть фиксированных wall/hero shader variants включены в прежний warm-up.
Native GL Compatibility и настоящий Forward+/Vulkan проверяются новым
run_hero_xray_tests с пиксельными проверками и запусками в CI.
