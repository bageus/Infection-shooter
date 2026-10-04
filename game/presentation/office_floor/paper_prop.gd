extends "res://game/presentation/office_floor/environment_prop.gd"

const SHREDS := preload("res://game/presentation/office_floor/paper_shreds.gd")

var _torn := false


func _ready() -> void:
	super._ready()
	# Loose paper is targetable by bullets but does not obstruct walking.
	collision_layer = 4
	collision_mask = 3


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	if _torn:
		return false
	_torn = true
	SHREDS.tear(self, hit_position, direction)
	call_deferred("_remove_torn_paper")
	return false


func get_projectile_material(_shape_index: int = -1) -> String:
	return "light"


func _remove_torn_paper() -> void:
	if not is_inside_tree():
		return
	collision_layer = 0
	if _visual != null:
		_visual.hide()
	for collision in _shapes:
		collision.set_deferred("disabled", true)
	queue_free()
