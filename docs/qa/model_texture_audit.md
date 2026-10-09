# Аудит текстур моделей

Дата: 09.10.2026. Проверено 258 активных моделей; 162 используют текстуры. Обновлены 15 GLB группы 03: все поверхности имеют встроенные base-color/normal/ORM изображения и UV. Все модели доступны через автоматически собираемую палитру группы 03; 03_file_cabinet_small_with_shelfs уже размещён на карте дважды. Старые изображения и удалённые кресла не возвращаются.

У server_rack найдены 11 неиспользуемых мешей GLB: runtime-аудит проверяет только меши, достижимые из сцен, включая сцены разрушения. Таблица ниже описывает весь исходный mesh payload. У server_rack3 удалена старая однотонная замена повреждённых материалов, чтобы сохранялись авторские PBR-текстуры. В CI добавлена загрузка всех 15 моделей через игровой каталог и проверка visual/collision/textures; staged regression проверяет сохранение материалов после повреждения стойки.

Локально project/resource/import gates и 11 Python tests PASS. Godot 4.7.2 в текущей среде аварийно завершается до импорта. На исходном main импорт, main/menu и два native renderer jobs прошли, но общий аудит упал; несколько cold-import jobs остановлены timeout 240 с. Лимит cold import увеличен до 600 с; assertions сохранены. Новая ревизия требует подтверждения CI. API, DTO, зависимости и архитектура прежние.

Источник: активные GLB текущего репозитория; папки с `.gdignore` исключены. Проверяются изображения, привязки материалов и UV. Наличие изображений само по себе не означает их использование.

