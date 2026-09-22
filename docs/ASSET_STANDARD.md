# Стандарт ассетов Infection

## Назначение

Этот документ фиксирует единый стандарт размеров и точек привязки для ручного левел-дизайна. Он не вводит процедурную генерацию уровней.

## Координаты и сетка

- 1 Godot unit = 1 метр.
- Базовый placement grid: 0.25 м.
- Архитектурные элементы, которые должны стыковаться друг с другом, обязаны иметь footprint и точки стыковки, кратные 0.25 м.
- Мебель и props не обязаны иметь габариты, кратные 0.25 м; к сетке привязывается их placement root.
- Уровень чистого пола: Y = 0.
- Масштаб канонической structural-сцены: Vector3(1, 1, 1). Нельзя исправлять стыки произвольным non-uniform scale экземпляров.

## Канонический pivot

Pivot означает origin корневого Node3D канонической .tscn-сцены. Исходный GLB/Blend может иметь другой origin: Visual разрешено смещать относительно root. Это предпочтительнее разрушительного редактирования исходной модели.

| Тип | Pivot |
|---|---|
| Прямая стена, окно, стена с дверью, стеклянная секция | bottom-center: центр длины и толщины, Y=0 |
| Колонна | bottom-center, Y=0 |
| Внутренний/внешний угол | пересечение строительных осей стен, Y=0 |
| Floor pad | центр X/Z, верхняя ходовая поверхность на Y=0 |
| Лифтовая кабина | центр входа кабины на уровне чистого пола |
| Отдельная распашная дверь | root совместим с родительским дверным модулем; hinge/door pivot остается локальным pivot анимации |
| Настенный prop | центр точки крепления к стене |
| Напольный prop | bottom-center |

## Аудит structural kit

### 01_* — базовый архитектурный kit

Эти ассеты являются каноническими строительными элементами и должны проходить проверку pivot/стыковки:

- 01_wall_straight.glb
- 01_wall_half_panel.glb
- 01_wall_outer_corner.glb
- 01_wall_inner_corner.blend
- 01_wall_door_2.glb
- 01_wall_door_2_without.glb
- 01_wall_door_3.glb
- 01_wall_door_3_without.glb
- 01_wall_emergency_door.glb
- 01_only_door_2.glb
- 01_only_door_3.glb
- 01_window_double.glb
- 01_window_corner.glb
- 01_column.glb
- 01_floor_pad.glb
- 01_elevator_door.glb
- 01_elevator_cabin_passenger.glb
- 01_elevator_cabin_freight.glb

WallStraight и WindowDouble в legacy wrapper имеют длину 2.25 м. Это ровно 9 шагов сетки 0.25 м и принимается как существующий базовый фасадный модуль. Не менять его на 2.0 или 4.0 м только ради круглого числа.

Legacy collision у WallStraight/WindowDouble имеет высоту 3.2 м. До визуальной проверки исходных mesh bounds 3.2 м считается текущей reference wall height, но высота не является шагом горизонтальной сетки.

Door/window variants, которые заменяют прямую секцию фасада, должны сохранять тот же placement root и совместимые connection points, что и WallStraight.

### 13_* — стеклянный kit: требует исправления/проверки

- 13_glass_wall_full.glb
- 13_glass_partition_half.glb
- 13_glass_partition_blinds.glb
- 13_sliding_glass_door.glb

Legacy GlassWall collision имеет длину 3.8 м, тогда как существующая authored-композиция размещает последовательные секции с шагом 4.0 м. Это создает номинальный зазор 0.2 м. Канонический стеклянный модуль должен иметь connection span 4.0 м (16 шагов сетки) либо authored placement должен использовать реальный span модели. Для текущей планировки целевой span = 4.0 м.

Нельзя исправлять 3.8 -> 4.0 случайным scale экземпляра. Предпочтительный порядок:
1. проверить реальные mesh bounds в Godot;
2. если геометрия действительно 3.8 м, исправить source mesh или добавить предсказуемые end caps/раму до 4.0 м;
3. сохранить root pivot bottom-center;
4. проверить collision после изменения.

### Legacy cubicle partition: требует исправления

Legacy 29_cubicle_straight_partition.glb используется через assets/cubicle_partition.tscn с collision width 2.8 м, а authored placement идет шагом 3.0 м. Номинальный зазор = 0.2 м.

Если этот ассет остается в level-design kit, его целевой connection span = 3.0 м (12 шагов). Если он выводится из активного structural kit, не переносить legacy 2.8 м как новый стандарт.

## Props 02-12, 14, 16

Не округлять физические размеры мебели, сантехники, коробок, столов, стульев, шкафов, растений, кухни и декора до 0.25 м. Для них стандартизируется placement pivot и scale=1, а не габарит.

Исключение: составные элементы, которые обязаны стыковаться между собой (например, кухонные секции), должны иметь документированные connection points, кратные выбранному локальному модулю.

## Персонажи, оружие и pickups

Не относятся к architectural grid. Их размеры определяются gameplay/animation requirements. Для персонажей gameplay root и visual root должны быть разделены; ступни визуальной модели выравниваются с gameplay floor без изменения физического root.

## Правило для level design

Использовать только канонические сцены из public/structural для новой архитектуры. Старые office_floor/assets structural wrappers считаются legacy и не должны быть источником размеров для новых помещений.

Перед добавлением нового structural asset проверить:
- scale = 1;
- root pivot соответствует таблице;
- Y=0 соответствует уровню пола;
- connection span кратен 0.25 м;
- соседние экземпляры стыкуются без щели/перекрытия;
- collision совпадает с визуальной геометрией;
- door/animation pivots не были заменены placement pivot.

## Требующаяся визуальная проверка

GitHub-исходники позволяют определить scene composition и legacy collision sizes, но не дают надежно подтвердить фактический AABB каждого импортированного GLB/Blend без импорта в Godot. Поэтому перед физическим редактированием source meshes нужно измерить реальные bounds в Godot и сверить их с целевыми connection spans выше.


## Автоматическая проверка в Godot

Для измерения реальных импортированных mesh bounds используйте:

```bash
python tools/audit_structural_assets.py
```

Для сохранения CSV:

```bash
python tools/audit_structural_assets.py --output structural_asset_audit.csv
```

Аудит загружает все `.tscn` из `public/structural`, объединяет AABB всех MeshInstance3D в координатах placement root и выводит: размеры X/Y/Z, min/max, расстояние origin до низа геометрии, ошибку кратности X/Z сетке 0.25 м, целевой connection span для 13_* glass и отклонение от него.

Для bottom-center structural asset значение `min_y` / `origin_to_floor` должно быть близко к 0. Для элементов с целевым span статус `CHECK` означает, что фактическая геометрия отличается от целевого размера более чем на 1 см.
