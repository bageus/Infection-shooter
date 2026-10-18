# Мусор материалов на полу

## Проверяемое поведение

- Книги, папки, листы — оба paper atlas; книжные стопки сохраняют разлёт книг.
- Коробки — преимущественно cardboard, немного бумаги/дерева/пластика.
- Столы и деревянные объекты — оба wood atlas с бумагой и редкими добавками.
- Кресла/диваны — ткань с пластиком/деревом; перегородки — дерево/ткань/бумага.
- Электроника — пластик, дисплеи/TV дополнительно стекло.
- Огнетушитель — несколько красных фрагментов только при разрыве; стол —
  единичная красная добавка максимум один раз на все стадии.
- Контуры независимы: ближние/средние/дальние пятна, редкие и меньшие вдали,
  случайные хвосты слева/справа. Лимиты и направление как у glass scatter.

## Автоматизация

`run_material_floor_debris_tests.gd` запускается headless и в native
Compatibility/Forward+ CI. Проверяет оба paper/wood набора, прозрачные поля,
видимые ячейки, индивидуальную шероховатость, shared memory/queue/idle,
фактические destruction hooks и native floor shader. Glass suite сохраняет
120 seeded profile checks, seams, holes и реальные стеклянные сцены.

## Ограничения и ручная приёмка

Декоративный мусор запекается сразу без ожидания падения. Только базовый пол,
не поверхность столов/лестниц/ковров. Старые следы могут вытесняться при
превышении16 секций; очередь64 общая для всех материалов. До40МиБ CPU+GPU
для color+R8 sections, около4.9МиБ CPU source cache; нет новых draw calls и
физических объектов. Один section upload означает две текстуры, не одну.

В игре сравнить несколько соседних одинаковых столов/коробок, прострелить
монитор и TV, порвать книгу/папку, разрушить кресло/перегородку, взорвать
огнетушитель. Убедиться, что бумага матовая, стекло блестит, хвосты различаются,
повторные выстрелы в уже разрушенный объект не добавляют бесконечный мусор.
Аппаратный FPS на Iris Xe и Web отдельно: software renderer не доказывает
производительность устройства.

## Результат 18.10.2026

Godot4.7.2: material/glass floor suites, office_breakage, staged_glb, glass_crack,
blast_break, debris, electronics_hit, destruction_fixes, prop_weight и
world_bindings — PASS. Последний world_bindings без SCRIPT ERROR после фикса
typed-empty recipe у nonscreen electronics; отдельный regression включён.
Реальная legacy table сцена проверена вместе с обычным staged table.
Native material+glass suites — PASS в Compatibility/OpenGL и настоящем
Forward+/Vulkan Mesa llvmpipe, изображение7материалов просмотрено. Нет
SCRIPT ERROR/ERROR/ObjectDB/RID при завершении. Native fixture останавливает
звук и ждёт release playback перед выходом.
Editor import exit0; project/spec/workflow/architecture/source-size/CI175
registrations/383 scene refs/diff — PASS. Iris Xe/Web остаются ручной приёмкой.
