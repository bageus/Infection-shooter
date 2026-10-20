# CI PR383/384 — 20.10.2026

Подтверждено по Actions39412200647/39412200675 и39418212472/39418212397:

- Незавершённые stash-конфликты в base_office_map.json (117) и base_office_layout.tscn (274) ломали сериализацию и PCK. Сохранён Updated upstream:4431objects, подготовленные трансформы согласованы с planning_settled_transform, включая исправления посадки стульев. Не конфликтовавшие авторские правки сохранены. Оба исходных варианта остаются в коммите47c8a19d; для извлечения Stashed changes нужно выбирать нижнюю сторону каждого блока. Новых объектов/перестановок вне этого разрешения нет.
- Runtime texture audit после этого выявил106ошибок:105слотов нового square table и один clock. Точные PNG извлечены движком из действующих GLB; источники и геометрия GLB неизменны. Импорт PNG применяет1024px/VRAM compression/mipmaps. Файлы import/source добавлены, чтобы clean CI имел те же настройки.
- Gameplay/planner repairs размещает тест крови в1000,1,1000 за пределами камеры. Budget maintenance через0.1с выгружала marks до assertions, поэтому результат зависел от скорости renderer. На время этой изолированной проверки unload_distance=INF, затем восстановлено. Assertions реального попадания на стену/пол и рендера сохранены; production renderer не менялся.

Проверено: validate_project PASS; model_texture audit292models/225textured/0failures; gameplay_planner_repairs forward_plus headless0failures; occlusion lifecycle headless0failures и без ERROR/resources-in-use. Native pixel checks локально не запускались, итоговый результат подтверждается Actions. Владельцы, зависимости, API, DTO, баланс, policy прежние. Общие исправления ресурсов применяются в обеих ветках, чтобы порядок слияния PR не влиял на CI.
