# Surface/pose: native audio teardown — 2026-10-25

База: main `303904d65af40818211ce9e0445159d3bafbd99c`, после merge PR #468. Task T004, Phase 1 / P1_LOGIC, Implementation. Scope — bootstrap test fixture и диагностика workflow; production поведение не меняется.

## Наблюдение CI

Run `40196456111`, job `121178426333` (Mission runtime regressions): все 223 headless suites PASS. Native surface_pose в Compatibility завершает assertions с 0 failures, затем движок сообщает 4 leaked ObjectDB instances и 2 resources still in use. Остальные native suites, включая Forward+, прошли. Строгий CI error/leak gate оставлен без изменений.

## Диагностика и исправление

В локальном native X11/Compatibility запуске WeakRef к активному playback музыки всё ещё жив после прежних двух process_frame, хотя сцена уже удалена: `AudioStreamPlaybackOggVorbis`, до следующего mix около 48 ms. Headless ветка music_crossfade не запускает native playback, поэтому не воспроизводит это условие. Сам исходный shutdown ERROR локально зависит от тайминга: baseline и четыре повторения завершились без leak; наблюдаемое удержание playback подтверждено отдельно.

Fixture записывает WeakRef к собственным активным AudioStreamPlayer / 2D / 3D playback перед удалением сцен и перед quit ждёт их освобождения, максимум 1000 ms. Оставшийся playback вызывает assertion failure, а не скрывается. Native probe удерживает реальный OGG playback на 50 ms через timer, моделируя позднее освобождение mixer ownership. Он проверяет, что ожидание действительно выполнено. Никаких новых пакетов проекта, новых зависимостей модулей, API/DTO или изменений звука игры.

CI включает `--verbose` только для native surface_pose, чтобы повторный leak показывал конкретные классы и resource paths. Exit code и существующий error scan сохранены.

## Проверки

Pinned Godot 4.7.2 stable (`ed1daf0bf`), Xvfb TCP, Mesa llvmpipe; вспомогательные renderer tools находятся вне репозитория.

- Fault injection с прежним завершением: 2 failures (ожидание playback и deferred ownership), как и ожидалось.
- Исправленная Compatibility: 0 failures, 2 tracked voices, ожидание 54 ms; без ERROR / leaked / resources still in use.
- Headless surface_pose, music_shutdown, world_bindings: каждый exit 0, без ошибок/утечек.
- Headless editor import: exit 0, без ERROR.
- `python tools/validate_project.py`: PASS, включая архитектуру, workflow/spec, source-size и регистрацию 231 suites (223 runtime + 8 explicit).
- `python tools/check_resource_paths.py`: PASS.
- `python tools/validate_scene_resources.py`: PASS, 387 references.
- `python tools/test_ci_suite_coverage.py`: 11 tests PASS.
- `python tools/test_runtime_suite_runner.py`: 3 tests PASS.
- `git diff --check`: PASS.

Первый запуск с аргументом forward_plus переключился на OpenGL из-за отсутствующего Vulkan ICD и не засчитан как Forward+ validation. Результат отдельного настоящего Vulkan-прогона фиксируется ниже. Полный GitHub CI нового PR требуется после публикации; результаты прежнего run не выдаются за проверку нового commit.

Настоящий Forward+ подтверждён строкой `Vulkan 1.4.318 - Forward+ - Using Device #0: Unknown - llvmpipe (LLVM 20.1.2, 256 bits)`: exit 0, 0 failures, 2 tracked voices, ожидание 44 ms; без ERROR / leaked / resources still in use.
