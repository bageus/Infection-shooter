# template_game — Godot architecture template

Архитектурный шаблон крупной игры для **Godot 4.x + GDScript**, рассчитанный на совместную работу разработчиков и AI-агентов.

## Архитектурная модель

Проект строится как модульный монолит:

```text
bootstrap -> presentation -> features -> core
        \-> infrastructure -----> core
```

Каждый модуль имеет `module.json`, одного владельца изменяемого состояния, небольшой публичный API и явный список зависимостей.

## Начало работы

1. Откройте проект в Godot 4.x.
2. Попросите AI прочитать [AI_START_HERE.md](AI_START_HERE.md) и репозиторий.
3. AI определит режим работы и начнёт интервью из [DISCOVERY_QUESTIONS.md](docs/DISCOVERY_QUESTIONS.md).
4. Заполните [GAME_SPEC.md](GAME_SPEC.md) — описание игры и последовательный план.
5. AI-агент обязан прочитать [AGENTS.md](AGENTS.md), затем `GAME_SPEC.md`.
6. Архитектура Godot описана в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
7. Новый модуль создаётся внутри `game/<layer>/<module>/` из [templates/module.json](templates/module.json).
8. Межмодульные контракты помещаются только в каталог `public/`.
9. Перед завершением работы выполните:

```bash
python tools/validate_game_spec.py
python tools/validate_workflow_state.py
python tools/validate_game_spec.py --ready
python tools/validate_workflow_state.py --ready
python tools/validate_architecture.py
godot --headless --path . --editor --quit
```

Вторая команда требует установленный Godot и проверяет импорт проекта.

## Автоматически проверяется

- направление зависимостей между слоями;
- наличие объявленных зависимостей;
- отсутствие циклов;
- обращения через `res://` в GDScript, сценах и ресурсах;
- доступ к другому модулю только через его `public/`;
- допустимость Autoload;
- запрещённый доступ к `/root/` из игровой логики;
- наличие обязательных архитектурных файлов.

Текстовые инструкции сами по себе не гарантируют соблюдение архитектуры. Поэтому правила продублированы в [architecture/policy.json](architecture/policy.json), проверяются скриптом и запускаются в GitHub Actions.

## Спецификация игры

`GAME_SPEC.md` отвечает на три вопроса:

1. Что это за игра и какой опыт она создаёт?
2. Как работают её механики, данные, состояния и ограничения?
3. Какова текущая фаза и какая задача должна выполняться следующей?

Пока файл имеет статус `DRAFT`, AI помогает заполнять спецификацию. После заполнения установите `status: READY`; команда `python tools/validate_game_spec.py --ready` должна пройти без ошибок.

## Непрерывность работы AI

- `PROJECT_STATE.md` хранит текущую фазу, сборку, риски и следующий результат.
- `ACTIVE_TASK.md` хранит единственную активную задачу и точное место продолжения.
- `BACKLOG.md` хранит последующие задачи и идеи.
- `docs/WORKING_AGREEMENT.md` фиксирует полномочия и предпочтения владельца.
- `docs/GLOSSARY.md` предотвращает расхождение терминов.

В конце каждой сессии AI обязан оставить одно точное следующее действие.
