# ADR-0052: Отдача, hit drag и отключаемый дым пуль

- Status: accepted
- Date: 2026-10-16
- Owners: bageus; features.player, features.infected, features.combat, bootstrap.app

## Context and decision

Прямой запрос #219 и комментарий требуют physical recoil, зависимую от силы врага
реакцию корпуса без остановки движения и дым у bullet decals с настройкой.
Величины делегированы владельцем. Числа, affected files и review декомпозиции:
[QA plan](../qa/weapon_recoil_and_impact_smoke.md).
Player private shot_recoil расходует bounded displacement от фактического muzzle;
chase_pace владеет non-stacking temporary hit speed penalty. Существующий notify_hit
сохраняет подпись, directional Hunger hit идёт в spring; остальные overlays прежние.
Spring ограничен14° и bounded angular velocity для очередей.
Combat public impact_effects получает additive bullet_smoke_enabled и
spawn_bullet_smoke(point, normal), описанные bullet_smoke_v1 manifest.
Bootstrap применяет optional bool interface_v1.bullet_impact_smoke (default true)
к уже существующему injected mission-local ImpactEffects. Новый owner/edge не нужен.

## Alternatives

Прямой teleport игрока проходит сквозь стену. Накопление velocity в locomotion
зависит от торможения и частоты кадров. Whole-body flinch прерывает ноги; отдельные
анимации попаданий теряют направление. Stun/stacked drag блокирует погоню очередью.
Unbounded particles и lights неоправданны для слабого дыма. Общий переключатель
электроники скрывает независимые эффекты и не выполняет запрос.

## Migration and rollback

Старые конфиги без ключа/с неправильным типом получают true; старые читатели
игнорируют новое поле. Карты/сохранения кампании, scene paths, gameplay DTO,
публичные подписи damage/animation и module edges прежние. Revert коммита полностью
возвращает прежнее поведение без конвертации данных. Архитектурных исключений нет.

## Validation and approval

Прямое поручение владельца реализовать #219 с выбором величины разрешает эти
additive настройки и контракт. Regression cases: successful/failed shot, направление,
частота кадров/стена/очередь, слабый/сильный враг/DoT/recovery, torso vs legs,
projection/particles budget/disable/cleanup, Video и старый конфиг. Actual результаты
фиксируются в QA и ACTIVE_TASK/PROJECT_STATE.
