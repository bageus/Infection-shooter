# R01 — ограниченное ожидание ресурсов и отмена загрузки

26.10.2026. T004/Phase1/P1_LOGIC, Implementation. База main9330742b; пользовательские migration scripts/UID и остальные изменения сохранены. PR487 merged, оба workflow head d043a9d4 SUCCESS.

## Поведение

- Ожидание каждого issued request в состоянии THREAD_LOAD_IN_PROGRESS ограничено120с. Диагностика указывает elapsed ms, путь, status и последнее значение native progress. Это не общий лимит длительности всей карты.
- Кооперативная подготовка scripts также проверяет deadline120с на path и existing alive callback между операциями/yields.
- Named-map `prepare_async` передаёт существующий alive callback внутрь очереди ресурсов. Недействительный callback удалённого владельца считается отменой, а default пустой Callable по-прежнему разрешает работу.
- Mission loading показывает отдельную кнопку «Отменить загрузку» / Cancel loading на стадиях запроса и подготовки ресурсов. Кнопка Back сохраняет прежнее значение: появляется при ошибке. Отмена прекращает новые запросы и возвращает прежнюю сцену/visibility/collision masks/pause/mouse через прежний rollback; успешный startup не публикуется. При уже освобождённой предыдущей миссии применяется прежний переход в главное меню.
- Перед instantiate и чтением startup map повторно проверяется отмена. При начале commit отмена скрывается; атомарный rollback частичного commit/warmup в этот инкремент не добавлен.
- После timeout/error частичный payload очищается. Повторный запрос файла, который ещё IN_PROGRESS в ResourceLoader, отклоняется с сообщением дождаться завершения: cancelled job не размножает ссылки на тот же native request.

## Жизненный цикл native request

Godot не предоставляет безопасного cancel уже запущенной native загрузки. Новый private `scene_resource_request.gd` владеет одной issued request и подготовленными script references. `take` не вызывает threaded_get при IN_PROGRESS и потребляет результат один раз; повторный start того же request запрещён. При отмене/timeout уже выданные jobs дочитываются отдельно после terminal status. Instance-bound process_frame callback держит только request/scripts, не CanvasLayer/сцену, и отключается после завершения.

Ожидание UI возвращается сразу, не дожидаясь зависшего native worker. Если worker реально никогда не завершится, его engine request/script references останутся до завершения/выхода приложения; это неизбежное ограничение отсутствия native cancel. Лимит очереди2 requests/attempt, Dummy renderer1 main-thread request сохранён. Глобального реестра/Autoload, автоматических retries и нового owner нет. Уже начавшуюся синхронную операцию load/compile нельзя прервать cooperative callback; deadline проверяется между операциями. Это не обещание прерывания заблокированного main thread/драйвера.

Root mission scene использует тот же queue/watchdog вместо отдельного бесконечного threaded loop. Dummy следует существующей политике очереди main-thread mesh safety; Compatibility/Forward+ используют background pipeline. Native fraction добавляется к монотонному progress; stats сохраняют прежние поля. Отменённая/неполная подготовка scripts не переиспользует visited cache при следующей попытке, а выданные старые jobs удерживают прежний preparation до безопасного release.

## Scope и review

Private bootstrap files: scene_resource_request, scene_resource_queue, scene_resource_preparation, planning_layout_loader, menu/mission_loader. Public module API, map/cache/network DTO, сцены/ресурсы, owners, dependencies, policy прежние; исключений нет. Default optional arguments сохраняют существующие вызовы. Mission loader392 строки и layout loader302 строки reviewed: orchestration прежнего startup/transaction, backend request lifecycle вынесен в отдельный helper; queue124 строки. Функции остаются ниже hard100, файлы ниже600. Широкий refactor UI/transactions не смешивался с исправлением ожидания.

## Fault injection и regression

Новый registered `run_loading_deadline_tests.gd` использует настоящую очередь, preparation, layout loader, CanvasLayer, SceneTree pause/input и rollback. Только native request/status/get/clock в негативных сценариях заменены контролируемым backend; реальный навсегда зависший Godot worker не создаётся и его появление в baseline не заявляется доказанным. Новый helper дополнительно проходит настоящий ResourceLoader request/status/get smoke на fixture scene.

