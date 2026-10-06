# QA второго прохода оптимизаций исполнения

Дата: 06.10.2026. Работа в T002 / PR #41, ADR-0036.

## Проверяемые изменения

| Модуль | Изменение | Проверка |
|---|---|---|
| office_floor/base_floor_renderer | 1200 плиток → не более 160 пространственных material batches для 80×60 без лестниц | run_floor_batch_tests; проёмы, края, высота, native изображение против отдельных meshes |
| office_floor/display_wall, display_view, display_content | only powered dynamic; исходные GIF-дедлайны; unchanged shader parameters не записываются | run_display_tests; циклы, питание, два экрана, TV wall/удаление/standalone |
| prototype_hud/prototype_hud, radar | снимки показателей; фон по resize; отметки до 20 Гц | weapon_icon/radar tests; depleted ammo, max HP, скрытие/resize |
| infected/severed_part | expiry Timer наследует physics/pause; callbacks только в окне крови | run_part_lifetime_tests и dismemberment/decor physics |
| combat/spent_casings | scene-local immutable material/shape cache, no idle cleanup | run_casing_resource_tests/cursor_aim; .7 scale, независимые тела, cap 40 |
| office_floor/tests/run_display_shadow_profile | 24 powered screens, ABBA shadows true/false, warmup 16 + sample 48 frames | оба native renderer, JSON и лог; настройки игры прежние |

## Автоматическая проверка

```bash
python tools/validate_project.py
python tools/test_architecture_scene_access.py
godot --headless --path . --editor --quit
```

Новые наборы находятся в mission_runtime.yml. Floor/radar tests запускаются
также с реальным renderer. Импорт, существующие gameplay suites, main 180 кадров,
menu captures, rendered smoke и оба renderer проверяются полным CI.
Локальные Python gates PASS; локального Godot нет. Итог runtime вписывается
после завершения CI, а не по успешной проверке исходников.

## Замер теней на целевом устройстве

В установленном Godot, из корня проекта:

```bash
godot --path . --rendering-method gl_compatibility --script game/presentation/office_floor/tests/run_display_shadow_profile.gd
godot --path . --rendering-method forward_plus --script game/presentation/office_floor/tests/run_display_shadow_profile.gd
```

Задать RUNTIME_PROFILE_DIR для сохранения JSON (папка создаётся автоматически).
Сценарий отключает VSync только в своём процессе, использует фиксированную камеру
и выводит renderer, число экранов, median/p95 wall frame ms, draw calls,
process/physics ms для каждого ABBA-прохода. Это время цикла кадра, не отдельный
GPU timestamp. Сравнить медианы двух проходов каждого режима. Не принимать
решение по одной выборке или по software GPU CI. Для браузера дополнительно
нужен экспорт и замер в настоящем desktop-браузере.

## Сравнение игрового кадра

1. Использовать одинаковую сохранённую карту, разрешение, renderer и настройки
   для кода до второго прохода (d9caa7f) и после него. Записать CPU/GPU, Godot,
   браузер/драйвер, VSync и число объектов. Не смешивать результаты разных устройств.
2. На карте проверить большой пол со лестничными проёмами, 24 включённых экрана,
   толпу и серию разрушений. После одинакового прогрева пройти одинаковый
   60-секундный маршрут с одинаковым оружием и камерой минимум три раза.
3. В Godot profiler записать process/physics frame time и native GPU profiler
   отдельно, draw calls, число объектов/активных тел, пики спавна и p95. Сравнить
   одинаковые участки, а не только средний FPS. Debug F3 предоставляет часть
   read-only показателей, но сам по себе не заменяет profiler.
4. Сравнить внешний вид пола и отверстий, следы крови/копоть, динамические
   экраны и их питание, объединённые TV, немедленные HP/ammo, масштаб гильз,
   кровь на частях и удаление/паузу. Постоянные planner-декорации сохраняются.

## Следующие решения по результатам

- Пул целых физических гильз: только если создание/удаление тел остаётся
  измеримым пиком после кеширования ресурсов. Требует сброса скоростей, возраста,
  исключений, звуковых таймеров и недопущения воспроизведения старого звука.
- Настройка качества теней экранов: только после целевых A/B и визуальной приёмки;
  текущие тени по умолчанию не меняются. Если выбирать адаптивное отключение,
  нельзя использовать только расстояние без учёта видимости и влияния на комнату.
- Общий FPS-эффект пока не подтверждён целевым устройством. CI измерения —
  проверка воспроизводимости сценария и correctness, не обещание производительности.

## Первый software CI sample (a087d63)

Сценарий отработал в обоих renderer без ошибок. Два ABBA-прохода каждого режима:

