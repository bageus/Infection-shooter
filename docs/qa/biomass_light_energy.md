# N03 — энергия ламп при запекании биомассы

25.10.2026. База main `7946f8b88b60f129b706531ae7d2387ca0d0ac55`, включает N02/PR472 и пользовательские добавления аудио. Прямое поручение владельца: следующий этап N03. T004 / Phase 1 / P1_LOGIC, Implementation.

## Изменение

В игре point fixture имеет один Spot, linear — два, rectangle — четыре. planner_light уже распределяет authored energy×multiplier: один Spot получает весь выход, многоточечная лампа отдаёт каждому 0.7 / N. Запекатель назначал каждому Spot целую authored energy×multiplier, из-за чего общая энергия была завышена.

planning_biomass_light_bake теперь считает SpotLight3D одного fixture один раз и применяет то же существующее распределение. Runtime planner_light, его баланс/бюджет/fade, shader и публичные интерфейсы не меняются. Правило явно связано комментарием и regression с настоящими public PackedScene fixtures; новый межмодульный helper/API не вводится. Ветка authored fixtures продолжает использовать authored значения, а не временный light_energy, который бывает нулевым вне camera budget и меняется при flicker. Legacy fixture без get_authored_energy продолжает использовать собственную энергию каждого Spot без повторного деления. Пустая запись budget_lights не делит на ноль.

| Форма, authored=1 и multiplier=1 | Runtime сумма | Bake до | Bake после |
|---|---:|---:|---:|
| point | 1.0 | 1.0 | 1.0 |
| linear | 0.7 | 2.0 | 0.7 |
| rectangle | 0.7 | 4.0 | 0.7 |

Это согласование энергии источников, а не обещание pixel-perfect PBR/GI/specular или FPS-ускорения. Цвет, position/direction, range, angle/cone и attenuation прежние. Grid/ray/page budgets не увеличены; новых runtime callbacks и сцен/материалов нет. Baker85 строк — отдельная ответственность save-time lighting, decomposition не требуется. DTO v8/cache v1, owners и dependency graph не меняются; исключений архитектуры нет.

## Существующие карты

PNG cache неизменяемый и на загрузке не пересчитывается. Для исправления уже сохранённых пересвеченных страниц нужно нажать Save Map/Layout ещё раз. Старые records/PNG не удаляются автоматически, signature/schema не меняются в N03. N04 (зависимость статического bake от настройки динамических теней), N05 (полнота fingerprint) и G01 (общие статические тени сцены) остаются отдельными задачами.

## Доказательства

Новый CI suite `run_biomass_light_energy_tests.gd` создаёт настоящие public planner_light PackedScene для трёх форм и сравнивает snapshot runtime SpotLight с входами запекателя.

- Baseline с исходным sampler main: **32 assertion failures, exit1**, без SCRIPT ERROR/leaks. Логи суммарной энергии: point1/1, linear0.7/2, rectangle0.7/4.
- Исправленный sampler: **0 failures, exit0**, суммы1/1, 0.7/0.7, 0.7/0.7.
- Для каждой формы проверены authored/multiplier 1/1, 2.75/0.65 и 0/1.2; каждый Spot и его geometric/color inputs сравниваются с настоящим runtime.
- Реальная лампа выходит из budget и успевает погаснуть; sampler всё равно использует её номинальную авторскую энергию. Аналогично runtime inactive и flicker.
- Настоящий sample(cell) строит RGB8 grid. Его центральный texel сравнивается с тем же diffuse evaluator, но с geometry/energy настоящих steady runtime Spot. Допуск — один шаг RGB8 плюс float epsilon, не допуск на пересвет.
- Legacy plain fixture из двух Spot сохраняет независимые light_energy; budget entry без Spot не создаёт вклад.

## Финальные проверки

Pinned Godot 4.7.2 `ed1daf0bf`, headless:

- biomass_light_energy, light_budget_cache, authored_transform_restore (N02), unresolved_map_records (N01), map_file — **все PASS**, exit0, strict log scan без ERROR/SCRIPT ERROR/ObjectDB/resource leaks.
- editor `--headless --path . --editor --quit`: exit0, error scan PASS.
- Project gates: PASS, 234 registered suites (226 runtime +8 special).
- Python CI coverage11 и runtime runner3 tests: PASS.
- Diff check PASS.

Ограничения: частичная рабочая копия с нужными import dependencies. Первая попытка light_budget_cache без трёх timing JSON экранов дала script errors при0assertion failures; после получения оригинальных JSON тест повторён и прошёл без ошибок. Полный biomass_floor_bake сообщил0assertion failures, но109 engine error lines из-за отсутствующих structural GLB при загрузке baked authored scene; этот запуск НЕ засчитан как PASS. Проверки не подавлялись, tests не ослаблялись. Full GitHub CI, пользовательская карта, native pixels/Windows/Web/FPS ещё не подтверждены. Runtime CI предыдущего N02 был cancelled; его успешность не заявляется по факту merge.

Следующий шаг: N03 PR/полный CI, затем N04 — разделить статическое запекание и пользовательский переключатель динамических теней. T004 остаётся IN_PROGRESS.
