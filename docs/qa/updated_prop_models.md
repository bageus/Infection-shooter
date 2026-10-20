# Подключение обновлённых моделей и сохранение цельного корпуса

20.10.2026, прямой запрос владельца, T004/Phase1/P1_LOGIC.
Новые шесть GLB уже присутствуют в main; бинарные файлы не заменяются.

## Обнаружено

Кулер и микроволновка имеют Intact_Whole и LargeParts(Body_Whole + Bottle_01/Door_01).
Обычный breakup превращал оба mesh в физические обломки и убирал исходную
коллизию. Старый bottle-burst определял PET-материал на всём Intact_Whole и мог
скрыть вместе с бутылью корпус. 09_white_board_stand отсутствовал в wall rules.
02_frige_dented был свободным телом, поэтому пули давали ему импульс.
Кейсы и напольная доска уже имеют единственную конечную стадию из двух mesh.

## Изменение

Private retained_prop_body на тех же owners presentation.office_floor восстанавливает
из авторских mesh отдельные intact body/attachment с общими неизменяемыми mesh
resources. Отдельные colliders дают адресное попадание по бутылке/дверце.
Попадание по детали отделяет одну цельную физическую часть; накопленный урон и
граната идут через прежний damage transition и также отделяют только её.
Корпус/его collider остаются, повторное попадание не создаёт новую деталь.
Пустой кулер не разрушается; оба кулера и холодильник anchored. Отдельная
02_water_cooler_bottle сохраняет прежний burst, новый запрос относится к кулеру.
Настенный 09_white_board_stand включён в существующее wall placement/support.
Напольный 09_board_stand_white остаётся напольным и разбивается на Board/Stand.
На авторской карте нет экземпляров 09_white_board_stand: перемещать существующий
объект произвольно не требуется; новые экземпляры используют wall probe/mount.

## Границы и риски

Player/combat rules/API/карты/сохранения/scene paths/dependency edges/policy прежние.
Root environment_prop до изменения598 строк, после592: replaces old bottle-only
adapter, новая логика отделена по одной ответственности. Новых исключений нет.
В существующем destruction suite ожидание burst заменено новым запросом:
одна бутылка, целый anchored корпус. Самостоятельная бутыль не изменялась.
QA использует настоящий catalog и GLB, публичные hit commands и реальные shape
indices. Проверки: targeted/общий урон/повторные hits/terminal fragments, точные
два фрагмента у двух кейсов/доски, wall back-plane и freeze, все fridge variants.

## Проверки и ограничения

Godot4.7.2 финальный editor import exit0, без ERROR/SCRIPT ERROR.
Пять suites updated_prop_models/destruction_fixes/wall_mount_support(26models)/
destruction_sound/prop_weight PASS. Повтор updated_prop_models после возврата
candidate PASS. На исходных environment_prop/wall_mount_models из main тот же
новый regression завершается exit1 с assertion failures; после восстановления
candidate exit0/0failures. Headless main.tscn запускается, 15 кадров, exit0.
validate_project (spec/workflow/architecture/size/CI197suites), scene384refs,
diff-check PASS. Бинарные GLB и авторская карта не изменялись.
Native/Web визуальная приёмка, FPS и проигрывание звуков здесь не заявляются.


## PR381: исправление CI20.10.2026

В run39351670784 runtime упал только общий destruction_wiring: он требовал
_broken и обломки от02_water_cooler_destructible, вопреки новому fixed whole
контракту. На прежнем suite локально воспроизведены ровно2failures. Теперь
точный plain cooler проходит отдельные позитивные проверки послеAK иGRENADE:
целостность, freeze/transform, collision layer и enabled shapes, visible Intact,
отсутствие fragments. Resource/stage wiring остаётся общим и обязательным;
ни один каталоговый объект не пропускается, остальные assertions прежние.
Новый audit230моделей/101staged —0failures; updated_prop_models —0failures.
Godot4.7.2 import exit0 безERROR/SCRIPT ERROR. Production код/модели/публичные
контракты/карты/DTO/owners/edges/policy не менялись. Следующий шаг — CI PR381.
