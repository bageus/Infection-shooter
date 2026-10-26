# N05 — форма лампы и актуальность запечённого слоя

26.10.2026. T004/Phase1/P1_LOGIC, Implementation. База main70ab64d.

## Результат

Private `bootstrap.app/planning_biomass_bake.signature` включает существующее поле `fixture_shape`. Point, linear и rectangle создают разное число SpotLight с разными offsets, поэтому при неизменных энергии/положении их старые страницы больше не считаются актуальными. Production capture уже сохраняет поле; loader и planner exit уже используют эту подпись — их алгоритмы не менялись.

После редактирования формы без сохранения выход из планировщика скрывает stale cache и сохраняет отображение исходников. Следующий Save Map/Layout запекает новый слой и записывает новую подпись. Возврат к исходной форме снова допускает соответствующие исходные страницы. Sync/async loader отклоняет только неподходящий optional cache, не карту/объекты.

API, map-v8/cache-v1 DTO, сцены, owners/dependencies и policy прежние; исключений нет. Script100 строки, одна прежняя обязанность canonical fingerprint, декомпозиция не требуется. Подписи, рассчитанные без нового входа, больше не совпадают: старые карты используют исходники до повторного Save Map/Layout. Автоматического bake при загрузке нет. JSON int/float и signed zero по-прежнему эквивалентны. Остальные отсутствующие входы или whole-scene shadow layer не объявляются реализованными.

## Интеграция N04

PR475 был merged в `fix/biomass-bake-lamp-energy` уже после попадания N03 в main, поэтому main70ab64d не содержит его исправления. В текущую ветку перенесён прежний commit N04 (private sampler, suite/QA), без изменения проверенной production логики. Новый PR направлен непосредственно в main. Новые ORM512/export/audio изменения владельца сохранены.

Прежний аудио blocker теперь закрыт другими main changes: git inventory assets/audio содержит0 WAV/.wav.import, runtime использует OGG; main содержит конвертацию7c34cd68 и новые hooks c4624b23. Аудиофайлы/политика в этом инкременте не меняются. Полный текущий CI sound_event локально не объявлен пройденным.

## Regression

`game/bootstrap/app/tests/run_biomass_cache_shape_tests.gd` использует настоящую public lamp scene, production CAPTURE, signature, editing/restore, loader.prepare/prepare_async и public baked view. Для проверки применимости используется синтетическая валидная PNG512 страница и source-command spy; suite не измеряет качество raster bake.

- Все6 направленных переходов point/linear/rectangle.
- До N05: **24 assertion failures, exit1**, без script errors/утечек (6 signature,6 stale visibility,12 sync/async stale acceptance).
- После N05: **0 failures, exit0**, error/leak scan чистый.
- Неизменная форма допускает старую страницу; изменение скрывает её и включает source; обновлённая подпись допускается, undo формы снова допускает исходный cache.
- Синхронная/фоновая подготовка проходят реальный JSON roundtrip, отбрасывают старый cache, принимают новый; prepared nodes освобождаются через production discard.
- Legacy map без fixture_shape/cache загружается; canonical JSON и -0.0 сохраняются.

## Проверки и ограничения

Pinned Godot4.7.2 `ed1daf0bf`, headless. N05, N04 static_shadow, N03 light_energy, light_budget_cache, N02 authored_restore, N01 unresolved_records, map_file — PASS, без engine errors/leaks на финальных запусках. Editor import/open — exit0, error/leak scan чистый. `validate_project.py` — PASS,238 suites (230 runtime+8 special),635 source files,177 size warnings текущей базы.14 Python coverage/runner tests и diff-check — PASS.

Первоначальные запуски sparse-копии нашли отсутствующие локально access_denied/light_flicker OGG. Материализованы оригинальные tracked assets, после этого чистый baseline/исправленный suite и затронутые регрессии запущены повторно. Ошибочные ранние запуски не считаются PASS.

Полный main-scene/biomass_floor_bake suite, native GPU, Windows/Web и FPS в этом инкременте не измерялись. Проверки полного GitHub CI — после публикации. G01 остаётся отдельной задачей: общий статический shadow layer и удаление вклада разрушенных объектов. Следующий шаг — проверить CI нового PR, затем следующий пункт аудита; T004 остаётся IN_PROGRESS.
