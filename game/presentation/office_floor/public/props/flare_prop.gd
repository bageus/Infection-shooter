extends Node3D
## Floor flare. Unlit until the player comes close, then it burns red: light is brightest
## beside it and falls off with distance. The planner switch can keep it dark for good.

const BUDGET_LIGHT := preload("res://game/presentation/office_floor/budget_omni_light.gd")
const IGNITE_DISTANCE := 2.5
const LIGHT_COLOR := Color(1.0, 0.12, 0.08)
const LIGHT_ENERGY := 1.6
const LIGHT_RANGE := 4.5
const FADE_SECONDS := 0.6

var _ignites := true
var _lit := false
var _glow := 0.0
var _light: OmniLight3D


func _ready() -> void:
	_light = BUDGET_LIGHT.create(LIGHT_COLOR, LIGHT_ENERGY, LIGHT_RANGE)
	_light.position = Vector3(0.0, 0.1, 0.0)
	_light.light_energy = 0.0
	_light.call("set_wanted", false)
	add_child(_light)


func _process(delta: float) -> void:
	if not _lit:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if not _ignites or player == null or player.global_position.distance_to(global_position) > IGNITE_DISTANCE:
			return
		_lit = true
		_light.call("set_wanted", true)
	_glow = move_toward(_glow, 1.0, delta / FADE_SECONDS)
	_light.light_energy = LIGHT_ENERGY * _glow
	if _glow >= 1.0:
		set_process(false)


## Planner switch: false keeps the flare dark for the whole mission.
func set_flare_enabled(enabled: bool) -> void:
	_ignites = enabled


func is_flare_enabled() -> bool:
	return _ignites
