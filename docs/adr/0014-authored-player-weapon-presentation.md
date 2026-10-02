# ADR-0014: Авторское крепление оружия и выбор анимации игрока

- Status: accepted
- Date: 2026-10-02
- Owner: bageus
- Modules: features.player, features.combat, features.character_animation

## Контекст

Canonical GLB уже содержат новую модель, RightHand/WeaponSocket_R, WeaponRoot,
Grip_R/Grip_L/Muzzle и семейства стоек. Старые wrappers используют отдельные
offsets и повороты; общий драйвер выбирает только idle/walk/run по подстроке.
Переподчинение gameplay weapon nodes скелету ломает shooter parent-chain и
SpentCasings. Player movement уже 370 строк: новые обязанности разделены.

## Решение

Оружие остаётся прямым ребёнком AimPivot. Player-local WeaponMount использует
authored socket и RemoteTransform3D для активного weapon root; update_scale=false.
Перед выстрелом дополнительно синхронизируется уже известный socket transform.
Combat-local настройка один раз нормализует Visual относительно WeaponRoot и
переносит authored Muzzle в существующий public Marker3D. В этих GLB ствол
направлен вдоль +X: basis маркера переводится в игровой -Z. При отсутствии
authored EjectionPort сохраняется старый маркер. Pickup использует те же GLB.

Стойкой владеет features.player: маленький RefCounted считает только successful
shots и gameplay delta; отдельный selector преобразует velocity в aim-local
пространство с hysteresis. Слоты, патроны, cooldown, projectile physics, баланс,
коллизия и input names прежние. IK и root motion не добавляются.

Единственное совместимое public дополнение animation_selection_v1:

`configure_clip_selector(selector: Callable) -> void`, где `selector() -> StringName`.

Selector задаёт только имя клипа. Повторная передача того же selector обновляет
выбор немедленно (например, перед fire), без повторной настройки библиотеки.
Драйвер проверяет существование клипа и использует blend 0.12. Без selector
поведение заражённых прежнее. Loop-настройки применяются к instance-owned
копиям ресурсов, не изменяя общие импортированные AnimationLibrary/Animation.
Новых зависимостей и обратного character_animation -> player ребра нет.

## Альтернативы

- Перенос оружия в Skeleton3D: ломает работающий combat parent-chain.
- Состояние стойки внутри общего драйвера: смешивает gameplay activity с
  воспроизведением заражённых и создаёт скрытую зависимость от Player.
- Копия всего shared driver в Player: дублирует playback и поиск AnimationPlayer.
- Runtime IK: не нужен до визуальной проверки авторских two-hand клипов.

## Миграция и откат

Canonical art paths остаются прежними. Удаляются старые offsets оружия и
Body Y=-0.9: меш нового персонажа центрирован относительно капсулы.
Новый персонаж смотрит вдоль +Z; Body.look_at использует use_model_front=true,
AimPivot сохраняет -Z. Начальный Body yaw 180 соответствует начальному aim.
Root/Visual transforms нормализуются в combat wrapper, не в Player movement.
Новых save/network DTO нет. Откатить весь presentation-коммит и ADR/manifest;
исходные GLB и карты менять не требуется.

## Риски и проверка

Импорт Godot убирает `_Loop` у основных Idle клипов; selector использует
проверенные импортированные имена. Крепление руки, масштаб, левая ладонь,
ориентация и crossfades требуют визуальной QA на движущемся персонаже.
Числовые тесты проверяют wiring, а не художественную точность хвата.
validate_project, все существующие runtime suites, новые stance/scene tests
и main 180 frames; Windows/Web visual QA по CHARACTER_WEAPON_QA.md.

## Approval

Владелец 02.10.2026 подтвердил показанный план, включая небольшое публичное
расширение animation driver. Это продолжение T002, без второго активного task.
