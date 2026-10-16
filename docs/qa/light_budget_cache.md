# O03 — кэш решений бюджетов света

Инкремент T004, владельцы прежние: bootstrap.app выбирает лампы, office_floor
выбирает screen glow и сохраняет собственную анимацию/мерцание. Production scope:
`planning_lighting.gd` и private internals `public/display_wall.gd`. Сцены, ассеты,
ресурсы, public API, DTO, зависимости, Autoload и policy exceptions не менялись.
Оба production файла ниже300 строк; rank/frustum/budget rules не переписаны.

## Что изменено

Сохранились проверки каждые0,15с/0,2с. Они проверяют входные данные, а не заново
строят ranked/settings/candidates, frustum и light writes при стабильной сцене.
Это input polling с кэшем результата, не обещание отсутствия всех обходов.

| Контроллер | Входы, после изменения которых обновляется решение |
|---|---|
| Лампы | Camera identity/global transform/camera transform/projection; состав и порядок budget_lights; global position, radius и fixture cost; local permission, shadow permission |
| Экраны | Та же камера; состав/порядок displays; global transform, visibility in tree, powered; состав screen lights и их global position; shadow permission; register/unregister/update_animation |

Power/flicker лампы применяются её прежними setters/clock независимо от budget.
Выключенная лампа по-прежнему занимает слот по старым правилам: изменение этой
семантики не входит в оптимизацию. Glow configuration повторно применяет бюджет
даже при прежнем powered, поскольку configure может сбросить light.visible.

При движении камеры используется прежний полный расчёт. Снимок входных данных
заполняется после остановки, затем переиспользуется. После изменения shadow owners
остаётся ещё один refresh для стабилизации прежнего keep bias0,49 и lit set.
Сохранены MAX_LIGHTS28/MAX_SHADOW6, VIEW_MARGIN2м, screen glow16/shadow4,
distances24/16/8м. Политика pause/planner, clock/atlas/layout displays прежние.
Прямой explicit refresh остаётся принудительным.

## Проверки поведения

`run_light_budget_cache_tests.gd` добавлен в mission_runtime CI. Он проверяет:

- отсутствие повторных lamp writes и display view/budget pass после стабилизации;
- продолжающуюся анимацию и реальное blackout/recovery авторской лампы;
- radius/fixture cost, изменение положения, позднее добавление/удаление группы;
- local lighting/shadow settings, powered/configure и повторную конфигурацию;
- дальний/вернувшийся display, скрытого родителя, отдельное смещение glow;
- добавление/удаление screen light и уход зарегистрированного display;
- ortho size, near/far, h/v offset, perspective/FOV, camera parent/rotation,
  viewport aspect, отсутствие камеры, смену камеры с теми же настройками.

Полный trace содержит36 последовательных изменений. На исходных production
скриптах и candidate битовые решения lit/visible/shadow совпадают на всех36
шагах. В исходнике новая регрессия падает по8 idle assertions, в candidate0.
Это сравнение поведения, не копия формулы ранжирования в assertions.

Релевантные suites: light_budget_cache, lamp_lighting, lighting, global_lighting,
planner_light_view, display_planner, display, world_bindings, planning_mode,
named_map_loading. Проверяется настоящая композиция и авторские JSON routes.

В существующем lamp_lighting fixture найдены2 orphan WorldEnvironment. Verbose
log подтверждает тип обоих узлов. Теперь они дети тестового controller и удаляются
вместе с ним; production teardown не менялся, предупреждения не подавлены.

## Измерение CPU

`profile_light_budgets.gd` — ручной микростенд:362 лёгких lamp nodes с costs1/2/4,
180 synthetic displays с настоящими SpotLight3D, camera и production controllers.
Это число ламп соответствует исходному аудиту;180 screens — размер стенда, не
заявление о составе shipped map. Пять прогревочных callbacks исключены; далее200
вызовов каждого контроллера в покое и200 с движением camera0,02м/вызов. Каждый
вызов передаёт delta0,2с, так что проходит прежний timer threshold.

