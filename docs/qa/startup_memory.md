# Память при запуске после обновления моделей

Скриншоты владельца: Godot 4.7.2, Windows, Forward+, Intel Iris Xe; `VkResult error -2` при загрузке display_content, затем невалидные RID и `mem is null` при загрузке атласов крови. Это указывает на исчерпание памяти; предупреждения о названиях переменных не являются причиной остановки.

В группах 03 и 05 находятся 232 встроенных изображения 2048×2048. Верхняя оценка RGBA8 с mipmaps без совместного использования — 4949 МиБ. Байтово одинаковые изображения повторяются в разных GLB.

Для 39 обновлённых моделей и семи моделей группы 02 закреплены параметры импорта: встроенные изображения вместо отдельных извлечённых PNG, затем EditorScenePostImport создаёт общие S3TC ресурсы в `assets/runtime_shared_maps/` (производные локальные ресурсы, исключённые из Git; Godot экспортирует их как зависимости сцены). Ключ учитывает SHA-256 пикселей, размер, формат, наличие mipmaps и normal-map usage. Сохраняются исходное разрешение 2K, UV, материалы, изображения внутри GLB и сцены разрушения. Сжатие выполняется только в редакторе; игра и экспорт загружают готовые ресурсы. Публичные API, DTO, карта, владельцы состояния и зависимости прежние. Архитектурных исключений нет.

Проверка памяти встроена в run_model_texture_tests: реальные игровые props должны разделять одни Texture2D по пути, использовать VRAM compression/mipmaps и укладываться в 192 МиБ. Внешние стикеры имеют отдельную import policy и исключены из этой проверки.

После обновления ветки редактор должен переимпортировать изменившиеся `.glb.import`. Дождаться завершения импорта перед F5. Если остался повреждённый старый кэш: закрыть Godot, переименовать `.godot` в `.godot_old` и открыть проект снова. Исходные модели и user:// сохранения не трогать. Также доступно Project → Tools → Reimport staged destructible GLBs; команда включает одиночные модели групп 03/05.

Локальная проверка: модельные карты — 37 общих ресурсов, 138,7 МиБ; display tests — 0 failures; отдельный импорт двух мониторов и загрузка экспортированного PCK из пустой папки с общими сжатыми ресурсами прошли. Финальный импорт и последующий runtime-аудит: 257 моделей, 184 textured, 0 failures; main 180 кадров без ошибок. Project gates, resource/import/scene checks, 11 Python tests PASS. Windows/Iris Xe и визуальная оценка S3TC требуют проверки владельцем.


## Повторный скачок после внешних PNG — 09.10.2026

На main 180f82cb дедупликация перевела карты GLB во внешние изображения, но их
`compress/mode=0` сохранился. Post-import обрабатывает ImageTexture, поэтому
CompressedTexture2D из PNG обходили этот механизм. Прежний runtime test тоже
пропускал их по классу и ошибочно сообщал только 3 карты / 10,7 МиБ.
225 внешних карт активных environment GLB >=512 px имеют верхнюю оценку
RGBA8 + mipmaps 3372 МиБ. Теперь их импорт использует VRAM compression (mode=2);
UID, исходные изображения, разрешение, UV, слоты материалов, mipmap и normal
настройки сохранены. Изменены .import, Godot сформировал S3TC destinations.

Runtime regression учитывает внешние Texture2D; 10730 ссылок обновлённых
props/колонны используют 40 общих карт, 136,0 МиБ. Проверяются сжатие,
mipmaps, ресурсная идентичность и прежний бюджет 192 МиБ. Проверка общего
normal между вариантами bookcase теперь действительно вызывается.

В одинаковом Godot 4.7.2 headless сценарии default 1034 records + restart:

| Метрика пика | До | После |
|---|---:|---:|
| Аллокатор Godot, МиБ | 2522,6 | 1062,5 |
| RSS процесса Linux, МиБ | 2770,9 | 1208,1 |

RSS и аллокатор — разные показатели; headless не измеряет VRAM.
Новый run_startup_resource_memory_tests включён в Mission CI: полная карта,
restart, authored snapshot, 403 props с коллизиями и headless allocator cap
1280 МиБ. Тест сохраняет и восстанавливает существующий user://planned_layout.json.
Скриншотное INCOMPATIBLE_TERNARY исправлено заменой fallback 0 на 0.0.

Локальная видимость геометрии теперь определяет коллизии мебели независимо
от pending.hide(). Во время restart старая Node3D миссия скрывается под overlay,
но её узлы/физика сохраняются до commit; ошибка восстанавливает прежнюю видимость.
Контактные тени используют локальные ShaderMaterial параметры вместо global
instance uniforms: повторный native restart воспроизвёл аппаратный лимит OpenGL
4096 entries; увеличение buffer_size его не устранило и не включено в изменение.
Shader/quad остаются общими, параметры принадлежат каждой тени. Положение,
footprint, fade и hiding assertions сохранены, добавлена независимость материалов.

После обновления дождаться переимпорта 225 изображений. При старом повреждённом
кэше закрыть Godot, переименовать .godot в .godot_old и открыть редактор снова.
Исходные изображения, GLB, карты и пользовательские сохранения сохраняются.
Windows/Iris Xe и Web требуют приёмки на устройстве владельца; Linux software
GPU не подтверждает поведение драйвера Intel и не является замером FPS.

Финальная проверка Godot 4.7.2: editor import, headless full map/restart,
Mission/Layout/Menu, prop weight, contact shadow, model textures PASS; native
Compatibility (Mesa llvmpipe, 320x180) full map/restart + display/contact PASS,
без ERROR/SCRIPT ERROR. Project/resource/import/scene gates, 15 Python texture
tests и diff-check PASS. Native V-Sync warning относится к software display.


