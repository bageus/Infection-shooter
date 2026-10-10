# Модели для переработки стадий разрушения

Источник: активные GLB и авторская base_office_map.json из репозитория. Это аудит геометрии, не замер FPS или числа физических тел. Mesh-узел считается отдельно от mesh-ресурса и его material surfaces. Повторные ссылки на один ресурс считаются отдельными узлами; недостижимые узлы исключены. Стадии определяются по тем же именам групп, которые использует environment_prop_geometry, и именам экспортированных сцен.

**Важное ограничение:** environment_prop_breakup.spawn_stage уже ограничивает один вызов 32 фрагментами, стеклянные shards — 12. Поэтому стадия из 93 мешей не означает 93 одновременно созданных физических тела. Однако её узлы и ресурсы заранее присутствуют в модели. DamageReady — локальные сколы; её общий размер не равен числу сколов от одного попадания.

Таблица отсортирована по максимальному размеру стадии × числу прямых размещений GLB на базовой карте. Размещения через structural .tscn не включены в эту колонку; 0 означает отсутствие прямых GLB-записей, а не отсутствие модели в игре. Всего проверено 240 активных моделей; 39 выбраны: стадия больше 32 mesh-узлов либо модель с 48+ узлами и 10+ прямыми размещениями. Полные данные всех моделей — в соседнем JSON.

| Модель | Всего mesh-узлов | Стадии разрушения: mesh-узлы | Прямых размещений |
|---|---:|---|---:|
| `06_simple_chair` | 99 | Fine: 52, Medium: 28, Modular: 6, Primary: 12 | 71 |
| `06_conference_chair` | 49 | Fine: 25, Medium: 13, Modular: 3, Primary: 7 | 30 |
| `07_reception_counter_two_heights` | 114 | LargeParts: 20, SmallFragments: 93 | 8 |
| `07_table_square_tall` | 97 | LargeParts: 8, SmallFragments: 88 | 6 |
| `07_table_longest` | 74 | LargeParts: 5, SmallFragments: 68 | 6 |
| `07_round_dining_table` | 52 | LargeParts: 3, SmallFragments: 48 | 8 |
| `03_file_cabinet_small_with_shelfs` | 155 | LargeParts: 28, SmallFragments: 126 | 2 |
| `07_coffee_table` | 86 | LargeParts: 5, SmallFragments: 80 | 3 |
| `10_couch_large_blue_destructible` | 129 | Modular: 14, Primary: 22, Medium: 38, Fine: 54 | 3 |
| `06_simple_chair_fell` | 99 | Fine: 52, Medium: 28, Modular: 6, Primary: 12 | 3 |
| `10_couch_red_destructible` | 121 | Modular: 12, Primary: 20, Medium: 36, Fine: 52 | 1 |
| `10_armchair_green_destructible` | 113 | Modular: 10, Primary: 18, Medium: 34, Fine: 50 | 1 |
| `04_cardboard_archive_box` | 38 | LargeParts: 37 | 1 |
| `03_file_cabinet_largest` | 145 | LargeParts: 26, SmallFragments: 118 | 0 |
| `04_crate_large_broken` | 143 | LargeParts: 25, SmallFragments: 117 | 0 |
| `04_crate_small_broken` | 135 | LargeParts: 25, SmallFragments: 109 | 0 |
| `01_VECTRION_Destructible` | 121 | LargeParts: 21, JaggedFragments: 99 | 0 |
| `08_divider_full_U_desk` | 169 | Fine: 96, Medium: 48, Modular: 4, Primary: 16 | 0 |
| `07_table_circular` | 97 | LargeParts: 8, SmallFragments: 88 | 0 |
| `07_table_square` | 86 | LargeParts: 5, SmallFragments: 80 | 0 |
| `08_divider_black_high` | 134 | Fine: 75, Medium: 39, Modular: 4, Primary: 15 | 0 |
| `08_divider_full_H_desk` | 128 | Fine: 73, Medium: 37, Modular: 4, Primary: 13 | 0 |
| `08_divider_full_H` | 124 | Fine: 72, Medium: 36, Modular: 3, Primary: 12 | 0 |
| `08_divider_full_U` | 124 | Fine: 72, Medium: 36, Modular: 3, Primary: 12 | 0 |
| `03_file_cabinet_smaller` | 84 | LargeParts: 16, SmallFragments: 67 | 0 |
| `08_office_desk_4_coner` | 137 | Modular: 6, Primary: 20, Medium: 50, Fine: 60 | 0 |
| `06_office_chair` | 87 | Fine: 49, Medium: 25, Modular: 3, Primary: 9 | 0 |
| `06_office_chair_2` | 89 | Fine: 49, Medium: 25, Modular: 3, Primary: 9 | 0 |
| `06_office_chair_2_fell` | 87 | Fine: 49, Medium: 25, Modular: 3, Primary: 9 | 0 |
| `04_cardboard_box_open` | 45 | LargeParts: 44 | 0 |
| `03_book_case_with_back_small` | 49 | LargeParts: 8, SmallFragments: 40 | 0 |
| `03_server_rack` | 111 | Modular: 10, Primary: 20, Medium: 40, Fine: 40 | 0 |
| `03_book_case_with_back` | 45 | LargeParts: 8, SmallFragments: 36 | 0 |
| `03_book_case` | 43 | LargeParts: 7, SmallFragments: 35 | 0 |
| `03_bookshelf` | 44 | LargeParts: 8, SmallFragments: 35 | 0 |
| `01_glass_door_breakable` | 39 | Glass_Shards: 34 | 0 |
| `01_glass_partition_blinds_breakable` | 39 | Glass_Shards: 34 | 0 |
| `01_glass_wall_full_breakable` | 36 | Glass_Shards: 33 | 0 |
| `03_book_case_small` | 41 | LargeParts: 7, SmallFragments: 33 | 0 |

## Требования к переработке

- В первую очередь обычные и конференционные стулья: уменьшить Fine/Medium, объединить мелкую фурнитуру, сохранить независимые ножки/спинку/сиденье.
- Для крупных шкафов, стойки рецепции и диванов объединить соседние мелкие куски; отдельно оставлять только функциональные крупные элементы.
- Начальный ориентир, не жёсткое правило: 12–24 физических фрагмента для стула, до 24–32 для крупной мебели. Более мелкую крошку представлять визуальным эффектом.
- Сохранить UV, material slots, имена Intact и стадий, имена семейств деталей для prefix-matching, масштаб и pivot. Проверить переход каждого крупного фрагмента в следующую стадию.
- Не объединять Intact со стадиями разрушения. Удалять неиспользуемые дубликаты; не подменять уменьшение mesh-узлов одним снижением числа треугольников.
