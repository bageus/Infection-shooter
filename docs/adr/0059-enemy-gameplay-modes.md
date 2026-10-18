# ADR-0059: Режимы взаимодействия врагов с игроком

- Status: accepted — прямой запрос владельца18.10.2026
- Owners: bootstrap.app — настройки/инъекция; features.infected — восприятие/атаки

Два независимых bool в interface_v1: enemies_ignore_player=false и
 enemies_no_damage=false. В General доступны RU/EN переключатели с подсказками.
Отсутствующие/неверно типизированные значения используют прежний обычный режим.

Bootstrap передаёт текущей mission цели transient metadata
`enemy_gameplay_modes_v1={ignore_player:bool,no_damage:bool}`. Это read-only
контракт для infected, не глобальное состояние и не сохранение карты. Любой
новый враг/призванный экземпляр читает политику своей уже внедрённой цели.
Обычные цели без metadata сохраняют прежние правила.

Ignore запрещает sight/noise/ally/hit/forced chase; активная погоня сбрасывается
на следующем physics step до обработки отложенного удара, idle wandering
сохраняется. Отключение возвращает forced chase для призванных врагов или
обычное обнаружение для authored врагов. No damage оставляет AI/анимации/звук
атак; только HP-команда swipe/Horde ram/Colossus wave блокируется. Ignore также
блокирует попадание ранее выпущенной волны. Урон окружению и самоурон игрока
не фильтруются. Оба режима могут работать одновременно; default/reset выключены.

Отклонены: глобальный static-флаг (скрытый owner), фильтрация всего урона игрока
(затрагивает самоурон), копирование флагов только существующим врагам (теряет
late spawns), null target (останавливает idle AI). API сигнатуры сохраняются;
расширение target contract задокументировано в manifests. DTO карт, dependency
edges, Autoload и policy прежние. Root infected600 reviewed: назначение цели
и связанные состояния сосредоточены в perception, root598; отдельный private
helper фильтрует только команды enemy damage. Settings General делегирует
построение двух переключателей отдельной функции. Откат — удалить opt-in UI/
инъекцию/guards; неизвестные preference keys безвредны старой версии.
