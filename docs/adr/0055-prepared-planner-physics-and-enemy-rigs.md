# ADR-0055: Подготовленная физика карт и постепенная сборка ригов

- Status: accepted
- Date: 2026-10-17
- Owners: bootstrap.app, features.infected, features.character_animation
- Related issue: #237

## Context

Save Layout записывал исходные позиции; resume пробуждал все свободные тела. Mission loader отдельно ожидал до10с/240ticks, пока число бодрствующих props уменьшится до600. Декоративные трупы создавали articulated physics после снимка карты. Rig damage geometry и индексация анимаций всех врагов строились синхронно в ready. Это подтверждённые пути кода, доля каждого в задержке на устройстве владельца пока не измерена.

## Decision

Bootstrap сохраняет владельца authored map и команды Save Layout/Save Map. Private settling scheduler проверяет collision volumes и симулирует контактирующие группы при paused gameplay, с прогрессом и порциями между кадрами. Целевой размер партии192; связанная контактами группа не разрывается, чтобы не получить опору на искусственно замороженном соседе. При незавершённой подстройке запись не публикуется. В Jolt supported тела с нулевой кинетической энергией могут повторять penetration recovery; после120ticks они переводятся в sleep. Падающее тело такой guard не проходит. Исходное пересечение пола маленькой частью корректируется перед симуляцией. Desk attachment baseline сбрасывается после неё, чтобы не применить перемещение второй раз. Материалы моделей не меняются; отдельный private helper показывает консервативные красные рамки с бюджетом8 объектов/кадр и немедленной проверкой выделенного.

DTO v8 получает optional settled_physics={version:1}; позиции/вращения прежние. Метка применима к сохранённому transform и инвалидируется при его изменении. Загрузка восстанавливает динамические props спящими, сохраняя collision/mass и возможность пробуждения взаимодействием. Архитектурные и настенные freeze-состояния не меняются.

Infected сохраняет владельца позы декора. Optional decor_pose.physics_v1 содержит version1, body transform (12 finite компонентов) и local bone transforms по именам костей. Поза восстанавливается до игры, без нового simulator; конечности остаются shootable. Подготовка использует прежний ragdoll guard с коротким planner-only busy limit, затем сохраняет local poses, останавливает/освобождает физические кости и signal connections. Повторная подстройка после редактирования создаёт свежие bones/guard. Публичные prepare_planner_physics/finalize_planner_physics обслуживают команду bootstrap.

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
