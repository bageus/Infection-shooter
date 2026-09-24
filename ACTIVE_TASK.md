---
task_version: 1
task_id: T002
status: IN_PROGRESS
phase: 1
owner: AI
updated: 2026-09-23
---

# Active task

## Goal
Build the first playable combat-slice foundation with an authored office floor, player, combat, infected enemies, infection source, and observable fail states.

## In scope
- hand-authored office floor from the newly grouped 01-16 object library;
- closed non-destructible perimeter with window/wall corner modules;
- expanded 80 x 60 m floor plan with elevator lobby, short connector corridor, small hall, broad left/right circulation, open combat areas and a small enclosed office;
- player defeat on zero health or falling below the floor;
- temporary defeat menu with restart and exit.

## Dependencies
READY game specification, accepted working agreement, architecture contract, and existing T001/T002 implementation.

## Affected modules
presentation.office_floor, features.combat and bootstrap.app. Player health remains owned by features.player.

## Out of scope
Procedural generation, save/checkpoints, final HUD, monetization, platform SDKs and campaign-wide content remain outside this T002 increment.

## Acceptance criteria
- Structural modules visually touch edge-to-edge with no visible gaps and no overlap beyond a tiny seam tolerance.\n- Exterior corners face inward correctly.\n- Perimeter and authored interior walls block the player.\n- The expanded floor and defeat menu remain functional.

## Progress
Палитра планировщика очищена от восьми пунктов, чьи сцены ссылаются на отсутствующие GLB. Неиспользуемые ссылки на отсутствующие угловые модели удалены из стартовой сцены. Клики и движения мыши внутри панели планировщика не размещают объекты на поле. Светильники получили режимы постоянного света, быстрого и медленного мерцания, редких отключений и настраиваемый шаг; значения нового и выбранного светильника сохраняются в карте и авторской сцене.

По уточнению владельца `07_table` переведён на физическое тело из столешницы и оставшихся ножек: первое попадание сразу разрушает выбранную часть; потеря одной ножки наклоняет стол к отсутствующей опоре, потеря двух ускоряет опрокидывание. При разрушении центра остальные ножки отделяются и падают. Физические предметы на столешнице получают толчок по направлению наклона. Оставшиеся после таймера 1–3 обломка не сталкиваются с игроком и другими телами.

По обратной связи владельца восстановлены ненулевой масштаб мешей из GLB и твёрдая коллизия исходного стола. Попадание переключает модель на пять адресных частей, далее создаёт физические фрагменты; после задержки остаётся 1–3 обломка на стол, не более 40 на сцену, затем исчезают и они. Следы пуль и дерева отображаются плоскими мешами в Compatibility, имеют общий предел 40 по принципу FIFO.

Structural asset audit completed. `docs/ASSET_STANDARD.md` now defines the 0.25 m placement grid, canonical root pivots, the existing 2.25 m facade module, and identifies the 13_* glass kit plus the legacy 2.8 m cubicle partition as requiring dimensional correction/visual verification. All canonical public structural scenes are now declared in the module manifest. Source GLB/Blend geometry has not been destructively rescaled before Godot AABB verification.

The office-floor composition was rebuilt for the newly oriented grouped object library. Old public asset-wrapper usage was removed from the active scene, including the former -90 degree model compensation. The floor footprint is doubled from 40 x 30 to 80 x 60. The perimeter uses window corners at all four corners, mostly window modules along the facade, a solid elevator/emergency-exit block on the south facade, scene-authored perimeter collision, and a regular interior column grid. Interior architecture now provides an elevator lobby, short connector, small hall, wide circulation, open areas and a small enclosed office using explicit inner/outer corner modules. Bootstrap now detects zero health and falling below the floor and shows a temporary restart/exit defeat menu.

## Validation
Локальные проверки выполнены: готовность спецификации и рабочего состояния пройдена; архитектурная проверка и лимит исходников блокируются существующими нарушениями. Изолированный импорт и тест сцены в Godot 4.5.2 прошли; полный проект требует Blender и остальных моделей.

## Risks
Полный проект импортирует .blend только с установленным Blender. Изолированная сцена использует проверенный GLB; визуальное совпадение всех частей и коллизий в игровом Godot 4.7.2 ещё требует просмотра.
## Validation evidence
Изолированный Godot 4.5.2 разобрал скрипты планировщика и светильника без синтаксических ошибок; проверка подтвердила реальные отключения, восстановление яркости и изоляцию клика по панели. Сверка всех пунктов палитры с деревом Git не обнаружила оставшихся ссылок на отсутствующие модели. Полный запуск игровой сцены остаётся ограничен отсутствующими ресурсами в текущей разреженной копии и ранее отмеченными нарушениями проверок.

Изолированный Godot 4.5.2 подтвердил лучом коллизию целого и модульного стола, адресное попадание по форме ножки, распад центра и ножек, опрокидывание после второй ножки, падение физического предмета со стола, вторичное дробление столешницы, предел 40 декалей и бесконтактные остаточные обломки. Полный headless импорт с разреженной копией репозитория вывел ошибки отсутствующих ресурсов и некорректных прежних `.import`; визуальная проверка в полной сцене Godot 4.7.2 остаётся необходимой. `validate_project.py` по-прежнему не проходит старые нарушения архитектуры и лимит `planning_mode.gd` (1383 строки); новый `staged_table.gd` превышает рекомендованный порог 300 строк, но не жёсткий лимит.

Проверка готовности спецификации и рабочего состояния пройдена. Архитектурная проверка и ограничение размера исходников всё ещё выявляют старые нарушения вне этого изменения. Изолированный Godot 4.5.2 подтвердил лучом коллизию intact и Top, переходы Leg/Top/Top_01, пределы 40 следов и 40 остаточных обломков и сохранение 1–3 фрагментов. Полная игровая сцена в Godot 4.7.2 требует проверки на стороне владельца.

User runtime screenshots exposed perimeter spacing, corner orientation and missing interior collision defects in the previous increment. This increment corrects those defects; repository CI must validate the static project gates.

## Blockers
No product blocker. Exact imported .blend bounds still require visual confirmation in Godot.

## Next exact action
В полном проекте Godot 4.7.2 проверить интерфейс палитры и настройку мерцания после сохранения и загрузки карты.

Проверить в полной сцене Godot 4.7.2 направленное падение стола при отстреле каждой пары ножек и поведение размещённых на нём физических предметов.

Проверить в полной сцене Godot 4.7.2 визуальную ориентацию отметин на стенах и предметах, все четыре ножки, восемь частей столешницы и исчезновение остаточных обломков.

Run repository gates, then measure imported structural mesh AABBs in Godot against `docs/ASSET_STANDARD.md`; correct the 13_* glass connection span to 4.0 m and any retained legacy cubicle partition to 3.0 m only after confirming source mesh bounds.

## Session handoff
T002 remains the only active task. After CI, visually verify seams and collision in Godot before adding furniture/content.
