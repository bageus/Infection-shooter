# QA второго прохода оптимизаций исполнения

Дата: 06.10.2026. Работа в T002 / PR #41, ADR-0034.

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
