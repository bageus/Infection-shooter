# Отдача и дым попаданий — issue #219

План: private player recoil state хранит оставшееся микросмещение, successful-shot seam
добавляет импульс от muzzle, movement расходует его collision-checked шагом.
0,5–2,5 см за выстрел, ограничение остатка 8 см; recovery 45 мс, без движения вперёд.
Infected chase_pace хранит краткий speed penalty до 15,4%, восстановление примерно
за 0,16 с; strength зависит от damage/max_health, не оставшегося HP. Существующий
notify_hit двигает только корпус; Hunger использует directional spring для пуль.
Combat impact_effects владеет bounded smoke runtime: до 16 пучков по 3 частицы,
не более 2 новых пучков за physics frame, lifetime 0,45 с. Только успешная проекция
bullet mark, без света. Bootstrap хранит optional interface_v1.bullet_impact_smoke
(default true), применяет к существующему ImpactEffects; Video RU/EN toggle.

Scope: player movement/private state, infected pace/root/Hunger, animation spring,
combat bullet/impact/private smoke, bootstrap preferences/settings, translations,
combat manifest, ADR, tests/CI. Owners/dependency edges прежние, DTO карт и gameplay
saves прежние. Новое additive свойство combat и необязательный preference key
обслуживают прямой запрос владельца; новых внешних зависимостей нет.

Decomposition review: player 544, infected 599, main 383 и animation driver >300.
Recoil/smoke state вынесены в private helpers; roots получают только wiring.
Infected pace уже владеет transient chase speed; penalty расширяет эту обязанность.
Driver/main не расширяются. Hard limit 600 сохраняется.

Риски: накопление очереди, dry fire/spin-up, низкий FPS/смена направления, стена
за спиной, Hunger overlay, LOD clocks, смерть/DoT, переключение во время миссии,
старый/неправильный конфиг, particles teardown и плотный shotgun/minigun.
## Реализация и проверки

Сила корпуса: clamp(damage / (0,2 × maxHP), 0,12, 1,1); угол ограничен14°,
накопление angular velocity ограничено. Ноги сохраняют текущую анимацию.
Hunger использует directional spring вместо недирекционного hit clip при попадании
пули. Краткий penalty равен strength×0,14, берётся максимум (не сумма), убывает
на0,95/с независимо от AI LOD; health damage менее1 не добавляет drag.

Новые run_shot_recoil, run_hit_drag и run_bullet_smoke зарегистрированы в canonical
CI manifest. Headless Godot4.7.2: все13 целевых suites завершились с0failures:
shot_recoil, hit_drag, bullet_smoke, shooting_camera, weapon_presentation,
roll_iframes, hit_reaction, hunger_behaviour, enemy_lod, settings_tabs, menu,
penetration_exit, projectile_step_budget. Menu дополнен проверкой smoke-off
на реальном start/restart; повтор menu и shot_recoil после последней правки тестов PASS (0 failures),
включая движение игрока и реальный restart. Итоговые результаты записаны в ACTIVE_TASK.

Новые tests проверяют collision wall/освобождение остатка, successful/dry/cooldown/
spin-up, направление muzzle, dt-independent state, накопление, ходьбу; реальных
Hunger/Titan, bounded slowdown/recovery и отсутствие обновления от tiny DoT;
реальную проекцию bullet mark, отсутствие receiving mesh, cap16/2frame,
clear/re-enable/expiry, legacy/malformed config и independent sparks setting.
Existing torso suite сравнивает плечи/таз/ноги с неповреждённым двойником.

Project/spec/workflow/architecture/source-size и CI coverage checks PASS,
scene_resources392refs PASS. Production player549/infected600/helper smoke64
строк; одно новое advisory предупреждение у длинного test fixture, hard limits
сохранены. Нет новых сцен/текстур/Autoload/зависимостей или архитектурных исключений.
Additive combat bullet_smoke_v1 и optional interface_v1 key описаны ADR0052.

Headless проверяет lifecycle/геометрию/направление и поведение, не видимость GPU
частиц. Native визуальная приёмка, FPS/Windows/Web не проверены. Следующее действие:
CI и визуальная проверка читаемости отдачи/дыма на слабом и мощном оружии.

