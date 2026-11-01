extends Node
## Occasional atmosphere from intact props near the player: phones ring, monitors and
## towers hum, coolers and biomass gurgle, a powered screen plays its intro tune. The
## reception counter is silent. A cheap one-second scan of the tagged props.

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const GROUP := &"ambient_sound"
const META := &"ambient_events"
const TICK := 1.0
## One phone beep lasts about a second; the pause after it makes the ring pattern.
const RING_PERIOD := 1.6
# event: [radius m, chance per tick, minimum seconds between plays, once per level]
const RULES := {
	&"phone_ring": [9.0, 0.35, 25.0, false],
	&"pc_hum": [4.0, 0.3, 14.0, false],
	&"cooler_gurgle": [5.0, 0.3, 18.0, false],
	&"biomass_gurgle": [5.0, 0.3, 12.0, false],
	&"display_intro": [6.0, 0.25, 30.0, false],
}
const MODEL_EVENTS := {
	"05_desk_phone.glb": [&"phone_ring"],
	"05_computer_tower_destructible.glb": [&"pc_hum"],
	"05_PC_destructible.glb": [&"pc_hum"],
	"05_minipc.glb": [&"pc_hum"],
	"05_monitor_destructible.glb": [&"pc_hum", &"display_intro"],
	"05_monitor_wide_destructible.glb": [&"pc_hum", &"display_intro"],
	"05_monitor2_destructible.glb": [&"pc_hum", &"display_intro"],
	"05_monitor3_server_destructible.glb": [&"pc_hum", &"display_intro"],
	"05_monitor4_server_destructible.glb": [&"pc_hum", &"display_intro"],
	"05_wall_TV_destructible.glb": [&"display_intro"],
	"05_wall_TV_frameless_destructible.glb": [&"display_intro"],
	"02_water_cooler_destructible.glb": [&"cooler_gurgle"],
	"02_water_cooler_bottle.glb": [&"cooler_gurgle"],
	"02_water_cooler_bottle_attached_destructible.glb": [&"cooler_gurgle"],
}

var player: Node3D
var _wait := randf() * TICK
var _next_allowed: Dictionary = {}
var _done: Dictionary = {}


## Marks a prop (by its model file) as an ambient sound source; no-op for other models.
static func tag(prop: Node, model_path: String) -> void:
	tag_events(prop, MODEL_EVENTS.get(model_path.get_file(), []))


static func tag_events(prop: Node, events: Array) -> void:
	if events.is_empty():
		return
	prop.set_meta(META, events)
	prop.add_to_group(GROUP)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or not is_instance_valid(player):
		return
	_wait = TICK
	var now := Time.get_ticks_msec() * 0.001
	var origin := player.global_position
	for source: Node in get_tree().get_nodes_in_group(GROUP):
		var prop := source as Node3D
		if prop == null or not prop.is_visible_in_tree() or prop.get("_broken") == true:
			continue
		for event: StringName in prop.get_meta(META):
			var rule: Array = RULES[event]
			if origin.distance_squared_to(prop.global_position) > float(rule[0]) ** 2 or not _ready_to_play(event, rule, now) or not _is_active(prop, event):
				continue
			if event == &"phone_ring":
				_ring(prop.global_position, _ring_beeps())
			else:
				SFX.play(self, event, prop.global_position)
			_next_allowed[event] = now + float(rule[2]) * randf_range(1.0, 1.6)
			_done[event] = true


# A phone rings in short bursts: usually one beep, sometimes two or three with pauses.
func _ring_beeps() -> int:
	var roll := randf()
	if roll < 0.6:
		return 1
	return 2 if roll < 0.85 else 3


func _ring(position: Vector3, beeps: int) -> void:
	SFX.play(self, &"phone_ring", position)
	if beeps > 1:
		get_tree().create_timer(RING_PERIOD).timeout.connect(_ring.bind(position, beeps - 1))


func _ready_to_play(event: StringName, rule: Array, now: float) -> bool:
	if bool(rule[3]) and _done.has(event):
		return false
	return now >= float(_next_allowed.get(event, 0.0)) and randf() < float(rule[1])


# Only a powered, animated screen plays its intro; other sources are always active.
func _is_active(prop: Node, event: StringName) -> bool:
	if event != &"display_intro":
		return true
	var display: Object = prop.get("_display")
	if display == null or not bool(display.get("powered")):
		return false
	for screen: Dictionary in display.get("screens"):
		if screen["dynamic"]:
			return true
	return false
