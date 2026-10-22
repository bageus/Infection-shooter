extends RefCounted

const DISPLAY := preload("res://game/bootstrap/app/menu/display_settings.gd")
const SHADOWS := preload("res://game/bootstrap/app/menu/shadow_quality.gd")
const BINDINGS := preload("res://game/bootstrap/app/menu/control_bindings.gd")
const UI_TRANSLATIONS := preload("res://game/core/localization/public/ui_translations.gd")
const CORPSE_BUDGET := preload("res://game/features/infected/public/corpse_budget.gd")
const ENEMY_DIFFICULTY := preload("res://game/features/infected/public/enemy_difficulty.gd")
const ENEMY_TUNING := preload("res://game/features/infected/public/enemy_tuning.gd")
const BLOOD_LEVEL := preload("res://game/core/vfx/public/blood_level.gd")
const EFFECTS_QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const DESTRUCTION_QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
var bindings := BINDINGS.new()

const FILE := "user://interface_settings.cfg"
const DEFAULTS := {"window_mode": 0, "resolution": "1280x720", "language": "ru", "brightness": 1.0, "text_scale": 1.0,
	"enemies_ignore_player": false, "enemies_no_damage": false, "enemy_difficulty": 1,
	"walk_speed_multiplier": 1.0, "walk_animation_multiplier": 1.0,
	"enemy_move_speed_multiplier": 1.0, "enemy_animation_multiplier": 1.0,
	"volume": 0.4, "effects_volume": 1.0, "music_volume": 1.0, "menu_music": true, "menu_music_volume": 1.0, "sound": true, "occlusion_mode": 0, "test_mutagen": false, "infinite_antidotes": false, "lighting": true, "game_lights_only": false, "electronic_particles": true, "blood_style": 0, "blood_level": 2, "effects_quality": 2, "destruction_quality": 1, "dodge_animation": 0,
	"bullet_impact_smoke": true, "sunlight": true, "shadows": true, "shadow_quality": 1, "mesh_lod": true, "keep_corpses": true, "floor_hints": true}
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
	values.window_mode = clampi(values.window_mode, 0, 1)
	if values.resolution != "auto" and DISPLAY.CATALOG.parse(values.resolution) == Vector2i.ZERO:
		values.resolution = DISPLAY.CATALOG.DEFAULT
	values.language = "en" if values.language == "en" else "ru"
	values.brightness = clampf(values.brightness, 0.8, 1.4)
	values.occlusion_mode = clampi(values.occlusion_mode, 0, 1)
	values.enemy_difficulty = clampi(values.enemy_difficulty, ENEMY_DIFFICULTY.LOW, ENEMY_DIFFICULTY.HIGH)
	values.blood_style = clampi(values.blood_style, 0, 1)
	values.blood_level = clampi(values.blood_level, 0, BLOOD_LEVEL.COUNT - 1)
	values.effects_quality = clampi(values.effects_quality, 0, EFFECTS_QUALITY.COUNT - 1)
	values.destruction_quality = clampi(values.destruction_quality, 0, DESTRUCTION_QUALITY.COUNT - 1)
	values.dodge_animation = clampi(values.dodge_animation, 0, 1)
	values.walk_speed_multiplier = clampf(values.walk_speed_multiplier, 0.5, 1.5) if is_finite(values.walk_speed_multiplier) else 1.0
	values.walk_animation_multiplier = clampf(values.walk_animation_multiplier, 0.5, 2.0) if is_finite(values.walk_animation_multiplier) else 1.0
	values.enemy_move_speed_multiplier = ENEMY_TUNING.clamp_multiplier(values.enemy_move_speed_multiplier)
	values.enemy_animation_multiplier = ENEMY_TUNING.clamp_multiplier(values.enemy_animation_multiplier)
	values.shadow_quality = clampi(values.shadow_quality, 0, SHADOWS.level_count() - 1)
	values.volume = clampf(values.volume, 0.0, 1.0)
	values.effects_volume = clampf(values.effects_volume, 0.0, 1.0)
	values.music_volume = clampf(values.music_volume, 0.0, 1.0)
	values.menu_music_volume = clampf(values.menu_music_volume, 0.0, 1.0)
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
func apply_to_game(tree: SceneTree, display_user_action: bool = false) -> void:
	if tree != null:
		DISPLAY.apply_to(tree.root, values, display_user_action)
	bindings.apply()
	UI_TRANSLATIONS.apply_language(str(values.language))
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
	var menu_bus := AudioServer.get_bus_index(&"MenuMusic")
	if menu_bus >= 0:
		AudioServer.set_bus_volume_db(menu_bus, linear_to_db(maxf(float(values.menu_music_volume), 0.0001)))
		AudioServer.set_bus_mute(menu_bus, not bool(values.menu_music) or float(values.menu_music_volume) <= 0.0)
	EFFECTS_QUALITY.set_level(int(values.effects_quality))
	DESTRUCTION_QUALITY.set_level(int(values.destruction_quality))
	var scene := tree.current_scene if tree != null else null
	if scene != null and scene.has_method("refresh_control_labels"):
		scene.call("refresh_control_labels")
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment if scene != null else null
	if world != null and world.environment != null:
		world.environment.adjustment_enabled = true
		world.environment.adjustment_brightness = float(values.brightness)
	if scene != null and scene.has_method("set_enemy_gameplay_modes"):
		scene.call("set_enemy_gameplay_modes", bool(values.enemies_ignore_player), bool(values.enemies_no_damage))
	if scene != null and scene.has_method("set_test_mutagen_enabled"):
		scene.call("set_test_mutagen_enabled", bool(values.test_mutagen))
	if scene != null and scene.has_method("set_infinite_antidotes_enabled"):
		scene.call("set_infinite_antidotes_enabled", bool(values.infinite_antidotes))
	if scene != null and scene.has_method("set_floor_hints_enabled"):
		scene.call("set_floor_hints_enabled", bool(values.floor_hints))
	if scene != null and scene.has_method("set_blood_level"):
		scene.call("set_blood_level", int(values.blood_level), int(values.blood_style) == 1)
	if scene != null and scene.has_method("set_dodge_animation_style"):
		scene.call("set_dodge_animation_style", int(values.dodge_animation))
	if scene != null and scene.has_method("set_walk_tuning"):
		scene.call("set_walk_tuning", float(values.walk_speed_multiplier), float(values.walk_animation_multiplier))
	if scene != null and scene.has_method("set_electronic_particles_enabled"):
		scene.call("set_electronic_particles_enabled", bool(values.electronic_particles))
	var impacts := scene.get_node_or_null("ImpactEffects") if scene != null else null
	if impacts != null:
		impacts.set("bullet_smoke_enabled", bool(values.bullet_impact_smoke))
	var lighting := scene.get_node_or_null("PlanningLighting") if scene != null else null
	if lighting != null:
		lighting.call("set_local_lights_enabled", bool(values.lighting))
		lighting.call("set_game_lights_only", bool(values.game_lights_only))
	var overhead := scene.get_node_or_null("GlobalOverheadLight") as DirectionalLight3D if scene != null else null
	if overhead != null:
		# Hiding the source removes its light and shadows without changing shader variants.
		overhead.visible = bool(values.lighting) and bool(values.sunlight) and not bool(values.game_lights_only)
	SHADOWS.apply(tree, bool(values.shadows), int(values.shadow_quality))
	if tree != null:
		# 0 turns automatic mesh LOD off; 1 is the engine default. No shader recompile.
		tree.root.mesh_lod_threshold = 1.0 if values.mesh_lod else 0.0
	CORPSE_BUDGET.keep = bool(values.keep_corpses)
	ENEMY_DIFFICULTY.level = int(values.enemy_difficulty)
	ENEMY_TUNING.move_multiplier = float(values.enemy_move_speed_multiplier)
	ENEMY_TUNING.animation_multiplier = float(values.enemy_animation_multiplier)
	if tree != null:
		ENEMY_TUNING.drive_live_enemies(tree)
	var occlusion := scene.get_node_or_null("OcclusionEffects") if scene != null else null
	if occlusion != null:
		occlusion.call("set_mode", int(values.occlusion_mode))
