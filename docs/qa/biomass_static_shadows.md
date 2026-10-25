# N04 — статические тени биомассы независимы от настроек

25.10.2026. T004, Phase1/P1_LOGIC. Основа — дерево N03 из PR474; PR ещё открыт, изменения N04 представлены отдельным stacked PR без merge.

## Исправление

Private `bootstrap.app/planning_biomass_light_bake.gd` больше не переносит runtime shadow flags в список источников. Для положительного diffuse contribution всегда проверяется существующий structural raycast: только `camera_occluder`, прежние collision mask7, исключения неструктурных тел и лимит32 попытки. Spot и Directional используют одну политику статического перекрытия. Динамические тени/их качество управляют runtime renderer как прежде; bake не включает их, не меняет atlas, sun range или light budget. Проверки выполняются только при сохранении, не в игровом кадре.

Прежние ambient, авторская энергия (включая N03), геометрия света, RGB8 grid33×33 и PNG pages остаются. API, DTO, сцены, shader, владельцы, зависимости и architecture policy не меняются; исключений нет. Sampler86 строк, новые обязанности/декомпозиция не нужны. Старые страницы PNG обновятся после **Save Map/Layout**; загрузка не перезапекает их.

Это тени существующего плоского слоя биомассы. Общих запечённых теней стен/объектов на всём полу, отдельного вклада разрушаемых объектов и его удаления здесь нет (G01). N05 — неполная подпись cache — остаётся отдельным этапом.

## Регрессия

Новый CI suite `game/bootstrap/app/tests/run_biomass_static_shadow_tests.gd` использует настоящие public fixture scenes point/linear/rectangle, DirectionalLight и реальную PhysicsServer-преграду. Настройки меняются production `menu/shadow_quality.apply`.

- До исправления: **13 assertion failures**, exit1; 12 несовпадений grid (3 формы×4 качества при Off) и несовпадение фактических PNG pages. Нет script errors/leaks.
- После исправления: **0 failures**, exit0, чистый error/leak scan.
- Для четырёх типов света сравниваются все байты grid при on/off и четырёх quality levels; центр действительно затенён, убранный structural marker делает его светлее.
- Настройки controller/sun range сохраняют выбранное значение после bake; неструктурная преграда пропускается.
- Настоящий raster builder создаёт идентичные PNG pages с on/off. JSON roundtrip и загрузка public baked view под другим профилем сохраняют пиксели, unshaded материал, отключённый cast_shadow и отсутствие process callback.

## Локальные проверки

Pinned Godot4.7.2 `ed1daf0bf`, headless:

- N04 suite, N03 biomass_light_energy, light_budget_cache, N02 authored_transform_restore, N01 unresolved_map_records, map_file: все exit0/0 failures, без engine errors/утечек.
- `--headless --path . --editor --quit`: exit0, error/leak scan чистый.
- `python tools/validate_project.py`: PASS, 235 suites (227 runtime+8 special), 630 GDScript files, прежние176 size warnings.
- `PYTHONPATH=tools python -m unittest tools/test_ci_suite_coverage.py tools/test_runtime_suite_runner.py`:14 PASS. Первоначальный запуск без PYTHONPATH дал import error; исправленный запуск выполнен, код тестов не менялся.
- `git diff --check`: PASS.

Локальная копия sparse; полный biomass_floor_bake/main scene, native GPU, Windows/Web и FPS не проверялись повторно. Внешний CI нового PR проверяется после публикации.

## Отдельный CI blocker предыдущей базы

PR474 / `df78e18c`: Architecture validation и Mission music transitions SUCCESS; Mission runtime regressions FAILURE, run40236269088. Единственный упавший headless suite — `game/core/audio/tests/run_sound_event_tests.gd` (job121298414524, exit64): OGG-only policy отвергает присутствующие WAV и `.wav.import` в assets/audio/sfx (access denied, biological_rupture и другие). N03 suite и biomass_floor_bake в полном CI — 0 failures, native jobs успешны. Это наблюдение по прежнему commit, не результат нового N04 CI. Аудиофайлы и policy не изменялись в N04; blocker требует отдельного согласованного инкремента без удаления пользовательских исходников.

Следующее действие: проверить PR/CI N04 и отдельно устранить WAV/OGG policy blocker; затем N05. T004 остаётся IN_PROGRESS.
