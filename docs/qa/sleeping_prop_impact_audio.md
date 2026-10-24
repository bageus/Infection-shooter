# Спящая мебель: остановка звуковых callbacks

Дата: 24.10.2026. Инкремент T004, первый пункт FPS-диагностики.
База: main `5ee4e6ef3ac36d6f1b56cb7bb372179ec02dce06` (PR460).

## Причина и исправление

`planning_physics.resume()` восстанавливает prepared sleep и в Node, и в
PhysicsServer3D. Прямое присваивание `sleeping` не сообщает
`sleeping_state_changed`, поэтому уже созданный ImpactSound мог оставаться
включённым у спящего тела. Обратный путь также важен: игровые bullet/push/blast
адаптеры могут задать `sleeping=false` перед импульсом, и старый спящий watcher
не просыпался по сигналу. Одного early return на sleep недостаточно.

Private watcher теперь наследует Node3D и получает уведомление о перемещении
родительского тела. Оно возобновляет наблюдение, если тело бодрствует. Физический
callback отключается при sleep/freeze. Native sleep/wake signal, явный wake
при отрыве крепления и reset_fragment при повторном использовании сохранены.
Таймеров/покадрового опроса спящих тел и глобального состояния не добавлено.
Геометрия, масса, импульсы, коллизии, сон физического тела и баланс не меняются.

Затронут только production файл
`game/presentation/office_floor/impact_sound_watcher.gd`, принадлежащий
`presentation.office_floor`. Runtime watcher не является частью authored
публичной сцены или map DTO. API, схемы сохранений, ресурсы, зависимости,
владельцы состояния и architecture/policy.json прежние; исключений нет.

## Проверка дефекта

`run_impact_sound_sleep_tests.gd` восстанавливает Node и native sleep (как prepared resume) для
4000 простых RigidBody3D и считает исполнения callback подклассом watcher.
После перехода в сон измеряются 60 физических тиков:

| Версия | Активных watchers в покое | Лишних callbacks за 60 тиков | Failures suite |
|---|---:|---:|---:|
| База main | 4000 | 240000 | 6 |
| Исправление | 0 | 0 | 0 |

Это измерение количества вызовов на изолированном стенде, не FPS полной карты.
Стенд проверяет native и scripted impulse wake, первоначально спящие тела,
повторный сон, frozen mounts и перемещение в paused planning, существующий
wall-detachment wake, fragment reset/re-entry, два реальных падения на пол
с повторным созданием `fall_metal` audio voice после scripted wake.
Headless проверяет dispatch звука; ручного прослушивания не было.

## Команды

```bash
python tools/validate_project.py
godot --headless --path . --editor --quit
godot --headless --path . --script game/presentation/office_floor/tests/run_impact_sound_sleep_tests.gd
godot --headless --path . --script game/presentation/office_floor/tests/run_sound_hook_tests.gd
godot --headless --path . --script game/core/audio/tests/run_sound_event_tests.gd
godot --headless --path . --script game/bootstrap/app/tests/run_planning_settle_tests.gd
godot --headless --path . --script game/presentation/office_floor/tests/run_debris_tests.gd
godot --headless --path . --script game/presentation/office_floor/tests/run_fragment_pool_tests.gd
godot --headless --path . --script game/presentation/office_floor/tests/run_prop_weight_tests.gd
```

## Итог проверки

Godot4.7.2 headless: все семь приведённых runtime suites PASS, без SCRIPT ERROR,
ERROR и сообщений о потерянных ObjectDB/RID. Повтор final focused suite:
0 failures,0 callbacks; тот же final suite с исходным watcher:
6 failures,240000 callbacks. Editor import без ERROR; validate_project PASS
(225 discovered suites:217 runtime+8special), git diff --check PASS.

Focused suite задаёт восстановленный sleep напрямую в пределах office_floor;
реальный bootstrap resume/PackedScene reload проверяет существующий
run_planning_settle_tests. Новых private cross-module dependencies не добавлено.

Windows/Web, карта владельца и прирост FPS не измерены. Следующие пункты
диагностики (двери, decals, screens, shadows) в эту правку не входят.