| Renderer | Тени: median frame ms | Без теней: median frame ms | Draw calls с/без |
|---|---|---|---|
| Compatibility | 83.367 / 83.341 | 29.363 / 29.709 | 180 / 49 |
| Forward+ | 45.350 / 45.979 | 45.461 / 45.169 | 26 / 26 |

Разница в Compatibility воспроизводится на software runner, в Forward+ на этой
сцене практически отсутствует. Это аргумент за renderer-specific целевые замеры,
а не за общее отключение теней или обещание такого FPS на пользовательском GPU.
100 спавнов гильз: 1837 µs в headless CI; 40 retained bodies, 2 cached shapes
при двух проверяемых размерах. Это CPU sample после изменения, не сравнение FPS.

Первый full run 37467295937 обнаружил ошибочные seam probes пола и dummy-renderer
matrix queries в новом тесте, а также неуказанный WeakRef в lifetime test.
Основная сцена, импорт, прежние gameplay/native suites, дисплеи, HUD, радар,
гильзы и shadow profile прошли. Матрицы/геометрия пола проверяются в обоих native
проходах; headless проверяет ресурсы/количество/пересборку. Исправленный полный run 37469570276 на 3b6ce879 прошёл: 51 headless набор,
main 180 кадров, menu captures, rendered smoke и 28 native запусков (14 в каждом
renderer), clean import/project/resource gates. Все native exit 0, фактических
SCRIPT/SHADER/ERROR нет. Architecture 37469570293 SUCCESS. Последующая запись
этих результатов меняет только документацию; код и тесты остаются прежними.

https://github.com/bageus/Infection-shooter/actions/runs/37469570276
https://github.com/bageus/Infection-shooter/actions/runs/37469570293


## Индекс поверхностей попаданий — PR #45

База сравнения: main 91c3783. features.combat хранит локальный BVH для faces
ресурса Mesh (до 128 ресурсов) и weak-кеш состава веток (до 128 корней).
Mesh.changed помечает индекс для перестроения при следующем запросе;
child_order_changed инвалидирует состав ветки. Видимость/metadata родителей,
shadow mode, ресурс меша и transform проверяются при каждом запросе.
У каждого наблюдателя собственная идентичность и weak-ссылка на владельца;
вытеснение и уничтожение отключают сигналы. Публичные контракты и UV-проекция
surface_stamp_v1 остаются прежними; архитектурных исключений нет.

Регрессия сравнивает 240 лучей с полным перебором: попадание/промах, координата
и нормаль при повороте, неравномерном и отрицательном масштабе. Отдельно проверяет
скрытие/показ, metadata, коллапс damage-stage, добавление/удаление/reparent,
замену/изменение/совместное использование Mesh, вложенные и независимые кеши,
ограничение 128 индексов и отключение callbacks. На меше из 8192 треугольников
локальное попадание выполняет 8 точных segment_intersects_triangle вместо 8192.
Это число геометрических проверок в контрольном случае, не коэффициент FPS.

```bash
godot --headless --path . --script res://game/features/combat/tests/run_impact_geometry_index_tests.gd
```

Отдельный Impact geometry regressions CI запускает эти scene-free helpers без
импорта игровых ассетов и выдаёт быстрый диагностический журнал. Полный Mission
runtime regressions сохраняет этот же тест и проверки реальных следов/стрельбы
в headless, Compatibility и Forward+.

Для целевого профиля сравнить одинаковую карту и маршрут стрельбы на 91c3783
и этой ревизии. Измерять отдельно первый выстрел по сложному объекту (ленивое
построение индекса) и последующие попадания; затем разрушение, перенос/падение,
появление новой геометрии и серии попаданий по разным объектам. Проверить кровь
и копоть на торцах, столах, стульях, соседних объектах и отсутствие копоти на
стекле. FPS Windows/Web и стоимость первого построения пока не измерены.


Проверенный код f5fece95: architecture 37505074242 SUCCESS, focused geometry
37505073991 SUCCESS и полный runtime 37505074182 SUCCESS. Godot 4.7.2:
clean import/project/resource gates, 54 headless набора, main 180 кадров,
menu captures, smoke и оба native renderer. Фактических SCRIPT/SHADER/ERROR нет.
Первые прогоны обнаружили вызов instance helper из RefCounted PREDELETE и
повторное подключение static bound callbacks у независимых/вложенных кешей.
Исправлены прямая очистка и отдельные weak-наблюдатели; регрессия проверяет оба
случая и shared Mesh. Последующий коммит записывает только документацию.

https://github.com/bageus/Infection-shooter/actions/runs/37505074182
https://github.com/bageus/Infection-shooter/actions/runs/37505073991
https://github.com/bageus/Infection-shooter/actions/runs/37505074242

## Последовательная оптимизация эффектов и дверей — 06.10.2026

Согласованный порядок: surface_stamp → взрывы → кровь → двери → части тел.

