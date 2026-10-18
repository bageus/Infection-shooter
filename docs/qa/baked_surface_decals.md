# Запечённые следы поверхностей

## Поведение для приёмки

- Стекло: локальный impact/hole из Glass4x2; sparse трещины из cells0/1/2/12
  Transparent fracture (1-1/1-2/1-3/4-1); cell13 (4-2) в четырёх углах с
  поворотами0/1/2/3. Другие cells — редкие маленькие impacts. После shatter
  все следы сняты; overflow не создаёт per-hit quad.
- Монитор/TV: после попадания экран тёмный, трещины остаются на receiver;
  полное разрушение скрывает Visual вместе с трещинами.
- Стены/колонны: bullet marks; редкие soft rubs. Штукатурка только после
  powerful оружия (18%), floor chips22%. Pistol/UZI её не снимают.
- Ходьба игрока/врагов: gait/distance-paced события, редкие слабые scuffs12%,
  максимум2support rays/physics frame и2floor scuffs/frame. Не под столами,
  на верхних площадках вместо опоры или над stair openings.
- Пол: damage ниже scuff, material debris выше обоих. Поздний скол не
  перерисовывает уже лежащее стекло/бумагу/дерево/картон/пластик.
- Planner → «Следы поверхностей…»: группа, непрозрачность и масштаб с preview.
  Настройки относятся к новым следам. Save Layout/named map/authored snapshot/
  scene bake сохраняют их; настройки учитываются при settings-only restore.
  Runtime пиксели не сохраняются. Malformed config отклоняется до clear.

## Бюджеты и ограничения

16 floor sections: прежние512px RGBA8+R8 debris и lazy256px damage/scuff,
queue64,2stamps+1section upload. Receiver cache12: шест128px граней в двух
384×256 RGBA textures, queue32,2stamps+1receiver upload. До56+18=74МиБ
CPU+GPU page storage, ~8.3МиБ source cache. Один overlay pass на receiver,
до12 дополнительных passes, без физики/узлов на каждый след. Idle processing
выключен. LRU удаляет старые следы и восстанавливает материал. Чужой
material_overlay не заменяется.128px грани ограничивают мелкие детали больших
стёкол; bounds projection может давать стыки на округлой колонне. Кровь и
старые furniture wood marks остаются отдельными прежними системами.

## Проверки 18.10.2026

Godot4.7.2, восстановленный main892c25a:

- Headless18/18 PASS: baked_surface_decal, glass_crack, glass_floor_debris,
  material_floor_debris, display, electronics_hit, floor_batch, office_breakage,
  destruction_fixes, projectile_step_budget, penetration_exit,
  impact_geometry_index, grenade_vfx, surface_decal_options, layout_loading,
  layout_bake, world_bindings, полный planning_mode save/load/restore/exit.
- Новый suite дополнительно проверяет alpha без изменения PNG, mipmaps,
  soot mask без белой каймы, floor layers, receiver LRU/idle/visibility,
  реальные glass/monitor/TV и восстановление corner fissures после eviction.
- Native baked_surface_decal + surface_decal_options PASS в Compatibility/
  OpenGL Mesa llvmpipe и настоящем Forward+/Vulkan1.3 llvmpipe LLVM17.
  Реальные shader pixels проверены отдельно в областях стены, стекла и пола;
  screenshot Forward+ просмотрен. Native fixture изолирует новые shaders;
  реальные игровые model hooks проверяются headless веткой.
- Editor import exit0 без SCRIPT ERROR/ERROR; project/spec/workflow/
  architecture/source-size/CI177 registrations и383 scene refs PASS, diff-check PASS.
  Большие roots reviewed как adapters; исключений нет.

Software native QA не доказывает аппаратный FPS. Вручную проверить Iris Xe и
Web: несколько соседних стёкол, TV/monitor, колонны, слои мусора, толпу и
размер/непрозрачность после сохранения и повторной загрузки карты.
