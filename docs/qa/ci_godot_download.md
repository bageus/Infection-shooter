# Восстановление CI PR206 и PR207 — 16.10.2026

## Причина

- PR206, run38814471542/job116695558349: native skin rendering и comparison PASS; WebGL2 fixture упал в build_web_skin_probe.py на HTTP HEAD экспортного шаблона: HTTP503 Service Unavailable.
- PR207, run38814785723/job116696606440 и impact run38814785823/job116696606586: curl install Godot получил HTTP503 и exit22. Последующие exit127 — отсутствие установленного godot. Игровые тесты в этих jobs не запускались.
- Общая недоступная точка: godot-releases.nbg1.your-objectstorage.com. Архитектурные gates обоих PR PASS. Это не доказательство дефекта A02/A03 и не основание ослаблять assertions.

## Изменение

Все восемь install paths в mission_runtime.yml/impact_geometry.yml вызывают tools/ci_download_godot.sh. Версия прежняя4.7.2. Основной источник — официальный Godot GitHub release, резервный — прежнее официальное зеркало. Curl имеет bounded retries/timeouts; ZIP сначала пишется во временный файл и принимается только с официальным SHA256 cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4. Неполный/повреждённый архив не устанавливается, после отказа обоих источников job падает.

Web RangedArchive делает до3 попыток на каждом из двух официальных источников, включая HEAD и отдельные GET Range. Проверяются статус206, точный Content-Range и длина; позиция сдвигается только после полного чтения. Сервер, проигнорировавший Range, отклоняется до чтения полного TPZ. ZipFile по-прежнему проверяет CRC извлечённого шаблона. Тайм-аут30с на сетевой запрос, backoff1/2с, постоянные HTTP ошибки/неправильный Range переключают источник без лишних повторов. Отказ обоих источников остаётся ошибкой.

## Проверки

- Шесть deterministic tests в tools/test_godot_template_download.py PASS:503 retry/fallback для HEAD, повтор Range без сдвига, отклонение полного ответа, короткий Range, полный отказ, EOF. Включены в enemy-skin CI job.
- Shell recovery с настоящим проверенным ZIP: отказ основного источника → резервный PASS; повреждённый основной архив → резервный PASS; два повреждённых → exit1 без final/partial файла PASS.
- Настоящая загрузка Linux ZIP из официального GitHub PASS; SHA256 совпал с release metadata. Версия и ресурсы движка не меняются.
- Настоящая сборка Web fixture с новым RangedArchive, Godot import и export Web PASS. Рендер Web-браузера локально в этом исправлении не запускался; остаётся проверкой CI.
- validate_project/spec/workflow, resource paths, diff-check и Godot editor import в обеих ветках PASS. Gameplay не менялся; прежние regression suites не ослаблены и не удалены.

Изменены только инструменты CI, workflows и документация; владельцы модулей, public API, сцены/ресурсы/DTO и зависимости прежние. Архитектурных исключений нет. Следующее действие — дождаться новых CI heads обоих PR и проверить фактическое завершение тестов. Merge не поручен.
