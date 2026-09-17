---
spec_version: 1
status: DRAFT
current_phase: 0
game_id: {{stable_game_id}}
title: {{working_title}}
owner: {{owner_or_team}}
last_updated: {{YYYY-MM-DD}}
---

# Game Specification — {{working_title}}

Этот файл является единым источником правды о том, **что это за игра, как она работает и что AI должен делать дальше**.

Допустимые статусы:

- `DRAFT` — спецификация заполняется; AI не создаёт игровую функциональность;
- `READY` — обязательные решения приняты; AI работает только в текущей фазе;
- `LOCKED` — базовая концепция зафиксирована; изменение ключевых решений требует ADR.

Если раздел неприменим, укажите `N/A — причина`. Не оставляйте место для догадок.

## 00. AI operating contract

AI обязан:

1. прочитать `AGENTS.md`, этот файл, архитектуру и манифесты затрагиваемых модулей;
2. проверить структуру командой `python tools/validate_game_spec.py`;
3. до разработки проверить готовность командой `python tools/validate_game_spec.py --ready`;
4. при статусе `DRAFT` работать только над уточнением спецификации;
5. начинать с `current_phase` и первой незавершённой задачи текущего этапа;
6. не добавлять механики, контент, платформы или технологии, которых нет в спецификации;
7. обозначать предположения и превращать значимые неизвестные в вопросы;
8. реализовывать минимальный вертикальный результат, а не всю систему сразу;
9. после изменения обновлять прогресс, решения и известные риски;
10. не объявлять этап завершённым без выполнения его критериев выхода.

При противоречии приоритет источников:

1. прямое актуальное указание пользователя;
2. этот файл;
3. утверждённые ADR;
4. `AGENTS.md` и `docs/ARCHITECTURE.md`;
5. манифесты модулей;
6. код и сцены;
7. предположения AI.

## 01. Document status

| Поле | Значение |
|---|---|
| Рабочее название | {{working_title}} |
| Короткое название/ID | {{stable_game_id}} |
| Версия спецификации | {{spec_revision}} |
| Ответственный | {{owner_or_team}} |
| Текущая фаза | {{phase_number_and_name}} |
| Целевая дата следующей проверки | {{review_date}} |
| Статус | {{DRAFT_READY_OR_LOCKED}} |

Причина текущей фазы и статуса:

{{status_reason}}

## 02. Game identity

### Концепция одним предложением

{{who_the_player_is_what_they_do_and_why_it_is_special}}

Формула:

> Игрок — {{player_role}}, который {{primary_activity}}, чтобы {{goal}}, при этом уникальность игры — {{unique_hook}}.

### Жанр

- Основной жанр: {{primary_genre}}
- Дополнительные жанры: {{secondary_genres_or_NA}}
- Режим камеры: {{camera}}
- Темп: {{pace}}
- Средняя длительность сессии: {{session_length}}
- Ожидаемая длительность прохождения: {{total_playtime_or_replay_model}}

### Elevator pitch

{{short_pitch_in_3_to_5_sentences}}

### Игры-ориентиры

| Игра | Что берём как ориентир | Что намеренно не повторяем |
|---|---|---|
| {{reference_1}} | {{useful_quality}} | {{excluded_quality}} |
| {{reference_2}} | {{useful_quality}} | {{excluded_quality}} |

## 03. Audience and product

- Основная аудитория: {{target_players}}
- Возрастной рейтинг: {{target_age_rating}}
- Требуемый игровой опыт: {{beginner_midcore_hardcore}}
- Основная мотивация игрока: {{mastery_story_collection_social_expression_or_other}}
- Модель распространения: {{premium_free_demo_subscription_or_other}}
- Монетизация: {{model_or_NA}}
- Регионы и языки первого релиза: {{regions_and_languages}}
- Почему аудитория выберет эту игру: {{player_value}}

### Продуктовые ограничения

- Бюджет: {{budget_or_constraint}}
- Размер команды: {{team_size_and_roles}}
- Доступное время: {{timeline}}
- Обязательные требования издателя/платформ: {{requirements_or_NA}}

## 04. Experience pillars

