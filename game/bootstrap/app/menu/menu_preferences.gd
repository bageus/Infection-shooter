extends RefCounted

const BINDINGS := preload("res://game/bootstrap/app/menu/control_bindings.gd")
var bindings := BINDINGS.new()

const FILE := "user://interface_settings.cfg"
const DEFAULTS := {"language": "ru", "brightness": 1.0, "text_scale": 1.0,
	"volume": 0.4, "effects_volume": 1.0, "music_volume": 1.0, "sound": true, "occlusion_mode": 0, "test_mutagen": false, "electronic_particles": true}
var values: Dictionary = DEFAULTS.duplicate()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(FILE) != OK:
		return
	bindings.load_config(config)
	for key in DEFAULTS:
		var value: Variant = config.get_value("interface_v1", key, DEFAULTS[key])
		if typeof(value) == typeof(DEFAULTS[key]):
			values[key] = value
	values.language = "en" if values.language == "en" else "ru"
	values.brightness = clampf(values.brightness, 0.8, 1.4)
	values.occlusion_mode = clampi(values.occlusion_mode, 0, 1)
	values.volume = clampf(values.volume, 0.0, 1.0)
	values.effects_volume = clampf(values.effects_volume, 0.0, 1.0)
	values.music_volume = clampf(values.music_volume, 0.0, 1.0)
	if values.text_scale not in [1.0, 1.15, 1.3]:
		values.text_scale = 1.0


func save_settings() -> Error:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("interface_v1", key, values[key])
	bindings.save_config(config)
	return config.save(FILE)


func reset() -> void:
	values = DEFAULTS.duplicate()
	bindings.reset()


## Applies the settings to the running game, not just the menu: master
## volume (the default 0.4 keeps the authored mix at 0 dB, up to +6 dB),
## sound on/off and the 3D scene brightness.
func apply_to_game(tree: SceneTree) -> void:
	bindings.apply()
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, not bool(values.sound))
		AudioServer.set_bus_volume_db(master, linear_to_db(clampf(float(values.volume) / float(DEFAULTS.volume), 0.0001, 2.0)))
	for bus_name in [&"SFX", &"UI", &"Music"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			var level := float(values.music_volume if bus_name == &"Music" else values.effects_volume)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.0001)))
			AudioServer.set_bus_mute(index, level <= 0.0)
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.has_method("refresh_control_labels"):
		scene.call("refresh_control_labels")
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment if scene != null else null
	if world != null and world.environment != null:
		world.environment.adjustment_enabled = true
		world.environment.adjustment_brightness = float(values.brightness)
	if scene != null and scene.has_method("set_test_mutagen_enabled"):
		scene.call("set_test_mutagen_enabled", bool(values.test_mutagen))
	if scene != null and scene.has_method("set_electronic_particles_enabled"):
		scene.call("set_electronic_particles_enabled", bool(values.electronic_particles))
	var occlusion := scene.get_node_or_null("OcclusionEffects") if scene != null else null
	if occlusion != null:
		occlusion.call("set_mode", int(values.occlusion_mode))
