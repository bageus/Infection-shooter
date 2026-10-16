# A06 — метки только живых заражённых

Дата: 16.10.2026. База main `3d4a9ab7`, Godot4.7.2 stable, Linux.

## Поведение

`presentation.prototype_hud/radar.gd` читает только непосредственных детей
уже переданного контейнера Enemies. Метка разрешена, если это Node3D,
состоящий в существующей группе `infected_alive`, видимый в дереве и ещё
не поставленный в очередь удаления. Жизнью и группой по-прежнему владеет
features.infected: `_die` синхронно удаляет членство до запуска эффектов трупа.
HUD не копирует health/is_dead и не собирает глобальный список SceneTree.

Сохранённые/вытесненные трупы, оторванные части и посторонние узлы не дают
меток. Явно скрытый живой корень/предок также исключается. Выход живого врага
за пределы камеры/радиуса радара не скрывает метку: прежнее прижатие к краю
и world_radius18м сохранены. Формы, цвета, ориентация, частота до20Гц,
фон/resize и pause behaviour прежние. Public API, сцены, ресурсы, DTO,
владельцы и зависимости модулей не изменены; архитектурных исключений нет.

## Доказательство и проверки

- Существующий `run_radar_tests.gd` расширен перехватом настоящего `_draw_blip`.
  В native rendering он вызывается настоящим `_draw`, headless вызывает только
  его внутренний проход по меткам, без Canvas draw вне render callback.
  Не ослаблены прежние cadence/hide/resume/resize assertions.
- Новые случаи: живой враг, видимый и скрытый труп, часть, посторонний Node3D,
  non-spatial Node в alive group, скрытый живой, queued enemy,
  alive из другого контейнера, удаление/добавление членства, живой вне frustum,
  скрытие/показ общего предка. Ожидаются точные координаты/число меток.
- A/B с тем же расширенным suite в реальном OpenGL Compatibility/Mesa llvmpipe:
  **исходный radar.gd —7 failures, исправленный —0**. Подменялся только
  production radar.gd; остальные код/fixtures/assertions одинаковы.
  Оба запуска имеют предупреждение V-Sync software driver; у исправленного
  SCRIPT ERROR/ERROR и ObjectDB warnings нет.
- Новый `bootstrap/app/tests/run_radar_lifecycle_tests.gd` использует публичные
  сцены радара и Hunger и тот же production-предикат. Настоящий spawn/show/hide,
  sever с частью в Enemies, смерть от пули, удержание видимого тела,
  реальное вытеснение через corpse budget, поздний spawn, queued deletion,
  очистка бюджета —0 failures, ObjectDB warnings нет. Suite добавлен в CI.
- Headless suites: radar, radar_lifecycle, armor_hud, world_bindings,
  occlusion, corpse_budget, ragdoll_budget, corpse_physics —8 PASS.
- `validate_project.py` (READY spec/workflow/architecture/scene/source size)
  PASS,121 прежних source-size warnings; resource paths/diff check PASS;
  Godot headless editor import PASS.

Локальный Forward+ запуск не засчитан: окружение не имеет Vulkan ICD/
VK_KHR_surface, поэтому движок переключился на Compatibility. Существующий
CI уже запускает расширенный radar suite в Compatibility и Forward+.
Windows/Web вручную не проверены. Изменение исправляет выбор целей,
прирост FPS этим проходом не измерялся и не заявляется.
