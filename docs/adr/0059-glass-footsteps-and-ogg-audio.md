# ADR-0059: Шаги по стеклу и единый OGG runtime

- Status: accepted
- Date: 2026-10-18
- Owners: features.player, presentation.office_floor, core.audio; bootstrap — композиция

## Context

Владелец поручил случайные четыре the_crunch_of_glass__1–4 при ходьбе по
физическим осколкам и стеклянной россыпи пола, The_heavy_character_1 при
перекате и удаление WAV после проверенной конвертации в OGG.

## Decision

Office-floor предоставляет read-only footstep_surface_v1.has_glass_at(world_position).
Bootstrap внедряет Callable в player.configure_footstep_surface; player не получает
зависимость на presentation. Audio проверяет поверхность только на фактическом
контакте анимации при is_on_floor; позиция вычисляется у подошвы CapsuleShape3D,
не у центра тела. При перекате walking contacts подавляются. Владельцы и граф
зависимостей прежние, исключений нет. Два additive контракта необходимы для
одной связи provider→composition→consumer; отдельная система поверхностей не нужна.

Private glass_footstep_surface читает существующие color/R8 roughness изображения:
до49 точек внутри радиуса18см, проверяет прозрачность, границы, лестничные отверстия,
высоту и transform. Только glass имеет roughness<0.2. Память секций/LRU/clear
прежние, новых текстур/узлов/тел/кадровых обработчиков нет. Физическое стекло
помечается только в настоящих glass spawn paths; один ограниченный shape query
layer4/max32 у подошвы не включает исчезнувшие collision-layer0 фрагменты.
Проверка использует текущую однопоточную конфигурацию физики проекта.

Core.audio регистрирует step_glass (4 варианта) с прежней случайной выборкой,
небольшим pitch jitter и voice limits. player_roll вызывается один раз при
принятом перекате. В main892c25a исходник отсутствовал; в main6fa115b он уже
добавлен. Настоящая запись преобразована в player_roll/player_roll_1.ogg и
подключена как обычное событие каталога. Temporary optional entry удалён.

Все восемь найденных WAV (включая добавленные перекат и два звука жалюзи) преобразуются в mono48kHz Vorbis quality5. Хеши,
длительность и источник сохранены в receipt; ffmpeg декодирует результат до
удаления источника и .wav.import. taking_skill сохраняет своё фактическое
звучание через taking_skill.ogg, прежний unused cooldown OGG не перезаписывается.
Восемь embedded PCM UI .tres и два runtime-generated PCM (menu click/tinnitus)
пересозданы теми же формулами как OGG; build_ui_sounds воспроизводит их.
Звон сохраняет полусекундную петлю, громкость и lifecycle.

## Rejected alternatives

- Player→office-floor dependency: нарушает направление слоёв и даёт цикл.
- Проверять радиус каждого разбитого окна: хруст на чистом полу, после LRU/clear.
- Area/коллизия на каждую декаль: лишние узлы, физика и память.
- Подмена отсутствующего переката другой записью: не соответствует поручению.
- Оставить PCM .tres/runtime WAV: не выполняет требование «только OGG».

## Migration plan

Добавить additive query/injection, обработать существующие контакты и glass spawns;
конвертировать/проверить записи, обновить ссылки, удалить PCM и исходные WAV.
Карты, save DTO, сцены, параметры движения и архитектурная policy прежние.

## Rollback plan

Revert task commit; восстановить старые PCM/ссылки и убрать query/injection/hooks.
Изменения сохранений и миграция данных не требуются.

## Approval

Прямой запрос владельца в этой беседе одобряет звуки поверхностей, перекат и
конвертацию/удаление WAV. Публикация/merge не поручены. Roll source появился при обновлении main и включён в текущую ревизию.