| Модель | Изображения | Поверхности с текстурами / всего | UV0 / всего | Карты |
|---|---:|---:|---:|---|
| `models/objects/03_drawer_cabinet.glb` | 0 | 0/7 | 0/7 | Только материал/цвет |
| `models/objects/03_file_cabinet_tall.glb` | 0 | 0/7 | 0/7 | Только материал/цвет |
| `models/objects/characters/enemy/Brute.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/characters/enemy/Colossus.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/characters/enemy/Horde.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/characters/enemy/Hunger.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/characters/enemy/Revenant.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/characters/enemy/Titan.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/characters/soldier_animated.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/enviroments/01/01_VECTRION_Destructible.glb` | 3 | 121/121 | 121/121 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_column.glb` | 3 | 3/3 | 3/3 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_elevator_cabin_freight.glb` | 3 | 31/34 | 31/34 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_elevator_cabin_passenger.glb` | 3 | 25/27 | 25/27 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_elevator_door.glb` | 3 | 12/12 | 12/12 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_floor_1x1.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_floor_2x2.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_floor_3x3.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_floor_corner_round.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_floor_corner_round_half.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_floor_pad.glb` | 3 | 1/2 | 2/2 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_glass_door_breakable.glb` | 4 | 6/42 | 42/42 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_glass_partition_blinds_breakable.glb` | 5 | 34/69 | 69/69 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_glass_partition_half_breakable.glb` | 5 | 2/35 | 35/35 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_glass_wall_full_breakable.glb` | 5 | 2/36 | 36/36 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_only_door.glb` | 3 | 2/2 | 2/2 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_stairs.glb` | 3 | 11/11 | 11/11 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_stairs_2.glb` | 3 | 11/11 | 11/11 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_wall_door.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_wall_door_without.glb` | 3 | 5/5 | 5/5 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_wall_emergency_door.glb` | 4 | 9/9 | 9/9 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_wall_half_panel.glb` | 3 | 4/5 | 4/5 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_wall_straight.glb` | 3 | 2/2 | 2/2 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_window_double.glb` | 3 | 5/6 | 5/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/01/01_wood_slat_partition_destructible.glb` | 3 | 28/28 | 28/28 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_arcade_machine_V1.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/02/02_arcade_machine_V2.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/02/02_arcade_machine_V3.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/02/02_arcade_machine_V4.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/02/02_arcade_machine_V5.glb` | 0 | 0/3 | 3/3 | Только материал/цвет |
| `models/objects/enviroments/02/02_arcade_machine_V6.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/02/02_capboard_down_destructible.glb` | 12 | 31/31 | 31/31 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_capboard_down_one_destructible.glb` | 12 | 25/25 | 25/25 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_capboard_down_sink_destructible.glb` | 15 | 50/50 | 50/50 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_capboard_up_double_destructible.glb` | 9 | 25/25 | 25/25 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_capboard_up_one_destructible.glb` | 9 | 19/19 | 19/19 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_coffee_machine_destructible.glb` | 15 | 43/43 | 43/43 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_coffee_vending_1_dented.glb` | 9 | 4/4 | 4/4 | baseColorTexture, clearcoatNormalTexture, clearcoatRoughnessTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture, specularTexture |
| `models/objects/enviroments/02/02_coffee_vending_2_dented.glb` | 4 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_dishwasher_dented.glb` | 6 | 12/12 | 12/12 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_frige_dented.glb` | 6 | 20/20 | 20/20 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_kittle_destructible.glb` | 12 | 16/16 | 16/16 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_microwave_destructible.glb` | 18 | 57/57 | 57/57 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_sink_pedestal_improved.glb` | 9 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_toilet_new.glb` | 9 | 8/8 | 8/8 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_vending_automat_1_dented.glb` | 9 | 15/15 | 15/15 | baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_vending_automat_2_dented.glb` | 9 | 15/15 | 15/15 | baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_vending_machine_fantas_dented.glb` | 7 | 28/28 | 28/28 | baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_wall_urinal_improved.glb` | 6 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_washing_machine_dented.glb` | 15 | 41/41 | 41/41 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_water_cooler_bottle.glb` | 6 | 2/2 | 2/2 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_water_cooler_bottle_attached_destructible.glb` | 12 | 32/32 | 32/32 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/02/02_water_cooler_destructible.glb` | 9 | 28/28 | 28/28 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_book_case.glb` | 9 | 78/78 | 78/78 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_book_case_small.glb` | 9 | 74/74 | 74/74 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_book_case_with_back.glb` | 9 | 102/102 | 102/102 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_book_case_with_back_small.glb` | 9 | 115/115 | 115/115 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_bookshelf.glb` | 9 | 71/71 | 71/71 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_box_1_metal_dented.glb` | 6 | 8/8 | 8/8 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_file_cabinet_large_shelf_fancy.glb` | 9 | 69/69 | 69/69 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_file_cabinet_largest.glb` | 9 | 331/331 | 331/331 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_file_cabinet_small_shelf_fancy.glb` | 9 | 65/65 | 65/65 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_file_cabinet_small_with_shelfs.glb` | 9 | 415/415 | 415/415 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_file_cabinet_smaller.glb` | 9 | 200/200 | 200/200 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_locker_tall_dented.glb` | 6 | 47/47 | 47/47 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_server_rack.glb` | 7 | 122/122 | 122/122 | baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_server_rack2.glb` | 10 | 158/158 | 158/158 | baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/03/03_server_rack3.glb` | 10 | 43/43 | 43/43 | baseColorTexture, emissiveTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/04/04_cardboard_archive_box.glb` | 2 | 39/52 | 52/52 | baseColorTexture |
| `models/objects/enviroments/04/04_cardboard_box_closed.glb` | 2 | 23/36 | 36/36 | baseColorTexture |
| `models/objects/enviroments/04/04_cardboard_box_open.glb` | 3 | 73/73 | 73/73 | baseColorTexture |
| `models/objects/enviroments/04/04_cardboard_boxes.glb` | 0 | 0/16 | 16/16 | Только материал/цвет |
| `models/objects/enviroments/04/04_cardboard_boxes_1.glb` | 2 | 21/29 | 29/29 | baseColorTexture |
| `models/objects/enviroments/04/04_crate_large_broken.glb` | 0 | 0/143 | 0/143 | Только материал/цвет |
| `models/objects/enviroments/04/04_crate_small_broken.glb` | 0 | 0/135 | 0/135 | Только материал/цвет |
| `models/objects/enviroments/04/04_military_crate.glb` | 12 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/enviroments/05/05_MFU_2_extra_trays_destructible.glb` | 0 | 0/15 | 0/15 | Только материал/цвет |
| `models/objects/enviroments/05/05_MFU_destructible.glb` | 0 | 0/10 | 0/10 | Только материал/цвет |
| `models/objects/enviroments/05/05_PC_destructible.glb` | 0 | 0/5 | 0/5 | Только материал/цвет |
| `models/objects/enviroments/05/05_aircondition_destructible.glb` | 0 | 0/6 | 6/6 | Только материал/цвет |
| `models/objects/enviroments/05/05_computer_mouse.glb` | 0 | 0/1 | 0/1 | Только материал/цвет |
| `models/objects/enviroments/05/05_computer_tower_destructible.glb` | 0 | 0/5 | 0/5 | Только материал/цвет |
| `models/objects/enviroments/05/05_desk_phone.glb` | 0 | 0/3 | 0/3 | Только материал/цвет |
| `models/objects/enviroments/05/05_keyboard.glb` | 2 | 2/2 | 2/2 | baseColorTexture |
| `models/objects/enviroments/05/05_lamp.glb` | 0 | 0/3 | 3/3 | Только материал/цвет |
| `models/objects/enviroments/05/05_laptop2_destructible.glb` | 0 | 0/5 | 5/5 | Только материал/цвет |
| `models/objects/enviroments/05/05_laptop_close_destructible.glb` | 0 | 0/21 | 0/21 | Только материал/цвет |
| `models/objects/enviroments/05/05_laptop_destructible.glb` | 0 | 0/21 | 0/21 | Только материал/цвет |
| `models/objects/enviroments/05/05_minipc.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/05/05_monitor2_destructible.glb` | 0 | 0/7 | 7/7 | Только материал/цвет |
| `models/objects/enviroments/05/05_monitor3_server_destructible.glb` | 0 | 0/11 | 11/11 | Только материал/цвет |
| `models/objects/enviroments/05/05_monitor4_server_destructible.glb` | 0 | 0/11 | 11/11 | Только материал/цвет |
| `models/objects/enviroments/05/05_monitor_destructible.glb` | 0 | 0/9 | 9/9 | Только материал/цвет |
| `models/objects/enviroments/05/05_monitor_wide_destructible.glb` | 0 | 0/9 | 9/9 | Только материал/цвет |
| `models/objects/enviroments/05/05_printer_destructible.glb` | 0 | 0/20 | 20/20 | Только материал/цвет |
| `models/objects/enviroments/05/05_wall_TV_destructible.glb` | 0 | 0/8 | 0/8 | Только материал/цвет |
| `models/objects/enviroments/05/05_wall_TV_frameless_destructible.glb` | 0 | 0/5 | 0/5 | Только материал/цвет |
| `models/objects/enviroments/05/05_wall_hand_dryer_improved.glb` | 0 | 0/5 | 0/5 | Только материал/цвет |
| `models/objects/enviroments/05/09_phone_a_base.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/05/09_phone_a_base_hang.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/05/09_phone_b.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/06/06_conference_chair.glb` | 12 | 99/99 | 99/99 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/06/06_office_chair.glb` | 15 | 232/232 | 232/232 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/06/06_office_chair_2.glb` | 15 | 254/254 | 254/254 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/06/06_office_chair_2_fell.glb` | 15 | 250/250 | 250/250 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/06/06_simple_chair.glb` | 12 | 222/222 | 222/222 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/06/06_simple_chair_fell.glb` | 12 | 222/222 | 222/222 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_coffee_table.glb` | 6 | 170/170 | 170/170 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_coffee_table2.glb` | 3 | 35/35 | 35/35 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_reception_counter_two_heights.glb` | 15 | 209/209 | 209/209 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_reception_counter_two_heights_2.glb` | 4 | 16/20 | 20/20 | baseColorTexture, metallicRoughnessTexture, normalTexture |
| `models/objects/enviroments/07/07_round_dining_table.glb` | 12 | 102/102 | 102/102 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_table.glb` | 3 | 34/34 | 34/34 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_table_circular.glb` | 6 | 192/192 | 192/192 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_table_longest.glb` | 6 | 146/146 | 146/146 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_table_square.glb` | 6 | 167/167 | 167/167 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/07/07_table_square_tall.glb` | 6 | 192/192 | 192/192 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_black_high.glb` | 9 | 255/255 | 255/255 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_black_high_half.glb` | 9 | 55/55 | 55/55 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_black_low.glb` | 9 | 55/55 | 55/55 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_black_low_half.glb` | 9 | 61/61 | 61/61 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_full_H.glb` | 6 | 244/244 | 244/244 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_full_H_desk.glb` | 12 | 309/309 | 309/309 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_full_U.glb` | 6 | 244/244 | 244/244 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_divider_full_U_desk.glb` | 12 | 330/330 | 330/330 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_office_desk_2.glb` | 12 | 138/138 | 138/138 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/08/08_office_desk_4_coner.glb` | 9 | 237/237 | 237/237 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/09/09_board_stand_white.glb` | 2 | 8/8 | 8/8 | baseColorTexture |
| `models/objects/enviroments/09/09_book_big.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_book_fat.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_book_filearchive.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_book_folder.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_book_small.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_book_st.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_books.glb` | 1 | 14/27 | 14/27 | baseColorTexture |
| `models/objects/enviroments/09/09_books_alt.glb` | 1 | 7/12 | 7/12 | baseColorTexture |
| `models/objects/enviroments/09/09_books_alt_2.glb` | 1 | 10/17 | 10/17 | baseColorTexture |
| `models/objects/enviroments/09/09_camera.glb` | 0 | 0/5 | 5/5 | Только материал/цвет |
| `models/objects/enviroments/09/09_case_with_money_close.glb` | 3 | 1/1 | 1/1 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/09/09_case_with_money_open.glb` | 10 | 6/6 | 6/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/09/09_casehand_1.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_casehand_2.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder.glb` | 0 | 0/1 | 0/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder_alt_1.glb` | 0 | 0/1 | 0/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder_alt_1_fell.glb` | 0 | 0/1 | 0/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder_alt_2.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder_alt_2_fell.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder_alt_fell.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_file_binder_fell.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_fire_extinguisher.glb` | 14 | 5/5 | 5/5 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/09/09_fruit_apple.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_fruit_banana.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_fruit_banana_b.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_fruit_orange.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_fruit_plate.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_fruit_plate_2.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_glass.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_glass_2.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_glass_water_bottle_clear_250ml.glb` | 0 | 0/6 | 0/6 | Только материал/цвет |
| `models/objects/enviroments/09/09_glass_water_bottle_green_330ml.glb` | 0 | 0/6 | 0/6 | Только материал/цвет |
| `models/objects/enviroments/09/09_marker.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_marker_eraser.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_mug.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_mug_alt_1.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_mug_alt_2.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_mug_alt_3.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_notepad.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_file_single.glb` | 0 | 0/3 | 3/3 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_a.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_a_2.glb` | 0 | 0/7 | 7/7 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_d_custom.glb` | 0 | 0/4 | 4/4 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_e.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_e_2.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_f.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_f_2.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_office_files_f_3.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_painting.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_painting_small.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_painting_small_2.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_A4_compact_crumpled_wad.glb` | 0 | 0/3 | 0/3 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_A4_heavily_crumpled.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_A4_moderately_crumpled.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_A4_slightly_crumpled.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_stack.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_paper_stray.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_towel_roll_h.glb` | 0 | 0/8 | 0/8 | Только материал/цвет |
| `models/objects/enviroments/09/09_paper_towel_roll_v.glb` | 0 | 0/4 | 0/4 | Только материал/цвет |
| `models/objects/enviroments/09/09_pen_1.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_pen_2.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_pen_3.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_pen_4.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_pen_5.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_pen_6.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_pencil.glb` | 0 | 0/4 | 4/4 | Только материал/цвет |
| `models/objects/enviroments/09/09_pencil_box.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_pencil_holder.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_plastic_water_bottle_blue_500ml.glb` | 0 | 0/5 | 0/5 | Только материал/цвет |
| `models/objects/enviroments/09/09_plastic_water_bottle_clear_330ml.glb` | 0 | 0/5 | 0/5 | Только материал/цвет |
| `models/objects/enviroments/09/09_stapler.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_tablet.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_toilet_paper_roll_h.glb` | 0 | 0/4 | 0/4 | Только материал/цвет |
| `models/objects/enviroments/09/09_toilet_paper_roll_v.glb` | 0 | 0/4 | 0/4 | Только материал/цвет |
| `models/objects/enviroments/09/09_trash_bin.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_trash_bin_small.glb` | 0 | 0/1 | 1/1 | Только материал/цвет |
| `models/objects/enviroments/09/09_wall_clock.glb` | 1 | 1/1 | 1/1 | baseColorTexture |
| `models/objects/enviroments/09/09_wall_mirror.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_white_board_big.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/09/09_white_board_stand.glb` | 0 | 0/2 | 2/2 | Только материал/цвет |
| `models/objects/enviroments/10/10_armchair_green_destructible.glb` | 6 | 181/181 | 181/181 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/10/10_couch_large_blue_destructible.glb` | 6 | 197/197 | 197/197 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/10/10_couch_red_destructible.glb` | 6 | 189/189 | 189/189 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_bamboo.glb` | 9 | 28/28 | 28/28 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_deco_2.glb` | 9 | 28/28 | 28/28 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_deco_3.glb` | 9 | 28/28 | 28/28 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_deco_plant.glb` | 9 | 28/28 | 28/28 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_plant_large.glb` | 9 | 30/30 | 30/30 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_plant_medium.glb` | 9 | 30/30 | 30/30 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/11/11_plant_small.glb` | 9 | 30/30 | 30/30 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_ammo_automate.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_ammo_minigun.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_ammo_pistols.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_ammo_shotgun.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_ammo_sniper.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_ammo_uzi.glb` | 3 | 7/7 | 7/7 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_antidote.glb` | 3 | 10/10 | 10/10 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_launcher_casing_lowpoly.glb` | 12 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_medkit.glb` | 3 | 6/6 | 6/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_pistol_casing.glb` | 9 | 3/3 | 3/3 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_rifle_casing.glb` | 9 | 3/3 | 3/3 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/12/12_shotgun_casing.glb` | 12 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/enviroments/13/13_wall_cafeteria.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/enviroments/13/13_wall_elevator.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/enviroments/13/13_wall_emergency_alarm.glb` | 0 | 0/8 | 0/8 | Только материал/цвет |
| `models/objects/enviroments/13/13_wall_exit_lit.glb` | 1 | 1/2 | 1/2 | baseColorTexture, emissiveTexture |
| `models/objects/enviroments/13/13_wall_fire_call_point.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/enviroments/13/13_wall_fire_door.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/enviroments/13/13_wall_light_switch.glb` | 0 | 0/2 | 0/2 | Только материал/цвет |
| `models/objects/enviroments/13/13_wall_meeting_room.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/enviroments/13/13_wall_toilet_female.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/enviroments/13/13_wall_toilet_male.glb` | 1 | 1/2 | 1/2 | baseColorTexture |
| `models/objects/weapons/ak_rifle_lowpoly.glb` | 3 | 6/6 | 6/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/aviation_minigun_lowpoly.glb` | 3 | 8/8 | 8/8 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/m4_rifle_lowpoly.glb` | 3 | 6/6 | 6/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/minigun_ammo_backpack_lowpoly.glb` | 3 | 6/6 | 6/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/pistol_lowpoly.glb` | 3 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/shotgun_lowpoly.glb` | 3 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/six_chamber_launcher_lowpoly.glb` | 3 | 6/6 | 6/6 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/sniper_rifle_lowpoly.glb` | 3 | 11/11 | 11/11 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
| `models/objects/weapons/uzi_lowpoly.glb` | 3 | 4/4 | 4/4 | baseColorTexture, metallicRoughnessTexture, normalTexture, occlusionTexture |
