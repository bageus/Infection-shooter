extends RefCounted
## Blood left on the floor by a wounded infected on the move or a dragged corpse.

var last_position := Vector3.ZERO
var segment_start := Vector3.ZERO
var distance := 0.0


func reset(position: Vector3) -> void:
	last_position = position
	segment_start = position
	distance = 0.0


# Emits wounded_moved / body_dragged on the owner after enough travel.
func track(owner: CharacterBody3D, dead: bool, untouched: bool, spacing: float, excluded: Array[RID]) -> void:
	var current := owner.global_position
	var travelled := current.distance_to(last_position)
	last_position = current
	if travelled > 3.0 or (not dead and untouched):
		segment_start = current
		distance = 0.0
		return
	distance += travelled
	if distance < (0.35 if dead else spacing):
		return
	owner.emit_signal(&"body_dragged" if dead else &"wounded_moved", segment_start, current, excluded)
	distance = 0.0
	segment_start = current
