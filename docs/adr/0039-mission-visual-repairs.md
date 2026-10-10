# ADR-0039: Исправления прицела, дыма и освещения

- Status: accepted
- Date: 2026-10-10
- Owner: bageus — прямой запрос исправлений
- Modules: bootstrap.app, features.infection_source, presentation.prototype_hud, presentation.office_floor

## Контекст и решение

Загрузчик после успешного перехода включал MOUSE_MODE_CAPTURED, хотя изометрическое прицеливание использует положение свободного курсора. Успешный start/restart оставляет MOUSE_MODE_VISIBLE; rollback прежний.

HUD сохраняет weapon_view_v1 и локальный 224×224 SubViewport. Угол обзора линзы учитывает отношение её диаметра к размеру viewport источника и keep_aspect: tan(scope_fov/2) = tan(source_fov/2) × diameter / source_span / magnification. Поэтому заданные 2.5× относятся к экранным пикселям, а не к сравнению углов больших и малых render views. Камера по-прежнему направлена в aim target.

Infection_source сохраняет поглощение, время жизни, барьерную маску, cap десяти временных облаков и depletion. Вместо PNG flipbook используется процедурный shader: две частоты value noise, мягкая граница, подъём и рассеивание. Default 3–4 puffs + один низкий слой, без отдельной симуляции спор; старые PNG и пользовательские ресурсы не удалены.

Office_floor назначает каждому третьему зданию вариант стеклянного офисного фасада. Остальные сохраняют бетон/окна; туман, отсутствие коллизий и бюджет 144 зданий прежние.

Bootstrap interface_v1 получает optional bool lighting=true. Video содержит переведённый переключатель, который через прежний PlanningLighting включает/отключает лампы и общий DirectionalLight. Фоновая подсветка Environment остаётся для видимости. Late lamps obey the existing node_added hook. Authored power/color/flicker и layout DTO не меняются.

## Альтернативы

Захват мыши с виртуальным курсором потребовал бы другой input contract. Один лишь меньший FOV не компенсирует экранный размер линзы. Тяжёлый volume raymarch и дополнительные частицы увеличивают GPU-нагрузку. Замена authored power на ноль при выключении света теряла бы настройки объектов.

## Миграция и откат

Старые interface_v1 без lighting получают true; старые читатели игнорируют поле. Reset возвращает true. Карты, сохранения кампании, public API, владельцы состояния и направления зависимостей прежние. Откатить данный коммит; старые PNG сохранены. Исключений архитектуры нет. Новая опция явно запрошена владельцем.

## Проверки

Scope regression сравнивает world coverage per pixel. Start/restart проверяют свободную мышь. Settings тестирует UI и сохранение bool; lighting тестирует off/on и позднюю лампу. Cloud тестирует отсутствие atlas samplers, лимит пяти прозрачных слоёв и жизненный цикл/поглощение. City native тестирует периодичность стеклянных зданий. Реальный FPS Windows/Web остаётся целевой проверкой владельца.
