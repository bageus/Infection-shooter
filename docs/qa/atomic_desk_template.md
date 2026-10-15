# A04 — безопасное применение шаблона стола

Дата: 16.10.2026. T004, фаза1/P1_LOGIC. База main `2744036c`, включая PR206/207, солнце PR209 и последнюю карту владельца. Ветка `codex/atomic-desk-template`, PR непосредственно в main.

## Результат и владельцы

`bootstrap.app` по-прежнему владеет шаблонами, их файлами, списком placed и размещением. Применение разделено на проверку, подготовку и синхронную замену:

1. `desk_setup_template_schema.gd` проверяет весь вложенный v1 payload: тип стола/версию, массивы zones/items, обязательные поля, положительные размеры, типы bool/string, конечные и представимые координаты, индексы зон, канонические доступные пути моделей внутри прежнего MODEL_ROOT. Пол зоны имеет height0, как в UI. Схема независима от workstation/zone loaders, чтобы не получить цикл FILES→RULES→WORKSTATIONS→FILES.
2. `desk_setup_template_files.gd` проверяет payload до записи и повторно после JSON roundtrip. Некорректная запись не заменяет предыдущий файл. Чтение проверяет всю структуру и не разрешает путь за пределы каталога шаблонов.
3. `desk_setup_template_actions.gd` копирует/нормализует зоны, проверяет их по существующим поверхностям и правилам, создаёт все новые модели в краткоживущем контейнере с выключенным процессингом и проверяет прежней геометрией/категориями. Проверяется и конечность координат после преобразования столом. При любом отказе освобождается только подготовленная композиция.
4. Только после полного успеха заменяются старые attachments, zones/front/selection и placed; новые узлы выходят из временного контейнера. Чужие attachments остаются. Нет await и промежуточного кадра частично применённого шаблона. Сообщение успеха появляется после commit.

Старые optional поля v1 (front, name, category, required, angle, yaw, zone hint) сохраняют прежние defaults; aliases нормализуются существующим ZONE_RULES, без копирования правил. Для старых зон без category сохраняется геометрический выбор; явно заданная категория должна соответствовать модели. Явно пустые zones/items означают намеренную очистку и разрешены. Структурная проверка файла и проверка пригодности к конкретному столу различаются: последняя выполняется при подготовке в UI.

Публичные API, scene/resource пути, JSON version1/карты DTO, зависимости и владельцы не менялись. Новых архитектурных исключений нет. Производственные файлы ниже300 строк, новый suite ниже500. ADR0003 уточняет замену прежнего частичного применения на отказ целиком.

## Регрессия

`game/bootstrap/app/tests/run_desk_template_atomic_tests.gd` читает/пишет настоящие user:// JSON и вызывает production load/save/load_selected. Контекст UI и factory в этом suite маленькие, с in-tree MeshInstance3D; настоящий planner отдельно проверяется существующим suite.

- **40 повреждённых payload**: неверные типы/массивы/zone/item, отсутствующие обязательные поля, zero/negative dimensions, неправильные bool/front/version/desk, зоны/координаты, недоступные/внешние пути. При отказе прежние object IDs, transforms, metadata, placed (включая посторонний объект), zones/front/index и UI остаются. Временных узлов не остаётся.
- Отдельно NAN/INF/непредставимые числа и переполнение world position после большого масштаба стола.
- Поздний отказ factory на второй модели, отсутствие видимой геометрии, позиция вне зоны/поверхности, неверная категория и пустая required-зона: вся подготовка освобождается, прежний стол сохранён.
- Валидная замена на перемещённом/повёрнутом столе; legacy defaults; допустимая floor-зона; выход из disabled staging и восстановление процессинга.
- Валидный пустой шаблон намеренно очищает только выбранный стол.
- Невалидная повторная запись сохраняет прежний файл побайтно; traversal-path отвергается.

A/B: новый suite со старыми `template_files.gd`/`template_actions.gd` из `24e1f84c` — **286 assertion failures, exit1** (есть также SCRIPT ERROR от непроверенных типов); после восстановления исправленных production-файлов — **0 failures, exit0**. Это число проверок сохранности состояния, не число отдельных дефектов. Новый schema остаётся доступен только для его прямых числовых проверок в обоих запусках; старые FILES/actions его не вызывают.

## Остальные проверки

Все8 целевых headless suites PASS (изолированный XDG_DATA_HOME для каждого, два процесса одновременно): desk_template_atomic, placement_templates_weapons, surface_pose, planner_persistence, planner_extension, planning_mode, world_surface, planner_object_settings в game/bootstrap/app/tests (`run_*_tests.gd`). После последних guards world-overflow/floor-height новый suite и настоящий placement_templates_weapons повторены; валидная загрузка дополнительно покрывает оба H/U divider desk. Итоговый полный прогон всех8 повторён на main2744036c с новой картой владельца и PASS. Новый suite включён в mission_runtime CI.

`tools/test_workstation_templates.py`:3 PASS. Spec/workflow READY, validate_project, scene_resources392 refs, resource paths, Godot editor import и diff-check PASS. Source-size120 прежних предупреждений, новых нет. В существующих main-based suites остаётся известное предупреждение60 ObjectDB при выходе (A05); новый atomic suite без него. Проверки/assertions прежних suites не ослаблялись.

## Унаследованный blocker последней карты

После обновления базы до main2744036c финальный architecture gate обнаружил три приватных cross-module script references в base_office_layout.tscn. Для18 разных публичных PackedScene проверен настоящий instance.get_script().resource_path: во всех18 скрипт совпал с92 явными overrides (38 pickup,31 body parts,23 corpse). Удалены только эти92 избыточных назначения и3 неиспользуемых ext_resource; остальные строки сцены, узлы, transforms и экспортированные свойства сохранены. base_office_map.json и project.godot не менялись. Это не разрешение архитектурного исключения.

После очистки validate_project и architecture PASS; scene resources392 refs, editor import PASS. Дополнительно прошёл run_startup_resource_memory_tests (startup/restart всей новой карты,0 failures) и повторный реальный placement_templates_weapons с H/U. Таким образом, проверено **9 разных suites**. Пик allocator в headless startup935.32MiB, RSS1187.56MiB, video0; это не GPU/FPS и не замер стоимости применения шаблона. Известное ObjectDB60 при выходе startup также остаётся A05.

## Ограничения и передача

Подготовка синхронная и временно держит новые узлы рядом с прежними. Она выполняется по нажатию загрузки шаблона; нового per-frame кода нет. Factory/ready callbacks существующих доверенных моделей остаются прежними; откат касается подготовленных узлов и состояния редактора, а не произвольных внешних действий чужого скрипта. Windows/Web и GPU-пиксели вручную не проверялись.

Следующее действие — проверить CI PR и применить валидный/повреждённый шаблон в обычной игровой сборке. Merge не поручен. После A04 следующий пункт аудита A05 (завершение background audio load requests). Откат — revert этого инкремента; миграции шаблонов/карт нет.
