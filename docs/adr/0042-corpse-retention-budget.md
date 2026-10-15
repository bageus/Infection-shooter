# ADR-0042: Удержание тел врагов с бюджетом

- Status: accepted
- Date: 2026-10-13
- Owners: владелец проекта; features.infected
- Related modules: features.infected, bootstrap.app.menu

## Context
По ADR-0041 тело врага исчезает примерно через 5 с после смерти: задержка `death_linger_seconds`, опускание под пол и скрытие. Владелец попросил держать тела на уровне как можно дольше без лишней нагрузки: не меньше 60 тел, удаление только при переполнении бюджета, переключатель в настройках. Нагрузка ограничена существующим лимитом 8 одновременных рэгдоллов (`death_ragdoll.gd`); спящие кости после задержки стоят мало, но не нулевую цену.

Ограничение, найденное при проверке: тело также удалялось целиком, когда заканчивалось облако мутагена смерти (`mutagen_cloud.gd`, до 14 с). `infected_capsule.gd` вызывал `queue_free()` по сигналу `depleted`, поэтому удержанное тело пропадало независимо от бюджета.

Для подсчёта удержанных тел нужна точка, общая для всех врагов. Существующий `death_ragdoll._active` уже хранит такое состояние как `static var`; новой практики здесь нет, но это глобальное изменяемое состояние, которое правила репозитория запрещают в общем виде.

## Decision
1. Новый файл `game/features/infected/public/corpse_budget.gd` (`class`-less `RefCounted`) хранит:
   - `static var keep` — флаг из настроек (`keep_corpses`, по умолчанию включён в меню, `false` до первого применения настроек);
   - `static var _corpses` — список удержанных тел с callable скрытия;
   - `MAX_CORPSES = 60`; при переполнении скрывается самое старое тело и останавливается его физика.
2. Тело удерживается, когда `keep` включён: после задержки рэгдолл освобождает слот `MAX_ACTIVE`, клип-путь сохраняет тело в конечной позе. Скрытие теперь делает только бюджет.
3. Окончание облака смерти не удаляет удержанное видимое тело (`cloud_gone`). Узел освобождается, когда тело и облако оба завершились (`hidden`).
4. Файл лежит в `public/` и объявлен в `public_api` модуля `features.infected`, потому что меню (`bootstrap.app`) задаёт флаг. Зависимость `bootstrap.app → features.infected` уже есть в `module.json`.

## Alternatives considered

### A. Autoload или сервис-локатор бюджета
Отклонено: правило 9 `AGENTS.md` запрещает Autoload и service locator для состояния геймплея.

### B. Бюджет в корне миссии, переданный каждому врагу
Чище по владению состоянием: миссия владеет списком тел и передаёт его при спавне. Отложено: требует изменения спавнера и всех путей создания врагов, а для проверки производительности сейчас достаточно статического реестра. Можно перейти, если тесты покажут проблему.

### C. Запекание осевших тел в статичный меш
Самый дешёвый по кадру вариант. Отложено до результатов измерений: владелец сказал, что частичное запекание подключит, если стабильность сильно «поплывёт».

## Consequences

### Positive
- Тела остаются на уровне до лимита 60 вместо 5 секунд.
- Переключатель `keep_corpses` возвращает прежнее поведение.

### Negative
- Глобальное изменяемое состояние `CorpseBudget` сохраняется; нужен отдельный переход на вариант B, если правила потребуют.
- Удержанные тела держат спящие кости в физическом мире; стоимость 60 тел не измерена.
- `infected_capsule.gd` на границе лимита 600 строк.

### Risks and mitigations
- Риск: статический список держит ссылки на тела между миссиями.
  Смягчение: `_prune()` убирает освобождённые узлы при каждом добавлении и подсчёте.
- Риск: тело не освободится, если облако закончилось до скрытия.
  Смягчение: `hidden` освобождает узел, если метка `cloud_gone` уже стоит.

## Migration plan
1. Файлы `corpse_budget.gd`, изменения `death_ragdoll.gd`, `infected_capsule.gd`, меню — одним коммитом (ветка `claude/project-thread-leju9v`).
2. Ключ `keep_corpses` добавляется в `interface_settings.cfg` с значением по умолчанию через существующий механизм слияния с `DEFAULTS`.

## Rollback plan
Выставить `keep_corpses` в `false` (поведение ADR-0041). Полный откат — revert коммита; ключ в cfg безвреден.

## Validation
- `run_corpse_budget_tests.gd`: лимит, вытеснение старейшего, освобождение удалённых узлов, сохранение тела при окончании облака.
- `run_ragdoll_death_tests.gd`: тело видно после задержки при включённом флаге; старый тест «тело скрывается» проходит при выключенном.
- `validate_project.py`: архитектура и размер файлов.
- Производительность (60 тел) — не измерена; проверяется владельцем.

## Approval
Одобрено владельцем проекта в треде 13.10.2026 («ADR оформляй»); выбор варианта 1+2 с переключателем подтверждён 13.10.2026.


## Implementation correction — 2026-10-15 (audit A01)

The owner requested the first audit fix. Releasing a ragdoll slot while leaving its simulator enabled did not enforce ADR-0041's eight-simulator budget. The retained pose is now transferred from physical-bone transforms (including body offsets and authored scale) into Skeleton3D bone poses, and the simulator is stopped before its slot is released. The visible-body budget remains sixty. Timed sink-and-hide also releases the slot when simulation stops, rather than waiting for cloud/owner teardown. Tree exit remains an idempotent fallback. The existing registry, ownership, public contracts and dependencies are unchanged; no architecture exception is introduced.

The earlier descriptions of retained sleeping physical bones and their unmeasured cost describe the original implementation. They no longer apply to retained ragdolls after this correction. Remaining skeleton/node costs and GPU performance with sixty bodies still require profiling. Validation and regression evidence: `docs/qa/ragdoll_budget.md`.
