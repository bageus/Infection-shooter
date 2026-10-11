# Город за окнами

32 процедурных box-здания, 4 MultiMesh batch, общий mesh/material/shader. Без изображений, физики и динамического света. Геометрия: 384 треугольника без учёта внутренних engine transforms. Бюджет не зависит от числа окон: окна вычисляются fragment shader. GPU время зависит от площади фасадов на экране; FPS и Windows peak RAM ещё не измерены.

Основная карта 80×60 м, зазор 30 м, основания y=-65. Высота 72–128 м. Для другой геометрии локации параметры location_size/street_gap задаются в CityBackdrop. Камера остаётся игровой; фон не добавлен в палитру и карты сохранения.

Проверить: из окон видны соседние фасады, при Q/E фон не исчезает, ближайшее здание не перекрывает границы этажа, restart не меняет городской силуэт. Автотест run_city_backdrop_tests.gd проверяет бюджет, отсутствие physics children, отключение shadow, зазор и воспроизводимость.

Проверено локально Godot 4.7.2: editor headless import без ERROR; run_city_backdrop_tests — 0 failures. validate_project/resource paths/scene resources PASS. Native shader compilation, итоговый вид из окон и FPS не проверены: графический display в окружении отсутствует. Headless dummy renderer не возвращает MultiMesh transforms, поэтому тест размещения проверяет сохранённые authored transforms, передаваемые в MultiMesh, а не driver readback.

## Глубина города — 10.10.2026

144 здания в 12 MultiMesh batches (32 близких, 48 средних, 64 дальних), 32 roof setbacks в одном batch, 4 street planes. Всего 17 render nodes и 2160 треугольников. Три фасадных варианта задаются instance color; голубая дымка статична по слою и не затрагивает помещение. Небо процедурное, ambient lighting прежнее. Без импортированных текстур, физических тел и источников света.

City tests: 0 failures. Полный project gate обнаружил существующую на origin/main 34da3d3 приватную ссылку base_office_layout.tscn → infected_capsule.gd, вне изменений города; source size/spec/workflow PASS. Native вид/FPS не измерены. Следующая приёмка: окна, Q/E, skyline gaps, restart на Windows.

## Исправление по image(9)

Скриншот показывает завесу высоких ближних домов и почти чёрное стекло. Зазор увеличен до 48м, шаг до 42м, добавлена шахматная глубина. Ближние корпуса преимущественно 42–86м от основания y=-65, с редкими 104м акцентами; это открывает крыши и дальний слой. Фасад unshaded: художественное освещение, вариации синего стекла и тёплых окон не зависят от слабого office ambient. Разделители и этажные полосы сглаживаются через fwidth. Это имитация отражений, без SSR и реальных интерьеров окон. Street shader без текстур. Бюджет узлов/геометрии прежний. City tests PASS; screenshot/render/FPS данного исправления ещё не получены. Общий gate по-прежнему блокируется прежней private infected_capsule reference в карте.

10.10.2026: по запросу владельца внешний город получает distance fog: ближние фасады слегка затуманены, дальние — силуэты и приглушённые окна; улицы смешаны с fog color минимум на 88%. Interior не затронут. Дальний shader пропускает расчёт отражений и материала, геометрия не culled туманом, FPS не измерен. City tests 0 failures; native shader/render приёмка pending. Следующее действие: проверить screenshot/FPS после обновления main.

10.10.2026 (image(10)): устранены открытые просветы тёмного sky под городом: FogGround plane 3000×3000 на y=-65.4, unshaded fog color, street fog 98–100%, нижняя/горизонтальная часть sky совпадает с fog color. Основания фасадов растворяются по высоте -65…-12м. +1 render node/+2 triangles; без текстур/физики. City headless tests 0 failures; native seam check pending. Следующее действие: проверить image из того же ракурса и Q/E.

10.10.2026 (пол и локальный свет): уменьшены контраст шума и интенсивность scuff/marks/traffic; worn roughness меняется мягче. Floor MultiMesh секции 16×16→8×8м, material variants 8→2 с диапазоном tint 0.99–1.01; максимальное число batches остаётся 160. Это снижает конкуренцию ламп за отдельный объект в Compatibility, но причина визуального переключения света ещё не доказана native кадром. Управление лампами/сохранения прежние. Floor tests 0 failures, включая <=16 tiles per section. Следующий шаг: сравнить свет нескольких ламп при движении героя и Q/E на Windows; FPS/native не измерены.
