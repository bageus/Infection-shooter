# Idle кровь и биомасса: третий пункт FPS

Дата: 25.10.2026. T004 / Phase1 / P1_LOGIC.
База main: `dd2e22d341814f965491e1e1b4749adcf45cb42a` (PR463 уже merged).

## Изменения

В presentation.office_floor blood_decal_prop повторно использует привязку,
когда anchor и сам decal неподвижны. Ручное изменение decal при неподвижном
anchor пересчитывает offset; перемещение anchor сохраняет прежний приоритет
follow. Видимость anchor читается один раз; неподвижная обычная кровь
проверяет прежние inputs/receivers перед вызовом projection body.
Неподвижная проекция была закэширована и до правки: тест подтверждает
ноль новых projected_geometry запросов до/после. Не заявляется устранение
полного построения меша на каждом кадре — его и раньше не было в этом случае.

_clip_biomass создаёт stamp array только при фактической подгонке. Прежние
transform/mesh invalidation, интервалы initial floor и support recheck,
FITS_PER_FRAME и RECHECK_FRAME_GAP сохранены. Root _process продолжает
отслеживать скрытие/удаление опоры и периодическую маску, поэтому биомасса
замечает разрушение поверхности. GPU/шейдеры/геометрия не упрощались.

BiomassFit после settle и завершения всех worker jobs отключает _process.
Private runtime child теперь Node3D: inherited transform notification
возобновляет обработку после движения. release и _start явно включают
обработку: новый сосед может запустить fusion у спящего leader, очередь
остаётся активной до получения результата. Удаление ведущего возвращает
оставшиеся pieces, _exit_tree по-прежнему дожидается worker.

Owners, public API, сцены/ресурсы, map/save DTO и dependency edges прежние;
новых Timer/Autoload/global state/policy exceptions нет. Runtime Fit не
сериализуется как authored сцена. Root486строк reviewed: прежний render и
attachment adapter, отдельного pass-through helper не требуется. Fit277строк
сохраняет единственную ответственность fusion lifecycle.

## Измерение

Новый run_decal_idle_tests использует 300 отдельных contract fixtures
с настоящим BiomassFit и считает вызовы subclass callback за60 process frames.
После начального settle: **18000 callbacks → 0**. Функциональная часть
использует также реальные blood_decal pieces и worker fusion.
Один окончательный suite с исходными двумя production scripts:6failures;
с исправленными:0failures.

Отдельный CPU цикл —300 реальных обычных blood_decal с anchor и вторым
receiver, готовая ArrayMesh projection от fixture collaborator,60 ручных
вызовов _process на каждый piece. Создание/загрузка/отрисовка не измеряются.
Пять отдельных процессов Godot4.7.2 на версию (--bench-only):

| Метрика | Исходный main | Исправление |
|---|---:|---:|
| Idle Fit callbacks/60frames | 18000 | 0 |
| Новых projected_geometry запросов в blood цикле | 0 | 0 |
| CPU медиана всего blood цикла, мс | 70.799 | 56.803 |
| Диапазон пяти blood циклов, мс | 58.684–76.219 | 56.415–62.192 |

Медиана этого изолированного blood цикла ниже примерно на19.8%.
Root callbacks прикреплённых пятен остаются; это не FPS полной карты и
не оценка GPU. Вариация CPU на общей машине видна в диапазонах.

## Проверки

Focused suite: idle callback count, собственное и inherited движение,
повторный settle/release; translated/rotated anchor, ручной offset edit,
secondary receiver invalidation, hide/show/free опоры; real single Fit idle,
новый сосед у спящего leader, worker commit, удаление leader и follower idle.

Godot4.7.2 headless, все0failures:
- run_decal_idle_tests
- run_biomass_tests (включая fusion/separation/rejoin, clip/support, broken/hidden anchors и planner)
- run_blood_decor_tests
- run_blood_normal_tests
- run_door_blood_attachment_tests
- run_biomass_floor_bake_tests (JSON/scene/planner/bake lifecycle)
- run_biomass_footstep_tests
- run_biomass_planner_tests
- run_blood_effects_tests

validate_project PASS:227 suites,219runtime+8special. Final editor import без ERROR,385scene refs,resource paths и diff-check PASS.
Windows/Web, ручная визуальная приёмка и FPS карты владельца не проверены.
Откат — revert этого инкремента, данные и схема сохранений совместимы.


### Исправление CI при обновлении main (25.10.2026)

CI проверял merge с main fb6c79a и нашёл undeclared dependency: в authored
base_office_layout (94a20af) добавлена публичная spawn_point.tscn из
features.spawning. Манифест office_floor теперь декларирует существующую
композиционную зависимость presentation→features; policy это разрешает,
циклов нет. Точка спавна, карта и её JSON сохранены; validators не ослаблены.


25.10.2026 — повтор CI PR464: Architecture validation уже PASS. Integration main smoke на merge02ef185 завершался timeout60 без script errors; локально тот же полный main.tscn/quit-after10 на merged candidate завершился exit0 за51.14с. Лимит smoke повышен до180с для startup/worker teardown полной authored карты на shared runner, error checks и прочие suites сохранены. Headless idle suite0failures, editor import и validate_project на head и merge с main PASS. Это ограниченный CI budget, не исправление/заявление FPS.
