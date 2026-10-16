# Следы выходной крови и лужа тела — 16.10.2026

T004/Phase1. База mainc6fa0d0a и непоглощённый им инкремент PR217/7f0c18f8.
Изменения карты/лестниц/авторского audio и прочие main commits сохранены.

## Результат и файлы

- Combat: prototype_bullet и public/impact_effects сообщают один optional
  penetration_blood факт для подтверждённого flesh exit. Снимок excluded RID
  фиксируется в момент этого выхода, а не после следующих контактов: уже
  пробитый пулей деревянный предмет сзади остаётся receiving surface для крови.
- Office-floor: public/blood_effects_3d.splatter_exit и private
  blood_exit_splatter используют существующие projected surfaces/budget/anchors.
  Три направления (axis, ±0,22rad), дальность1,2–3м и масштаб0,7–1,6 по энергии;
  если поверхность в веере не найдена — floor fallback в0,4–1м впереди.
  Мебель/перегородка/стена — один и тот же механизм receiving surface.
- Infected: private corpse_blood_pool читает Hips/Chest только внутри своего
  модуля, ждёт короткую остановку корпуса, сообщает blood_pool_ready один раз.
  Нет rig — fallback; early removal — последняя точка; pause останавливает timer;
  максимум2,2с. Root599 строк: lifecycle delegation, существующий чистый
  _blood_exclusions упрощён без временной переменной. Владельцы не перенесены.
- Bootstrap main добавляет две scene-local подписки/выбор правильного события:
  infected pool по blood_pool_ready, player/legacy по прежнему blood_death.
  Немедленный death fact для других потребителей сохранён.
- Лужа использует прежний death_id dedup и floor normal, появляется под
  сообщённым фактическим центром корпуса; footprint увеличен до1,5–2,2м,
  delay0,05–0,15с. Growth1–3с прежний: decal/quad расширяются, clipped projection
  в Compatibility появляется через fade-in. Физику и урон это не меняет.

Public additive signatures/три manifest и ADR0051 обновлены. Owners/dependency
edges/DTO/сцены/сохранения/ассеты прежние. Root main>300 reviewed как composition;
прикладная проекция вынесена в office_floor helper. Архитектурных исключений нет.

## Проверки

Godot4.7.2 headless/Dummy,11 разных suites PASS:

1. `run_exit_blood_surface_tests` (новый bootstrap): настоящая пуля и живой
   публичный infected; wall receiver, пробиваемый деревянный receiver, локальное
   следование при перемещении мебели, no surface/no floating mark. Настоящий
   мёртвый infected: blood_death остаётся немедленным, затем ровно одна лужа
   на полу с X/Z в0,05м от reported torso point и footprint>=1,5м.
2. `run_corpse_blood_pool_tests` (новый infected): moving Hips/Chest не создают
   преждевременный pool; settle даёт точный midpoint; id/RID сохранены;
   pause/fallback/early deletion и отсутствие double event; непрерывное
   движение ограничено max observation window.
3. `run_blood_effects_tests`: прежние normals/projection/moving anchors,
   dedup после удаления enemy, clear, lifetime, side splatter, growth/depth.
4. `run_blood_events_tests`: прежние damage и немедленные death semantics.
5. `run_penetration_exit_tests`.
6. `run_body_penetration_tests`.
7. `run_projectile_step_budget_tests`.
8. `run_gameplay_planner_repairs_tests` (full-map startup/restart, wiring).
9. `run_ragdoll_budget_tests`.
10. `run_blood_floor_bake_tests`.
11. `run_blood_dormant_tests`.

Новые suites включены в существующий runtime CI. Import editor и project/spec/
workflow/architecture/source-size/scene resources/diff gates PASS. Финальные
runtime/editor логи без SCRIPT ERROR/ERROR/ObjectDB leak warnings; остаётся
предупреждение среды об отсутствии `/proc/self/exe`.

## Ограничения и следующая проверка

Dummy не проверяет художественную читаемость/пиксели. Нужна ручная приёмка
Compatibility/Windows/Web: кровь на стенах/стекле/мебели и под разными размерами
врагов, очереди, ragdoll/clip fallback, Q/E, новое/старое освещение. FPS не
измерялся. Blood fan ограничен геометрией/дальностью и не симулирует столкновение
каждой GPU-капли. Постоянно движущееся тело оставляет лужу в sampled point к2,2с;
уже пролитая кровь за ним не перемещается. Проекция при отсутствующей или
удалённой поверхности пропускается; бюджеты могут отложить/вытеснить следы.
PR217 был слит до публикации7f0c18f8: этот инкремент с выходными эффектами
будет опубликован отдельным PR. Следующее действие — CI и визуальная приёмка;
merge не поручен.
