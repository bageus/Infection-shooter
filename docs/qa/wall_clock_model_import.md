# Новые настенные часы: проверка подключения

20.10.2026, T004/Phase1/P1_LOGIC, прямой запрос владельца.
База main60c8c8d. GLB в main побайтно совпадает с подготовленной моделью:
863b8faa41afc104f49d69c85467f74503bbf920. Три PBR-материала, встроенный2K PNG,
3072треугольника, исходный диаметр0.6042105м/толщина0.03393457м.

## Подключение и исправление

Модель найдена через настоящий planning_catalog; настенный флаг/freeze и collider
активны, после попадания часы целиком теряют крепление. В авторских JSON и baked
scene пять прежних ссылок на тот же путь GLB. Подменять бинарную модель не нужно.
Проблема: автоматически созданный importer использует unrestricted2K texture;
существующий run_model_texture_tests отвергает часы по runtime budget1024px.

Фикс: сохранить GLB import profile и извлечённый2K PNG с отдельным PNG profile:
VRAM compression, size_limit1024, mipmaps. Source GLB/PNG2K прежние, игровой
texture1024. Используется штатная схема Godot extract и уже существующая политика
проекта; новые плагины/public API/scene paths/DTO/owners/dependency edges не нужны.

## Нерешённые исходные проблемы main

В main до изменений общий model_texture suite:106failures, включая1 у часов;
остальные относятся к другим моделям. Также main содержит117 merge-конфликтов
в base_office_map.json и274 в base_office_layout.tscn. JSON не парсится, Godot
не загружает baked scene (line6337). Варианты конфликта содержат4431/4428объектов,
есть различия положения до3.15м: автоматический выбор удалит часть авторских
изменений. Эти файлы и остальные импорт-профили не входят в clock PR.
Общий validate_project не выявляет эти исходные проблемы.

## Проверки

До фикса: специализированная проверка clock import/catalog/material/wall damage
проходит при2048px; общий suite обнаруживает превышение clock runtime budget.
После фикса: clock catalog/material/bounds/collider/wall damage probe —5refs/0failures,
runtime dial1024. Wall mount support suite26models/0failures. Editor import exit0
безERROR/SCRIPT ERROR, validate_project/spec/workflow/architecture/CI197suites PASS.
Общий model_texture suite292models:106→105failures. Сравнение сообщений: устранена
ровно ошибка clock1024budget; остальные сообщения побайтно прежние, новых нет.
Пределы общего теста не менялись. Source GLB SHA прежний, извлечённый PNG2K
побайтно равен embedded image. Native/Web pixels не проверялись.
