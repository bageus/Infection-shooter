# Группы звуков заражённых

Автоматически: `python tools/update_enemy_audio_report.py`. Проверка актуальности: `--check`.

Вариант = отдельная запись. Выбор из группы альтернативный: несколько голосов одновременно не наслаиваются. Микроизменения высоты и громкости не считаются новыми комбинациями. Вероятности относятся к попытке воспроизведения; бюджет голосов и уже звучащая речь могут её пропустить.

## Добавленные группы

| Группа | Файлов / вариантов | Исходные записи |
|---|---:|---|
| hunger_idle | 2 | the_cry_of_a_person_3, hunger_idle_2 |
| hunger_voice | 2 | the_scream_of_an_inf_1, hunger_voice_2 |
| hunger_fours_voice | 2 | the_scream_of_an_inf_4, hunger_fours_voice_2 |
| hunger_alert | 2 | sounds_of_zombies_ta_2, hunger_alert_2 |
| hunger_attack | 3 | the_scream_of_an_inf_2, sounds_of_zombies_ta_3, hunger_attack_3 |
| hunger_agony | 1 | the_scream_of_an_inf_22 |
| hunger_feeding | 1 | zombie_damage_sounds_4 |
| revenant_voice | 3 | the_scream_of_an_inf_3, revenant_voice_2, revenant_voice_3 |
| revenant_attack | 3 | sounds_of_zombies_ta_4, revenant_attack_2, revenant_attack_3 |
| heavy_death | 1 | colossus&titan_death_1 |
| colossus_attack | 1 | colossus_attack_1 |
| colossus_idle | 1 | colossus_idle_1 |
| horde_idle | 2 | horde_idle_1, horde_idle_2 |
| hunger_death | 1 | hunger_death_1 |
| revenant_death | 1 | revenant_death_1 |
| revenant_idle | 2 | revenant_idle_1, revenant_idle_2 |
| titan_attack | 1 | titan_attack_1 |
| colossus_voice | 1 | roar_heavy_4 |
| titan_idle | 2 | titan_idle_1, titan_idle_2 |

В группах 32 записей, 19 групп. Источники обозначены историческими именами; WAV удалены по запросу владельца, в игре остаются OGG.

## Действия и состояния

| Вид / действие | Группы альтернатив | Вероятность голоса | Голосовых записей | Исходов, включая тишину |
|---|---|---:|---:|---:|
| hunger / idle | hunger_idle / growl_hunger | 65% | 5 | 6 |
| hunger / voice | hunger_voice / growl_hunger | 100% | 5 | 5 |
| hunger / fours | hunger_fours_voice / hunger_voice | 100% | 4 | 4 |
| hunger / idle_scream | hunger_voice | 100% | 2 | 2 |
| hunger / alert | hunger_alert | 100% | 2 | 2 |
| hunger / attack | hunger_attack / growl_hunger | 50% | 6 | 7 |
| hunger / pain | growl_hunger | 35% | 3 | 4 |
| hunger / agony | hunger_agony | 100% | 1 | 1 |
| hunger / feeding | hunger_feeding | 100% | 1 | 1 |
| hunger / death | hunger_death | 100% | 1 | 1 |
| revenant / idle | revenant_idle | 65% | 2 | 3 |
| revenant / voice | revenant_voice / growl_revenant | 100% | 6 | 6 |
| revenant / attack | revenant_attack / growl_revenant | 50% | 6 | 7 |
| revenant / pain | growl_revenant | 35% | 3 | 4 |
| revenant / death | revenant_death | 100% | 1 | 1 |
| colossus / idle | colossus_idle | 65% | 1 | 2 |
| colossus / voice | colossus_voice / growl_colossus | 100% | 4 | 4 |
| colossus / attack | colossus_attack | 50% | 1 | 2 |
| colossus / pain | growl_colossus | 35% | 3 | 4 |
| colossus / death | heavy_death | 100% | 1 | 1 |
| titan / idle | titan_idle | 65% | 2 | 3 |
| titan / voice | growl_titan | 100% | 3 | 3 |
| titan / attack | titan_attack | 50% | 1 | 2 |
| titan / pain | growl_titan | 35% | 3 | 4 |
| titan / death | heavy_death | 100% | 1 | 1 |
| horde / idle | horde_idle | 65% | 2 | 3 |
| horde / voice | growl_horde | 100% | 2 | 2 |
| horde / attack | growl_horde | 50% | 2 | 3 |
| horde / pain | growl_horde | 35% | 2 | 3 |

Fours применяется к Hunger на четвереньках; голос hunger_fours_voice используется только в этой позе, а не в обычной стойке. Agony запускается только вместе с успешным стартом Agonize. Feeding звучит после BiteDown, с интервалом 2,4–3,2 с и прекращается при подъёме, тревоге, потере ноги или смерти. Idle scream не вызывает тревогу.

## Комбинации конкретного действия

У атаки отдельно выбираются замах, необязательный голос и звук контакта. Таблица считает завершённую атаку с контактом; при промахе звука контакта нет. Pain всегда содержит flesh_hit, голос добавляется с вероятностью 35%. Death — один видовой звук, для остальных enemy_death. Не считаются pitch, задержки, разрыв конечности и особые умения — это отдельные события.

| Вид | Замах × (голос или тишина) × удар | Замах × (голос или тишина) × укус | Получение урона | Смерть |
|---|---:|---:|---:|---:|
| hunger | 112 | 84 | 24 | 1 |
| revenant | 112 | 84 | 24 | 1 |
| zombie | 96 | 72 | 36 | 4 |
| brute | 64 | 48 | 24 | 4 |
| titan | 32 | 24 | 24 | 1 |
| colossus | 32 | 24 | 24 | 1 |
| horde | 48 | 36 | 18 | 4 |

Scream_zombie и прежняя группа roar_heavy удалены. Первое обнаружение использует hunger_alert или голос своего вида. roar_heavy_4 перенесён в colossus_voice для обычной речи Colossus. Каждая строка контакта применима только когда данный способ атаки поддерживается видом; таблица не добавляет новые атаки.

## Добавление записей

1. Конвертировать запись в моно OGG Vorbis q5/48 кГц и проверить декодирование; после проверки удалить WAV и его import.
2. Использовать путь sfx/<event>/<event>_<index>.ogg, обновить EVENTS и enemy_voice_groups.json.
3. Для новой группы добавить действие в enemy_voice_profile.gd, затем выполнить генератор и профильные тесты.

tools/import_audio_refresh.py воспроизводит замену из исходного коммита 0e154b73. Старый build_added_audio.py описывает предыдущий импорт с исходниками; текущую папку им не пересобирать.
