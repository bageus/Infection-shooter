# Удалённые устаревшие сцены — 30.09.2026

Проверена ревизия `7712a3e2d2f3fa70322f8f1e0a7637955d433ef3`.
Владелец прямо разрешил удалить неиспользуемые сцены с устаревшими путями моделей.

| Набор | Количество | Назначение и причина удаления |
|---|---:|---|
| `public/office_floor.tscn` | 1 | Прежний демонстрационный офис 36×28 м; текущий запуск использует `bootstrap/app/main.tscn` и основной этаж 80×60 м. Вызовов сцены нет; удалена её запись из манифеста. |
| `assets/*.tscn` | 22 | Мебель, стены, окна, аптечка, боеприпасы и декорации только старого демонстрационного офиса. 19 сцен ссылаются на отсутствующие старые GLB; 3 исправные сцены нужны только этому неиспользуемому офису. |
| `public/props/*.tscn` | 51 | Старые индивидуальные обёртки коробок, стульев, столов, кабинетов, кухни и сантехники. Текущий каталог создаёт актуальные GLB через `environment_prop`, `bathroom_fixture` или `paper_prop`; на старые обёртки нет ссылок. |
| `public/structural/*.tscn` | 3 | Старые внутренний/внешний угол стены и угловое окно; моделей нет, каталог и основной этаж их не используют. |

Всего удалено 77 сцен и принадлежащий только старому офису `office_floor.gd` с UID.
Модели, текстуры и основная сцена этажа сохранены.

Проверены прямые ссылки в GDScript/сценах/ресурсах, актуальный каталог планировщика,
4-МБ сцена `base_office_layout.tscn` и объявленные публичные пути. Динамическая
сборка путей структурных сцен и pickups заменена явным словарём путей.
Строки миграции старых карт сохраняются как исторические идентификаторы: они
не загружают удалённые сцены, а выбирают актуальную модель или пропускают уже
неподдерживаемый элемент, как прежде. Доступа к пользовательским `user://maps`
в этой проверке нет; нельзя обещать восстановление каждого неизвестного старого
элемента. Карты версии 5 и путь `base_office_layout.tscn` не менялись.

`tools/validate_scene_resources.py` и шаг CI теперь проверяют наличие всех
ресурсов, указанных в `ext_resource`, чтобы устаревшие ссылки не возвращались.

## Полный перечень

- `game/presentation/office_floor/assets/ammo_case.tscn`
- `game/presentation/office_floor/assets/broken_wall.tscn`
- `game/presentation/office_floor/assets/coffee_table.tscn`
- `game/presentation/office_floor/assets/crate_large.tscn`
- `game/presentation/office_floor/assets/cubicle_partition.tscn`
- `game/presentation/office_floor/assets/desk.tscn`
- `game/presentation/office_floor/assets/file_cabinet.tscn`
- `game/presentation/office_floor/assets/fire_extinguisher.tscn`
- `game/presentation/office_floor/assets/glass_half.tscn`
- `game/presentation/office_floor/assets/glass_wall.tscn`
- `game/presentation/office_floor/assets/locker.tscn`
- `game/presentation/office_floor/assets/long_table.tscn`
- `game/presentation/office_floor/assets/medkit.tscn`
- `game/presentation/office_floor/assets/plant_large.tscn`
- `game/presentation/office_floor/assets/plant_medium.tscn`
- `game/presentation/office_floor/assets/rubble.tscn`
- `game/presentation/office_floor/assets/sofa.tscn`
- `game/presentation/office_floor/assets/standing_desk.tscn`
- `game/presentation/office_floor/assets/wall_straight.tscn`
- `game/presentation/office_floor/assets/water_cooler.tscn`
- `game/presentation/office_floor/assets/window_double.tscn`
- `game/presentation/office_floor/assets/workstation_quad.tscn`
- `game/presentation/office_floor/public/office_floor.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_archive_box.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_box_closed.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_box_open.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_1.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_11.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_2.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_3.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_4.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_5.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_6.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_8.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_stack.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_stack_2.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_stack_3.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_stack_4.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_stack_5.tscn`
- `game/presentation/office_floor/public/props/02_cardboard_boxes_stack_6.tscn`
- `game/presentation/office_floor/public/props/04_crate_large.tscn`
- `game/presentation/office_floor/public/props/04_crate_small.tscn`
- `game/presentation/office_floor/public/props/04_plastic_storage_bin.tscn`
- `game/presentation/office_floor/public/props/05_desktop.tscn`
- `game/presentation/office_floor/public/props/06_executive_chair.tscn`
- `game/presentation/office_floor/public/props/06_executive_chair_fell.tscn`
- `game/presentation/office_floor/public/props/06_office_chair_fell.tscn`
- `game/presentation/office_floor/public/props/07_table_L_shaped.tscn`
- `game/presentation/office_floor/public/props/07_table_long.tscn`
- `game/presentation/office_floor/public/props/08_office_desk.tscn`
- `game/presentation/office_floor/public/props/08_office_desk_lamp.tscn`
- `game/presentation/office_floor/public/props/08_table_square.tscn`
- `game/presentation/office_floor/public/props/08_workstation_dual.tscn`
- `game/presentation/office_floor/public/props/08_workstation_partitioned.tscn`
- `game/presentation/office_floor/public/props/08_workstation_partitioned_dual.tscn`
- `game/presentation/office_floor/public/props/08_workstation_quad.tscn`
- `game/presentation/office_floor/public/props/08_workstation_quad_without.tscn`
- `game/presentation/office_floor/public/props/09_standing_desk.tscn`
- `game/presentation/office_floor/public/props/10_coffee_table.tscn`
- `game/presentation/office_floor/public/props/10_coffee_table_and_sofa.tscn`
- `game/presentation/office_floor/public/props/10_sofa.tscn`
- `game/presentation/office_floor/public/props/14_fire_extinguisher.tscn`
- `game/presentation/office_floor/public/props/14_water_cooler.tscn`
- `game/presentation/office_floor/public/props/16_kitchen_lower_complete.tscn`
- `game/presentation/office_floor/public/props/16_kitchen_upper_4.tscn`
- `game/presentation/office_floor/public/props/16_refrigerator.tscn`
- `game/presentation/office_floor/public/props/16_round_dining_table.tscn`
- `game/presentation/office_floor/public/props/16_sink_pedestal.tscn`
- `game/presentation/office_floor/public/props/16_snack_vending_machine.tscn`
- `game/presentation/office_floor/public/props/16_toilet_floor.tscn`
- `game/presentation/office_floor/public/props/16_wall_hand_dryer.tscn`
- `game/presentation/office_floor/public/props/16_wall_mirror.tscn`
- `game/presentation/office_floor/public/props/16_wall_urinal.tscn`
- `game/presentation/office_floor/public/structural/wall_inner_corner.tscn`
- `game/presentation/office_floor/public/structural/wall_outer_corner.tscn`
- `game/presentation/office_floor/public/structural/window_corner.tscn`
