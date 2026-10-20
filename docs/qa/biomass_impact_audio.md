# Звук попадания в настенную биомассу

Запрос владельца20.10.2026, основа main188b0b1, T004/Phase1/P1_LOGIC.

`assets/audio/sfx/biomass/Thudding_impact_of_b.wav` (384078bytes,2s,stereo48kHz) преобразован штатным converter в OGG Vorbisq5/mono48kHz (24917bytes,2s). Штатные микрофейды5мс и ограничение пика, без обрезки длительности/синтеза вариантов. SHA256/параметры записаны в glass_audio_processing.json; WAV удалён после проверки декодирования.

core.audio добавляет hit_biomass. office_floor через существующий surface_decal_events.hit играет позиционный удар при попадании в непрозрачную часть настенной биомассы, поверх существующего звука основания. Private BiomassImpactAudio хранится в decal, на внедрённом projection anchor находятся только WeakRef. Проверяются текущий transform, нормаль, plane distance, visible mesh bounds и alpha atlas либо текущей fused texture. Объединённые мосты озвучиваются, скрытые члены не дублируют звук. Удаление и перепривязка снимают регистрацию. Нет обхода всей карты, новых process/physics callbacks или физических тел. Рендеринг/коллизии/баланс, owners/API/DTO/dependencies/policy прежние.

Проверено на Godot4.7.2 headless:

- editor import exit0 без SCRIPT ERROR/ERROR;
- validate_game_spec/workflow --ready, validate_project, check_import_files979, validate_scene_resources: PASS;
- convert_runtime_audio --check:11receipts, SHA256/decode/OGG-only PASS;
- test_audio_generation:18tests PASS;
- run_biomass_tests:0failures, включая полный bullet→impact_pool→floor surface hit→sound, alpha/голую стену, позицию, movement, deletion, fused bounds/alpha/hidden members;
- run_sound_event_tests, run_blood_decor_tests, run_biomass_catalog_tests:0failures;
- git diff --check: PASS.

Native прослушивание не выполнялось. Изменения карты и GLB отсутствуют. Следующее действие — CI PR и ручная проверка громкости в игре; слияние не запрошено.
