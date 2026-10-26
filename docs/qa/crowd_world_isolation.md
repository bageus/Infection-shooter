# Q02 — crowd separation изолирован по World3D

26.10.2026. T004/Phase1/P1_LOGIC, Implementation. База main2836f85. PR483 уже merged, все3 workflows его head3d022321 SUCCESS; прежние CI blockers закрыты.

## Исправление

`features.infected/crowd_separation.gd` хранит `_current`/`_previous` по physics-space RID. Private `_WorldFrame` группирует cells, body IDs и positions одного мира/кадра. Важно изолировать и previous positions: при reparent в другой мир нельзя вычислять отталкивание от старой позиции из покинутого мира.

Общий rollover по physics frame и прежнее отбрасывание snapshot после пропущенного кадра сохранены. Snapshot содержит только числа, позиции, RID-ключ и packed arrays, не удерживает Node/World3D. При следующем rollover остаются только последний/текущий кадры активных миров, постоянного реестра миров нет. При отсутствии соседей в предыдущем кадре этого мира возвращается zero после регистрации текущего положения.

Радиусы/scale,3×3 соседние клетки, диапазон клеток2м, push cap2.5м/с, обработка совпавших движущихся пар и collision mask/layers прежние. Два SubViewport, намеренно использующих один World3D, по-прежнему взаимодействуют. Нового global service/Autoload/owner нет: это прежний private module-owned derived cache с дополнительной областью ключа. Public API/DTO/scenes/resources/dependencies/policy не меняются; исключений нет. Production файл93 строки, одна ответственность, декомпозиция не требуется.

## Регрессия

Новый registered suite `game/features/infected/tests/run_crowd_world_tests.gd` работает с настоящими SubViewport, World3D и CharacterBody3D, без mock PhysicsServer и без ручного reset private cache.

- До исправления: **7 assertion failures, exit1**, без script errors/утечек.
- После: **0 failures, exit0**, чистый error/leak scan.
- Разные миры: совпадающие позиции и соседние клетки не создают phantom push, включая чередование порядка регистрации.
- Общий World3D в разных viewports: ожидаемые противоположные скорости ±1.7857143м/с при spacing0.2м/default width0.7м.
- Две близкие пары в разных мирах дают те же скорости, несмотря на interleaving/reverse order; mask bit2 снят, map mask1 и bullet layer2 остаются.
- Reparent из worldA/position50 в worldB/position0.2 использует snapshot соседей B и новую позицию, а не прежнюю позицию A.
- После пропуска physics frames stale neighbours не используются.
-8 циклов create/free/recreate: WeakRef подтверждает освобождение World3D, новый мир не наследует соседей удалённого.

## Сохранение поведения внутри одного мира

Временный headless probe сравнил исходный script из main2836f85 и исправленный.90 Node3D, сетка10×9 со spacing0.25м;120 physics frames, positions обновляются `push/60`, порядок регистрации одинаковый. Все **10800 velocity vectors совпали точно**. Каждый процесс завершается чисто.

Для90 вызовов spread/frame median после первых2 кадров:1228.5мкс до /1227.5мкс после (одна пара запусков в этой среде). Это проверка на явную дополнительную стоимость и совпадение поведения, не статистический benchmark и не результат игрового FPS/GPU. Тяжёлые rendered/native/Windows/Web замеры не выполнялись.

## Проверки

Pinned Godot4.7.2 `ed1daf0bf`. Targeted suites и editor проверяются в текущем инкременте; полный GitHub CI — после публикации. Частичная локальная копия: первоначальный старый crowd suite дал0 assertions, но сообщил missing audio files. Материализованы оригинальные tracked growl_hunger/hunger_fours_voice/hunger_voice/step_light OGG; ранний запуск не считается PASS. Production audio не изменялось.

`validate_project.py` — PASS,239 suites (231 runtime+8 special),636 sources,177 существующих size warnings.14 Python CI coverage/runner tests и diff-check — PASS. 

Следующее действие: проверить отдельный PR/CI Q02, затем R01 — controlled diagnostics/cancel/deadline фоновой загрузки. G01 остаётся отдельным дизайном общего статического shadow layer. T004 остаётся IN_PROGRESS.


Финальная проверка:5 focused suites crowd_world, crowd_separation (реальная толпа12 и moving coincident pair), chase_real_enemy_slope, chase_route, chase_search_motion — exit0/0 failures, без engine errors/утечек. Реальный infected дошёл до цели на flat/slope15,100% floor contact в174/375 проверенных кадрах. Final headless editor import/open — exit0, error/leak scan чистый. Исходный новый world suite7failures→0, однопроцессные trace before/after без ошибок/утечек.


## Repair всех import jobs PR487 — 26.10.2026

Head059425b9: Architecture SUCCESS, run40340793554 — все11jobs FAILURE на стадии Import (до runtime assertions). В runtime job121634619998 и planner Forward+121634620287 повторяются одни parser errors: `assets/icons/game_icon_{32,64,128,256,512}.png.import:6`, Expected value, got '='. В каждом файле из base2836f85 остались `<<<<<<< HEAD / ======= / >>>>>>>107de261` вокруг двух UID. Это не ошибка world snapshot/crowd logic.

Удалены только markers и дублирующий incoming UID. Сохранены UID исходного HEAD, сверенные с094f5ff8; path/source/params и PNG не меняются. Хеши всех5 PNG совпадают с git HEAD. Parser errors воспроизведены на pinned Godot4.7.2 editor:20 ERROR lines; после исправления0 errors/leaks. ConfigFile.load и Texture2D.load для всех5icons PASS, размеры32/64/128/256/512 совпадают.

`check_import_files.py` теперь отклоняет unresolved merge/diff3 markers в существующем import metadata. Он включён в validate_project для раннего отказа; существующие valid=false/unsafe recompression checks сохранены.6 unit tests (merge/diff3/incomplete, valid metadata, quoted marker text, failed import, recompression) PASS, добавлены в architecture workflow. Вместе с11coverage+3runner —20Python tests PASS. До исправления actual metadata новый gate отклонял все5 файлов, после PASS. Финальные editor, icon probe, crowd_world и crowd_separation — exit0, error/leak scans чистые; project239suites/636sources/177warnings, import guard и diff-check PASS.

Production Q02 code/математика/owners/API/DTO/сцены/бинарные icons не меняются в repair. Full new GitHub CI/native/Windows/Web пока CI_PENDING. Следующее действие — обновить текущий PR487 и проверить все jobs.
