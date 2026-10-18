# Проверка шагов по стеклу и OGG

База main892c25a, Godot4.7.2, Phase1/T004. Отсутствует The_heavy_character_1:
реализован ровно один запрос player_roll при принятом перекате и optional
canonical OGG entry. Для завершения нужен сам файл записи; звук не подменён.

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
После поступления записи переката запустить converter, убедиться в одном
player_roll OGG на принятие roll, отсутствии звука при cooldown/idle.
Прослушивание, Iris Xe/Web FPS и ручная Windows приёмка здесь не выполнены.

## Автоматический результат

Чистый editor import Godot4.7.2 без ошибок. Все17 перечисленных targeted suites
прошли; sound_event повторён после добавления OGG-only CI guard. 18 Python
тестов audio_generation PASS. Project/spec/workflow/architecture/source-size,
CI176 registrations,383 scene references, resource paths, export pack и diff PASS.
Все5 новых конвертаций и30 исторических подтверждены hashes/decode; исходники
отсутствуют в git tree и отдельной чистой worktree. Корреляция reverse cues
после выравнивания Vorbis padding >0.999. Ручная/аппаратная приёмка не выполнена.
