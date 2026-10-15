# Музыка и голоса — 15.10.2026

База: main c10f774. Реализовано в codex/adaptive-music-enemy-voices, T004.
Правила и принятые параметры — ADR-0048.

## Реализация

- 17 исходных WAV, 27 OGG (17 рядом с WAV, 10 копий по группам). Исходники:
  97 252 826 байт; игровые OGG с групповыми копиями:9 153 124 байта. Оригиналы
  не удалены и не изменены; runtime не загружает WAV.
- main_menu: задержка1с, loop. menu_from_game: срезан хвост1с, затем overlap80мс,
  итог58.92с. Серверы: срезан хвост0.3с, затем overlap80мс, итог2.62с, mono.
  Остальные музыкальные петли также overlap80мс. Boom6.08с, не loop.
- Меню имеет отдельную шину MenuMusic, переключатель и громкость, RU/EN.
  Существующий Music управляет только миссией; master/sound управляет всем.
- Миссия читает только агрессивных infected_alive через is_alerted,4Гц.
  >3: crossfade2с в Tower Hunt; <=3 на протяжении3с: fade2с → boom → calm.
  Новый бой прерывает окончание. Пауза останавливает музыкальный clock миссии;
  меню играет в паузе. Диалоги/refresh не перезапускают запись меню.
- Серверные шкафы03_server_rack*: один локальный источник на высоте1м,
  inverse-distance/unit1м/max4м, без обработки на каждом кадре; выключается при
  фактическом разрушении. Звук принадлежит шкафу, SFX, уходит вместе с ним.
- 9 новых групп/10 записей для Hunger/Revenant; случайность по действию и старые
  записи как альтернативы. Один голос на врага, общий прежний бюджет SFX.
  Голос агонии начинается с успешной анимацией; жевание после BiteDown,
  период2.4–3.2с, прерывается при смене действия. Все голоса позиционные.
- Исправлен порядок script/audio properties в семи сценах: Godot игнорировал
  выставленные до script голос/шаги/pitch. Теперь применяются авторские значения.
- docs/ENEMY_AUDIO_GROUPS.md генерируется из runtime-профилей и каталога,
  содержит количества всех участвующих групп, вероятности и конечные комбинации
  атак/получения урона/смерти. Его актуальность проверяется в Architecture CI.

## Владельцы и ограничения размера

bootstrap сохраняет композицию и локальные настройки/музыку, core.audio —
каталог и bounded positional playback, infected — голос по своему состоянию,
office_floor — визуальный prop и его шум. Новых API, dependency edges,
Autoload или архитектурных исключений нет. interface_v1 аддитивно получает
menu_music и menu_music_volume; старые файлы читаются с defaults. Сцены изменены
только перестановкой звуковых свойств; карты, gameplay/save/network DTO прежние.

Крупные main, environment_prop и infected_hunger сохраняют свои роли границ
сцен; добавлены только вызовы локальной аудиокомпозиции/состояний. Музыка,
серверный звук и voice profile вынесены отдельно; искусственного split ради
строк нет. infected_capsule остаётся599 строк: существующий audio.tick перенесён
до early return unaware без расширения файла сверх600.

## Выполненные проверки

Godot4.7.2.stable.official.ed1daf0bf, headless, каждый из14 наборов exit0 и без
SCRIPT ERROR/ERROR:

| Набор | Результат |
|---|---|
| run_adaptive_audio_tests | PASS: пороги3/4, подсчёт агрессии, fade/boom, повторный бой, пауза, delay, menu lifecycle, реальные controls, старые preferences, mute independence |
| run_infected_voice_tests | PASS: прежние one-callout assertions и новая проверка отсутствия крика у unaware |
| run_enemy_voice_tests | PASS: существование событий, случайность и пропуски, фактические Hunger/Revenant, агония, жевание, прекращение, alert при прерывании еды, освобождение |
| run_server_audio_tests | PASS: все3 настоящих модели, loop/trim/параметры затухания, фактическое разрушение, отсутствие шума на обычном prop |
| run_sound_event_tests | PASS |
| run_sound_hook_tests | PASS |
| run_destruction_sound_tests | PASS |
| run_menu_tests | PASS |
| run_settings_tabs_tests | PASS |
| run_ui_sound_tests | PASS |
| run_hunger_behaviour_tests | PASS |
| run_enemy_perception_tests | PASS |
| run_enemy_idle_lod_tests | PASS |
| run_horde_escalation_tests | PASS |

Дополнительно:

- validate_project.py: PASS (spec ready, workflow ready, architecture, source size).
- check_resource_paths.py: PASS после staging новых файлов.
- check_import_files.py: PASS,930 imports.
- validate_scene_resources.py: PASS,378 references.
- update_enemy_audio_report.py --check: PASS.
- Godot --headless --editor --quit: exit0, без SCRIPT ERROR/ERROR.
- main.tscn --quit-after120: exit0, без SCRIPT ERROR/ERROR; прежнее предупреждение
  «63 ObjectDB instances» при выходе остаётся, как отмечено в PROJECT_STATE.
