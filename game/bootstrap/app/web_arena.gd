extends RefCounted
## Mission hooks of the wave director's modes: the platform's endless level, and the web arena
## ("Wave N" caption before each wave, clearing the Horde wave completes the level).
const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const PLATFORM := preload("res://game/infrastructure/platform/public/platform.gd")
const MAP_MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const WALLET := preload("res://game/bootstrap/app/web_wallet.gd")
const LEVEL_CAPTION := preload("res://game/bootstrap/app/level_caption.gd")


## Safe to call again: the director's signals are connected once.
static func sync(main: Node, director: Node, level: String) -> void:
	if not is_instance_valid(director):
		return
	var campaign := CAMPAIGN.new()
	campaign.load_file()
	director.set("endless", not level.is_empty() and level == campaign.endless_level(PLATFORM.detect_id()))
	director.set("web_source", MAP_MODE.is_web)
	if not director.has_meta(&"web_arena_bound"):
		director.set_meta(&"web_arena_bound", true)
		director.connect("wave_announced", _announce.bind(main))
		director.connect("arena_cleared", _complete.bind(main))
		var enemies: Node = main.get("enemies")
		enemies.child_entered_tree.connect(_watch_kills.bind(main))
		for enemy in enemies.get_children():
			_watch_kills(enemy, main)
		main.tree_exiting.connect(WALLET.flush)


## Every infected placed or spawned pays coins on its death (web maps only); a Horde's summons pay nothing.
static func _watch_kills(enemy: Node, main: Node) -> void:
	if enemy.has_signal("blood_death") and not enemy.has_meta("summoned_by"):
		enemy.connect("blood_death", _paid.bind(enemy, main))


static func _paid(_position: Vector3, _excluded: Array, _death_id: int, enemy: Node, main: Node) -> void:
	if MAP_MODE.is_web():
		WALLET.add_kill(_kind(enemy.scene_file_path))
		_show_coins(main)


static func _kind(scene_path: String) -> String:
	for kind: String in SPAWN_CONFIG.ENEMY_SCENES:
		if SPAWN_CONFIG.ENEMY_SCENES[kind] == scene_path:
			return kind
	return "hunger"


## Coin counter in the top right corner, created on first use.
static func _show_coins(main: Node) -> void:
	var label: Label = main.get_meta(&"web_coins_label") if main.has_meta(&"web_coins_label") else null
	if label == null:
		var layer := CanvasLayer.new()
		layer.layer = 50
		label = Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		label.offset_left = -240.0
		label.offset_top = 12.0
		label.offset_right = -16.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		layer.add_child(label)
		main.add_child(layer)
		main.set_meta(&"web_coins_label", label)
	label.text = main.tr("webCoins").replace("%d", str(WALLET.coins()))


static func _announce(wave: int, is_boss: bool, main: Node) -> void:
	var caption: CanvasLayer = LEVEL_CAPTION.new()
	caption.caption = main.tr("webWaveHorde") if is_boss else main.tr("webWave").replace("%d", str(wave))
	caption.seconds = 2.0
	main.add_child(caption)
	_show_coins(main)


static func _complete(main: Node) -> void:
	WALLET.flush()
	if not bool(main.get("_ended")) and not bool(main.get("_dying")):
		main.call("_end_run", "MISSION COMPLETE")
