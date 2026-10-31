extends SceneTree

const UI_TRANSLATIONS := preload("res://game/core/localization/public/ui_translations.gd")
const TABLE := "res://assets/interface/translations.json"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	_check(table.has("ru") and table.has("en"), "table has ru and en sections")
	var ru_keys := (table["ru"] as Dictionary).keys()
	var en_keys := (table["en"] as Dictionary).keys()
	ru_keys.sort()
	en_keys.sort()
	_check(ru_keys == en_keys, "ru and en tables use the same keys")

	UI_TRANSLATIONS.apply_language("en")
	_check(TranslationServer.get_locale() == "en", "English setting sets the en locale")
	_check(tr("controlLost") == "CONTROL LOST — MUTATION TAKES OVER", "English HUD string resolves through tr()")
	_check(tr("hudEnemies") % 3 == "ENEMIES 3", "English counter format resolves through tr()")

	UI_TRANSLATIONS.apply_language("ru")
	_check(TranslationServer.get_locale() == "ru", "Russian setting sets the ru locale")
	_check(tr("controlLost") == "КОНТРОЛЬ ПОТЕРЯН — МУТАЦИЯ ВЗЯЛА ВЕРХ", "Russian HUD string resolves through tr()")
	_check(tr("objectiveFireExit") == "Двигайся к пожарному выходу!", "Russian objective resolves through tr()")
	_check(tr("objectiveFindKey") == "Найди ключ от пожарного выхода", "Russian key objective resolves through tr()")
	_check(tr("hudSelectWeapon") % "2" == "Выбрать оружие [2]", "Russian tooltip format resolves through tr()")

	print("UI translation tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
