extends RefCounted

const FILE := "user://interface_settings.cfg"
const DEFAULTS := {"language": "ru", "brightness": 1.0, "text_scale": 1.0,
	"volume": 0.4, "sound": true}
var values: Dictionary = DEFAULTS.duplicate()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(FILE) != OK:
		return
	for key in DEFAULTS:
		var value: Variant = config.get_value("interface_v1", key, DEFAULTS[key])
		if typeof(value) == typeof(DEFAULTS[key]):
			values[key] = value
	values.language = "en" if values.language == "en" else "ru"
	values.brightness = clampf(values.brightness, 0.8, 1.4)
	values.volume = clampf(values.volume, 0.0, 1.0)
	if values.text_scale not in [1.0, 1.15, 1.3]:
		values.text_scale = 1.0


func save_settings() -> Error:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("interface_v1", key, values[key])
	return config.save(FILE)


func reset() -> void:
	values = DEFAULTS.duplicate()
