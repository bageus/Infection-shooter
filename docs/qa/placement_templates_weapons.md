# Планировщик: preview, шаблоны и оружие — 10.10.2026

В рамках T002 по прямому запросу владельца.

- `bootstrap.app/planning_geometry`: ray исключает корень и все дочерние CollisionObject3D обычного preview, даже если импорт создаёт/включает shapes позже. Wall tools сохраняют прежние исключения соседних wall tools. Preview RigidBody заморожен, PROCESS_MODE_DISABLED запрещает движение/анимацию.
- `desk_setup_template_files`: прежний JSON v1 и каталог user://desk_setups; запись через закрытый и повторно прочитанный временный файл, только затем rename. Перезапись не обнуляет прежний файл до успешной проверки; список сортируется.
- `desk_setup_mode`/`desk_setup_visuals`: кнопка TOP VIEW ставит оптическую ось точно вниз, screen-up соответствует локальному направлению стола. Zoom сохраняет ракурс; orbit/reset возвращают наклон. Проекция камеры прежняя.
- `planning_catalog`/`planning_controls`: отдельная кнопка Weapons над палитрой; pistol/UZI/shotgun/launcher/AK/M4/sniper/minigun используют восемь bootstrap сцен с прежним weapon_pickup. Weapon index задан в сцене, карта v8 сохраняет прежнее поле scene. Первый runtime tick берёт фактически загруженную позицию, а bob авторского pickup не опускается ниже опорной высоты. Preview не вращается; prompt меши исключены из bounds.
- `office_floor/environment_prop`: валидность mesh проверяется до передачи в типизированный is_glass_mesh, в обоих material/hit путях. Прежняя механика попаданий не меняется.
- `planning_blood_placement`: устранён shadowed point warning из скриншота.

Публичные API, DTO v1/v8, state owners и зависимости прежние; architecture exceptions нет. Новые сцены приватны для bootstrap. Исходные модели/текстуры не меняются. Ошибка старого dented PNG на скриншоте отдельно не воспроизведена: чистый импорт текущих ресурсов завершён без ошибок.

## Декомпозиция

Проверены файлы выше 300 строк. Geometry сохраняет ответственность расчёта placement; controls — UI команд; objects — lifecycle авторских экземпляров; EnvironmentProp — прежняя scene boundary. DeskSetupMode (597 строк) получает одну кнопку, реализация ракурса остаётся в существующем DeskSetupVisuals. Новые обязанности в эти файлы не переносятся; искусственные pass-through классы не добавлены. Все hard limits соблюдены.

## Проверки

Godot 4.7.2 headless import PASS без ERROR/SCRIPT ERROR. Project gate (strict specification/workflow, architecture, source size), resource paths и import profiles PASS; Python workstation templates: 3 tests PASS.

Headless suites PASS: новый placement_templates_weapons, planning_mode, planner_persistence, planner_contact, planner_extension, destruction_wiring, pickup_floor. Новый suite включён в Runtime CI. Проверены активная self-collision preview, 60 повторных placement ticks, table и shelf zones + attached mouse + overwrite + reload + unicode, точная ось сверху и zoom/orbit, восемь типов оружия после повторного map v8 round trip, сохранённая высота runtime bob, freed glass dispatch. Аудит разрушения: 230 моделей / 98 staged / 0 failures.

Windows/Web визуальная приёмка и новый GitHub CI ещё требуют проверки. Точное следующее действие: принять draft PR после CI и проверить TOP VIEW, оружие на полу/столе и повторное открытие шаблонов после перезапуска игры.