Укажите 3–5 принципов. Каждая механика должна поддерживать хотя бы один.

| ID | Принцип | Как ощущается игроком | Как проверить |
|---|---|---|---|
| P1 | {{pillar}} | {{player_feeling}} | {{observable_test}} |
| P2 | {{pillar}} | {{player_feeling}} | {{observable_test}} |
| P3 | {{pillar}} | {{player_feeling}} | {{observable_test}} |

### Игра намеренно не является

- {{explicit_non_goal_1}}
- {{explicit_non_goal_2}}
- {{explicit_non_goal_3}}

## 05. Platforms, input and constraints

| Параметр | Решение |
|---|---|
| Целевые платформы | {{platforms}} |
| Минимальное оборудование | {{minimum_hardware}} |
| Основное управление | {{keyboard_mouse_gamepad_touch}} |
| Дополнительное управление | {{additional_input_or_NA}} |
| Разрешения/соотношения сторон | {{display_targets}} |
| Офлайн-режим | {{offline_behavior}} |
| Требование сети | {{network_requirement_or_NA}} |
| Целевая частота кадров | {{fps_target}} |
| Язык реализации | GDScript |
| Версия движка | Godot 4.x: {{exact_version}} |

### Карта управления

| Действие игрока | Input Map action | Устройства | Контекст |
|---|---|---|---|
| {{action}} | {{snake_case_action}} | {{devices}} | {{context}} |

## 06. Core loop

### Цикл одной минуты

1. Игрок получает: {{input_or_situation}}.
2. Игрок решает: {{decision}}.
3. Игрок действует: {{action}}.
4. Игра отвечает: {{feedback}}.
5. Игрок получает: {{reward_or_consequence}}.
6. Состояние изменяется: {{progression_change}}.
7. Возникает следующий выбор: {{next_hook}}.

### Цикл одной сессии

{{session_loop}}

### Долгосрочный цикл

{{long_term_loop}}

### Условия интересного решения

{{what_makes_choices_non_trivial}}

## 07. Game flow and states

### Точка входа

{{what_happens_from_launch_to_first_control}}

### Состояния игры

| Состояние | Вход | Действия игрока | Выход | Сохраняется |
|---|---|---|---|---|
| {{state_name}} | {{entry_condition}} | {{allowed_actions}} | {{exit_condition}} | {{yes_no}} |

### Победа, поражение и завершение

- Условие локального успеха: {{local_success}}
- Условие локального поражения: {{local_failure}}
- Условие завершения игры/забега: {{game_end}}
- Поведение после завершения: {{post_game}}
- Возможность продолжить: {{continue_rules}}

## 08. Mechanics registry

Каждая механика получает стабильный ID. Неописанная механика не реализуется.

| ID | Механика | Владелец состояния | Вход | Основное правило | Выход | Фаза |
|---|---|---|---|---|---|---|
| M001 | {{mechanic}} | {{module}} | {{input}} | {{rule}} | {{output}} | {{phase}} |

## 09. Mechanic specification

Скопируйте подраздел для каждой механики из реестра.

### {{M_ID}} — {{mechanic_name}}

- Цель для игрока: {{player_purpose}}
- Владеющий модуль: {{module_id}}
- Состояние-владелец: {{authoritative_state}}
- Предусловия: {{preconditions}}
- Входные команды: {{commands}}
- Правила и формулы: {{rules_and_formulas}}
- Результат: {{outputs}}
- Обратная связь: {{visual_audio_haptic_feedback}}
- Ошибки и отказ: {{failure_behavior}}
- Граничные случаи: {{edge_cases}}
- Сохранение: {{persistence}}
- Сеть и авторитет: {{network_authority_or_NA}}
- Производительный бюджет: {{budget}}
- Критерии приёмки:
  - {{acceptance_given_when_then_1}}
  - {{acceptance_given_when_then_2}}

## 10. Player and controllable entities

- Роль игрока: {{player_role}}
- Доступные действия: {{verbs}}
- Основные характеристики: {{stats_or_NA}}
- Ограничения: {{constraints}}
- Получение урона/ошибки: {{damage_or_failure_model}}
- Восстановление: {{recovery}}
- Смерть/поражение: {{death_or_failure}}
- Настройка персонажа: {{customization_or_NA}}

