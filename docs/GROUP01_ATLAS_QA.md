# Проверка атласа 01 и исправление CI PR #80

## Причина падения

Mission runtime regressions run 38048699952 (merge 7db85c5) остановил все шесть jobs на этапе Import. В runtime job 114203301932 и weapon forward_plus job 114203301796 подтверждён ERR_FILE_CORRUPT для `06/atlas/chairs_normal.png`. Architecture run 38048699919 прошёл: прежний статический аудит проверял наличие файла, но не его целостность.

## Исправления

- Исходный PNG размером 3 801 813 байт — точный обрезанный префикс целой карты 4 845 951 байт, встроенной в `06_office_chair.glb`. Недостающий хвост восстановлен; перекодирования и изменения пикселей нет.
- 12 GLB групп 06–08 используют существующие внешние карты вместо идентичных embedded payloads. Для каждого переписанного GLB проверен прежний semantic_digest: геометрия, материалы, UV, стадии и image bytes сохранены. Удалено 101 816 100 байт embedded дубликатов (97,10 МиБ).
- Девять PNG имеют сохранённые import profiles: размер в игре не более 1024², VRAM compression, mipmaps, корректный normal-map profile. Исходники не уменьшались. Импортные настройки GLB и прежние UIDs восстановлены из 61e8003.
- У `07_reception_counter_two_heights_2` существовавшие core + 12 Facade_Chip образуют `DamageReady`; дублирующий parent core в LargeParts очищен. Весь BIN chunk и остальные поля GLB неизменны. Игровой контракт требует именно in-place DamageReady, поэтому тест стойки не ослаблен.
- Physics regression сравнивает прирост скорости после одного попадания, а также фактическое движение кресла/урны и малое движение тяжёлого стола. Сравнение итогового пути разных коллайдеров было неверно: новая форма кресла скользит дальше урны. После попадания урна получает 2,13 м/с, кресло 0,98 м/с. Production physics и веса не менялись.
- Статический аудит PNG проверяет CRC, границы chunks, IEND и завершение zlib stream. Regression fixtures ловят обрезанный chunk и незавершённый image stream; повреждённый PNG из main теперь отклоняется до Godot.

## Локальная проверка Godot 4.7.2

- Чистый editor import и последующий импорт последней исправленной модели: без SCRIPT ERROR/ERROR.
- Model textures: 257 моделей, 184 textured, 0 failures.
- Group01: 0 failures, общий atlas payload 4,67 МиБ; тестовая 01_column_2 побайтово прежняя.
- Staged GLB, prop weight, elevator collision, startup resource memory, layout/mission loading, debris, balance и contact shadow: PASS.
- Main: 180 кадров без ошибок.
- validate_project, scene/resource/import/dedup, полный Architecture Python block и geometry compare-ref 61e8003: PASS.
- Выполнены все 72 headless-набора из Mission runtime workflow. Первый прогон: 71 PASS, surface_decor — 3 failures из-за новых имён материалов стола. После добавления aliases Warm_White_Laminate/Graphite_Surface_Metal повторный surface_decor и shader_warmup PASS; итог 72/72. Ответственность office_surface_decor не расширена: добавлена только совместимость имён в существующую таблицу finish, декомпозиция не требуется.

Полный native CI проверяется после публикации нового head PR #80. Локально native display недоступен; FPS и визуальная приёмка атласа не измерены. Публичные API, save DTO, зависимости и владельцы состояния не менялись, архитектурных исключений нет.
