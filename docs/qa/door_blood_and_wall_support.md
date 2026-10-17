# Кровь на дверях и потеря настенного крепления — issues #234 / #235

Запрос владельца17.10.2026: кровь на открывающейся двери движется вместе с ней;
любой настенный предмет на разрушенной деревянной перегородке падает вниз.

## Причины и исправление

- Swing leaf создаёт MovingDoorBody под pivot, рядом с mesh. Прежний surface
  resolver не находил соседнюю створку; planner сохранял кровь без anchor либо
  привязывал её к раме. InteractiveDoor регистрирует collider → visible leaf
  через прежние configure_world/register_surface. Регистрация работает до и
  после _ready; лифтовые створки используют тот же путь.
- Bootstrap при восстановлении wall/object blood коротким локальным ray
  уточняет фактическую поверхность. Пятна без attachment и с ошибочной рамой
  получают runtime leaf anchor; правильный сохранённый owner не заменяется соседним.
  Исходные attachment owner/mesh и object_id при восстановлении не переписываются.
  Нет близкой поверхности — прежняя привязка сохраняется. Floor blood не меняется.
  Синхронная загрузка, async startup и undo получают существующий impacts adapter.
  Пустые object_id не трактуются как owner старых непривязанных пятен.
- Разрушение wood slat partition раньше обходило только partition_signs
  (VECTRION). Теперь все WallMountModels входят в module-local wall_mounted_props;
  private WallMountSupport проверяет видимые bounds в координатах перегородки
  и параллельность плоскостей. Допуск контакта6см, без широкого world AABB.
  Обе стороны и смещённые pivots учитываются; соседние опоры не освобождаются.
- Прежний fall_off_with_glass освобождает любое целое замороженное wall prop:
  wake + gravity/downward impulse. Телевизор/шкаф/сантехника не помечаются
  разрушенными от потери опоры; их последующий damage остаётся доступен.
  Существующее исчезновение маленьких wall signs через1с сохраняется.

## Регрессии

Новый run_door_blood_attachment_tests: пять public дверей, обе стороны,
поворот/масштаб, настоящее движение half/open/closed, placed/saved/unbound/stale
frame blood, sync/async restoration и оба runtime пути (clipped mesh и Decal).
Проверяются actual leaf receiver, parent projected pieces и неизменный transform
пятна относительно створки. Новый suite зарегистрирован в headless manifest и
в native Compatibility/Forward+ CI; assertions не отключены в Dummy.

Новый run_wall_mount_support_tests обходит все25 моделей WallMountModels,
включая оба телевизора, часы, картины, зеркало, доску, кондиционер, оба навесных
шкафа, сушилку/писсуар, огнетушитель, логотип и10 настенных указателей/приборов.
На каждую модель: обе стороны повёрнутой/масштабированной перегородки,
back-plane placement по actual geometry, сохранение опоры после слабого попадания,
полное разрушение пулями или grenade damage, waking и снижение высоты>15см за
30 physics ticks, idempotent repeat; соседняя параллельная опора и предмет за
краем остаются замороженными. Debris container не внедряется: падение предмета
должно происходить от потери опоры, независимо от толчка взрыва/обломков.

Исходный код воспроизвёл отсутствие planner attachment на распашных дверях и
сохранение крепления большинства моделей; исправленная версия проходит новые
проверки. Локально используется Godot4.7.2; итоговые результаты ниже/в PR.

## Границы

Office-floor владеет прежними физикой/визуалом, combat — проекцией, bootstrap —
композицией и восстановлением. Public signatures, module dependencies, scenes,
resources, DTO v8, health/destruction balance прежние; миграции и исключений нет.
Новые placements сохраняют существующие optional attachment owner/mesh; legacy
recovery меняет только производный runtime anchor, сохраняя authored поля побайтно. Door/prop roots>300 строк reviewed: scene composition/physics adapters;
геометрия контакта вынесена в private helper, root prop уменьшается575→564 строки,
door569→587, main383 не растёт. Новые private helpers<300 строк.

Headless проверяет геометрию и lifecycle обоих render paths, но не пиксели и
субъективный вид. Native renderer regression входит в CI. Ручная Windows/Web
приёмка и FPS не измерены. Следующий ручной сценарий: залить створку кровью,
несколько раз открыть/закрыть, затем разрушить перегородку с телевизором и шкафом.

## Локальные результаты

Godot4.7.2: все16 целевых suites PASS; в каждом финальный success marker,
SCRIPT ERROR/ERROR/ObjectDB/RID leaks0. Новый door suite6с, support suite19с;
полный список охватывает blood effects/decor/dormant, office breakage,
door runtime, layout loading, planner persistence, world bindings, destruction
wiring, wall fixtures, gameplay/planner repairs, door locks/selection, exit blood.
Editor import exit0 без ошибок; validate_project (включая READY gates,
architecture/source size/166 CI suites), validate_scene_resources392 refs,
git diff --check PASS. Native выполнения проверяются отдельно CI.

## Исправление CI round trip

Первый CI выявил две ошибки сохранения/загрузки: planning_mode и display_planner.
Recovery повторно вычислял mesh и записывал его в authored blood_attachment:
в реальной карте генерируемое имя менялось @MeshInstance3D@5919→@17545.
При загрузке восстанавливается производный anchor, затем через существующий
configure_blood_attachment возвращаются исходные поля. Recovery не назначает
новый object_id пустому owner. Новые placements по-прежнему сохраняют attachment.
Оба прежних строгих full-map equality assertions сохранены. Новый door suite
дополнительно сравнивает исходные configs до/после sync/async recovery и проверяет
фактический runtime anchor вместе с движением каждого пятна.

После исправления четыре целевых suites display_planner/planning_mode/
door_blood_attachment/named_map_loading PASS (39/54/5/2с на этом прогоне).
Editor import и все project/scene/diff gates повторно PASS. CI финальной
исправленной ревизии проверяется отдельно; переход к следующему if !cancelled
шагу не считается признаком успеха предыдущего шага.
