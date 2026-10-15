# A05 — жизненный цикл аудиопрогрева

Дата: 16.10.2026. База: main `d91b33d2`, Godot 4.7.2 stable, Linux headless.

## Результат

`office_floor/audio_warmup.gd` — внутренний узел существующего mission warmup.
Он живёт под переданным корнем миссии, отдельно от четырёхкадрового viewport,
и удерживает все60 AudioStream до выхода миссии. Готовые/неудачные запросы
завершаются через load_threaded_get; во время кадра IN_PROGRESS пропускается.
После завершения очередь пуста и `_process` выключен. На паузе сбор продолжается.
Повторные запросы учитывают cache и состояние ResourceLoader; пересекающиеся
миссии разделяют immutable streams. Если прежний владелец уже освободил общий
результат, оставшийся владелец повторяет загрузку асинхронно.

При раннем выходе `_exit_tree` завершает оставшиеся запросы, затем освобождает
streams. Только этот путь может ждать чтения: отмены threaded request здесь нет.
Длительность ожидания на медленном диске отдельно не измерялась.
Сигнатуры SoundEvents, публичные контракты, owners/зависимости модулей, сцены,
аудиофайлы, DTO и форматы сохранений прежние; исключений архитектуры нет.

## Проверки

- Исходный `run_shader_warmup_tests.gd` на main: assertions0 failures,
  **60 ObjectDB instances leaked at exit**. С исправлением —0 failures,
  предупреждений ObjectDB нет; добавлены assertions, что после удаления
  viewport продолжают жить AudioWarmup и все60 streams, очередь завершена.
- Новый `run_audio_warmup_lifetime_tests.gd`: все9 вариантов двух событий,
  неизвестное событие, повторный start, два одновременных владельца, пауза,
  отключение polling, идентичность ресурсов, weakref после teardown,
  раннее удаление, повторная миссия, уход владельца общего результата.
  Assertions0 failures, предупреждений ObjectDB нет. Suite добавлен в CI.
- Отдельная временная отрицательная проба с повреждённым .tres:
  request вернул OK; до сбора THREAD_LOAD_FAILED(2), после —INVALID_RESOURCE(0),
  pending0/streams0. Две ожидаемые ошибки парсинга/загрузки ресурса,
  предупреждений ObjectDB нет. Fixture не включена в игровые assets.
- Целевые suites: lifetime, shader_warmup, sound_event, adaptive_audio,
  server_audio, startup_resource_memory, sound_hook, ui_sound,
  destruction_sound, skill_sound, planner_persistence —11 наборов PASS.
- Startup включает загрузку и перезапуск полной карты5363 объектов;
  failures0, предупреждений ObjectDB нет. Первый замер: allocator935.40MiB,
  RSS1207.49MiB, video0; это headless проверка, не оценка FPS.
- `validate_project.py` PASS (включая READY spec/workflow, architecture,
  scene/resources и source-size); Godot editor import PASS; diff check PASS.
  Source-size121 прежних предупреждений, новых превышений нет.

Поведение кадрового прогрева и завершение ресурсов проверены автоматикой.
Windows/Web и прослушивание реального микса остаются ручной приёмкой.
Это исправление подтверждает причину60 предупреждений warmup; другие утечки
из исходного аудита (например lamp_lighting) требуют отдельной проверки.
