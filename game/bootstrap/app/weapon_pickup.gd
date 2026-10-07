extends Node3D

const ART := preload("res://game/features/combat/public/launcher_visual.gd")
const BADGE := preload("res://game/core/world_badge/public/world_badge.gd")
const ACTION := "pickup_weapon"

@export_range(0, 3) var weapon_index := 3
var _base_position := Vector3.ZERO
var _time := 0.0
var _hint: Node3D


func _ready() -> void:
	add_to_group("weapon_pickups")
	_base_position = global_position
	var art := ART.make_pickup_visual(weapon_index)
	add_child(art)
	art.scale = Vector3.ONE * 0.9
	art.position.y = 0.0
	# Pick-up prompt: the bound key as a HUD key cap that keeps "pressing".
	_hint = BADGE.key(binding_label(), 0.78)
	_hint.visible = false
	add_child(_hint)


func _process(delta: float) -> void:
	_time += delta
	global_position.y = _base_position.y + sin(_time * 1.6) * 0.07
	rotation.y += delta * 0.55
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) <= 2.4
	if near and not _hint.visible:
		_hint.call("set_label", binding_label())
	_hint.visible = near


func claim(player: Node3D) -> bool:
	if player.global_position.distance_to(global_position) > 2.4 or not player.has_method("pickup_weapon"):
		return false
	if not bool(player.call("pickup_weapon", weapon_index)):
		return false
	queue_free()
	return true


static func binding_label() -> String:
	var events: Array = InputMap.action_get_events(ACTION) if InputMap.has_action(ACTION) else []
	if events.is_empty():
		return "G"
	var event: InputEvent = events[0]
	if event is InputEventMouseButton:
		return ["LMB", "RMB", "MMB"][clampi((event as InputEventMouseButton).button_index - 1, 0, 2)]
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return OS.get_keycode_string(key_event.physical_keycode if key_event.physical_keycode else key_event.keycode)
	return event.as_text()
