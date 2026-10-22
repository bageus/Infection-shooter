extends SceneTree
const LOOT := preload("res://game/features/pickups/public/drop_table.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const CATALOG := preload("res://game/features/infection/public/infection_runtime.gd")
var failures := 0

func _initialize() -> void:
	_loot_probabilities()
	_cards()
	print("Issue7 card and loot tests: %d failures" % failures)
	quit(failures)

func _loot_probabilities() -> void:
	var plain := {"ammo": 0, "medkit": 0}
	var boosted := plain.duplicate()
	for sample in 10000:
		var roll := (float(sample) + 0.5) / 10000.0
		for pair in [[plain, 1.0], [boosted, 1.3]]:
			var id := LOOT.roll_item(roll, {"ammo_pistol": 1.0, "medkit": 1.0}, 0.6, pair[1])
			if not id.is_empty():
				pair[0]["ammo" if id.begins_with("ammo_") else "medkit"] += 1
	_check(boosted.ammo == plain.ammo * 1.3, "Recycling raises actual ammo drop chance by thirty percent")
	_check(boosted.medkit == plain.medkit, "Recycling preserves non-ammo drop probabilities")

func _cards() -> void:
	var catalogue := CATALOG.new()
	var old_locale := TranslationServer.get_locale()
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for row in catalogue.skill_catalog():
			var text := TEXT.description(str(row[0]))
			_check(not text.contains("{") and not text.begins_with("mutationSkill_"), "Every card resolves localized tuning: " + str(row[0]))
	TranslationServer.set_locale("ru")
	_check(TEXT.description("bone_armor").contains("23%"), "Bone Armor rounds only its displayed percentage")
	TranslationServer.set_locale(old_locale)
	catalogue.free()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
