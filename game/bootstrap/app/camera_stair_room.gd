extends Node
## Level-start camera yaw, and the camera pitch offset while the player stands in a room with a staircase.
const START_YAW := -138.65
const EPSILON := 0.01
var actor: Node3D


func setup(player: Node3D) -> void:
	actor = player
	var view: Dictionary = actor.call("get_camera_adjustment")
	view.yaw = START_YAW
	actor.call("set_camera_adjustment", view)


func _process(_delta: float) -> void:
	if is_instance_valid(actor):
		actor.set("camera_stair_room", _in_stair_room())


# A room is a set of darkness zones sharing a room_id; the stair's room is the one whose zone contains the stair.
func _in_stair_room() -> bool:
	var zones := get_tree().get_nodes_in_group("darkness_zone")
	var rooms: Array = []
	for stair in get_tree().get_nodes_in_group("staircase"):
		for zone in zones:
			var room: int = zone.get("room_id")
			if room > 0 and zone.call("_edge_distance", stair.global_position) < EPSILON:
				rooms.append(room)
	for zone in zones:
		if rooms.has(zone.get("room_id")) and zone.call("_edge_distance", actor.global_position) < EPSILON:
			return true
	return false
