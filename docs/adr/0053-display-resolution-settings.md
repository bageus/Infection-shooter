# ADR-0053: Разрешение и режим окна

- Status: accepted
- Date: 2026-10-16
- Owner: bageus — прямой запрос актуальных разрешений и window/fullscreen
- Module: bootstrap.app

## Context and decision

Существовала непостоянная fullscreen кнопка, окно стартовало1280×720. Владелец
запросил Video выбор разрешения, включая integrated GPUs, и режима окна.
Добавлены optional interface_v1.window_mode:int=0 (windowed0/fullscreen1) и
resolution:String="1280x720". "auto" выбирает native budget; прежние defaults
сохранены. Список 720p/900p/FullHD/QHD/4K,16:10/ultrawide фильтруется по монитору;
fullscreen дополнительно по aspect. Неподходящий выбор разрешается в ближайший
доступный budget без supersampling. Native всегда доступен.

Private display_catalog выполняет чистые расчёты. Private display_settings —
bootstrap adapter для mode/placement/root3Dscale. Он создаётся под root window,
живёт между миссиями, подписан на size_changed один раз, без polling.
Повторный apply того же mode/resolution не меняет window size/position. Windowed
помещается в рабочую область текущего монитора с запасом для decorations. Resize
fullscreen использует фактический размер viewport, изменяя только scaling_3d_scale;
canvas_items/base1280×720, текст и координаты input/camera не меняются. Bilinear
поддерживается Compatibility; новый renderer/FSR/plugin не добавляется.
Web не меняет размер canvas и запрашивает mode только из пользовательского действия;
браузер может отказать fullscreen. Headless не делает нативных window вызовов.

## Alternatives

Непроверенный фиксированный список выдаёт недоступные размеры. window_set_size
в fullscreen не уменьшает GPU render budget. Viewport stretch снижает также
качество UI и меняет координаты прицела. Отдельный SubViewport усложняет composition
без необходимости. Обновление display на каждом slider apply сбрасывает ручное
положение/размер окна. Поэтому platform calls вынесены в private adapter.

## Migration and rollback

Старые конфиги используют windowed1280×720; неправильные типы/значения получают
безопасный default. Новые ключи остаются optional interface_v1, старые readers их
игнорируют. Карты/gameplay saves/public module API/сцены/dependency edges/owners и
architecture policy прежние. Revert возвращает старую кнопку; preference file
допускает игнорирование новых полей. Архитектурных исключений нет.

## Validation and approval

Прямое поручение владельца разрешает дополнительные локальные preferences и
переключатели. QA: docs/qa/display_resolution_settings.md. Tests: size/aspect/filter,
small screens/offset monitor, fallback/malformed/legacy/save/reset, UI language,
3Dscale и неизменность canvas/UI, lifecycle/повторный apply, реальный start/restart.
Native fullscreen/renderer pixels и FPS требуют доступного display backend.

## Native CI follow-up — 17.10.2026

Adapter записывает mode/size/position через injected Window, чтобы состояние
Viewport не зависело от повторного OS ConfigureNotify после DisplayServer write.
Native CI использует Xvfb+Openbox (EWMH manager), дожидается ready и завершает
его вместе с suite. Assertions fullscreen/restore сохранены; OS и scene размеры
должны совпасть два кадра в пределах2с. Public API/DTO/owners/edges прежние.
