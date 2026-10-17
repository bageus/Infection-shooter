# ADR-0056: Активные ветки мутаций и два назначения

- Status: accepted
- Date: 2026-10-17
- Owners: features.infection, features.player, features.infected, bootstrap.app
- Related issue: #245

## Context

Владелец заменил12 самостоятельных активных навыков четырьмя ветками, в каждой
первые два уровня и один из двух взаимоисключающих вариантов третьего.
После уточнения утверждены независимые cooldown5/6/8с, начиная после конца
эффекта; Q/E для двух назначений и Z/X для камеры. Цены и пороги сохраняются,
Might занимает прежний этап Toxic Mutation. Passive Claws: один удар каждые3с,
радиус1,5м; Berserk сохраняет параметры. Прочие числа — issue245.

## Decision

Infection сохраняет владельца learned/locked/бюджета/таймеров. Catalog содержит
16 узлов активных навыков (четыре кандидата на ветку),23 пассивных/гибридных.
Первые два приобретённых активных навыка заполняют два свободных назначения;
прокачка заменяет ID той же ветки в слоте без перезаписи ручного выбора.
Назначение предыдущего уровня и дублирование ветки запрещены. Неэкипированный
навык не кастуется через публичную команду. Forgotten очищает слот, locked
dormant сохраняет. Возврат доступности запускает полный cooldown. Готовность
экипированного навыка сообщает прежний signal skill_cooldown_finished один раз.
Core audio сопоставляет этот event с новым authored taking_skill.wav.

Private active_skill_state отделяет назначения и последовательность
effect→cooldown от mutation_tree правил. Skill_requirements DTOv3 добавляет
active/level/alternative/cooldown, чтобы UI не зависел от позиции в массиве12.
Публичные equipped_skills/assign_skill/assignable_skills описаны в manifest.
Extensions откладывают recovery, крупный delta переносит только излишек времени
за концом эффекта. Passive cooldown reduction не сокращает длительность эффекта.

Player применяет отдельный private active_mutation_effects. Damage аур
интегрируется по времени с ограничением остатком длительности; молния наносит
фиксированный урон повторным целям, максимум6/8/10 попаданий, дистанции8/3м.
Power Strike использует фронтальную трапецию длиной3м, ширина1→3м.
Infected private mutation_status владеет collision-limited движением к
конечной точке (метры), poison duration и причиной смертельного DOT. Только
сам DOT от infection-final вызывает однократный взрыв40/4м; смерть от пули
во время отравления не вызывает его. Взрыв не накладывает заражение.
Root infected600 reviewed: выделены status методы вместо роста root.
Player dash0,4с/6м отключает только collision со слоем врагов, сохраняет стены,
останавливает движение при препятствии без закрытия damage window и восстанавливает
исходную маску. Вертикальная floor recovery не расходует горизонтальный путь.

Bootstrap сохраняет владельца UI/input preferences. Новый private loadout UI
показывает два выбора над деревом. Финальные узлы рисуются развилкой; HUD
содержит только два назначенных значка. Названия/описания/параметры RU/EN
обновлены. Старые default Q/E+4/5 мигрируют в Z/X+Q/E, custom layout сохраняется.
Version marker active_layout_version2 находится внутри прежнего controls_v1;
устаревшие skill_3/4 больше не применяются и удаляются при сохранении.
Roots tree UI/player effects >300 reviewed: новые обязанности выделены в
private helpers, исключений source-size нет.

## Alternatives considered

- Один общий таймер двух навыков отклонён владельцем; независимые таймеры.
- Автовыбор любых четырёх learned skills по порядку каталога не соответствует
  явным двум назначениям и отменяет ручной выбор.
- Запуск recovery одновременно с аурой даёт наложение6с эффекта и короткого
  cooldown; владелец явно выбрал начало после завершения.
- Импульс скорости вместо метров не гарантирует утверждённую дистанцию.

## Migration plan

Карты, props, gameplay persistence и DTO антидота не меняются. Существующих
persisted gameplay snapshots дерева нет (ADR0047). Старые retired IDs при
reconcile очищаются прежним механизмом; сохранённые настройки custom keys
не перезаписываются. New public commands/DTOv3 аддитивны, прежние runtime
команды сохраняются с новой согласованной eligibility. Смена owners,
dependency edges, Autoload или исключения policy отсутствуют.

## Rollback plan

Revert PR возвращает каталог/механики/UI. Controls defaults можно сбросить
в настройках. Карт и пользовательских map files миграция не затрагивает.

## Validation

Новые active_skill_state, active_mutation_effects, mutation_status,
mutation_dash_motion и active_loadout_ui suites регистрируются в CI.
Проверяют mutual exclusion в обе стороны, slots/auto-upgrade/custom selection,
dormancy/reactivation/cooldown/extension/coarse delta, точные damage/radii,
реальные collision/distances, DOT-only explosion, input migration и teardown.
Старые тесты retired active skills обновлены под согласованные механики;
пассивные/гибридные проверки сохранены. Полный runtime/editor/project gates
выполняются отдельно, результаты в QA/PR. Native Windows/Web/Iris Xe
и прослушивание authored taking_skill требуют ручной приёмки.

## Approval

Владелец уточнил шесть вопросов и прямо поручил реализацию17.10.2026.
Additive контракты обеспечивают утверждённые два слота/метры/причину DOT;
архитектурных исключений нет.
