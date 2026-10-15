# Web fallback для скинов врагов (WebGL2)

Причина: в Godot 4.7.2 instance uniform UBO на WebGL2 отдаёт слой крови 0 чистым соседям
(godotengine/godot#112674, исправлено в 4.8). Проба `tools/web_skin_probe.gd` падала с `clean neighbor`.

Решение (версия движка и зависимости не менялись):
- На Web (`OS.has_feature("web")`) `BodySkinMaterials.acquire()` выдаёт каждому телу собственные
  материалы и собственную одно-слойную страницу `Texture2DArray`; `blood_layer` - обычный параметр материала.
- Шейдер для Web собирается из `body_wound.gdshader` заменой одной строки объявления
  (instance uniform -> uniform), поэтому исходник один, native-шейдер не изменён.
- Native-путь (общие материалы на страницу, 128 слоёв, instance uniform) не менялся.
- `Lease.materials` и `Lease.selector()` скрывают различие для вызывающего кода и тестов.

Проверено локально (Godot 4.7.2, gl_compatibility под xvfb, llvmpipe):
- run_shared_skin_tests (включая новый тест per-body пути), run_enemy_animation_tests,
  run_body_mesh_cache_tests, run_dismemberment_tests, run_body_blood_bake_tests,
  run_body_topology_tests, run_blood_events_tests, run_infected_voice_tests: 0 ошибок.
- Проба на native и с принудительным per-body путём: `errors: []`.
- editor import: без ошибок.

Не проверено локально: настоящий Web-экспорт и запуск в браузере (нет шаблонов экспорта и Chrome).
Это подтверждает CI (job enemy-skin-rendering, шаг WebGL2).
