# Ресепшен 07_reception_counter_two_heights_2 — issue251

Запрос владельца: создание/сохранение шаблонов и неподвижность модели.
Принятая интерпретация: корпус закреплён в игре; в Planning его можно размещать
и редактировать его шаблон. Разрушение фасада и физические сколы сохраняются.

## Изменения

- bootstrap.app: модель зарегистрирована в workstation catalog с отдельным
  ключом `reception_2`. Старый `reception` не меняется: геометрия двух моделей
  различна, автоматическое смешивание пользовательских шаблонов недопустимо.
- Новый authored profile содержит нижнюю поверхность0.78м и верхнюю1.10м.
  Высоты и размеры проверены по горизонтальным треугольникам Intact GLB:
  нижняя столешница x±1.61/z−0.65…0.25, верхняя x±1.70/z−0.02…0.45.
  Зоны с небольшим отступом от края разделены по Z, чтобы верхняя столешница
  не перекрывала размещение на нижней.
- office_floor: существующий EnvironmentProp._ready закрепляет только корпус
  этой модели через freeze. Толчки персонажей/пуль уже учитывают этот флаг;
  переход DamageReady и отделённые фрагменты сохраняют прежние правила.

## Проверки — итоговые наборы PASS

Baseline:
- Python regression падает: у `_2` нет записи шаблона.
- Реальный staged GLB regression падает4раза: freeze до урона, отсутствие
  сдвига после толчка/пули/импульса, сохранение положения при разрушении и сколах.

Проверки итоговой реализации:
- Python workstation tests:4 PASS, включая отдельный ключ и обе высоты.
- staged_glb: неподвижность при push_from_character/UZI/внешнем импульсе,
  переход фасада и физический отрыв скола; прочие staged props не меняются.
- placement/templates/weapons: обычная кнопка TEMPLATE доступна; создание,
  сохранение/перезапись/применение, повторный вход, placement из сохранённого
  шаблона, Shift drag на обеих столешницах, реальная высота основания предметов,
  сериализация двух предметов и сохранение freeze после Planning resume.
- wall_mount_support:25 других моделей сохраняют прежние правила крепления.
- Полный planning_mode: authored-map save/load/exit.
- validate_project (включая spec/workflow/architecture/source-size/174CI suites),
 383 scene resource references, editor import Godot4.7.2 и git diff --check.

Владельцы/API/DTO/сцены/зависимости/policy прежние; исключений нет.
EnvironmentProp570 строк: настройка тела остаётся в существующем composition
callback, дополнительного helper для одной строки не требуется.

Ручная Windows/Web приёмка мышью не выполнена. Публикация ветки и PR явно
поручена владельцем; следующий шаг — проверить CI PR и ручной сценарий.


## PR274: исправление CI (18.10.2026)

В run39110370218 / runtime job117625025157 падали пять наборов.

- display_planner: conference chair повторно поднимался на0.025м во время
  загрузки. Loader подавляет spawn-time grounding существующей меткой только
  на время ready; для неподготовленных кресел метка сразу снимается. Координаты,
  rotation/scale и optional settled_physics остаются прежними. Добавлена
  регрессия старой v6 карты с малой отрицательной Y и повторной загрузкой;
  полное сравнение полей authored map сохранено без ослабления точности.
- named_map_loading: clear_layout обращался к отсутствующему session.host в
  минимальном окружении. Optional host читается через get; поддержаны Node и
  Dictionary sessions, очистка стеклянного мусора в полной миссии сохраняется.
- skill_vfx: отсутствующие атласы оставляли навыки без графики. Setup один раз
  проверяет доступность и включает существующие procedural effects при их
  отсутствии, включая старое сохранённое значение настройки false. Проверки
  видимости, количества, времени жизни и range domes сохранены; acid pool test
  учитывает реальную нормаль PlaneMesh или QuadMesh и поворот камеры.
- flipbook: тест требовал удалённые владельцем PNG. Вместо этого проверяется
  безопасный null для отсутствующего optional atlas; проверки существующих
  ресурсов, циклов, кадров, fade и ground geometry сохранены.
- status_fx: звёзды оглушения зависели от удалённого PNG. Новый private
  infected/stun_stars строит три золотые звезды из геометрии, вращает их над
  головой и плавно удаляет. Проверены наличие геометрии, окончание статуса,
  poison overlay и очистка на смерти.

Удалённые ассеты не восстановлены. Новых public API, DTO, сцен, dependency
edges, owners, Autoload или architecture exceptions нет. Player VFX411 и
planning_objects474 reviewed: сохранены существующие adapters; визуальный
helper звёзд имеет отдельную ответственность. Публикация — в ту же ветку PR274.


Повторная проверка на Godot4.7.2 после восстановления временной среды:
9/9 suites PASS без SCRIPT ERROR/ERROR: display_planner, named_map_loading,
skill_vfx, status_fx, flipbook, planning_settle, placement/templates/weapons,
staged_glb и полный planning_mode save/load/exit. Последний завершился за81с.
Skill_vfx отдельно повторён после проверки направления нормали PlaneMesh — PASS.
Editor import exit0; validate_project (175CI registrations),383 scene resource
references,956 import files,4 Python workstation tests и git diff --check PASS.
Новый CI запускается публикацией repair commit; ручная Windows/Web приёмка
остаётся непроведённой.


CI f5d2511, run39137646389:166/167 runtime suites PASS, включая все5
исходных падений. Единственный оставшийся runtime_debug ожидал переключения
на удалённые sprite sheets. Проверка исправлена: legacy preference0 сохраняется
на диске, при этом доступные procedural effects продолжают работать. Полный
runtime_debug локально PASS; project gate, editor import и diff PASS.
Production code в follow-up не меняется. Все7 rendering jobs, architecture и
обе impact geometry jobs этого запуска PASS. Следующий шаг — новый полный CI.
