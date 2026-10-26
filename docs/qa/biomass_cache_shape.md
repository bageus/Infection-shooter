# N05 — форма лампы и актуальность запечённого слоя

26.10.2026. T004/Phase1/P1_LOGIC, Implementation. База main70ab64d.

## Результат

Private `bootstrap.app/planning_biomass_bake.signature` включает существующее поле `fixture_shape`. Point, linear и rectangle создают разное число SpotLight с разными offsets, поэтому при неизменных энергии/положении их старые страницы больше не считаются актуальными. Production capture уже сохраняет поле; loader и planner exit уже используют эту подпись — их алгоритмы не менялись.

После редактирования формы без сохранения выход из планировщика скрывает stale cache и сохраняет отображение исходников. Следующий Save Map/Layout запекает новый слой и записывает новую подпись. Возврат к исходной форме снова допускает соответствующие исходные страницы. Sync/async loader отклоняет только неподходящий optional cache, не карту/объекты.

API, map-v8/cache-v1 DTO, сцены, owners/dependencies и policy прежние; исключений нет. Script100 строки, одна прежняя обязанность canonical fingerprint, декомпозиция не требуется. После исправления CI ниже старые подписи default point сохраняются; старые nondefault linear/rectangle caches отклоняются на load до создания view и используют исходники до Save Map/Layout. Автоматического bake при загрузке нет. JSON int/float и signed zero по-прежнему эквивалентны. Остальные отсутствующие входы или whole-scene shadow layer не объявляются реализованными.

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


## Repair CI PR481 — 26.10.2026

Head09f495ad: Architecture SUCCESS; runtime40310195156 FAIL, music40310195027 timeout180, planner Forward+ timeout300. Runtime assertions N04/N05 прошли, но старый biomass_floor_bake дал3 failures и ui_sound сообщил2 resources still in use. Артефакт planner-rendering-forward_plus12644342771: контакт/occlusion/P2 PASS, extension дошёл до corpse physics177746мс и не завершил aim до300с; script/shader errors нет.

Подтверждённая регрессия N05: добавление нового столбца во все canonical rows меняло подпись даже у point/default карты. Поэтому shipped cache из5 страниц для322 source pieces больше не подходил. Теперь прежние canonical rows сохраняются для отсутствующего/default point; только nondefault topology добавляет именованное поле в row. Default hashes/готовые PNG сохраняются, все6 смен формы по-прежнему различаются. Старый nondefault cache не совпадает с новой подписью уже на loader.prepare и отбрасывается до создания view, поэтому не может затем восстановиться как cache другой формы. Save после правок строит новый cache. Файлы авторской карты/страниц не переподписаны и не изменены.

Старый lighting regression ожидал, что private lamp.shadows=false отключает structural ray: это отменено N04. Теперь тест сначала исключает roof из camera_occluder для проверки цвета/энергии, затем возвращает и проверяет тень при том же false. Signed-zero probe использует runtime0, а не общий failures count (прежний первый failure превращал «zero» в -1).

UI sound fixture отслеживает weak refs активных playback до удаления frontend/tree UI и ждёт фактического освобождения mixer ownership (не более1с) перед quit. Реальная OGG playback специально удерживается50мс: проверка доказывает ожидание отложенного mixer release даже на быстрых машинах. Production audio и test assertions сохранены.

Лимиты music180/planner300 не увеличены; восстановление default cache устраняет добавленную работу на старте. Окончательное устранение обоих тайм-аутов подтверждается только новым CI, а не локальным предположением. Public API/DTO/owners/edges прежние; исключений нет.


Финальная локальная проверка repair: после материализации оригинальных structural GLB и enemy game rigs полный biomass_floor_bake на старых HEAD script/test воспроизводит ровно3 assertion failures (exit3), на исправленных —0 (exit0), без прочих engine errors/leaks.9 targeted suites PASS: biomass_floor_bake, cache_shape, static_shadow, light_energy, light_budget_cache, authored_restore, unresolved_records, map_file, ui_sound. UI suite дополнительно3 последовательных процесса PASS с delayed mixer probe. Editor import/open чистый. Project gates238suites/635files/177warnings и14Python PASS. Native/music/planner timings повторяет GitHub CI; до его результата они CI_PENDING, пределы180/300 прежние.
