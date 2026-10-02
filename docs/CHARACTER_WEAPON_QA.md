# Визуальная приёмка персонажа и оружия — Godot 4.7.2

Canonical GLB сохранены; gameplay weapons остаются в AimPivot. Игрок владеет
stance/таймерами, shared driver — playback. Форматы карт и баланс прежние.

## Подтверждённый импорт

- Body/TacticalGuardian_Humanoid_014/Skeleton3D; RightHand index 31.
- Socket: Body/TacticalGuardian_Humanoid_014/Skeleton3D/RightHand/WeaponSocket_R.
- AnimationPlayer: Body/AnimationPlayer. 52 клипа; основные Idle импортируются
  без `_Loop`, суффиксы `.001/.002` становятся `_001/_002`.
- У всех четырёх weapon assets есть WeaponRoot, Grip_R, Grip_L, Muzzle.
  EjectionPort в GLB отсутствует, public fallback сохранён.
- +X authored Muzzle переводится в -Z public marker. Body model front = +Z.

## Маршрут

1. Проверить высоту ног и capsule-floor контакт: новый Body без Y=-0.9;
   камера, aim, движение и коллизия не изменены ради визуального меша.
2. Shotgun → Pistol: ONE_HAND. Первый успешный выстрел ONE_HAND, второй
   через <2 с TWO_HAND. Через >=2 с следующий снова ONE_HAND.
3. Повторить с Uzi: первый реально выпущенный bullet ONE_HAND, второй TWO_HAND;
   удержание кнопки, cooldown, reload и пустой магазин не считаются выстрелами.
4. 20 с полного бездействия Pistol/Uzi → LOWERED. Mouse jitter не сбрасывает
   таймер. Mouse movement/WASD/fire/reload/switch/roll/Q/E поднимают ONE_HAND.
   Пауза не расходует таймер. Fire не задерживается из-за blend 0.12.
5. Shotgun и Launcher всегда TWO_HAND и никогда LOWERED. Проверить правую
   ладонь у основного хвата, левую у Grip_L. При плохом хвате записать точный
   клип/кадр; IK остаётся follow-up после оценки authored animation.
6. Проверить Forward/Backward/Left/Right каждого семейства при aim в четырёх
   направлениях, Q/E, диагональном WASD, sprint и roll. Нет axis chatter,
   двойного разворота Body или перемещения от root motion.
7. Оружие остаётся в правой кисти при ходьбе и переключении, старое скрыто,
   масштаб постоянен. Muzzle/flash на конце ствола, гильзы идут из fallback порта.
8. Проверить launcher pickup/drop и повторный подбор каждого оружия: те же
   модели на земле, верный слот/HUD/ammo; grenade появляется у authored Muzzle.
9. Повторить при потере контроля, мутации, restart и загрузке карты.
10. Проверить заражённых: прежние idle/walk/run и отсутствие player stance.
    Пройти маршрут в Windows и desktop Web, сравнить FPS с прежним вариантом.

## Ограничения

Headless не подтверждает визуальное прилегание ладони, отражение масштаба в
кадре, ориентацию всех meshes, плавность blend или FPS. Новые бронежилет,
рюкзак и наколенники не добавлялись. Старые вспомогательные art узлы с именем
__OLD_SOCKET_UNUSED__ не используются как крепления и не удаляются из GLB.

## Автоматическая проверка

Implementation 0a47a5c проверен Godot 4.7.2 в CI:
https://github.com/bageus/Infection-shooter/actions/runs/37024856817.
Все четыре обязательных validator, 250 resource references, Python workstation
(3), glass (1), scene-access (3), новый weapon presentation набор (0 failures),
12 прежних runtime-наборов и main 180 кадров прошли. Runtime без ошибок.
Editor import exit 0 с прежними отсутствующими palette1.png/couches.png и
конфликтом имени дублирующего Idle_Pistol_Down_001 в исходном GLB: импорт не
считается чистым. Эти ошибки присутствовали и до presentation-изменений в
inspection CI 37023172595. Canonical выбранные idle/walk доступны и проверены.

Следующее действие: открыть ветку в Godot 4.7.2 и пройти визуальный маршрут
выше; художественный хват/стопы/левую руку/FPS headless не подтверждает.
