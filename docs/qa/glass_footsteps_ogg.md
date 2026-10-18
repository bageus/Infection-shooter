# Проверка шагов по стеклу и OGG

База main6fa115b, Godot4.7.2, Phase1/T004. В main добавлен настоящий
The_heavy_character_1: конвертирован в player_roll_1.ogg, подключён обычным
событием и проверяется на реальном движении игрока. Два новых blinds WAV
также конвертированы; все восемь конвертаций имеют hashes/decode receipt.

## Проверки

- run_glass_footstep_tests: настоящая player сцена/пол, подошва capsule, пиксели
  стекла, чистый пол/бумага/высота/transform/clear; random64 контакта покрывают
  все4 supplied recordings. Roll/airborne молчат как walking. Реальное разрушение
  glass_wall_full помечает shards, проверяются физическое стекло без декали и
  исчезновение layer0. Освобождённый query collaborator безопасен.
- sound_event, ui_sound, blast_feedback: Vorbis resources, voice limits,
  pause/lifecycle, непрерывная полусекундная петля звона. Reverse cues после
  lossy encoding сравниваются дополнительно через decode/correlation с учётом Vorbis block padding (до512samples).
- convert_runtime_audio.py --check: hashes, decode, source WAV/import removal,
  отсутствие AudioStreamWAV и прямых WAV ссылок во всём runtime.
- import_audio_refresh.py --check: прежние обработанные записи byte-identical.
- Existing glass/material debris, destruction, player skill/roll and world
  binding suites проверяют отсутствие регрессий исходной композиции.

## Ручная приёмка

Разбить окно, монитор/телевизор; пройти и пробежать по крупному стеклу и
россыпи, затем выйти на чистый пол. После clear/map reload хруст пропадает.
Бумага/дерево не должны давать хруст. Перекат не вызывает walking cues.
Убедиться в одном player_roll OGG на принятие roll, отсутствии звука при
cooldown/idle. Звук должен соответствовать The_heavy_character_1.
Прослушивание, Iris Xe/Web FPS и ручная Windows приёмка здесь не выполнены.

## Автоматический результат

На объединении с main6fa115b: clean editor import Godot4.7.2 без ошибок.
Все19 targeted suites PASS: прежние17 плюс baked_surface_decal и
surface_decal_options. Roll regression проигрывает настоящий player_roll_1.ogg
ровно один раз при принятии переката. 18 Python audio_generation tests PASS.
Project/spec/workflow/architecture/source-size/CI184 registrations/384 scene refs,
resource paths/export pack/diff PASS. Receipt8 и исторические30 конвертаций
подтверждены hashes/decode; WAV/.wav.import/PCM ресурсов не осталось.
Конфликты с main разрешены с сохранением обеих функций: хруст стекла и
процедурные следы шагов. Ручная/аппаратная приёмка не выполнена.

## Исправление CI baseline

Старый pinned d7245e7 использует UI PCM .tres. Его код нельзя запускать с
assets текущего кандидата: эти ресурсы намеренно удалены после конвертации.
Workflow архивирует game и assets одного baseline commit; shared models/addons/
.godot остаются прежними. Старый случай воспроизвёл8 preload ошибок, новый
успешно компилирует оба настоящих skin probe (--headless --check-only).
Old PCM существует только во временном эталоне CI; production OGG-only guard
сохранён. Реальное native сравнение проверяется новым CI.