- core.vfx/surface_stamp_cache: caller-owned cap 128 Mesh, immutable arrays/BVH,
  Mesh.changed invalidation, раздельные weak observers и teardown. Старый
  surface_stamp.build остаётся stateless и служит эталоном. Временный proxy
  процедурного пола не задерживается в кеше. Точные clipping, normal/UV,
  glass/material, offset и output cap 4096 прежние. Контракт — ADR-0037.
- combat/grenade_explosion: до shelter rays отбрасываются только объекты без
  damage/stun callbacks и без возможности rigid impulse. Frozen damageable
  остаются; factor=0 не исключает старый base impulse 2. Порядок damage,
  исключение contact, wall shelter, scorch и баланс прежние.
- office_floor/blood_mark_budget: global/per-surface counts учитывают fading;
  связанные FIFO выбирают прежний oldest non-fading без полного прохода и
  сдвига массивов. Таймер 0.1 s останавливается без marks/pending/deaths;
  относительный clock и pause-aware fade/death delay сохраняются. Пока есть
  следы, bounded weak/surface/expiry sweep оставлен для прежнего lifecycle.
- office_floor/interactive_door: локальная Area отбирает физические тела для
  emergency doorway, затем прежние actor groups, health и origin bounds.
  Elevator peers связываются при enter_tree и взаимно при новых экземплярах;
  WeakRef и текущие distance/group membership проверяются при request.
  Leaves/recesses/hinge получают pose только при изменении open amount и
  первоначальной инициализации. Glass break collision и key hint остаются live.
  Разделение рассмотрено: private door_presence отвечает за локальный broad
  phase; анимация/состояние/авторинг остаются в существующем door script.
- infected/body_part_topology: в существующих prepared data кешируются first
  appearance unique IDs, remapped indices и weighted bone IDs. Membership
  уже кешировался ранее; повторный remap и ненужные bone matrices устранены.
  Current skeleton pose, skinning, normals, UV, CUSTOM0, center/hull/materials
  вычисляются для каждого sever. Публичных изменений у infected нет.

Автоматические regressions: stamp cache vs stateless (80 transforms + dense,
Mesh mutation/replacement, glass, singular scale, cap/cleanup); FIFO vs array
после 2000 случайных удалений; body topology vs frozen baseline (4/8 weights,
80 poses × 3 chains, arrays/center/hull); door presence/health/bounds, moved,
added/deleted/reentered peers и отсутствие stationary pose writes; blood
counters/retirement/clear/idle/wake. Frozen baseline — только test oracle.
Все source-size production limits соблюдены; существующий door script
по-прежнему выше 300 строк. Новое предупреждение касается только сохранённого
66-строчного baseline build_piece в тестовой fixture.

Focused Godot 4.7.2 run 37517775924 PASS: impact geometry 0 failures, stamp
32/2048 кандидатов и 0 failures, blood FIFO PASS, body topology 0 failures.
Финальный код 65196f4d: architecture 37519444419 SUCCESS; focused geometry
+ integration 37519444758 SUCCESS (door/blood/grenade/body 0 failures).
Полный runtime https://github.com/bageus/Infection-shooter/actions/runs/37519444432
SUCCESS: чистый import, project/resource/Python gates, 58 headless наборов,
main 180 кадров, menus, rendered smoke и 28 native запусков (14 в каждом
Compatibility/Forward+). Все native exit 0; фактических SCRIPT/SHADER/ERROR
нет. Локально validate_project, 3 Python scene-access tests, YAML parse и
diff-check PASS. Последующий коммит только обновляет результаты и path
triggers focused workflow, тестовые assertions/production code прежние.
Это не замер FPS Windows/Web.

Интеграционная проверка обнаружила уже существовавший дефект main 5b7e07:
PNG Toxic Gas Cloud Atlas удалён, но mutagen_cloud оставлял его preload.
Ссылка заменена на добавленный владельцем Six-frame green smoke sprite
sheet.png; пользовательские изображения сохранены. Новый blood FIFO test
сначала читал records до обработки public deferred effect queue: добавлены
два physics_frame ожидания, production logic не менялась. Быстрый integration
job запускает actual main и door/blood/grenade/body tests; его triggers также
включают атласы мутагена, чтобы replacement path проверялся при следующей
замене. Визуальная субъективная приёмка нового атласа остаётся ручной.

Ручная приёмка: одинаковые карта/seed/оружие/настройки и 60-секундный маршрут
до/после; повторные попадания и взрывы у сложной мебели, кровь/разрушение
получателя, emergency door с толпой/ключом, elevator и glass swing, sever в
разных позах. Сравнить profiler spikes/CPU physics и видимые pixels, а также
память первого и повторного запроса. Не переносить software-CI FPS на целевое
устройство. Тест 32/2048 характеризует выборку геометрии, а не весь кадр.
