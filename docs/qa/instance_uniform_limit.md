# Лимит instance uniform: 256 объектов

Ошибка `global_shader_parameters_instance_allocate: Too many instances using shader
instance variables ... Maximum items supported by this hardware is: 4096` приходит
из-за того, что Godot резервирует 16 записей буфера (максимум instance uniform на
объект) под каждый объект с `instance uniform`, независимо от числа переменных.
На OpenGL буфер ограничен 4096 записями, поэтому одновременно живых объектов с
instance uniform не больше 256. Увеличение `rendering/limits/global_shader_variables/buffer_size`
не помогает: это аппаратный предел.

Проверка (Godot 4.7.2, opengl3, xvfb): 600 MeshInstance3D с шейдером с одним
`instance uniform` дают 344 ошибки, то есть принимаются 256.

Что занимало слоты: каждое тело врага (`blood_layer`), его два слоя облака мутагена
(`progress`, `phase`, ...) и каждая меш-поверхность под ядом (`fade`). Трупы,
которые остаются на уровне (до 60), плюс до 90 живых врагов исчерпывали лимит
примерно за 9 минут игры.

Исправление: тела, облака и яд используют обычные параметры материала, у каждого
объекта свой материал. Остались instance uniform у короткоживущих эффектов
(`flipbook`, `skill_fx`, `range_dome`, `berserk_eyes`): их одновременно живёт мало.
Новые постоянные или массовые объекты не должны использовать `instance uniform`.