## 11. World and level structure

- Структура мира: {{linear_hub_open_world_runs_levels_other}}
- Единица контента: {{room_level_mission_region_other}}
- Загрузка и переходы: {{loading_model}}
- Генерация: {{authored_procedural_hybrid}}
- Возврат в посещённые области: {{backtracking}}
- Разрушение/изменение мира: {{world_persistence}}
- Координаты и масштаб: {{scale_and_units}}

### Правила уровня

{{level_design_rules}}

## 12. Content model

| Тип контента | Формат Godot | Стабильный ID | Кто создаёт | Оценочный объём |
|---|---|---|---|---|
| {{content_type}} | {{tres_tscn_json_other}} | {{id_format}} | {{role}} | {{count}} |

- Что является данными, а не кодом: {{data_driven_scope}}
- Правила именования ID: {{id_rules}}
- Поведение при отсутствующем контенте: {{missing_content_behavior}}
- Валидация контента: {{validation_rules}}

## 13. Progression and economy

- Единица прогресса: {{progress_unit_or_NA}}
- Постоянный прогресс: {{meta_progression_or_NA}}
- Временный прогресс: {{run_progression_or_NA}}
- Ресурсы и валюты: {{currencies_or_NA}}
- Источники ресурсов: {{sources_or_NA}}
- Расходы ресурсов: {{sinks_or_NA}}
- Разблокировки: {{unlock_rules_or_NA}}
- Защита от тупиков: {{anti_softlock}}
- Сброс прогресса: {{reset_rules_or_NA}}

## 14. Combat or primary conflict

Если боя нет, опишите главный конфликт или укажите `N/A — причина`.

- Модель конфликта: {{combat_or_conflict_model}}
- Цели: {{targets}}
- Урон/результат: {{resolution_formula}}
- Защита: {{defense}}
- Ресурсы действий: {{stamina_mana_cooldown_or_NA}}
- Временные эффекты: {{status_effects_or_NA}}
- Приоритет правил: {{resolution_order}}
- Защита от эксплойтов: {{anti_exploit}}

## 15. NPC and game AI

- Типы агентов: {{agent_types_or_NA}}
- Наблюдаемая информация: {{perception}}
- Скрытая информация: {{hidden_information}}
- Модель решений: {{state_machine_behavior_tree_utility_other}}
- Частота обновления: {{update_frequency}}
- Навигация: {{navigation_model}}
- Поведение при невозможной цели: {{fallback}}
- Детерминизм: {{determinism_requirement}}
- Бюджет на количество агентов: {{agent_budget}}

## 16. UI, UX and accessibility

### Обязательные экраны

| Экран | Назначение | Вход | Выход | Пауза игры |
|---|---|---|---|---|
| {{screen}} | {{purpose}} | {{entry}} | {{exit}} | {{yes_no}} |

- HUD показывает: {{hud_information}}
- Обучение: {{tutorial_model}}
- Ошибки пользователю: {{error_presentation}}
- Переназначение управления: {{remapping}}
- Субтитры: {{subtitle_rules}}
- Масштаб текста: {{text_scaling}}
- Контраст/цветовая слепота: {{visual_accessibility}}
- Снижение движения/вспышек: {{motion_flash_options}}
- Доступность звука: {{audio_accessibility}}

## 17. Visual and audio direction

- Визуальный стиль: {{visual_style}}
- Цвет и освещение: {{color_lighting}}
- Читаемость игрового состояния: {{readability_rules}}
- Ограничения ассетов: {{asset_budgets}}
- Анимационный стиль: {{animation_style}}
- Звуковой стиль: {{audio_style}}
- Музыкальная логика: {{music_logic}}
- Приоритет аудиосигналов: {{audio_priority}}

## 18. Save, loading and settings

- Что сохраняется: {{saved_state}}
- Точки сохранения: {{save_triggers}}
- Количество слотов: {{slots}}
- Автосохранение: {{autosave}}
- Формат и версия: {{format_and_version}}
- Миграции: {{migration_policy}}
- Восстановление повреждений: {{recovery}}
- Облако: {{cloud_or_NA}}
- Настройки отдельно от прогресса: {{settings_storage}}
- Поведение при несовместимой версии: {{incompatibility_behavior}}

