# Оптимизация кэша частей тела — этап 1

Производные меши раньше индексировались по instance ID исходного ресурса. После освобождения миссии загрузка того же файла создаёт новый ID; старые результаты оставались в статическом словаре.

Кэш теперь выделен в приватный helper features.infected. Для authored assets ключ использует resource path и SHA256 сериализованных bind/bone mapping данных. Это исключает смешивание разных скелетных привязок. Безымянные runtime meshes используют отдельный instance identity. Converted mesh хранит исходную identity, поэтому повторная подготовка уже преобразованного меша не добавляет ещё один CUSTOM0 mesh.

LRU ограничен 16 записями и 64 МиБ учтённой геометрии: сохранённые vertex/normal/UV/bone/weight/index arrays, bind данные, buffers converted mesh и LOD indices. Это не лимит RAM всей игры: shared materials/textures и накладные расходы engine/driver не включены. Отдельный oversized результат не кэшируется. Живые consumers сохраняют ссылки на mesh/data при eviction; кэш не освобождает их принудительно.

Конверсия геометрии остаётся в body_part_mesh.gd; helper отвечает только за identity и retention. Оба файла ниже порога 300 строк. Public API, модель урона, state owners, dependencies, DTO и исходные модели не меняются.

Проверки: run_body_mesh_cache_tests (headless/native), enemy LOD (17 levels), dismemberment, corpse physics, topology, full authored map start + 3 restart, layout bake. Новые cache tests включены в Mission CI; source audit tests — в Architecture CI. Full-map count теперь берётся из BASE, чтобы авторские изменения карты не делали фиксированные 1034/1033 устаревшими. В base_office_layout удалены redundant script overrides, наследуемые из public enemy scene; настройки экземпляров сохранены.

Список моделей для переработки и метод подсчёта: destruction_model_rework.md; полные строки всех активных моделей — destruction_model_rework.json. Команда обновления: python tools/audit_destruction_meshes.py. Поисковые группы runtime и exported scene names учитываются отдельно; mesh nodes не равны unique mesh resources, surfaces или одновременно spawned bodies.
