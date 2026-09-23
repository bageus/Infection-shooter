extends "res://game/presentation/office_floor/physical_prop.gd"

func _ready() -> void:
	max_health = 45.0
	bullet_impulse = 2.6
	character_push_impulse = 3.4
	max_linear_speed = 5.5
	max_angular_speed = 10.0
	super._ready()
	add_to_group("pushable_chair")