- ffprobe: фактическая длительность всех17 OGG совпадает с manifest в пределах10мс;
  mono/stereo и loop metadata проверены. Все10 групповых копий byte-identical
  соответствующим конвертированным записям.
- git hash-object против HEAD: все17 оригинальных WAV неизменны.
- git diff --check: PASS.

## Уточнения существующих тестов

settings_tabs выбирал последний HSlider и считал его игровым music_volume.
Добавление нового ползунка нарушило это предположение. Теперь у sliders есть
имя по setting key, существующие проверки сохранения выбирают MusicVolume.
Дополнительный тест нажимает именно MenuMusicToggle/MenuMusicVolume.

Hunger feeding проверял FOURS через3кадра при цели на40м. _on_aggro действительно
даёт FOURS, но следующий far LOD step правильно переводит на ходьбу в стойке за
пределами charge_range. Прохождение зависело от ObjectID/фазы12кадров. На исходном
main обычный запуск PASS, а при принудительной следующей LOD фазе в кадре+2 тот же
baseline воспроизводит1failure «It leaps up on all fours». В fixture цель перед
криком переносится на8м, feral=true: это условия для устойчивого бега на четвереньках.
Проверки/пороги не ослаблены; production AI не менялся ради теста.

Дополнение при публикации: прежняя voice_test_body не имела public is_alerted,
который теперь читает audio.tick. Заглушка дополнена этим методом и управляемым
флагом, исходные assertions run_infected_voice_tests сохранены; дополнительно
проверено, что nearby unaware не вызывает call-out. Исправление только тестовое,
production поведение не менялось. Этот14-й набор также проходит локально.

## Осталось

Прослушать Windows/Web: уровень музыки относительно SFX, слышимый шов длинных
петель, шум серверов при подходе4→0м, соответствие жевания движениям челюсти.
Аудиоустройства и GPU в этой проверке нет. Native/Web CI не запускался локально.
Параметры времени музыкальных переходов — выбранные значения реализации,
редактируются в mission_music.gd. Владелец отдельно разрешил публикацию PR и merge после зелёного CI.

Следующее точное действие: опубликовать PR на базе main c10f774, дождаться
зелёного GitHub CI и слить по прямому поручению владельца; затем прослушать в игре. T004 остаётся IN_PROGRESS для
общей задачи; этот аудиоинкремент готов к ревью.

## CI follow-up: мгновенное завершение музыки

Run38738989668: Architecture и все6 native jobs PASS, полный runtime завершил
игровые assertions без ошибок, но3 suites (world_surface, planner_persistence,
placed_ammo_pickup) оставляли4 audio objects/2 resources при немедленном выходе.
Verbose минимального probe на2кадра подтвердил конкретные остатки:
AudioStreamPlaybackOggVorbis, OggPacketSequencePlayback и их OGG/packet resources.
Явный stop/очистка stream в _exit_tree сам по себе не устранял headless race.

Исправление соответствует прежнему core.audio/SFX: headless не запускает
декодер. Музыкальные состояния/fade/delay сохраняются, окончание boom идёт по
локальному паузируемому Timer той же длительности. Меню хранит active независимо
от аудиоустройства; реальные desktop/Web players продолжают играть OGG. На выходе
музыка останавливает tween/timer/players и снимает stream refs.

Новый run_music_shutdown_tests повторяет мгновенное освобождение и quit через
один кадр; baseline даёт4 objects/2 resources, fixed — без audio leaks/ERROR.
Все3 упавших CI suites, shutdown, adaptive_audio и server_audio локально PASS
с прежними assertions и строгой проверкой ERROR. Существующее63 ObjectDB warning
в больших main fixtures остаётся и не скрывается. Native adaptive_audio и
server_audio дополнительно включены в оба renderer jobs; их teardown ждёт100мс
освобождения микшером, а checks по SCRIPT ERROR/ERROR не изменены.

База при публикации исправления обновлена до main1bf979e (#193/#194).
Сохранены все обновления main; конфликт разрешён только объединением журналов
ACTIVE_TASK. В Hunger fixture остаются frame-based ожидания из main и условия
charge/feral из аудиоветki. Проверки/лимиты не ослаблены.

Main затем продвинулся до66284af (PR191: skin materials). Он включён целиком;
новые rendering/Web checks, skin code и артефакты не изменены аудиоветкой.
Конфликты журналов объединены без удаления решений/блокеров, Hunger fixture
сохраняет относительную цель8м из main, feral=true и bounded frame waits.