## 19. Multiplayer and social

Если игра одиночная, укажите `N/A — однопользовательская игра`.

- Режим: {{single_coop_pvp_async_or_NA}}
- Число игроков: {{player_count_or_NA}}
- Авторитет: {{server_client_host_or_NA}}
- Подключение/лобби: {{connection_flow_or_NA}}
- Потеря соединения: {{disconnect_behavior_or_NA}}
- Повторное подключение: {{reconnect_or_NA}}
- Реплицируемые состояния: {{replicated_state_or_NA}}
- Предсказание/интерполяция: {{prediction_or_NA}}
- Версия протокола: {{protocol_version_or_NA}}
- Античит: {{anti_cheat_or_NA}}

## 20. Technical budgets

| Бюджет | Цель | Устройство/сценарий | Способ измерения |
|---|---|---|---|
| FPS | {{fps}} | {{hardware}} | {{profiler_test}} |
| Frame CPU | {{milliseconds}} | {{scenario}} | {{measurement}} |
| Frame GPU | {{milliseconds}} | {{scenario}} | {{measurement}} |
| RAM | {{memory}} | {{scenario}} | {{measurement}} |
| VRAM | {{memory}} | {{scenario}} | {{measurement}} |
| Загрузка | {{seconds}} | {{transition}} | {{measurement}} |
| Размер сборки | {{size}} | {{platform}} | {{measurement}} |
| Активные сущности | {{count}} | {{worst_case}} | {{measurement}} |

## 21. Scope

### MVP — обязательно

- {{must_have_1}}
- {{must_have_2}}
- {{must_have_3}}

### После MVP — желательно

- {{should_have_1}}
- {{should_have_2}}

### Не входит в проект

- {{out_of_scope_1}}
- {{out_of_scope_2}}

### Правило изменения масштаба

{{who_can_change_scope_and_what_must_be_removed_or_replanned}}

## 22. Quality and acceptance

### Общая Definition of Done

Функция готова, только если:

- соответствует механике и принципам опыта;
- имеет одного владельца состояния;
- работает через объявленные публичные контракты;
- покрыта необходимыми тестами;
- корректно сохраняется/реплицируется, если применимо;
- укладывается в бюджеты;
- имеет понятную обратную связь и обработку ошибок;
- документация и манифесты обновлены;
- архитектурная и продуктовая проверки проходят.

### Критические пользовательские сценарии

| ID | Given | When | Then |
|---|---|---|---|
| A001 | {{initial_state}} | {{action}} | {{expected_result}} |

### Недопустимые дефекты релиза

- {{release_blocker_1}}
- {{release_blocker_2}}

## 23. Risks, legal and dependencies

| Риск | Вероятность | Влияние | Ранний сигнал | Снижение риска | Владелец |
|---|---|---|---|---|---|
| {{risk}} | {{low_medium_high}} | {{impact}} | {{signal}} | {{mitigation}} | {{owner}} |

- Сторонние плагины/SDK: {{dependencies_or_NA}}
- Лицензии ассетов: {{license_policy}}
- Персональные данные: {{privacy_or_NA}}
- Возрастные/платформенные требования: {{compliance}}
- План замены критических зависимостей: {{fallback}}

## 24. Sequential development plan

AI выполняет только текущую фазу. Следующая начинается после выполнения критериев выхода.

### Phase 0 — Discovery and specification

Цель: устранить противоречия и неизвестные, влияющие на фундамент игры.

Обязательный результат:

- концепция, аудитория и платформы определены;
- основной цикл описан;
- MVP и исключения зафиксированы;
- ключевые механики имеют критерии приёмки;
- отсутствуют `[BLOCKER]`;
- `python tools/validate_game_spec.py --ready` проходит.

AI начинает именно здесь, если спецификация имеет статус `DRAFT`.

### Phase 1 — Logic prototype

Цель: проверить главное игровое решение без дорогого контента.

Порядок:

