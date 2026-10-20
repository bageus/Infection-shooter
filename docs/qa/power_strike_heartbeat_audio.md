# Авторские звуки мощного удара и Второго сердца

Запрос владельца20.10.2026, основа main741fbc80, T004/Phase1.

- `power_blow/a_powerful_destructi_1.ogg`: событие `skill_power_strike`, все три уровня навыка через существующий успешный `skill_cast`. Когти сохраняют прежний звук.
- `heartbeat/very_loud_a_strong_b_1.ogg`: событие `skill_heartbeat`, запускается при создании процедурной анимации сердца. Голос дочерний узел анимации, следует за игроком, наследует паузу и удаляется вместе с эффектом. Запись проигрывается один раз, без pitch jitter и зацикливания. Существующий `skill_second_heart` при спасении сохранён.
- Оба WAV2с/stereo48кГц преобразованы штатным `tools/convert_runtime_audio.py` в mono48кГц/Vorbisq5. Без обрезки длительности; штатные микрофейды5мс и ограничение пика. Исходники удалены только после декодирования и записи SHA256 в `assets/audio/glass_audio_processing.json`.
- Исходные WAV суммарно768156байт, новые OGG41697байт. Пути/метаданные лицензий в CREDITS обновлены.

Проверено на Godot4.7.2 headless:

- `python tools/validate_game_spec.py --ready`, `validate_workflow_state.py --ready`, `validate_project.py`: PASS.
- `python tools/convert_runtime_audio.py --check`:10 записей, SHA256/decode/OGG-only PASS.
- `python -m unittest discover -s tools -p test_audio_generation.py`:18 tests PASS.
- `run_sound_event_tests`, `run_skill_sound_tests`, `run_skill_vfx_tests`, `run_mutation_skill_mechanics_tests`:0failures.
- Headless editor import: exit0, без SCRIPT ERROR/ERROR.
- `git diff --check`: PASS.

Тесты проверяют реальные OGG пути, отдельный звук для каждого уровня удара, отсутствие замены когтей, запуск/следование/пауза/раннее завершение сердцебиения вместе с анимацией. Сцены, публичные API, DTO, owners, dependencies и policy не менялись. mutation_skill_vfx выше300строк reviewed: локальное представление навыков сохраняет одну обязанность, новая подсистема не нужна.

Прослушивание и визуальная приёмка в native не выполнялись. В main остаются прежние конфликты авторской карты: отдельные scene/export CI могут падать, как в PR383. Выбор раскладки владельцем ожидается; в этом PR карта не меняется.