Команда (для каждого процесса отдельный пустой XDG_DATA_HOME):

```bash
godot --headless --path . --script game/bootstrap/app/tests/profile_light_budgets.gd
```

Исходный production и candidate сравниваются на одном стенде. Переключение двух
файлов выполнялось только между завершившимися процессами и восстанавливалось
в finally. Runtime suites/импорт не выполнялись параллельно замерам.
`light_budget_cache_metrics.json` содержит сырые mean/p95/max и allocator samples.
Godot4.7.2, DisplayServer=headless/Dummy. configured_renderer=gl_compatibility —
настройка проекта, не доказательство настоящего GL рендера.

## Фактический результат

Три последовательные interleaved пары original/cached. Значения ниже — медиана
mean по3 процессам, время одного callback. Сырые p95/max сохранены в JSON.

| CPU callback | Исходник | Кэш | Изменение в покое |
|---|---:|---:|---:|
| Лампы, покой | 1460,465 мкс | 238,780 мкс | −83,7% |
| Экраны, покой | 464,470 мкс | 186,905 мкс | −59,8% |
| Лампы, движение | 1420,395 мкс | 1354,825 мкс | та же полная логика |
| Экраны, движение | 477,155 мкс | 457,670 мкс | та же полная логика |

При движении результаты того же порядка, без статистической гарантии: original lamps1417,595–1509,075,
cached1316,310–1388,225мкс; original screens451,450–505,400,
cached446,325–470,640мкс. Различие по движению не выдаётся за улучшение FPS;
CPU scheduler создаёт outliers (max до8,8мс в исходнике и5,3мс в candidate).

Allocator after warmup/end: original62335017/62349733 bytes,
candidate62512819/62527535 bytes. Разница177802 bytes (173,6КиБ) включает
дополнительный код/состояние/кэш; это не пик памяти карты и не VRAM.
После прогрева steady allocator в обоих вариантах вырос на14716 bytes из-за
массивов samples стенда, не из-за неограниченного накопления light inputs.
Снижение аллокаций inferred из пропуска ranked/settings построения; полный
профиль числа allocator operations не снимался.

## Итоговые gates

На main7cb8560 (включает O02/PR225):10 целевых suites PASS, без SCRIPT ERROR,
ERROR и ObjectDB/RID leak warnings. После устранения повторного view-state query
повторены light_budget_cache/lamp_lighting/display/planner_light_view —4 PASS
(0/6/2/32с);36-step replay заново совпадает с исходником. Editor import exit0
без ошибок; project/spec/workflow/architecture/scene/resources/diff PASS,
source-size450 файлов/122 advisory warnings, лимиты не менялись.

## Ограничения и native приёмка

Замеры описывают CPU конкретных callbacks, не время игрового кадра и не FPS.
Physics/draw calls/GPU/VRAM/пик полной карты в этом стенде не измеряются. Кэш
занимает дополнительную память. Наблюдение позиций/настроек остаётся O(N) на
прежнем timer, latency обнаружения не увеличена. Это локальная оптимизация,
не утверждение о главном bottleneck движения по полной локации.

Native render capture не выполнен: Xvfb отсутствует. Визуальная приёмка на
Compatibility/Forward+, Windows/Web и отсутствие видимых вспышек теней остаются
непроверенными. Код света/цвета/материалов и shader не менялся. Native маршрут:

1. На той же карте/позиции включить local lights и shadows, затем неподвижную
   камеру: записать кадр/видео и CPU baseline/candidate.
2. Медленно pan/zoom/rotate камеру через край frustum и границы shadow budget;
   проверить прежний запас видимости и отсутствие скачков shadow ownership.
3. В planner двигать/масштабировать fixtures, менять shape1/2/4 и undo/load;
   проверить тот же budget и независимое мерцание.
4. Выключать/ломать/скрывать/возвращать экраны, перемещать ТВ и проверять
   объединение стены, анимацию и возвращение свечения.
