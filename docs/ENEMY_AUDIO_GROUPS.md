# Группы звуков заражённых

Автоматически: `python tools/update_enemy_audio_report.py`. Проверка актуальности: `--check`.

Вариант = отдельная запись. Выбор из группы альтернативный: несколько голосов одновременно не наслаиваются. Микроизменения высоты и громкости не считаются новыми комбинациями. Вероятности относятся к попытке воспроизведения; бюджет голосов и уже звучащая речь могут её пропустить.

## Добавленные группы

| Группа | Файлов / вариантов | Исходные записи |
|---|---:|---|
| hunger_idle | 1 | the_cry_of_a_person_3 |
| hunger_voice | 1 | the_scream_of_an_inf_1 |
| hunger_fours_voice | 1 | the_scream_of_an_inf_4 |
| hunger_alert | 1 | sounds_of_zombies_ta_2 |
| hunger_attack | 2 | the_scream_of_an_inf_2, sounds_of_zombies_ta_3 |
| hunger_agony | 1 | the_scream_of_an_inf_22 |
| hunger_feeding | 1 | zombie_damage_sounds_4 |
| revenant_voice | 1 | the_scream_of_an_inf_3 |
| revenant_attack | 1 | sounds_of_zombies_ta_4 |

В каждой группе выбирается одна запись, поэтому количество одиночных звуковых комбинаций равно числу файлов. Сейчас 10 новых записей в 9 группах. Соседние OGG рядом с WAV — конвертированные оригиналы; копии в группах — те же записи и повторно не считаются.

## Действия и состояния

| Вид / действие | Группы альтернатив | Вероятность голоса | Голосовых записей | Исходов, включая тишину |
|---|---|---:|---:|---:|
| hunger / idle | hunger_idle / growl_hunger | 65% | 4 | 5 |
| hunger / voice | hunger_voice / growl_hunger | 100% | 4 | 4 |
| hunger / fours | hunger_fours_voice / hunger_voice | 100% | 2 | 2 |
| hunger / idle_scream | hunger_voice / scream_zombie | 100% | 6 | 6 |
| hunger / alert | hunger_alert / scream_zombie | 100% | 6 | 6 |
| hunger / attack | hunger_attack / growl_hunger | 50% | 5 | 6 |
| hunger / pain | growl_hunger | 35% | 3 | 4 |
| hunger / agony | hunger_agony | 100% | 1 | 1 |
| hunger / feeding | hunger_feeding | 100% | 1 | 1 |
| revenant / idle | revenant_voice / growl_revenant | 65% | 4 | 5 |
| revenant / voice | revenant_voice / growl_revenant | 100% | 4 | 4 |
| revenant / attack | revenant_attack / growl_revenant | 50% | 4 | 5 |
| revenant / pain | growl_revenant | 35% | 3 | 4 |

Fours применяется к Hunger на четвереньках; голос hunger_fours_voice используется только в этой позе, а не в обычной стойке. Agony запускается только вместе с успешным стартом Agonize. Feeding звучит после BiteDown, с интервалом 2,4–3,2 с и прекращается при подъёме, тревоге, потере ноги или смерти. Idle scream не вызывает тревогу.

## Комбинации конкретного действия

У атаки отдельно выбираются замах, необязательный голос и звук контакта. Таблица считает завершённую атаку с контактом; при промахе звука контакта нет. Pain всегда содержит flesh_hit, голос добавляется с вероятностью 35%. Death — один enemy_death. Не считаются pitch, задержки, разрыв конечности и особые умения — это отдельные события.

| Вид | Замах × (голос или тишина) × удар | Замах × (голос или тишина) × укус | Получение урона | Смерть |
|---|---:|---:|---:|---:|
| hunger | 96 | 72 | 24 | 4 |
| revenant | 80 | 60 | 24 | 4 |
| zombie | 96 | 72 | 36 | 4 |
| brute | 64 | 48 | 24 | 4 |
| titan | 64 | 48 | 24 | 4 |
| colossus | 64 | 48 | 24 | 4 |
| horde | 48 | 36 | 18 | 4 |

Остальные виды используют прежние growl_* / scream_zombie / roar_heavy. Каждая строка контакта применима только когда данный способ атаки поддерживается видом; таблица не добавляет новые атаки.

## Добавление записей

1. Положить WAV в zombie_misc, внести имя в GROUPS в tools/build_added_audio.py.
2. Запустить конвертацию. Оригиналы не меняются. Отдельные синтетические варианты не создаются.
3. Увеличить число вариантов соответствующего события в sound_events.gd; при новой группе добавить профиль действия в enemy_voice_profile.gd.
4. Выполнить этот генератор и тесты sound_event, adaptive_audio, enemy_voice.

Группы повреждения и смерти пока используют существующие записи; добавлять новую специфическую запись следует в соответствующий профиль, без случайного смешения видов.
