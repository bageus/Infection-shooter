# ADR-0066: пресеты площадок и Autoload Platform

Статус: принято прямым запросом владельца 27.10.2026.

## Решение

Одна кодовая база для itch, Яндекс Игр и десктопа. Площадка задаётся
пресетом экспорта Godot с custom feature tag: «Web itch» (`itch`) и
«Web Yandex» (`yandex`, в head подключён `/sdk.js`). Прежние «Web» и
«Windows Desktop» не меняются (id площадки `desktop`).

Новый модуль infrastructure.platform владеет id площадки и адаптером.
Autoload `Platform` — единственный мост к SDK, разрешён policy для слоя
infrastructure. Остальной код знает только `Platform.id`, `is_yandex()` и
`show_ad()` / сигнал `ad_finished(shown)`. Yandex-адаптер работает через
JavaScriptBridge и опрашивает window-переменные, поэтому колбэки JS не живут
дольше объекта. Тесты используют mock-адаптер без SDK.

bootstrap.app получает `campaign_config.json` (версия 1): режим и список
уровней для каждой площадки; неизвестная площадка берёт `desktop`. Подключение
к выбору уровней и бесконечный режим — следующие PR.

CI экспортирует пакеты обоих новых пресетов отдельным job (platform_presets.yml): job runtime уже упирается в лимит 30 минут.
Состояния игры, DTO, сохранения и существующие владельцы не меняются.
