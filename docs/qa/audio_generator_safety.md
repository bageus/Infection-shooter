# A08 — безопасная повторная генерация SFX

Дата: 16.10.2026. База main `12d2570`, Python с numpy2.3.5/scipy1.17.0,
ffmpeg/libvorbis и Godot4.7.2, Linux headless.

## Что исправлено

`tools/audio_generation_manifest.json` — внутренний список253 генерируемых
OGG (base220, weapon14, destruction19) с отдельным генератором и SHA256.
Авторские события из import receipts/voice groups исключены; scream_zombie
и roar_heavy помечены retired. Проверка receipt выполняется и при запуске,
и перед публикацией, чтобы новый импорт также защищал событие.
Это данные offline tools; runtime owners, public API, DTO и зависимости игры
не меняются, архитектурных исключений нет.

Генераторы больше не удаляют весь SFX и не забирают соседние файлы по glob.
Заменять/восстанавливать разрешено только перечисленные пути. Отсутствующий
owned файл можно восстановить. Изменённый вручную файл, symlink, другой owner,
неизвестный/авторский/retired --only или несовпадение набора recipe outputs
приводит к отказу. Автоматического force/adopt режима нет.

Все результаты сначала кодируются вне проекта. Ошибка encoder не меняет
каталог, credits или manifest. Перед commit повторно проверяются исходные
SHA и manifest. Готовые файлы заменяются атомарно каждый по отдельности;
обычные ошибки commit откатывают уже заменённые файлы. Manifest обновляет
хеши только опубликованных outputs. Это не транзакция на случай выключения
питания; одновременные запуски генераторов не поддерживаются.

CREDITS сохраняет существующий текст и авторские разделы, включая окончания
строк. Обновляются только marker blocks `GENERATED AUDIO generator:event`.
Частичный --only сохраняет credits других событий. Старые строки attribution
сохранены как история; новый generator block перечисляет текущие источники.

build_added_audio.py — исторический WAV importer: требует явный
--historical-import и отказывается работать при наличии нынешнего refresh
receipt, до convert/voice-group/receipt writes. Его convert/import_settings
сохранены для исторического import_audio_refresh. Работать с ним следует
в pre-refresh checkout с исходными WAV, а не повторно в текущем проекте.

## Запуск

Сначала посмотреть план без декодирования, синтеза или записи:

```bash
python tools/build_sounds.py --dry-run
python tools/build_weapon_sounds.py --dry-run
python tools/build_destruction_sounds.py --dry-run
```

Примеры разрешённой генерации:

```bash
python tools/build_sounds.py /path/to/source-collections --only hit_metal
python tools/build_weapon_sounds.py --only m4_fire
python tools/build_destruction_sounds.py --only break_lamp
```

После успешного запуска review/commit включают audio outputs, credits и
обновлённый manifest. При конфликте SHA сначала выяснить происхождение
изменённого файла: новую авторскую запись исключить из generated ownership,
добавить в protected/import receipt. Не обновлять SHA вслепую для обхода отказа.
Новые generated пути или числа вариантов допускаются явной правкой manifest
с проверкой источников; generator не усыновляет существующие файлы сам.

## Проверки

- Проба исходных entrypoints в temp: build_sounds удалил чужой sentinel,
  авторские key/spin и prefix credits; build_weapon_sounds заменил key/spin.
  Реальная папка assets не использовалась для этих запусков.
- `python tools/test_audio_generation.py`:18 tests PASS. Настоящие main()
  с изолированными корнями/encoder stubs проверяют полный rebuild трёх tools,
  unknown/authored/retired paths, dry-run без recipes, SHA conflicts до и после
  encode, отсутствие лишних/недостающих outputs, частичный --only и credits,
  CRLF/UTF-8 authored prefix, restore, symlink/path/duplicate owner validation,
  malformed credits, encoder/commit failure и исторический importer guard.
  Проверен и manifest против всех текущих253 файлов проекта.
- Настоящий weapon --only m4_fire в temp:3 Vorbis, mono44.1kHz,0.13с;
  destruction --only break_lamp с копиями настоящих source OGG:2 Vorbis,
  mono44.1kHz,1.35с. ffprobe подтвердил codec/channels/rate/duration,
  protected sentinels/credits сохранены, новые manifest SHA валидны.
- Три настоящих CLI --dry-run PASS. py_compile PASS.
- Godot sound_event и sound_hook suites PASS, editor import PASS;
  project/spec/workflow/architecture/scene/resources/diff gates PASS,
  source-size121 прежних warnings. Python suite и dry-runs добавлены в CI;
  SciPy — уже используемая зависимость offline generators — установлен для CI.
- Все assets, текущий CREDITS, receipts, sidecars, game/content/project.godot
  в PR остаются byte-identical базе. Аудио не пересобиралось в проекте.

Полная пересборка base из внешних коллекций не выполнена: исходных коллекций
здесь нет. Полный entrypoint проверен с recipe/encoder fixtures; реальное DSP
проверено на M4 и destruction. Windows/Web и прослушивание не выполнялись.
