extends RefCounted
## Collision of a door laid on the floor: off across the door's subtree so it can be walked over, restored when it stands up.

var _layers := {}


## Call every tick with the laid state; it only switches when the state changes.
func set_off(door: Node3D, fallen: bool) -> void:
	if fallen != _layers.is_empty():
		return
	for body: CollisionObject3D in door.find_children("*", "CollisionObject3D", true, false):
		if fallen:
			_layers[body] = body.collision_layer
			body.collision_layer = 0
		elif is_instance_valid(body):
			body.collision_layer = _layers[body]
	if not fallen:
		_layers.clear()
