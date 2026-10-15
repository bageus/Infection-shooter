# A03 — стена за мебелью защищает от взрыва

Дата: 2026-10-15. T004, фаза 1/P1_LOGIC. База: main `fcfc5837` (PR204 уже слит). Ветка `codex/blast-wall-shelter`, PR непосредственно в main.

## Исправление

`features.combat/public/grenade_explosion.gd:is_sheltered` прекращал поиск после шести неподходящих тел и возвращал false, даже если следующая стена ещё не проверена. Вместо этого один ray query переиспользуется с пополняемым списком исключённых RID до свободного луча либо структурной стены. Каждый пропущенный collider исключается целиком, поэтому поиск конечен по числу разных тел на отрезке; число 6 не заменено другим произвольным пределом.

Прежние правила сохранены: только StaticBody3D без take_projectile_hit и вне собственной иерархии цели считается укрытием; RigidBody3D (включая frozen), разрушаемые объекты и собственные hitboxes пропускаются. Mount clearance 0.35 м позволяет настенному предмету получить урон у его стены. Подпись метода и dispatch взрыва прежние. Никаких новых слоёв коллизии, публичных API/DTO/сцен/ресурсов, зависимостей или владельцев состояния не вводилось. Архитектурных исключений нет.

Новый тест размещён в bootstrap/app: только этот существующий composition-модуль уже зависит от public combat и public office_floor, необходимых для настоящего дверного проёма. Production-изменение остаётся целиком в features.combat. Файлы grenade_explosion и нового теста ниже 300/500 строк.

## Доказательство и проверки

Godot 4.7.2, Linux headless. Новый `game/bootstrap/app/tests/run_blast_shelter_tests.gd`: **прежний production — 21 ошибка/exit1, исправленный — 0 ошибок/exit0**. Все запросы выполнялись в настоящем World3D, raycasts не подменялись.

- 0/6/10/64 пропущенных тел, луч с обеих сторон стены; те же цепочки без стены остаются открытыми.
- Отдельно RigidBody3D с чередованием frozen/dynamic, StaticBody3D с take_projectile_hit и собственные static hitboxes цели.
- Прежнее исключение разрушаемой стены и mount clearance с обеих сторон.
- Реальный public/structural/wall_door_3_without.tscn с mesh collisions: луч проходит через проём за десятью предметами, но тот же дверной косяк закрывает цель при смещении x=0.95; обе стороны.
- Реальный explode(): за стеной и десятью предметами урона нет, открытая цель от того же взрыва получает урон.

Все **8 suites PASS**, exit0 без ERROR:

| Suite | Каталог |
|---|---|
| run_blast_shelter_tests | game/bootstrap/app/tests |
| run_grenade_vfx_tests | game/features/combat/tests |
| run_balance_tests | game/presentation/office_floor/tests |
| run_blast_feedback_tests | game/bootstrap/app/tests |
| run_blast_break_tests | game/presentation/office_floor/tests |
| run_destruction_wiring_tests | game/bootstrap/app/tests |
| run_mutagen_cloud_tests | game/features/infection_source/tests |
| run_glass_crack_tests | game/presentation/office_floor/tests |

Новая регрессия включена в mission_runtime CI. В blast_feedback остаётся известное предупреждение60 ObjectDB при выходе (A05 исходного аудита); остальные семь логов без таких предупреждений. Это не исправление A05.

`validate_game_spec.py --ready`, `validate_workflow_state.py --ready`, `validate_project.py`, `validate_scene_resources.py` (393 refs), `check_resource_paths.py`, Godot editor import и diff-check PASS. Source-size:119 прежних предупреждений, новых нет, жёсткие пределы соблюдены.

## Производительность и соседние проверки

Поиск синхронный: для N неподходящих тел требуется до N+1 ray query. Это устраняет неверное решение об отсутствии стены; фиксированной верхней границы6 теперь нет. Сценарий64 тел проверяет завершение и правильный результат, но не доказывает FPS при массовых взрывах. Стоимость длинных перекрывающихся цепочек, GPU/Windows/Web не профилировались. При дальнейшей оптимизации нужен явный структурный collision layer/другой точный фильтр с сохранением нынешних правил, а не новое число попыток.

Отдельно просмотрены mutagen_cloud._support_height (лимит16) и cloud_wall_field.barrier_distance (лимит8): это иные запросы с другими критериями. Существующий mutagen_cloud suite PASS; плотные цепочки для них в этом инкременте не проверены, поэтому исправление гранаты не объявляется доказательством исправности или поломки облаков/навыков.

## Передача

Выяснено: PR205 был слит в codex/retained-ragdoll-budget после PR204, но mainfcfc5837 A02 не содержит. Чтобы доставить тот же неизменённый проверенный head032d52ae в main, создан отдельный [PR206](https://github.com/bageus/Infection-shooter/pull/206). Слитый PR205 не переоткрывался, чужая история не переписывалась. A03 не включает A02; обе ветки направлены в main.

Следующее действие — проверить CI A03 и PR206. Merge не поручен. После A03 следующим пунктом исходного аудита остаётся A04 (невалидный шаблон стола). Откат A03 — revert его кода/тестов/CI; миграции данных нет.