## Vulkan shader/cache crash после PR #76 — 09.10.2026

На main 2537eff3 исправление внешних текстур уже присутствует. Новый скриншот
показывает realloc_static/alloc_static null, Malformed smolv Fragment,
shader_create_from_bytecode_with_samplers, free_rid с неверного render thread
и _load_from_cache. Порядок сообщений допускает последующие ошибки после
неудачного выделения памяти; по скриншоту нельзя доказать повреждение кэша
или дефект конкретного GLSL. Предупреждение INTEGER_DIVISION не объясняет crash.

В project.godot был только mobile renderer override: desktop неявно выбирал
Forward+. Теперь основной renderer — gl_compatibility (OpenGL); config/features
также отражает Compatibility. Существующие PBR-текстуры, материалы и карта
сохраняются. Это ограниченный обход проблемного Vulkan/RenderingDevice пути.
Forward+ можно отдельно запускать через --rendering-method forward_plus для
диагностики; исправление его драйвера и субъективное совпадение изображения
не заявляются. Различия renderer-specific эффектов проверяются визуально.

После обновления полностью закрыть все процессы Godot и открыть проект заново.
В правом верхнем углу редактора должен быть Compatibility. Дождаться импорта
и выполнить F5, старт полной карты и restart. При сохранении ошибки именно
shader cache закрыть Godot и переименовать только .godot/shader_cache в
shader_cache_old, если каталог существует. Это сохраняет предыдущий кэш;
исходные модели, текстуры и user:// сохранения не затрагиваются.

Локальная проверка запуска проводится без --rendering-method: renderer
должен выбираться из project.godot. Linux/Mesa software GPU не подтверждает
поведение Windows/Intel и не является замером FPS.

Проверка Godot 4.7.2 с выбором renderer из проекта: editor import и
validate_project PASS; native full map 1034 records, 403 furniture collisions,
start + restart + 180 frames: 0 failures, без ERROR/SCRIPT/SHADER ERROR.
Пики: allocator 442,8 МиБ, Linux RSS 1702,1 МиБ, render video monitor 802,7 МиБ.
Shader warmup и global lighting native suites: 0 failures. Известное
предупреждение V-Sync относится к software display. Windows не проверен.
Следующий шаг: обновить проект до этого изменения, полностью перезапустить
редактор в Compatibility, подтвердить F5/start/restart на Windows/Iris Xe.


## alloc_static null в Compatibility на Iris Xe — 09.10.2026

09.10.2026 (godot.log владельца, Iris Xe/OpenGL): Compatibility уже активен; alloc_static(mem=null) предшествует signal 11. Без символов стек не определяет конкретный ресурс или размер запроса. В рамках T002 снижен footprint: 275 активных внешних import profiles окружения — VRAM compression и лимит 1024 px; встроенные карты 46 GLB ограничены на импорте, post-import wrapper переименован и профили обновлены для автоматического переимпорта. Исходные GLB/PNG/JPG, UV, PBR slots, карта и сохранения сохранены; игровые карты вблизи могут быть менее резкими. Bootstrap пишет renderer/profile/phase/path и allocator/video MiB в godot.log. Native Linux Compatibility start/restart/180 frames: 0 failures; RSS 1676,7→1322,4 МиБ, video 802,7→500,5 МиБ; allocator 442,8→442,9 МиБ (практически без изменения). Model textures: 258 models / 185 textured, 0 failures; groups03/05 136→34 МиБ, CI cap 48 МиБ. Headless start/restart: allocator 769,3 МиБ, RSS 914,8 МиБ, 0 failures; CI cap снижен 1280→896 МиБ. Project/resource/import/Python texture gates PASS. Windows fix не подтверждён; это измеренное снижение памяти и диагностика для следующего сбоя. Public API/DTO/owners/dependencies прежние; архитектурных исключений нет. Следующее действие: после обновления дождаться импорта, полностью перезапустить Godot и проверить start/restart на Windows; при сбое взять новый godot.log с Mission begin/profile 1K и последним resource/phase.


| Метрика, native Linux/Mesa | До | После |
|---|---:|---:|
| Пик RSS процесса | 1676,7 МиБ | 1322,4 МиБ |
| Пик video monitor | 802,7 МиБ | 500,5 МиБ |
| Пик Godot allocator | 442,8 МиБ | 442,9 МиБ |

Обе native проверки: один Godot 4.7.2, тот же main b732dd7, чистый импорт, Compatibility, 320x180, полная authored карта, start + restart + 180 кадров. Software GPU использует системную память; video monitor показывает ресурсы движка, а не физическую VRAM Intel. Пики семплируются на кадрах во время переходов. RSS после импорта относится к отдельному игровому процессу, не сумме редактора и игры. На Windows фактическое снижение и отсутствие crash ещё не проверены.

Регенерация встроенных текстур запускается изменением import_script/path на bounded_texture_post_import.gd с сохранением UID wrapper. Без обновления GLB profiles старый импорт мог бы сохранить прежние 2K карты. Старые игнорируемые assets/runtime_shared_maps остаются на диске, но новые сцены используют ресурсы 1K; удалять пользовательские кэши автоматически не требуется.

Бюджеты 192/1280 МиБ выше описывают прежние проверки; текущие бюджеты 48/896 МиБ. Model suite проверяет размеры игровых карт всех environment GLB и сохранение PBR/UV/palette/collisions; отдельные display decals не переводятся на этот профиль.
