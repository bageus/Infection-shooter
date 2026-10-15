# Обновление звуков — 15.10.2026

База: `0e154b73` (исходники владельца). Инкремент T004, фаза1.

## Результат и соответствия

| Исходник | Событие / применение |
|---|---|
| fire_extinguisher_boom | extinguisher_burst, разрыв огнетушителя |
| fire_extinguisher_fell | extinguisher_fall, первое падение |
| Sci-fi_metal_pop_sou | skill_cooldown_done, positive→zero активного кулдауна |
| Done_alive | skill_second_heart, успешное выживание после смертельного урона |
| hunger_*, revenant_* | соответствующие действия/варианты своего вида |
| colossus_idle/attack | простой / голос замаха Colossus |
| titan_idle/attack | простой / голос замаха Titan |
| horde_idle, horde_summon_1 | простой / призыв Horde |
| hunger_death_1, revenant_death_1 | смерть своего вида |
| colossus&titan_death_1 | heavy_death для обоих видов |
| roar_heavy_4 | colossus_voice_1, обычная речь Colossus, без перекодирования |
| m4_reload, ak_reload, sniper_reload | отдельные события перезарядки трёх винтовок |
| minigun_spin_1 | прежний путь петли минигана, новая запись |
| door_close_1 | закрытие обычной двери (папка door_close) |
| key_pickup_1 | подбор ключа |

Фактическое новое имя файла на четвереньках — `hunger_fours_voice_2.wav`;
сохранён прежний `_1`, добавлен `_2`. Titan idle уже были OGG, не перекодированы.
30 WAV→mono/48kHz/Vorbis q5, фейды5мс, ограничение пика, для spin
перекрытие петли80мс. Длительности, каналы и исходные/выходные SHA256
записаны в `assets/audio/audio_refresh_processing.json`. Каждый итоговый OGG
декодирован ffmpeg до удаления WAV. Все36 WAV (30 новых и6 музыкальных)
удалены; уже обработанные музыкальные OGG byte-identical базе.

Заменённые старые варианты огнетушителя/падения/двери/ключа удалены.
`scream_zombie` не существует в каталоге; последний `roar_heavy` перемещён
в colossus_voice. Способности, AI-слышимость, длительности перезарядки,
карта, сохранения и сетевые форматы не менялись. Добавлен публичный факт
infection.skill_cooldown_finished; контракт в module.json и ADR0048.

## Проверки

Godot4.7.2 Linux, headless:

- editor import exit0 без SCRIPT ERROR/ERROR;
- 15 различных suites PASS: sound_event, infected_voice, enemy_voice,
  skill_sound, infection/run_tests, hit_effect, new_weapon, destruction_sound,
  sound_hook, shader_warmup, mutation_skill_mechanics, adaptive_audio,
  server_audio, horde_escalation, hunger_behaviour;
- skill_sound проверяет начальное zero, обычное окончание, ускорение,
  отсутствие повторов/сигнала для неизученного навыка и Done_alive;
- new_weapon проверяет реальный звук перезарядки АК/M4/sniper и отмену;
- enemy_voice проверяет idle/death каждого нового вида и отсутствие
  удалённых событий; existing sound_hook Hunger fixture обновлён
  с общего enemy_death на видовой hunger_death;
- validate_project PASS (включает ready-spec, workflow, architecture и size);
  validate_scene_resources PASS:393; report --check PASS;
  import_audio_refresh --check PASS:30 decode/hash checks, нет WAV/import;
  git diff --check PASS.

shader_warmup завершился с прежним предупреждением ObjectDB (60 instances),
без ERROR; предупреждение не скрывалось. Новые изменённые production-файлы
меньше300строк; существующие предупреждения длинных функций не расширялись.

## Следующее действие

Создать PR, проверить CI, затем прослушать на Windows/Web: падение и разрыв
огнетушителя, оба способа завершения кулдауна, выживание при1HP, голоса
каждого вида, перезарядки/отмену, стык spin, призыв Horde, дверь и ключ.
В среде нет аудиоустройства: субъективная громкость и слышимый стык
не подтверждены. Полный runtime/native/Web CI не объявляется пройденным
на основании этих15 локальных suites. Merge этим запросом не поручен.


## Статус публикации

Владелец явно разрешил отправку кода, аудио и документации, включая оба
журнала, в bageus/Infection-shooter и создание PR. Предыдущий approval
blocker снят. Публикуется проверенное дерево; следующий шаг — запуск CI
и ручное прослушивание. Merge не поручен.