1. реализовать минимальную доменную модель главной механики;
2. проверить правила автоматическими тестами;
3. использовать временные данные и визуал;
4. измерить, возникает ли требуемое интересное решение;
5. удалить или изменить неработающие правила до расширения проекта.

Критерий выхода: главный цикл логически работает и подтверждён тестом/наблюдением.

### Phase 2 — Playable prototype

Цель: дать игроку пройти один полный короткий цикл.

Порядок:

1. ввод;
2. минимальная сцена;
3. главная механика;
4. обратная связь;
5. локальный успех/поражение;
6. перезапуск цикла.

Критерий выхода: новый пользователь может пройти цикл без помощи разработчика.

### Phase 3 — Vertical slice

Цель: один короткий фрагмент, близкий к целевому качеству.

Он включает:

- репрезентативный контент;
- UI и обучение;
- звук и визуальную обратную связь;
- сохранение, если оно является частью цикла;
- целевую производительность;
- сбор наблюдений и ошибок.

Критерий выхода: подтверждены игровой опыт, качество и реалистичная стоимость производства.

### Phase 4 — Production foundation

Цель: подготовить безопасное масштабирование.

Порядок:

1. окончательно определить границы модулей;
2. стабилизировать форматы данных;
3. создать контентные валидаторы и инструменты;
4. настроить сборки и тесты;
5. версионировать сохранения и сеть;
6. утвердить бюджеты.

Критерий выхода: новый контент добавляется без изменения базовой архитектуры.

### Phase 5 — Content production

Цель: производить запланированный контент повторяемым способом.

Правила:

- сначала репрезентативный набор, затем массовое производство;
- каждая единица проходит автоматическую проверку;
- новые механики не добавляются без изменения scope;
- регулярно собираются играбельные сборки.

Критерий выхода: весь MVP-контент присутствует от начала до конца.

### Phase 6 — Alpha

Цель: игра полностью проходима, функциональность MVP закрыта.

Работы:

- устранение блокирующих ошибок;
- баланс основных систем;
- миграции сохранений;
- проверка всех критических сценариев;
- профилирование худших случаев.

Критерий выхода: нет известных блокеров полного прохождения.

### Phase 7 — Beta

Цель: стабилизация без расширения функций.

Работы:

- исправления;
- совместимость платформ;
- доступность и локализация;
- нагрузочные и длительные тесты;
- подготовка магазина, поддержки и отката.

Критерий выхода: выполнены критерии релиза и план восстановления проверен.

### Phase 8 — Release and live support

Цель: безопасно выпустить и поддерживать игру.

Порядок:

1. релиз-кандидат;
2. резервные копии и откат;
3. поэтапный выпуск, если возможно;
4. мониторинг сбоев;
5. классификация обратной связи;
6. исправления без нарушения сохранений и протоколов;
7. ретроспектива и обновление плана.

## 25. Current milestone and task queue

### Текущая цель

{{single_measurable_milestone_goal}}

### Критерии входа

- {{entry_criterion_1}}
- {{entry_criterion_2}}

### Последовательность задач

AI выбирает первую незавершённую задачу, зависимости которой выполнены.

- [ ] T001 — {{small_verifiable_task}}
- [ ] T002 — {{small_verifiable_task}}
- [ ] T003 — {{small_verifiable_task}}

### Критерии выхода

- {{exit_criterion_1}}
- {{exit_criterion_2}}

### Запрещено в текущем этапе

- {{current_phase_non_goal_1}}
- {{current_phase_non_goal_2}}

## 26. Decisions and open questions

### Утверждённые решения

| ID | Решение | Причина | Дата | Владелец |
|---|---|---|---|---|
| D001 | {{decision}} | {{reason}} | {{date}} | {{owner}} |

### Блокирующие вопросы

Удалите маркер `[BLOCKER]` после принятия решения.

- [BLOCKER] {{question_that_changes_architecture_scope_or_player_experience}}

### Неблокирующие вопросы

- {{question_that_can_wait}}

## 27. Change log

| Версия | Дата | Изменение | Автор |
|---|---|---|---|
| {{version}} | {{date}} | {{change}} | {{author}} |
