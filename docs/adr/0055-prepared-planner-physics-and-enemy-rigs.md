# ADR-0055: Подготовленная физика карт и постепенная сборка ригов

- Status: accepted
- Date: 2026-10-17
- Owners: bootstrap.app, features.infected, features.character_animation, presentation.office_floor
- Related issue: #237

## Context

Save Layout записывал исходные позиции; resume пробуждал все свободные тела. Mission loader отдельно ожидал до10с/240ticks, пока число бодрствующих props уменьшится до600. Декоративные трупы создавали articulated physics после снимка карты. Rig damage geometry и индексация анимаций всех врагов строились синхронно в ready. Это подтверждённые пути кода, доля каждого в задержке на устройстве владельца пока не измерена.

## Decision

Bootstrap сохраняет владельца authored map и команды Save Layout/Save Map. По уточнению владельца24.10 private scheduler симулирует всю подвижную локацию совместно при paused gameplay. Отдельные партии больше не фиксируются: верхний предмет не должен опираться на ещё замороженную будущую партию. Физические трупы участвуют вместе с props; поддержанные позы фиксируются после покоя мебели, затем вся мебель проверяется снова. Только после native sleep либо устойчивых скоростей/transforms публикуются final positions/poses и sleep stamps. При paused SceneTree sleep/kinetic state читается непосредственно из PhysicsServer3D. Для Jolt penetration recovery разрешён sleep только после120ticks минимальной кинетической энергии и подтверждённого верхнего контакта с StaticBody/frozen опорой; падающий предмет/подвижная опора не проходят guard. Начальное пересечение пола корректируется по collision bounds до симуляции; для BoxShape bounds считаются без debug meshes. При timeout/cancel запись не публикуется и исходные координаты как обходной snapshot не сохраняются; прежние JSON/backup/scene остаются нетронутыми. Status показывает ход подготовки. Лимит3600physics ticks/120с — аварийный выход, не критерий успешного сохранения. Desk attachment baseline сбрасывается после симуляции. Красные предупреждения сохраняют прежний bounded budget.


DTO v8 получает optional settled_physics={version:1}; позиции/вращения прежние. Метка применима к сохранённому transform и инвалидируется при его изменении. Загрузка восстанавливает динамические props спящими, сохраняя collision/mass и возможность пробуждения взаимодействием. Архитектурные и настенные freeze-состояния не меняются. Bootstrap устанавливает prepared transform metadata до ready; office_floor не выполняет повторный legacy подъём conference chair на2,5см. Root environment_prop выше300 reviewed: здесь только один guard в существующем scene adapter, geometry/debris остаются выделенными helpers.

Infected сохраняет владельца позы декора. Optional decor_pose.physics_v1 содержит version1, body transform (12 finite компонентов) и local bone transforms по именам костей. Поза восстанавливается до игры, без нового simulator; конечности остаются shootable. Подготовка использует прежний ragdoll guard с planner-only busy guard без таймера принудительной остановки, при подтверждённой опоре и покое мебели articulated pose фиксируется после180ticks (3с при60Гц), поскольку суставы могут продолжать вращение; неподдержанная падающая поза не считается готовой. Затем сохраняет local poses, останавливает/освобождает физические кости и signal connections. Повторная подстройка после редактирования создаёт свежие bones/guard. Публичные prepare_planner_physics/finalize_planner_physics обслуживают команду bootstrap.

Mission-local visual_preparation_budget принадлежит infected, камера внедряется bootstrap. Не более одной стадии animation/body_parts за кадр, до64 проверок weak refs, радиус40м в плоскости пола. Character animation получает opt-in defer_setup и idempotent prepare_visual; set_active сохраняется. Исходные meshes/rigs видимы, откладываются клипы, modifiers и damage geometry. Урон и обязательные one-shot timings подготавливаются синхронно. Без внедрённой очереди прежние сцены готовы немедленно. Новых owners, dependency edges, Autoload или глобальных реестров нет.

## Alternatives considered

- Повторять массовую подстройку за loading overlay: оставляет задержку каждого запуска, отклонено.
- Заморозить все props навсегда/скрывать дальних врагов и коллизии: меняет взаимодействия и бой, отклонено.
- Полный streaming meshes/skeleton resources: требует отдельного формата моделей; текущий запрос закрывается постепенной дополнительной подготовкой поверх существующих видимых моделей.

## Migration plan

Старые v1–v8 карты загружаются без изменений; Save добавляет optional payload. Валидатор до замены карты проверяет version,12 finite компонентов, невырожденный body basis, до256 костей. Для костей допускается authored scale0.0005 severed modifier, при этом нулевые/неfinite transforms отвергаются. Неизвестные имена костей игнорируются при совместимой замене модели. Baked scene сохраняет exported позу и transform metadata.

## Rollback plan

Revert возвращает старый runtime. Старый reader игнорирует optional поля; seed/pose/facing и прежние координаты остаются доступны. Загрузка никогда автоматически не переписывает пользовательскую карту.

## Validation

Новые regressions: падение/опора, восстановление поз всех костей через JSON, mutilated scales, embedded Horde part, sleep/resume/invalidation, actual map-file/capture/loader round trip, deferred collision/health/damage/timing, <=1phase/frame, weak teardown. Прежние planner/persistence/map/mission/corpse/animation suites, editor import и repository gates. После сброса временной среды финальные проверки повторяются; фактическая плавность Windows/Web/Iris Xe требует замера владельцем. Очередь предоставляет phases_completed/max_phase_usec для локальной диагностики.

## Approval

Владелец изучил план issue237 и прямо поручил реализацию, отдельную ветку и PR. Additive контракты и optional save payload служат этому результату. Исключений architecture policy нет; смены owners/layers/dependency directions нет.
