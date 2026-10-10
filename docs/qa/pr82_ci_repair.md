# Исправление проверок PR #82

## Причины

Architecture run 38064794177 останавливался на трёх отсутствующих телефонах в migration targets planning_catalog. Mission runtime run 38064794191 останавливал все шесть jobs на Import: GLB групп 02/03 всё ещё ссылались на удалённые PNG, включая общие карты из папки 05. Отдельный runtime группы 04 уже проходил.

После восстановления ресурсов обнаружен следующий блокер Architecture: генератор display_surfaces не распознавал суффиксы материалов Dark_Display_Glass.00N и объединённые в один primitive поверхности двух серверных мониторов.

## Изменения

- Восстановлены 206 исторических файлов: только используемые изображения с прежними import profiles и три отдельные legacy-модели телефонов с зависимостями. Git blobs совпадают с историческими объектами; геометрия и пиксели не переработаны. Общие cross-folder ссылки сохранены, dedup check: 0 duplicates/0 changed models.
- Для шести PNG атласа 05 зафиксированы VRAM compression, mipmaps, runtime size limit 1024 и disabled automatic recompression. Исходные PNG и GLB атласа 05 сохранены.
- Генератор дисплеев распознаёт суффиксы имён материалов, разделяет соединённые по вершинам группы треугольников двойных мониторов и исключает тонкие рамки/опоры. Пересобраны девять профилей; размеры экранов совпадают с прежними, изменения центров меньше 0.000001 м. Добавлены два регрессионных теста и запуск в Architecture CI.
- Группа 04, public API, scene contracts, save DTO, владельцы состояния, module dependencies и policy не меняются. Архитектурных исключений нет.

## Проверки

Godot 4.7.2: два импорта завершились exit 0 без ERROR/SCRIPT ERROR. Model texture tests: 257 моделей / 188 с текстурами / 0 failures; shared updated maps 32.0 МиБ. Group04: 1.167 МиБ / 0 failures. Staged GLB, display, layout loading и planner persistence PASS. validate_project, scene/resource/import checks, texture dedup, display rebuild check, group01/group04 static checks и существующие Python unit suites PASS; новые два display tests PASS.

Полный headless-набор workflow и повторный GitHub CI проверяются после публикации исправления; итог фиксируется в ACTIVE_TASK/PROJECT_STATE.

## Ограничения

Восстановленные необходимые исходники добавляют около 112 МиБ файлов. Это восстановление зависимостей существующих моделей, а не завершение атласной оптимизации групп 02/03. GPU-бюджеты ограничены импортом; требуется отдельная корректная миграция GLB/UV/материалов перед повторным удалением этих исходников. Профилирование FPS и визуальная приёмка Windows/Web не входят в исправление падения CI.