- Timeout одного stalled job после готового payload: partial resources очищены, следующий path не запрашивается, ошибка содержит путь/status/progress.
- Cancel с двумя pending jobs; terminal failure при втором stalled job; immediate request rejection; retry/dedup после завершения; busy previous request без повторной выдачи.
- Ни одного native get при IN_PROGRESS; все issued jobs потреблены ровно один раз после delayed completion.
- WeakRef подтверждает удержание preparation/job при detach и освобождение обоих после completion.
- Freed callback owner отменяет queue и script preparation до выдачи запроса.
- Layout cancellation завершается до instantiate/clear/commit.
- Mission Cancel при исходной pause=false/true и вызов Back во время ожидания: старые visibility/layers/masks/pause восстановлены, completed(false) один раз; поздний completion не меняет current_scene. Timeout оставляет pending=null, возвращает Back и показывает диагностику файла.
- Реальный native request возвращает PackedScene, повторный start/get не выдаёт/не потребляет запрос повторно.

## Локальная проверка

Pinned Godot4.7.2 `ed1daf0bf`, отдельный XDG_DATA_HOME для каждого финального suite:

- loading_deadline, p2_optimization (включая реальный Dummy/main-thread mesh loader), mission_loading (startup/restart/corrupt-save recovery), named_map_loading, layout_loading, unresolved_map_records, authored_transform_restore: все7 suites exit0,0 failures, error/leak scans чистые.
- Final editor import/open exit0, без ERROR/SCRIPT ERROR/leaked/resources still in use.
- `validate_project.py`: PASS,241 suites (233 runtime+8 special),640 sources,177 size warnings; import metadata guard PASS.
-20 Python import-guard/CI coverage/runner tests и diff-check PASS.

Изначальные расширенные startup прогоны sparse-копии выявили отсутствующие локально original SFX, launcher art, blood/debris PNG (0 assertions, но engine errors). Они не считались PASS; материализованы исходные tracked dependencies и финальные suites повторены в изолированных user-data directories. Один промежуточный fault probe остановлен; последующие финальные изолированные прогоны чистые. Assets/модели/аудио не изменены в git.

Полный GitHub CI нового head, actual native Compatibility/Forward+/Web/Windows, визуальный вид Cancel и FPS/target hardware не подтверждены локально. Симуляция stalled backend проверяет контроллер/cleanup, а не исправление внутренних зависаний самого Godot. Следующее действие — PR/полный CI R01, затем отдельный дизайн G01 общего static shadow layer. T004 остаётся IN_PROGRESS.


## Интеграция свежего main7de9687c перед публикацией

За время реализации в main после9330742b появились10 новых WAV,26 orphan .wav.import, удаление обязательного runtime break_metal_3.ogg и повторные merge markers в5 icon imports. Эти проблемы не скрывались в CI и не были смешаны с логикой loading lifecycle. Main интегрирован локально; user project name/credits edits сохранены.

Сопутствующий compatibility repair:5 icon UID conflicts разрешены с сохранением исходных HEAD UID и PNG. Все10 WAV побайтно перенесены в source_audio/incoming_2026_10_26 с SHA256 manifest и original path mapping; ничего из исходных записей не потеряно. Папка исключена из Godot import/export через .gdignore и явный source_audio/* в обоих presets, check_export_pack проверяет исключение и отсутствие runtime references.26 generated orphan WAV sidecars удалены. Только отсутствующий обязательный break_metal_3.ogg восстановлен конвертацией соответствующего нового WAV через существующий converter (mono48k/Vorbis5,5ms fade/peak cap); результат ffmpeg-decode проверен, source сохранён. Остальные9 записей оставлены исходниками для отдельного подключения, текущие OGG/voice groups/credits не заменялись.

На интегрированном дереве повторены8 targeted suites: R01/P2/mission_loading/named/layout/N01/N02/sound_event — все exit0 без errors/leaks; final editor чистый. Runtime OGG-only contract снова PASS. Export source audit и audio generation dry-run PASS;20 import/coverage/runner Python PASS, отдельный audio-generation suite проверен. Full CI нового head всё ещё CI_PENDING.

Событие `break_metal` переведено в защищённые в `tools/audio_generation_manifest.json`: варианты 1/2 сохранены, новый записанный вариант 3 не может быть перезаписан синтетическим генератором.
