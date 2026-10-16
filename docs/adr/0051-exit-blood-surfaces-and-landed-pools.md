# ADR-0051: Следы выходной крови и лужа под упавшим корпусом

- Status: accepted
- Date: 2026-10-16
- Owner: bageus
- Modules: features.combat, features.infected, presentation.office_floor, bootstrap.app

## Контекст

Владелец запросил следы от выходных брызг на стенах, перегородках и мебели,
а после падения тела — кровь под ним и вокруг. Exit particles из PR217 не
сообщали renderer о выходе. Старый blood_death содержит предполагаемый landing,
который может отличаться от фактического положения ragdoll.

## Решение

Существующий combat impact_effects добавляет typed optional факт
`penetration_blood(position, direction, energy, excluded: Array[RID])`.
Bullet сообщает его после достижения подтверждённого flesh exit. Exclusions
снимок фиксируется отдельно для каждого выхода; последующие пробитые предметы
не исключаются из уже сформировавшейся струи крови. Bootstrap соединяет факт с
`BloodEffects3D.splatter_exit`, office_floor сохраняет владельца surface queries,
проекции, local anchors, mark budget и baking. Private helper делает веер трёх
лучей, либо один floor fallback, размер и дальность растут по энергии.

Infected добавляет compatible факт `blood_pool_ready(position, excluded,
death_id)`. Private дочерний corpse_blood_pool наблюдает среднюю позицию Hips и
Chest Timer-ом0,1с, не раньше0,5с и до2,2с, считая0,3с без значимого смещения
остановкой. Отсутствие rig использует прежний прогноз. Раннее удаление сообщает
последнюю точку один раз; WeakRef не удерживает тело. Таймер подчиняется паузе.
Немедленный blood_death сохранён для существующих слушателей.

Bootstrap для источников с новым фактом подписывает pool только на него;
player/legacy остаются на blood_death. Office_floor создаёт одну лужу прежним
deduplicated death budget с большим footprint1,5–2,2м и короткой задержкой
0,05–0,15с. Прежние способы появления: рост decal/quad или fade-in clipped
projection в Compatibility. Depth/attachment/baking прежние.

## Альтернативы

- Combat обращается в renderer или ищет сервис: нарушает направление слоя.
- Вызвать splatter_hit для выхода: теряется remaining energy и применяется
  throttle входных попаданий; выходные следы могут пропасть.
- Увеличить только старую лужу в predicted landing: не следует фактическому
  смещению ragdoll. Позиция костей остаётся внутри владельца infected.
- Урон/физика на каждой капле: не нужны для визуального результата; bounded
  веер использует существующую систему blood surface.

## Последствия и ограничения

Additive public signatures отражены в трёх module.json. Owners, dependency
edges, Autoloads, карта/сохранения/DTO прежние; архитектурных исключений нет.
Exit mark requests живут в прежней очереди64/32; admission сохраняет бюджет220.
Geometry projection и anchors остаются office_floor-owned. Новый infected
helper существует лишь в коротком окне падения. Вечно движущийся ragdoll
сообщает позицию к2,2с; дальнейшее смещение не передвигает уже пролитую кровь.
Нет receiving surface — нет летающей лужи/декали. Старые death facts совместимы.

## Миграция и откат

Миграции нет. Применить оба producer факта, consumer и bootstrap wiring вместе.
Откатить эту группу файлов/manifest/ADR: прежние death_pool/splatter_hit
сигнатуры и ассеты сохранены, gameplay урон/пробитие/смерть прежние.

## Проверка

Новые end-to-end bullet→wall/furniture marks, проходимый деревянный receiver,
local movement anchor, отсутствующая поверхность, настоящий умерший enemy,
положение пола под reported torso, один pool footprint>=1,5м. Helper tests:
движущиеся кости, settle/max timeout, pause, fallback, early deletion/idempotence.
Прежние blood projection/baking/dormancy, blood events, ragdoll budget,
projectile step budget и gameplay wiring. Подробности QA в
`docs/qa/exit_blood_surfaces_and_corpse_pools.md`.

## Approval

Владелец прямо запросил оба визуальных поведения16.10.2026 в этой беседе.
Совместимые факты добавлены только для связи этих существующих владельцев;
новой ответственности глобального сервиса или изменения dependency policy нет.
