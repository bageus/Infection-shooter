# ADR-0057: Запечённая стеклянная крошка на базовом полу

- Status: accepted
- Date: 2026-10-18
- Owners: presentation.office_floor; bootstrap.app — только композиция
- Related modules: presentation.office_floor, bootstrap.app

## Context

Владелец выбрал первый прототип только для стекла и добавил атлас
`models/objects/textures/glass_decals/4x4 glass debris texture atlas.png`.
Нужно оставлять мелкую россыпь после разрушения без новых физических тел.
Compatibility/Web и слабая Iris Xe требуют ограничить память и работу кадра.
Базовый пол уже объединён в MultiMesh-секции 8×8 м с двумя вариантами материала.

## Decision

Office-floor сохраняет владение представлением пола и разрушений. Приватный
GlassFloorBake смешивает уменьшенные ячейки атласа в CPU Image через native
Image.blend_rect, затем обновляет не более одной ImageTexture за активный кадр.
16 секций по 512×512 RGBA8 занимают до 16 МиБ CPU + 16 МиБ GPU, дополнительно
ограниченные копии исходных ячеек и импортированный атлас. Mipmaps runtime
текстур отсутствуют. Очередь ≤64, максимум два штампа за кадр, плотность ≤4
штампов в метровой ячейке. Вытесняется секция, в которую дольше не писали.
После опустошения очереди и dirty секций floor callbacks выключаются.

BaseFloorRenderer изменяет только затронутые derived материалы. Шейдер
смешивает цвет и шероховатость по floor-local UV на верхних гранях; сам mesh
пола обрезает лестничные проёмы. Нет наложенных quad, z-fighting, дополнительных
рисующих вызовов, коллизий или Node на осколок. GlassFloorScatter размещает
штампы по реальной горизонтальной оси pane (в том числе открытой двери),
проверяет центр размещения лучом против соседних стен. Четвертьобороты и 16
вариантов дают вариативность без GDScript-растеризации каждого пикселя.

Additive glass_floor_debris_v1: bootstrap явно передаёт existing public Floor
через configure_glass_debris; structural root перенаправляет своему GlassBody,
environment_prop — private breakup. Break guards остаются прежними; трещины и
unbreakable exterior не дают россыпь. Существующие крупные физические фрагменты
не меняются. Clear layout и перестройка пола очищают transient слой; формат
карт/сохранений не расширяется. Owners, dependency edges и policy прежние.

## Alternatives considered

### Постоянные отдельные накладки или частицы

Легко добавить, но количество узлов/перекрывающихся поверхностей растёт.
Отвергнуто для накапливаемой мелкой крошки.

### SubViewport с накоплением

Даёт произвольное вращение на GPU. Для первого прототипа native CPU blit проще
проверять в headless, не требует retained framebuffer/readback и имеет жёсткие
границы работы. При измеренной проблеме upload можно отдельно сравнить GPU.

## Consequences

### Positive

- Новое мелкое стекло не добавляет физику или draw calls.
- Память, очередь и число обновлений ограничены, idle обновлений нет.
- Исходный атлас и исходные общие материалы неизменны.

### Negative

- Старые россыпи исчезают при вытеснении 17-й секцией и очистке карты.
- Слой покрывает только существующий базовый пол, не столы/лестницы/ковры.
- Нет объёмного силуэта, физического взаимодействия или динамики осколков.
- Проверка стен у центра штампа не является точным обрезанием его края стеной.

### Risks and mitigations

- Section seams/alpha: реальные пиксели атласа и четыре соседние секции в tests.
- Память/очередь: overflow и idle regressions, возврат clean materials при clear.
- Native/Web/FPS: native suite в обоих CI renderer; аппаратная Iris Xe/Web
  приёмка отдельно, headless не объявляется доказательством GPU performance.

## Migration plan

1. Импортировать существующий PNG без изменения авторских пикселей.
2. Подключить opt-in collaborator к существующим break guards.
3. Связать слой с derived материалами, зарегистрировать tests в CI.

## Rollback plan

Удалить инъекцию configure_glass_debris из bootstrap; без collaborator прежние
разрушения продолжают работать. Затем удалить shader/helper добавления.
Карты, баланс, сохранения и исходные ассеты миграции не требуют.

## Validation

run_glass_floor_debris_tests: все 16 кадров, transparent pixels, seams, queue,
LRU, density, idle, floor materials, four public glass scenes, cracks/exterior.
run_world_bindings_tests: фактическая инъекция через structural public root и
props. Existing glass_crack/floor_batch/destruction_fixes/office_breakage.
Godot4.7.2 editor import; validate_project/architecture/source-size/scene refs.
Native shader pixels проверяются тем же новым suite в Compatibility/Forward+.

## Approval

Владелец в этой беседе выбрал только стекло, добавил атлас и прямо поручил
«подключи к игре как мы и обсуждали». Это одобрение данной additive инъекции;
новых owners, dependencies, Autoload или архитектурных исключений нет.
