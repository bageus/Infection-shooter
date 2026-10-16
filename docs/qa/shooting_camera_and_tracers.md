# Реакция камеры и яркость стрельбы — 16.10.2026

Прямой запрос владельца, инкремент T004/Phase1. База main12d2570f.

## Результат

Player получает импульс только после успешного `_fire_weapon`. Private
`shooting_camera_state` хранит нормализованную прибавку дистанции, не боевое
состояние оружия. Первый импульс: pistol/Uzi0,5%, M40,65%, AK/rifle0,75%,
minigun0,8%, shotgun1,2%, sniper1,5%, launcher1,8%. Каждый новый успешный
выстрел накапливает прибавку до жёсткого предела3%. После последнего выстрела
удержание0,3с, затем линейное снятие1,2 процентного пункта/с. Существующее
экспоненциальное сглаживание камеры8/с убирает скачки. Максимальный envelope
возвращается к нулю за2,8с; камера плавно завершает возврат. Manual zoom и
weapon bonus образуют baseline, к которому применяется процент. FOV и
снайперская magnification прежние. Pause останавливает gameplay delta.

Combat сохраняет прежние ammo_* изображения/solid core, направление и физику
пули. Один короткий additive quad с двумя боковыми полосами и ослабленным
хвостом добавляется для bullet weapons; граната прежняя. Mesh/материал полос
immutable и разделяются через существующий cache по оружию. На летящую пулю
приходится один дополнительный mesh draw; новых lights/particles/physics/rays
нет. Заявления об ускорении/FPS не делались.

Вспышка использует прежние atlas6frames/anchor/duration: opacity0,85→0,95,
albedo×1,15, начальная emission0,42→1,25 с прежним затуханием по кадрам.
Новых ассетов/зависимостей/owners/API/сцен/DTO/архитектурных исключений нет.
Player root остаётся548 строк; отдельное состояние выделено по ответственности,
root только передаёт успешный shot и применяет envelope к прежней камере.

## Проверки

Godot4.7.2, headless/Dummy:

- `run_shooting_camera_tests.gd`:0 failures. Первый импульс, сила оружия,
  100 последовательных выстрелов каждого типа, cap/hold/recovery, независимость
  recovery от delta. Реальный Player: success/cooldown/empty magazine/spin-up;
  baseline9/24м плюс pistol/AK/sniper/minigun bonus, достижение3% и возврат.
- `run_weapon_presentation_tests.gd`:0 failures.
- `run_projectile_step_budget_tests.gd`:0 failures.
- `run_cursor_aim_tests.gd`:0 failures.
- `run_new_weapon_tests.gd`:0 failures. После400 выстрелов камера теперь
  обновляется240 шагами1/60с перед прежним точным assertion возврата baseline.
  Это учитывает новый envelope; gameplay assertions не ослаблены.
- Headless editor import:exit0.
- `validate_project.py`, spec/workflow ready, scene_resources:PASS.
- `git diff --check`:PASS.

В финальных runtime/editor логах нет SCRIPT ERROR/ERROR/ObjectDB leak warnings.
Есть предупреждение среды об отсутствии `/proc/self/exe`.
Новый camera suite добавлен в существующий runtime CI.

## Осталось проверить вручную

Headless Dummy не проверяет пиксели, shader GPU compilation и художественную
яркость. Нужна Compatibility/Windows/Web приёмка: короткие/длинные очереди,
светлый/тёмный фон, все bullet weapons, Q/E, ручной zoom, sniper scope, pause.
Проверить, что исходная пуля читается внутри полос и вспышка не пересвечивает
изображение. Pixel scope assertion существующего new_weapon suite отложен им
до native CI, headless результат не считается такой проверкой.

Следующее точное действие: native визуальная приёмка и публикация PR по
поручению владельца. Ветка `codex/shooting-camera-and-tracers`; merge не поручен.
