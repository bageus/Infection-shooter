# ADR-0059: Запечённые следы стекла, стен и пола

- Status: accepted
- Date: 2026-10-18
- Owners: presentation.office_floor (пиксели), bootstrap.app (authored настройки/композиция), features.combat (подтверждённые попадания)
- Related modules: presentation.office_floor, bootstrap.app, features.combat, features.player, features.infected

## Context

Прямой запрос владельца: два glass atlas, сколы/мягкие потёртости стен и
колонн/пола, редкие следы шагов, трещины дисплеев, planner opacity/size, bake
и PR. Инкремент T004/Phase1/P1_LOGIC, без смены игрового владельца здоровья.

## Decision

Один floor-owned cache234 исходных96px RGBA8 cells (~8.3МиБ CPU), исходные
PNG и shared материалы неизменны. Прежние16 floor sections512px RGBA8+R8
получают два lazy256px слоя. Shader всегда смешивает damage→scuff→debris,
независимо от времени попадания. До56МиБ CPU+GPU вместо40МиБ; queue64,
2stamps+1section upload/frame, density4 на метровую ячейку каждого слоя.

Для стен/колонн/стекла/prop receivers — cache12 MeshInstance3D, две384×256
RGBA текстуры (damage/scuff), шесть128px face regions, до18МиБ CPU+GPU,
queue32,2stamps+1receiver upload/frame, density6 на face-grid cell. Один
material_overlay/pass на receiver, без Node/quad/тела на попадание. Локальные
bounds/нормали определяют UV, авторская общая texture не меняется. WeakRef,
visibility cleanup и LRU освобождают overlay; чужой overlay не заменяется.
Обе очереди пусты — processing выключен. Суммарно не более4 stamps и2
section/receiver uploads за активный кадр; внутри каждого число текстур
ограничено слоями. Память pages до74МиБ CPU+GPU плюс CPU source cache.

Glass4x2 impact/hole использует прежние GLASS_CENTERS для точного центра.
Transparent fracture sparse cells0/1/2/12 =1-1/1-2/1-3/4-1. Cell13 (4-2)
появляется в четырёх углах с поворотами0/1/2/3 один раз на живую страницу;
остальные cells могут добавляться редким маленьким impact. Прочность и
2–4 hits до shatter прежние. После shatter receiver очищен; overflow
пропускает визуальный штамп, не создаёт fallback quad. Display disable
оставляет тёмный receiver видимым, трещины исчезают при скрытии всего Visual.

Combat получает optional Callable из bootstrap; bullet/blast подтверждённая
геометрия передаётся floor без конкретной presentation зависимости. В полной
миссии bullet/scorch идут в bake; без collaborator standalone projected-mark
fallback совместим. Scorch сохраняет прежнюю soot alpha mask без белой каймы.
Пластырные сколы — wall/column, только мощное оружие, шанс18%; floor damage22%.
Пистолет/UZI не снимают штукатурку; редкий soft wall rub12%.

Player gait и distance-paced infected сообщают шаг через существующий impact
pool; не добавлен per-actor process/SceneTree scan. Max2 опорных rays/physics
frame,12% редких floor scuffs и max2stamps/frame. Не на базовом полу/над
проёмами следы не рисуются. По умолчанию floor scuff18%, wall scuff14% opacity.

Planner popup редактирует семь групп opacity0..1,size0.25..2 с preview.
Контролы явно относятся к новым следам; уже запечённые пиксели не пересчитываются.
Optional map-v8 surface_decals_v1 валидируется до clear/replace, сохраняется
в JSON/authored snapshot/signature и metadata baked scene. Absent→defaults.
Runtime пиксели не сохраняются. Public contracts описаны в трёх manifests;
это один визуальный инкремент на существующих edges, не отдельные сервисы.

## Rejected alternatives

- Node/Decal/quad на каждый выстрел: растут объекты и draw calls, нет bake.
- Bake в UV общего атласа: след повторяется на других моделях и гранях.
- Один слой пола: поздний скол закрывает старый мусор.
- Перерисовка всей истории всех stamps: лишняя CPU работа кадра.
- Ежекaдровое сканирование толпы ради шагов: новые постоянные расходы.

## Consequences

До12 дополнительных receiver overlay passes и ограниченная память; эффект
не бесплатный. LRU убирает старые следы,128px грани ограничивают мелкие детали
крупных окон. Bounds face projection может давать стыки на округлых колоннах
и поверхностях разной глубины. Новые следы не наносятся под столами/на верхних
площадках вместо опорной поверхности. Кровь и старые furniture wood marks
остаются отдельными прежними системами; текущий запрос не меняет их owners.

## Migration plan

Использовать5 уже загруженных владельцем PNG, добавить private bake/events
и lower floor layers. Внедрить callbacks в main, локальные glass/display
adapters, optional validated map field и planner controls. Карты без поля,
старые APIs/прочность, граф dependencies/Autoload/policy сохраняются.

## Rollback plan

Снять новые callbacks/UI/adapters, вернуть floor shader/bake по ADR0058.
Optional map field можно игнорировать/удалить при сохранении. Пользовательские
PNG не удалять; сохранения кампании и баланс миграции не требуют.

## Validation

Baked surface tests: реальные atlas pixels/alpha, независимые floor layers,
receiver budgets/LRU/idle/visibility, actual glass/monitor/TV, shatter, steps,
powerful eligibility и native shader. Planner suite: opacity/size/preview,
JSON/scene round-trip, signature/settings-only restore и malformed settings.
Существующие glass/material/office/combat/display/layout/planning regressions.
Iris Xe/Web аппаратный FPS проверяется отдельно от software native QA.

## Approval

Владелец явно перечислил atlases, события, слои, planner controls, bake и
«реализуй и создай PR». Additive contracts/optional DTO нужны для порученного
результата. Несколько adapters рассмотрены как один scope; новых владельцев,
dependencies, Autoload или архитектурных исключений нет.
