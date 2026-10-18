# Режимы врагов — 18.10.2026

General / Основные: два независимых переключателя с RU/EN подписями и
подсказками. Оба выключены по умолчанию, сохраняются и возвращаются к false
через Reset. Старые или неверно типизированные ключи сохраняют обычный режим.

- «Враги игнорируют игрока»: продолжают idle wandering; sight, proximity,
  noise, ally cries, hits и forced chase не агрят. Уже начатая погоня/отложенный
  удар прекращаются до следующей симуляции атаки. Новые/призванные враги
  читают те же текущие правила цели. Отключение восстанавливает forced chase
  призванных либо обычное обнаружение authored-врагов.
- «Враги не наносят урон»: преследование/анимации/звуки атак обычные, но swipe,
  Horde ram и Colossus wave не вызывают HP-команду цели. Ignore тоже блокирует
  ранее выпущенную волну. Урон игрока врагам, разрушения и самоурон прежние.

## Проверки — PASS

Godot4.7.2, без SCRIPT ERROR/ERROR:
- enemy_gameplay_modes: Hunger/Revenant/Horde/Colossus, proximity/shot/noise/
  alert/forced, сохранение движения и полученного урона, live on/off,
  отмена pending attack, no-damage swipe/ram/in-flight wave и defaults.
- settings_tabs: General UI, tooltip, toggle, reload/reset, malformed values,
  фактическая bootstrap-инъекция в цель; прежние controls/display checks.
- enemy_perception, hunger_behaviour, horde_escalation: обычные правила сохранены.
- editor import; validate_project (spec/workflow/architecture/source size и
 176 зарегистрированных suites); scene resource references; diff check.

Владельцы: bootstrap — настройки и mission target metadata_v1; infected —
восприятие/атаки. ADR0059/manifests описывают additive target contract.
Новых зависимостей/Autoload/map DTO/исключений policy нет. Root infected598;
perception остаётся единым владельцем awareness/target assignment, фильтрация
команд урона отделена в private helper. Main только внедряет настройки.

Ручная Windows/Web приёмка UI в бою остаётся. Владелец поручил создание PR;
следующее действие — проверить его CI и ручной сценарий.
