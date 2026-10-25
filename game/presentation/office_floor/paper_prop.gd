extends "res://game/presentation/office_floor/environment_prop.gd"
## Paper shares the complete-disposal rule; no persistent scraps or duplicate hit route.

func _ready() -> void:
	super._ready()
	collision_layer = 4
	collision_mask = 3

func get_projectile_material(_shape_index: int = -1) -> String:
	return "light"
