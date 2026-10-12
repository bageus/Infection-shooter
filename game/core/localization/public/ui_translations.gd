extends RefCounted
## Registers the one UI string table (assets/interface/translations.json) with TranslationServer.
## Menus and the in-game HUD both resolve text with tr(key); the language setting only picks the locale.
## To add a string: add the same key under "ru" and "en" in translations.json, then call tr(key) in code.

const TABLE_PATH := "res://assets/interface/translations.json"
static var _registered := false


## Safe to call from any scene; the table is registered once.
static func ensure_registered() -> void:
	_register_once()


static func apply_language(language: String) -> void:
	_register_once()
	TranslationServer.set_locale("en" if language == "en" else "ru")


static func _register_once() -> void:
	if _registered:
		return
	_registered = true
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	for locale: String in table:
		var translation := Translation.new()
		translation.locale = locale
		var messages: Dictionary = table[locale]
		for key: String in messages:
			translation.add_message(key, str(messages[key]))
		TranslationServer.add_translation(translation)
