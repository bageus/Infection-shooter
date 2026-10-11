# ADR-0038: Винтовки, комплект минигана и увеличенный прицел

- Status: accepted
- Date: 2026-10-08
- Owner: bageus
- Modules: features.combat, features.player, presentation.prototype_hud, bootstrap.app

## Контекст

Владелец поручил подключить исправленные weapon pack v2 модели, четыре новых pickup, двухручные винтовочные стойки от Launcher, низкий хват минигана и комплектный рюкзак. Новые GLB имеют другую систему осей и длиннее прежнего launcher; простое крепление оставляет поддерживающую руку вне цевья.

## Решение

Combat сохраняет ammo/cooldown/reload/projectiles. Публичный набор сцен аддитивно получает ak_rifle, m4_rifle, sniper_rifle, minigun; индексы 0–3 прежние, новые 4–7. Новые параметры authored scene: прямое питание из reserve, casing multiplier, view bonus, scope magnification, выравнивание grip. Все четыре используют ammo_automate и 12_rifle_casing; sniper/minigun увеличивают гильзу ×1.15 через существующий casing_v1. Запас mini 400, reload запрещён, HUD показывает TOTAL. Rifle fire — существующая лицензированная запись одиночной винтовки; M4/mini — assault_rifle_fire.

Player сохраняет equipment/camera/stance. Приватный SkeletonModifier3D подгоняет две руки к реальным Grip_R/L без изменения длин костей, после базового Launcher-клипа и до torso aim. Миниган использует более низкое положение руки на животе. Gameplay weapon остаётся прямым ребёнком AimPivot: shooter и casing hierarchy не меняются. Рюкзак следует Spine и виден только при экипированном mini; pickup/drop показывает лишь пулемёт, атомарно экипируя весь комплект.

Новый совместимый weapon_view_v1 на существующей public/player.tscn: `get_weapon_view() -> Dictionary {camera: Camera3D, target: Vector3, magnification: float}`. Это transient read-only данные, без сохранения. Bootstrap внедряет игрока в public/crosshair.tscn через `configure(actor)`. HUD owns только локальную оптическую картинку: 224×224 SubViewport с тем же World3D, реальным увеличением FOV 2.5× и круглой маской; при другом оружии или скрытом HUD rendering отключён. Увеличение включается при выборе sniper, как отдельно подтвердил владелец. Камера player расширяет расстояние +3 м у AK/M4/mini и +8 м у sniper, поверх сохранённого пользовательского zoom; переключение возвращает прежний обзор.

Новых зависимостей, state owners, Autoload, map/save/network форматов и architecture exceptions нет. Manifests отражают новые сцены и runtime queries.

## Альтернативы

- Переподчинить оружие рукам: нарушает существующий shooter parent-chain.
- Рисовать увеличенный прицел без оптического изображения: не выполняет запрос приближения.
- Подключить внешний IK/animation plugin: лишняя зависимость; достаточно существующего SkeletonModifier3D.
- Второй ammo counter mini: нарушает прямое питание из 400 reserve; используется прежний единственный combat owner.

## Миграция и откат

Runtime GLB размещаются в каноническом weapons/; URI карт адаптированы к weapons/textures/. Исходный импортированный владельцем pack остаётся под models/ с .gdignore, scripts/previews/sources/master_4k также исключены; CSV — под ignored sources. Canonical pistol возвращён из pistol_lowpoly(2).glb. Старые сцены и IDs сохранены. Откатить данный коммит целиком; старые slot/map DTO остаются читаемыми.

## Проверки и риски

Новый run_new_weapon_tests: повреждение/spread/capacity, 4 sniper выстрела/reload, все 400 mini выстрелов без reload, реальные projectile IDs, socket/grip, reachable supporting hand, backpack lifecycle, pickup без рюкзака, world/FOV scope и native red-target pixel assertion. Старые weapon presentation, casing, cursor aim, mutation stats, HUD/icons и main smoke сохраняются. Прицел добавляет второй малый render view только для sniper; FPS на целевом Web/Windows требует отдельного замера. Нативные pixel-проверки выполняет существующая CI в Compatibility и Forward+.

## Approval

Прямой запрос владельца 08.10.2026 разрешает новые оружия, поведение и визуальный прицел; отдельно подтверждено включение scope при выборе винтовки. Расширение публичных runtime queries минимально для этого поручения; направление зависимостей прежнее.
