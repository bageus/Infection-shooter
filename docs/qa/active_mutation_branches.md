# Активные мутации — issue245 / PR246

Ветка `codex/rework-active-mutations`. Утверждённые числа и миграция — ADR0056.

## Результат

Четыре ветки, в каждой уровни1/2 и один из двух вариантов3. Цены и пороги
прежние; Might заменяет Toxic Mutation. Два назначения Q/E; первые изученные
автоматически занимают свободные слоты, улучшения заменяют ID своей ветки,
ручной выбор сохраняется. Неэкипированный навык нельзя кастовать. Camera Z/X.
HUD и меню показывают два слота; пустые недоступны без навыков. Финальные
выборы и кнопки закрепления не перекрываются. Обычные улучшения сохраняют
семейный glyph, альтернативный финал имеет отдельный. Passive/active Claws
намеренно используют общий знак когтей. Описания/параметры локализованы RU/EN.

Независимые базовые cooldown5/6/8с начинаются после завершения эффекта;
продление Berserk отодвигает recovery. Passive ускорения прежние. Upgrading
не обнуляет уже идущий таймер. Locked dormant сохраняет слот; возвращение
доступности запускает полный cooldown, затем taking_skill. Forgotten очищает
назначение. Dormancy завершает активную ауру/пользу Berserk без скрытого
остатка effect timer при последующей реактивации.

Blood Burst1 без push, radius2.4м; последующие уровни отбрасывают за край
радиуса. Discharge: fixed10/20/30 damage ×6/8/10 hits, first8м/links3м,
повторные цели разрешены; level3 stun1.2с. Storm следует за игроком6с,
radius4м/40DPS/stun2с. Power Strike: трапеция3м, width1→3м; damage30/40/50,
push4/5/5м, final stun1.5с. Dash0.4с/6м, damage50 once/victim, push2м
в стороны; стены останавливают motion, но не damage window. Active Claws
50/60/70DPS, duration2.5/3.5/4.5с, radius3/4/5м. Passive Claws один удар25
каждые3с/radius1.5м. Только смерть от infection DOT10DPS/3с вызывает
однократный explosion40/radius4м, без повторного заражения; bullet death нет.

## Проверки

- Godot4.7.2; полный manifest165 suites выполнен. Первоначально три падения:
  старое требование уникального glyph на каждый узел; чтение отсутствующих
  controls keys в walk_tuning/adaptive_audio. Исправлены, затем все17 связанных
  suites прошли на итоговом коде. Assertions пассивов/геометрии сохранены;
  glyph assertion теперь отличает уровни одного навыка от независимых навыков.
- В полном параллельном запуске divider suite не оставил completion marker;
  отдельный запуск PASS. Body penetration/roll i-frames/legacy pickups также
  повторены с явными финальными success markers. Все165 наборов покрыты
  успешным запуском с учётом этих повторов; SCRIPT ERROR/ERROR/ObjectDB/RID
  сообщений в итоговых выбранных результатах нет. Это не утверждение, что
  первый общий запуск завершился зелёным: в нём было3 failures.
- Пять новых suites: active_skill_state, active_mutation_effects,
  mutation_status, mutation_dash_motion, active_loadout_ui. Есть настоящие
  collision body/wall, реальные player/runtime и DOT смерти; mocks отдельно
  проверяют точные damage budgets и форму зон. Крупный delta не удлиняет DOT
  и ауры; повторные удары/stun refresh не складывают длительности.
- Default, legacy, custom и empty controls config проверены. Автоматическая
  миграция не забирает Z/X у пользовательских команд. Отсутствующая секция
  не вызывает ошибок ConfigFile. Skill_3/4 удаляются при apply/save.
- Source-size PASS490, root infected600; spec/workflow READY PASS;
  CI registration173 discovered =165 runtime +8 explicit native; scene refs
  PASS395, diff check PASS. Editor import без script errors. Отдельный чистый
  audio-import probe подтверждает явный res://default_bus_layout.tres.
- CI предыдущей ревизии подтвердил clean import после UID fix; native display
  обнаружил empty-config ошибки, исправленные в финальной ревизии. Результаты
  CI финального head публикуются в PR; каждый step оценивается отдельно.

## Исправления падений CI

Пустой/legacy ConfigFile теперь имеет безопасный fallback `{}`; отдельный
regression проверяет отсутствие ошибок Godot. Ожидания иконок учитывают
общий glyph уровней одной способности и отдельные альтернативы.

В авторской карте удалены92 redundant script overrides, у каждого проверено
совпадение со скриптом публичной сцены instance. Трансформы, параметры поз,
конфиги и дочерние узлы сохранены. Private bake canonicalizer удаляет только
совпадающие inherited script bindings и неиспользуемые их declarations;
другие script overrides сохраняются. Повторный bake для part/corpse/pickup
проверяет отсутствие private references. Policy/allowlist не ослаблены.
`validate_project.py` теперь PASS, включая architecture.

Native occlusion captures имели правильные cyan/red/amber силуэты, но тест
смешивал logical camera coordinates и физические пиксели окна при
canvas_items stretch. Sampler учитывает отношение image/visible_rect;
пороги цвета, геометрия и lifecycle assertions прежние. Повторный CI
обоих renderers проверяет исправление.

Headless CI7035e48:164 suites без failures, planning_mode exit124/121с.
Текущий полный локальный runner: All165 suites passed,0 SCRIPT ERROR/ERROR;
planning_mode118с, отдельный параллельный стресс с4 worker threads115с.
Только этому полному save/restore тесту дан execution budget180с;
остальные suites120с. Все assertions, полная карта и physics ticks сохранены.
Журналы runtime публикуются отдельным artifact сразу после headless step,
до долгих rendered captures; имя включает run_attempt.

## Ручная приёмка

На Windows/Web/Iris Xe проверить RU/EN дерево и две ячейки, Q/E и Z/X,
auto-equip/upgrade/manual reassignment, невозможность двух finals. Применить
навык с длительностью: сначала синяя длительность, затем cooldown5/6/8с,
затем один taking_skill. Проверить антидот/locked dormant и реактивацию,
Claws versus passive pulse, одиночную/парную молнию, поле на ходу,
метры push/препятствия/dash и DOT-only explosion. Визуальная плавность,
прослушивание и frame-time на оборудовании владельца не измерены.
Merge не поручен; T004 остаётся IN_PROGRESS.
