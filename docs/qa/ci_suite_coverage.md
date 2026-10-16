# Q01 — полнота регистрации тестов в CI

Инкремент T004, база `2a531767` (main после PR227). В исходном аудите было пять
пропущенных suites. На этой базе corpse_budget уже включён; остальные четыре
добавлены в обычный headless job:

- bootstrap: planner_door_lock, planner_door_select, ui_translation;
- prototype_hud: mutation_veil.

## Что изменено

Прежние145 entries из heredoc mission_runtime перенесены **в прежнем порядке** в
`.github/runtime_suites.txt`; четыре новых добавлены в конец. Итого149. Workflow
передаёт этот файл прежнему `tools/run_runtime_suites.sh` с3 workers. Сам runner
не менялся: отдельный XDG_DATA_HOME/user:// для каждого suite,120с timeout,
ненулевой exit или SCRIPT ERROR/ERROR в логе дают failure. Совпадающие basename
запрещены валидатором: именно basename определяет имя лога и user-dir runner.

Ещё8 наборов не дублируются в общем списке. Их существующие места запуска и
причины указаны в `.github/suite_jobs.json`:

| Workflow/job | Suites | Режим |
|---|---|---|
| mission_runtime/runtime, отдельные шаги | group04_asset, model_texture, display | headless |
| impact_geometry/geometry | stamp_cache, body_topology, blood_fifo | isolated minimal project |
| impact_geometry/integration | door_runtime | headless, существующий targeted path filter |
| mission_runtime/runtime, renderer loop | display_shadow_profile | настоящий Compatibility/Forward+ |

Это регистрации существующих запусков, **не разрешения пропускать тесты**.
Path filters/условия/renderer отдельных jobs сохранены. В частности, suites из
impact_geometry запускаются по его прежнему фильтру;149 общих — при запуске
mission_runtime. Наличие регистрации не означает запуск любого job на каждом PR.
Штатный Web skin probe и native jobs не переписаны.

`tools/validate_ci_suites.py` включён в validate_project, поэтому architecture
workflow проверяет его на каждом PR/push main, включая docs-only изменения.
Перед runtime runner он вызывается повторно. Gate сверяет все
`game/**/tests/run_*.gd` с двумя списками и проверяет:

- отсутствие нового незарегистрированного или удалённого/stale suite;
- отсутствие дублей, пересечения двух списков и коллизий имён логов/user-dir;
- использование канонического файла настоящей командой runtime job;
- конкретные workflow/job/mode/reason каждой отдельной регистрации;
- запуск через `godot --script`, включая существующие shell loops и `res://`.

Простое упоминание пути в комментарии, trigger paths, echo или другом job не
считается запуском. Это ограниченный stdlib reader **текущего формата workflows**:
job keys с2 пробелами, literal `run: |`/некавыченный inline run, явный Godot path
или for-list. Это не общий YAML/shell интерпретатор, не замена GitHub проверке
синтаксиса/условий и не доказательство успешного runtime. При переходе к matrices,
reusable workflows, folded/quoted run или генерации команд нужно обновить reader
и его regression cases; неизвестный способ исполнения не даёт регистрации PASS.

Capture/profile/helper файлы без префикса `run_` не являются run-suites. Новый
`run_*.gd` даже с диагностическим именем потребует регистрации; существующий
run_display_shadow_profile явно оставлен native. Ручной O04 profiler не добавлен
в CI как timing assertion.

## Найденное падение door-select

Первый запуск новых suites на неизменённом тесте дал2 failures: дверь не удаётся
выбрать в поисковой области и финальный selected не равен двери. Probe подтвердил
viewport1280×720, видимую дверь с ненулевым AABB и попадание пикера в другие placed
nodes текущей карты. Старый fixture искал свободный пиксель только рядом с текущей
камерой, где новая расстановка уже перекрывает лучи.

Тестовая камера перед размещением двери сдвинута на(1000,1000,1000); дверь по
прежней формуле оказывается перед ней в пустой области. Настоящие camera ray,
геометрия двери, planner._input и все assertions сохранены: активная дверь в
палитре, отсутствие новой установки, выбор установленной, открытие её settings.
Production пикер/обработка ввода и карта не менялись. Это стабилизация fixture,
а не исправление или подавление gameplay ошибки.

## Выполненные проверки

- До добавления4: gate FAIL ровно по4 unregistered suites; после — PASS,
  **157 discovered =149 runtime +8 explicit jobs**.
- 11 Python regressions PASS: valid registry, новый/удалённый suite, duplicate,
  одинаковые basename, отсутствие вызова manifest, comment/filter/echo/wrong-job,
  вложенный renderer loop, loop без script, mode/reason/workflow, пересечение
  списков, helper/profile вне run discovery. Запускаются в architecture workflow.
- 5 исходных Q01 Godot suites через штатный runner, отдельные user dirs,2 workers:
  **5 PASS**, без SCRIPT ERROR/ERROR; door-select до fixture correction2→0.
- Прежние145 путей и порядок переноса проверены относительно git baseline.
- Дополнительно test_architecture_scene_access:3 PASS.
- validate_project PASS (452 GDScript,122 прежних advisory warnings), resource
  paths PASS, headless editor import PASS без ERROR, git diff --check PASS.

Команды:

```bash
python tools/test_ci_suite_coverage.py
python tools/validate_ci_suites.py
python tools/validate_project.py
```

Изменены CI/tools и один bootstrap test fixture. Игровые владельцы состояния,
public API, сцены, ассеты, save/network DTO, module edges и policy прежние;
новых зависимостей и архитектурных исключений нет. FPS/Windows/native/Web в этом
инкременте не проверялись; полный149 headless прогон и render jobs остаются CI.
Дальше — D01: сначала доказать потребителей и совместимость кандидатов на очистку;
D02 и отдельное архитектурное замечание Q02 не считаются выполненными.
