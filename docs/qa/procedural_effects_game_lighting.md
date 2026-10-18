# Процедурные эффекты, освещение и погоня — T004

Дата: 18.10.2026. База: `892c25a0f40688a64a92bd1d38f0f5d2a394d41c`.
Решение: [ADR-0059](../adr/0059-procedural-effects-and-game-lighting.md).

## Результат

- scream_zombie_1…5 уже отсутствуют в текущем main. Каталог, видовые профили,
  retired-event фильтр генератора и проверки звуков сохранены; удалённые
  записи не восстанавливаются.
- Навыки используют существующий процедурный комплект при любых старых
  значениях skill_effects. Выбор спрайтового backend и его код удалены.
  Новые active_aura/power_strike и механика issue245 сохранены.
- Взрыв использует огонь/искры/дым/обломки/вспышку без flipbook; длительность
  завершения дыма и игровой урон прежние. Мутагены уже были процедурными.
- Удалены оставшиеся в main6 PNG (12 604 060 байт) и6 import-файлов из fx_skills,
  mutagen, grenade_explosion_layers. Это исходные байты, не замер RAM/VRAM/FPS.
  UI-иконки, атласы декалей, бумага/искры/огнетушитель не удалялись.
- Звёзды оглушения — один разделяемый ArrayMesh из30 треугольников, без
  текстур/теней, с локальным вращением и окончанием вместе со статусом.
- В Video добавлен «Только игровое освещение» / «Game lights only» и подсказка.
  При включении убирает global directional, ambient source/energy и отражения
  неба. Сохраняет lamps/displays/gameplay effects. Master lighting управляет
  лампами как раньше; сохранённый sunlight временно перекрывается режимом.
  В комнате без игровых источников может стать темно — это ожидаемо.
- TextScale теперь в General; прежний ключ/значения и применение масштаба
  сохраняются. Новый game_lights_only отсутствует в старом cfg → false;
  неизвестный skill_effects больше не читается и не пишется.
- Chase pace постоянно возвращает скорость бега независимо от расстояния и
  времени. Тест проверяет80 секунд погони на четырёх дистанциях. Скорость
  при изменении move_speed учитывается сразу; hit/recover_hit сохранены.
  Атаки, препятствия, stun, слышимость и блуждание прежние; infected_capsule
  этим инкрементом не меняется. Стартовый крик/анимация Hunger сохранены.

## Проверки

Godot4.7.2, headless: **24/24 suites PASS**, итоговые логи без ERROR,
SCRIPT ERROR и resource-leak warnings. Сценарии охватывают reload настроек, состав вкладок, сочетание
master/sun/game-only, повторные входы/выходы планировщика, восстановление
окружения, lifetime VFX/stun, continuous chase, hit drag, новые active skills,
восприятие/блуждание/толпу, звуки и меню start/restart.

Импорт и статические gates выполняются на финальном коде. Дополнительно
проверяются check_resource_paths, check_export_pack, validate_ci_suites,
актуальность аудиоотчёта и18 unit-тестов генерации звуков.

## Границы проверки и rollback

Реальная картинка Windows/Web и FPS локально не измерялись; native CI сохраняет
существующие проверки рендеров. Зелёный headless результат не заменяет визуальную
проверку. Полный CI нового PR проверяется отдельно после публикации.

Owners/dependency edges/Autoload/карта/gameplay save/network DTO прежние;
архитектурных исключений нет. Публичные функции flipbook прежние, удаление
конкретных atlas constants и ассетов одобрено владельцем и описано ADR0059.
Откат — revert инкремента; старый cfg остаётся совместимым.


### Итоговый набор

- `run_status_fx_tests.gd` — PASS
- `run_hit_reaction_tests.gd` — PASS
- `run_enemy_voice_tests.gd` — PASS
- `run_infected_voice_tests.gd` — PASS
- `run_flipbook_tests.gd` — PASS
- `run_grenade_vfx_tests.gd` — PASS
- `run_skill_vfx_tests.gd` — PASS
- `run_settings_tabs_tests.gd` — PASS
- `run_global_lighting_tests.gd` — PASS
- `run_enemy_animation_tests.gd` — PASS
- `run_hunger_behaviour_tests.gd` — PASS
- `run_hit_drag_tests.gd` — PASS
- `run_enemy_perception_tests.gd` — PASS
- `run_enemy_idle_lod_tests.gd` — PASS
- `run_active_mutation_effects_tests.gd` — PASS
- `run_runtime_debug_tests.gd` — PASS
- `run_mutagen_cloud_tests.gd` — PASS
- `run_sound_event_tests.gd` — PASS
- `run_crowd_separation_tests.gd` — PASS
- `run_enemy_lod_tests.gd` — PASS
- `run_unaware_motion_tests.gd` — PASS
- `run_menu_tests.gd` — PASS
- `run_lighting_tests.gd` — PASS
- `run_light_budget_cache_tests.gd` — PASS

Editor import exit0 без ERROR/SCRIPT ERROR. Source_size/architecture/project,
scene_resources, resource paths, export source/pack audit, CI coverage175
(167 runtime+8 job registrations), audio report актуальность — PASS.
Audio generation —18 unit tests PASS. Diff-check PASS. Native/Web screenshots
и общий CI нового PR на момент публикации ещё не проверены.
