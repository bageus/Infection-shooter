# Музыка миссии: Hold / Threat / Hunt

Прямой запрос владельца20.10.2026. Hold уточнён до56секунд. T004/Phase1/P1_LOGIC.

## Записи

Actions Prepare mission music успешно выполнил readiness gates, conversion/decode/hash checks. tower_hold_1.wav60с → tower_hold.ogg56с; tower_threat_1.wav120с → tower_threat.ogg120с сloop_offset30.08с. Первые30с — вступление,31-я секунда начинается в30.0;80мс головы петли уже сведены с её хвостом. server_oper.ogg119.92с → server_oper_active.ogg89.92с: первые20/последние10с удалены, offset0.08с. Все записи stereo48kHz/Vorbisq5, пик ограничен0.89. Receipt assets/audio/mission_music_processing.json. WAV удалены после проверки, исходный server_oper.ogg сохранён. Seamless исключён только из runtime playlist.

## Переходы

MissionMusic наблюдает подтверждённый projectile_blood заражённых и публичный is_alerted, не здоровье/AI. До попадания спокойная музыка; больше10агрессоров включаетHunt независимо от попадания. При <10Hunt затухает вThreat, ровно10 сохраняет прежний режим. После3с без активного боя музыка возвращается к активной частиServer Oper. ПовторThreat в том же бою послеHunt начинает тело, не вступление.

MusicCrossfade удерживает не более3голосов, интерполирует мощность из текущих gains за4с, не перезапускает уже играющий нужный голос. Готовые calm/threat/hunt петли повторяются native loop одним голосом с авторским loop_offset; runtime перекрытие4с удалено после сообщения о двойном бите Server Oper. Явные повторы Hold сохранены. Скрытый headless не запускает декодеры, но сохраняет clocks/state. Пауза замораживает музыку миссии.

CompletionMusic создаётся bootstrap root при успехе и явно передаётся по ссылке front_end/loader. Сам проигрыватель не переподвешивается, курсор не сбрасывается. Долгое меню/загрузка повторяютHold с4с overlap; при выходе вmain завершается текущая56с запись, затем main_menu плавно включается. На готовности следующей миссии Hold затухает за4с вместе с началомcalm. Ошибка загрузки передаёт голос вmain, отмена освобождает его. ШинаMenuMusic сохраняет настройки меню. Continue выбирает следующую карту цепочки; для standalone-прототипа без следующей карты остаётся существующий restart route.

Bootstrap остаётся владельцем; нет Autoload, service lookup, новых module dependencies или gameplay/public/save DTO. main.gd>300 reviewed: только композиция, музыкальная логика вынесена в private helpers. loader>300 reviewed: активация pending выделена отдельно от загрузки; функции <=100.

## Проверки

Readiness gates и offline conversion Actions: PASS. Следующий этап — project gates, Godot import, run_adaptive_audio_tests (headless/native), shutdown, loading, menu, level carry/chain и общий CI. Итоговые статусы добавляются после выполнения. Native playback через Dummy проверяет lifecycle, субъективная громкость/музыкальность склеек требует прослушивания владельцем.


## Итог проверки кодовой версии d927be352c82917a694ee98e0d303df7b700fb0c

Actions39482802949 полностью SUCCESS: decode/SHA/duration receipt, validate_project, Godot4.7.2 import, run_adaptive_audio_tests/headless и native(gl_compatibility/Dummy), music_shutdown, mission_loading, menu integration, level_carry и level_chain —0failures. Assertions включают точный gain continuity, Threat body-loop overlap, тот же playback instance при смене сцены, долгую загрузку/ошибку и очистку Hold на готовности уровня. Architecture39482803153 SUCCESS. Эти результаты относятся к неизменяемому коду/тестам указанного commit; следующий commit содержит только документацию. Общий runtime/rendering CI выполняется отдельно. Субъективная оценка громкости/музыкальности переходов остаётся ручной приёмкой.


20.10.2026 — loop fix проверен: validate_project (spec/workflow/architecture/source-size/CI coverage) PASS, conversion receipt/decode/SHA PASS, чистый Godot4.7.2 import без ERROR, adaptive_audio и music_shutdown0failures, diff-check PASS. Native wrap проверит существующий Actions job; локального display/Xvfb нет, субъективное прослушивание не выполнено. Следующее действие: review PR исправления петли и native CI; T004 IN_PROGRESS, merge не поручен.


21.10.2026 — PR400 CI repair (T004/IMPLEMENTATION, Phase1/P1_LOGIC): Architecture39492262408 и runtime39492262389 падают на одном resource-path gate: после конверсии остались tower_hold_1.wav.import и tower_threat_1.wav.import без WAV. Музыкальный workflow39492262387, включая native wrap, SUCCESS; все7 rendering jobs SUCCESS. Удалены только2 устаревших sidecar, process_mission_music --check теперь отклоняет оставшийся sidecar удалённого WAV (воспроизведён FAIL до удаления и PASS после). PASS: readiness/project gates,384scene refs,resource paths,export audit,18audio-tool tests,conversion/decode/SHA. Runtime/gameplay/OGG/API/DTO/owners/dependencies прежние, архитектурных исключений нет. Следующее действие: опубликовать исправление в ту же ветку PR400 и проверить новый CI; merge не поручен.
