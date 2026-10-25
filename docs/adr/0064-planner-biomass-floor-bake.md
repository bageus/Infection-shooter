# ADR-0064: Сохранение планировщика и статический raster cache напольной биомассы

- Status: accepted
- Date: 2026-10-24
- Owners: bootstrap.app (сохранение/загрузка), presentation.office_floor (пиксели/визуалы)
- Related modules: bootstrap.app, presentation.office_floor

## Context

Профилировщик владельца: 306 `_project_surface`, 322 `_clip_biomass` и 12.61 мс скриптов в кадре 68.49 мс. В игре геометрия/освещение авторской напольной биомассы статичны. Save Layout блокируется при timeout settling, а typed for в resume приводит freed-instance к Node раньше проверки.

## Decision

Ссылки проверяются как Variant до приведения к Node. Уточнение владельца24.10 отменяет fallback из первой версии PR457: карта сохраняется только после совместного settling всей локации (см. ADR0055). При timeout/cancel ни capture, ни raster/light bake, ни запись JSON/scene не начинаются; существующее сохранение не заменяется.

Map v8 получает optional `floor_biomass_v1={version:1,y,pages:[{x,z,png}],source_signature}`: sparse участки 8×8м, 512×512 RGBA PNG base64, не более64. Source_signature — SHA256 canonical render inputs (порядок pieces сохранён, числовые поля нормализованы до4 знаков, JSON int/float эквивалентны); при несовпадении cache не используется. Исходные blood records сохраняются, остаются редактируемыми. Новый public baked_biomass_floor — владелец transient Image/Texture/plane; отдельный private rasterizer того же модуля; `set_floor_biomass_baked` public blood scene — явная команда из bootstrap. Footstep alpha-запрос читает страницы. Новых dependency edges, owners, Autoload/policy exceptions нет.

Save Map/Layout после capture создаёт pages между кадрами. Запекается diffuse освещение именно напольной биомассы: постоянные авторские SpotLight (включая sublights вне текущего camera budget), DirectionalLight, ambient и raycast тени structural camera_occluder. Это упрощённая diffuse модель; не точная копия Godot PBR/GI/specular. Основные игровые лампы и свет других/динамических объектов остаются прежними. Flicker не переносится в cache. Исходные наклонные/прикреплённые/настенные pieces сохраняют прежний renderer. Объём напольных pieces и их подъём на стену заменяется плоской текстурой по прямому поручению владельца.

Runtime получает готовые PNG, не выполняет raster/light bake; plain unshaded planes без shadows/collisions/process. Исходные eligible pieces не создают visual/fit nodes. Planner показывает исходники; exit использует cache только при совпадении signature, иначе старые pixels скрыты и остаются исходники до следующего Save. Packed scene хранит тот же cache и экспортируемый flag исходников.

## Alternatives considered

### LightmapGI

Даёт более точный свет, но запекание доступно только в editor, требует UV2 и Forward+/Mobile; не подходит для кнопки Save внутри Compatibility/Web игры.

### Только остановить callbacks

Сохраняет меши и освещаемые PBR материалы сотен pieces; не выполняет требование о текстуре пола.

## Consequences

Сохранение дороже (progress между bounded raster rows/light grid rows), загрузка не пересчитывает свет. 64 страницы — до64МиБ RGBA CPU +64МиБ GPU до mipmaps (GPU +≈21МиБ), плюс PNG/JSON. Ограничение страниц/encoded bytes; PNG dimensions проверяются до decode. Для большой карты с >64 заполненными страницами map сохраняется без cache с явным bake warning; исходники остаются видимыми. Резкого роста FPS не обещаем: CPU script time — лишь часть показанного кадра.

## Migration plan

Optional v1 cache в существующем v8, без замены старых blood records. Legacy maps продолжают работать и получают cache при следующем сохранении. Битый cache отклоняется валидатором до замены текущей карты. Неизвестные отсутствующие GLB остаются отдельной проблемой ресурсов, не заменяются похожими моделями.

## Rollback plan

Удалить optional floor_biomass_v1 и выключить exported floor_biomass_baked в baked scene; source blood records неизменны. Для кода — revert инкремента; исходные карты без cache совместимы.

## Validation

Lifecycle resume с удалённой записью; timeout rollback; JSON/PNG roundtrip, crop/rotation/scale, malformed cache, footsteps, editor/game switch, stale cache, saved scene. Full project gates + relevant planner/biomass suites. Ручная проверка на пользовательской карте/GPU обязательна для сравнения внешнего вида; целевого Windows hardware здесь нет.

## Approval

Прямое поручение владельца 24.10.2026: сначала исправить layout/краш, запекать биомассу и её неизменное освещение при сохранении планировщика.


25.10.2026 — исправление canonical signature: числовой signed zero после
String.num(...,4) нормализуется в «0.0», как при JSON-сериализации.
Ранее native -0.0 давал другую SHA256 относительно сохранённого JSON, из-за
чего корректные PNG страницы не проходили проверку при загрузке. Отрицательные
ненулевые значения и точность подписи прежние; реальный сдвиг по-прежнему
инвалидирует cache. Формат map-v8 и источник-объекты не меняются. Старый cache
с уже несовпадающей подписью использует прежний безопасный fallback и
обновляется при Save Map/Layout; исходные данные не удаляются.


25.10.2026 — N03: save-time sampler применяет существующую долю энергии
planner_light к каждому Spot:1 для единственного, 0.7/N для многоточечной
лампы. Источник — authored energy×multiplier, без transient fade/flicker,
поэтому вне camera budget свет не теряется. Runtime/DTO/API/owners/edges
прежние; уже сохранённые PNG обновляются следующим Save Map/Layout. Реальные
public fixtures и RGB8 grid проверены, подробности docs/qa/biomass_light_energy.md.
