---
state_version: 1
status: IMPLEMENTATION
current_phase: 1
current_milestone: P1_LOGIC
active_task_id: T002
last_completed_task_id: DISC-001
build_status: T002_EXPANDED_FLOOR_PENDING_VALIDATION
updated: 2026-09-23
---

# Project state

## Current outcome
Числовые поля планировщика снова принимают цифры с клавиатуры. Обычная и аварийная двери не перекрывают проём неподвижной коллизией при открытии; закрытые полотна продолжают блокировать проход.

Регрессия выбора объектов в палитре устранена; столешница после разрушения больше не удерживает оставшиеся ножки неподвижными. Все четыре ножки падают как отдельные физические тела.

Палитра больше не показывает восемь пунктов без моделей; нажатия в панели не создают объекты в мире. Для размещённых светильников доступны скорость/шаг мерцания и редкие отключения с сохранением параметров.

Тестовый стол теперь физически наклоняется к отстреленной ножке и быстрее падает без двух опор; попадание по центру разбрасывает столешницу и освобождает ножки. Физические предметы сверху получают импульс по направлению наклона. Оставленные обломки перестают препятствовать проходу.

По прямому запросу владельца тестовый `07_table` получил поэтапное разрушение, а пули — общие декали попаданий. После обратной связи исправлены нулевой масштаб деталей и коллизия исходного стола. Декали заменены на плоские меши для Compatibility; бюджет 40 общих следов и 40 остаточных обломков.

T002 remains active. The combat slice now uses the newly grouped/oriented object library for a rebuilt 80 x 60 authored office floor. The new composition has a continuous perimeter, window-heavy facade, elevator/emergency-exit block, columns, planned internal circulation and temporary defeat handling for zero health or falling out of the playable floor.

## Current phase
Phase 1 — Logic prototype, extended into the owner-requested T002 playable slice.

## Current milestone
P1_LOGIC.

## Active task
T002 — Minimal combat slice. Status: IN_PROGRESS.

## Build and validation
Изолированный тест Godot 4.5.2 подтвердил работу светильника и блокировку клика по панели. Указанные в палитре модели сверены с деревом Git; полная сцена Godot 4.7.2 требует визуальной проверки.

Изолированная проверка в Godot 4.5.2 прошла для адресных попаданий, разрушения центра, опрокидывания и падения предмета; полный импорт в разреженной копии репозитория содержит ошибки отсутствующих ресурсов. `validate_project.py` не проходит прежние нарушения архитектуры и размер `planning_mode.gd`; `staged_table.gd` теперь выше рекомендованных 300 строк.

Проверки готовности спецификации и рабочего состояния прошли. Архитектурная проверка и лимит исходников падают на существующих файлах вне этого изменения. Изолированный тест в Godot 4.5.2 прошёл, полная игровая сцена ещё не проверена.

Изолированный тест лучами и переходами стадий прошёл; импорт полного проекта требует всех ресурсов и Blender.

## Current risks
Structural asset audit found inconsistent connection spans in legacy glass/cubicle modules. The canonical standard is now documented at `docs/ASSET_STANDARD.md`; destructive source-mesh edits remain blocked on Godot AABB/visual verification.

The new source object library is stored as .blend files; local Godot import therefore depends on Blender being available during import. Exact mesh pivots/extents require visual review. Scene-authored collision provides the authoritative closed gameplay boundary.

## Known blockers
No product blocker. Godot visual/import verification remains required.

## Next action
В полном проекте Godot 4.7.2 визуально проверить опрокидывание при разных сочетаниях потерянных ножек и выпадение размещённых на столе предметов.

Проверить обновлённый стол и видимость следов пуль в полной игровой сцене Godot 4.7.2, затем отдельно устранить старые нарушения проверок репозитория.

После проверки стола измерить границы структурных мешей в Godot и исправить подтверждённые размеры остекления и перегородок.

## Handoff notes
Perimeter and interior wall collision is scene-authored. The latest correction tightens structural module spacing and fixes exterior corner orientation based on user runtime screenshots.
