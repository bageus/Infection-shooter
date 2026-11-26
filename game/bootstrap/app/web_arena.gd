extends RefCounted
## Mission hooks of the wave director's modes: the platform's endless level, and the web arena
## ("Wave N" caption before each wave, clearing the Horde wave completes the level).
const CAMPAIGN := preload("res://game/bootstrap/app/campaign_config.gd")
const PLATFORM := preload("res://game/infrastructure/platform/public/platform.gd")
const MAP_MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")
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


static func _announce(wave: int, is_boss: bool, main: Node) -> void:
	var caption: CanvasLayer = LEVEL_CAPTION.new()
	caption.caption = main.tr("webWaveHorde") if is_boss else main.tr("webWave") % wave
	caption.seconds = 2.0
	main.add_child(caption)


static func _complete(main: Node) -> void:
	if not bool(main.get("_ended")) and not bool(main.get("_dying")):
		main.call("_end_run", "MISSION COMPLETE")
