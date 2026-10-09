# Город за окнами

32 процедурных box-здания, 4 MultiMesh batch, общий mesh/material/shader. Без изображений, физики и динамического света. Геометрия: 384 треугольника без учёта внутренних engine transforms. Бюджет не зависит от числа окон: окна вычисляются fragment shader. GPU время зависит от площади фасадов на экране; FPS и Windows peak RAM ещё не измерены.

Основная карта 80×60 м, зазор 30 м, основания y=-65. Высота 72–128 м. Для другой геометрии локации параметры location_size/street_gap задаются в CityBackdrop. Камера остаётся игровой; фон не добавлен в палитру и карты сохранения.

Проверить: из окон видны соседние фасады, при Q/E фон не исчезает, ближайшее здание не перекрывает границы этажа, restart не меняет городской силуэт. Автотест run_city_backdrop_tests.gd проверяет бюджет, отсутствие physics children, отключение shadow, зазор и воспроизводимость.

Проверено локально Godot 4.7.2: editor headless import без ERROR; run_city_backdrop_tests — 0 failures. validate_project/resource paths/scene resources PASS. Native shader compilation, итоговый вид из окон и FPS не проверены: графический display в окружении отсутствует. Headless dummy renderer не возвращает MultiMesh transforms, поэтому тест размещения проверяет сохранённые authored transforms, передаваемые в MultiMesh, а не driver readback.
