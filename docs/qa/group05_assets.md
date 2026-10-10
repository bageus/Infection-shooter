# Оптимизация группы 05

22 прежних пути моделей сохранены. Цельная модель — группа Intact; повреждения представлены пустыми именованными группами и загружаются Geometry при нужном переходе. 35 отдельных GLB стадий, общий atlas из трёх карт и 22 immutable material definitions. Публичные API, map DTO v8, владельцы состояния и зависимости прежние; архитектурных исключений нет.

| Ресурсы | До | После |
|---|---:|---:|
| GLB при первоначальной загрузке всей группы | 26,02 МиБ | 3,91 МиБ |
| Все GLB, включая отложенные стадии | 26,02 МиБ | 10,11 МиБ |
| Исходные PNG | 6 / 13,14 МиБ | 3 / 7,00 МиБ |
| Все GLB + PNG | 39,16 МиБ | 17,11 МиБ |

Это размеры исходных ресурсов, не RSS, GPU память или FPS. Треугольники не упрощались: одинаковые вершины со всеми атрибутами сварены, индексы стали 16-bit там, где допустимо. Развёрнутые последовательности треугольников, нормалей, UV, tangents и цветов проверены на точное совпадение. Трансформации сохранены. Индексные extras, которые ссылались на прежние номера узлов, удалены; source_part и смысловые extras сохранены.

## Атлас и материалы

Существующий авторский atlas 05_shared_basecolor/normal/orm сохранён побайтово. Исходники 2048²; runtime import basecolor 2048², normal/ORM 1024², VRAM compression и mipmaps, normal compression enabled. Материалы разделяются между экземплярами и стадиями. Сохранены metallic 0/0.9/1, roughness, normal scale, свечение лампы и double-sided flags. Цветовые множители и emission преобразованы linear → sRGB как при оригинальном импорте GLTFDocument; headless тест сравнивает параметры с прямым glTF импортом.

## Структура и удаление лишнего

Потерянное распределение сцен исправлено у шести моделей: laptop2, monitor, monitor_wide, monitor2, monitor3_server, monitor4_server. Исходные пустые LargeParts/Power_Off/SmallFragments сцены заменены настоящими группами по сохранённым именам узлов. Повреждения больше не участвуют в первоначальной геометрии/коллизиях.

У MFU, MFU_2_extra_trays, aircondition, laptop, laptop_close, printer и wall_TV исходные SmallFragments содержали те же номера узлов, что LargeParts. Семь дублирующих стадий удалены; более мелкое разрушение этим моделям не добавляется. Остальные реальные фрагменты сохраняются. Plain mouse/keyboard/lamp/minipc/hand dryer не получают новых стадий.

Удалены три electronics_* PNG и три их локальных generated imports: ни один GLB всего models не ссылается на них. Удалены устаревшие atlas_report.json/structure_report.json; происхождение и актуальная статистика сведены в asset_report.json, README обновлён. Исходники сохранены в Git по a48e5a49028b0871852f4418eeb8eb2670671ea2. Нужные карты atlas/05_shared_* и atlas_manifest.json сохранены.

Отдельные GLB и imports стадий увеличивают число рабочих файлов. Это необходимо для стандартной загрузки PackedScene по требованию; сокращены именно лишние ресурсы и общий объём. Пользовательские файлы других групп не затронуты.

Старые 09_phone_* и 05_phone_* paths сохранённых карт перенаправляются на существующий 05_desk_phone.glb. Кatalog содержит ровно 22 модели; вложенная damage папка не попадает в палитру.

## Дисплеи

build_display_surfaces читает вынесенную Power_Off, нормализованные material names и mesh IntactGeometry. Два серверных экрана могут находиться в одном material primitive: извлекаются несвязанные поверхности, тонкие рамки/опоры исключаются. Все размеры экранов прежние; максимальное отличие координат от прежнего JSON — 3.2e-7 м. Профили и source hashes пересчитаны по актуальным GLB, schema v1 прежняя.

## Проверки

- check_group05_assets: 22 модели / 35 стадий, точные triangle attributes/transforms/material factors, atlas PNG identity, live buffers, import profiles PASS.
- test_group05_assets: 4 regressions пустых сцен / реальных фрагментов / duplicate stages / plain props PASS.
- Godot 4.7.2 run_group05_asset_tests: 0 failures; холодные placeholders, реальный переход от попадания, idempotence, поздние стадии, общие mesh/material resources, instance isolation, исходные PBR параметры, compressed+mip textures и палитра PASS.
- run_display_tests и run_debris_tests: 0 failures.
- validate_project, check_resource_paths, validate_scene_resources (350 references), check_import_files (729), git diff --check PASS.
- test_model_textures (7), test_destruction_mesh_audit (5), test_texture_deduplication (10), workstation templates (3), architecture scene access (3) PASS.
- build_display_surfaces --check PASS. Полный static texture audit: 315 missing external image errors других групп 02/03 на исходном main; у 05 errors нет.
- Общий run_staged_glb_tests: три failures authored base-color серверной стойки 03_server_rack3, исходные PNG отсутствуют в main. Проверка Power_Off ноутбука и остальных стадий этого набора проходит. PR #81 отдельно исправляет 03; изменения 05 не включают его assets.
- Последний incremental editor import: exit 0, без ERROR/SCRIPT ERROR. Первый холодный импорт всего main сообщал отсутствующие карты 02/03 и завершился exit 134; полный чистый импорт/старт игры не объявляются PASS.

Новый static check и regression test включены в Architecture CI; runtime suite включён в Mission runtime CI. Глобальные baseline ошибки сохраняют общий CI красным до отдельного восстановления ресурсов других групп.

## Нужна ли переработка моделей

Дополнительная работа рекомендуется для 05_laptop и 05_laptop_close: у цельной модели примерно 55 тысяч исходных vertex entries, особенно тяжёлая клавиатура. Текущая сварка сохраняет авторские треугольники; для дальнейшего сокращения нужен low-poly keyboard/normal bake с визуальным сравнением. 05_keyboard и 05_printer также стоит проверить при целевых массовых количествах. Новое мелкое разрушение не требуется. Поддержка закреплённого Internal_Unit кондиционера оставлена на уровне исходных extras, существующие правила физики не расширялись.

Для 10000 объектов lazy stages экономят загрузку повреждений, но число Intact draw calls и physical bodies само по себе не становится бесплатным. Shared atlas/materials создают базу для batching; FPS/RSS и GPU память требуют отдельного воспроизводимого замера Windows/Web на целевом уровне. Native визуальная приёмка, глянец, lamp emission и качество normal 1024² ещё не проверены человеком.

Опубликовано: [draft PR #83](https://github.com/bageus/Infection-shooter/pull/83), ветка optimize/group05-atlas, без merge. Дерево реализации совпало с проверенной локальной версией (66f8c432550b829464f60e945f7a118876b3b42a). Следующее действие: визуальная приёмка Windows/Web и замеры FPS/памяти.
