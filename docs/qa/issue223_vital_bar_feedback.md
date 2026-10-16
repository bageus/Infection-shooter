# Issue223: здоровье и мутация — анимация изменений

Прямой запрос владельца: одинаковое поведение обеих шкал. T004/Phase1/P1_LOGIC.

## Изменения

Только presentation.prototype_hud:

- `vital_bar_feedback_state.gd`: два независимых instance для здоровья/мутации;
  snapshot текущей цели, целочисленный displayed count, белый trail и pulse;
- `vital_bar_feedback.gd`: локальный Control overlay/адаптер к ProgressBar,
  Label и optional CriticalMarker;
- `prototype_hud.gd`: configure двух adapters, передача snapshot targets,
  advance вне snapshot guard. Root433 строки; новая анимационная обязанность
  выделена по ответственности, прежняя композиция/сигнатуры сохранены.

Fill получает реальный health/mutation сразу. Числа движутся по1 целому за
update, с минимальным интервалом0,02с (до50/с при достаточном FPS). При низком
FPS счёт ограничен одним числом на отображаемый кадр, поэтому большой перепад
считается дольше; список старых анимаций не накапливается, цель всегда последняя.
Направление count определяется текущим displayed относительно новой цели.

Белый сегмент занимает интервал между предыдущим и новым fill. Hold0,12с,
затем fade0,28с и приближение trailing edge к текущей цели. В росте белый лежит
поверх добавленного заполнения, в снижении — над освобождённым участком.
Reversal начинает новый интервал от предыдущей цели. Continuous fractional
mutation не удерживает бесконечно растущий белый участок: trailing edge
догоняет актуальную цель после первого hold.

Pulse0,28с: sin envelope от1 к0,95/1,05 в середине и обратно ровно к1.
Пульсы не складываются. Целочисленные изменения запускают pulse; fractional
mutation обновляет fill/trail без перезапуска pulse каждый кадр. Reversal
переключает направление. Первое отображение и смена максимума синхронизируются
сразу без искусственного damage/heal; смена языка не сбрасывает состояние.

Bar/число пульсируют отдельно для каждой шкалы. Существующий control-loss
scale1×1,6 умножается на pulse, critical marker остаётся на threshold position.
Прежние heal/alarm/DNA эффекты сохранены. Белый overlay рисуется sibling-ом
bar и не наследует её цветовой modulate, но повторяет DNA self-modulate alpha.
Свойства игрового состояния, threshold rules, armor, сцены/пути, public API,
ресурсы, сохранения/DTO и dependencies не изменены. Архитектурных исключений нет.

## Проверки

Godot4.7.2 headless/Dummy:

- `run_vital_bar_feedback_tests`:PASS. Initial/no flash, count±1/zero,
  latest-target retarget и100быстрых reversal, hold/fade, точный peak95/105,
  отсутствие stacking, continuous fractional lag, max range/clamp. Настоящие
  Controls: fill immediate/count delayed, overlay sibling bounds/order,
  control-loss scale composition, marker position, DNA alpha, resize.
- `run_vital_bar_hud_tests`:PASS. Настоящие Player и HUD: damage/heal,
  mutation absorption/antidote, обе шкалы, продолжение анимации после snapshot
  cache, завершение idle, armor, locale/maxHP и реальная пауза дерева.
- Прежние `run_armor_hud_tests`, `run_weapon_icon_tests`,
  `run_vitals_fx_tests`, `run_mutation_feedback_tests`:PASS.
- `run_gameplay_planner_repairs_tests`:PASS; полная загрузка карты/restart
  и существующее gameplay/planner wiring.
- Editor import, `validate_project.py`, spec/workflow ready, architecture,
  source size, CI suite coverage, scene resources и diff checks:PASS.

В финальных этих логах SCRIPT ERROR/ERROR/ObjectDB leaks нет. Предупреждение
среды `/proc/self/exe` сохраняется. Два новых test functions выше50строк
reviewed как последовательные fixtures; hard limit не превышен.

Оба новых suites зарегистрированы в `.github/runtime_suites.txt`. Первый
также добавлен в существующий rendered loop Compatibility/Forward+. Там
SubViewport pixel assertion проверяет, что overlay действительно белый под
зелёным bar.modulate. Локальный Dummy явно пропускает pixel assertion;
рендерный/художественный результат пока не объявляется проверенным.

Дополнительный вызов `run_menu_tests` завершился с exit0, но без итогового
PASS marker, поэтому не включён в список подтверждённых suites. Его полный
menu/start/restart результат следует оценивать по CI. Новые HUD fixtures
проверили сам Player/HUD lifecycle и паузу отдельно.

## Ручная приёмка

Проверить обе шкалы при burst damage/heal, наборе/сбросе мутации, разных FPS,
масштабе текста, critical control-loss и DNA blink. Снижение мутации сжимает
индикатор по направлению числа, даже когда это полезно игроку. Пауза замораживает
presentation; initial/max sync не воспроизводит старые события. FPS gain не
измерялся. Следующее действие — CI (включая white pixels) и визуальная приёмка
PR для issue223; merge не поручен.
