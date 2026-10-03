extends StaticBody3D
## Bullet-only hit volume on one bone of a corpse (ADR-0017). Characters never
## touch it (physics layer 3); hits are forwarded to the owning body parts.

const HIT_LAYER := 4

var parts: Node
var part: StringName


func _ready() -> void:
	collision_layer = HIT_LAYER
	collision_mask = 0


func take_projectile_hit(damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, weapon: String) -> bool:
	if is_instance_valid(parts):
		parts.call("hit_corpse", part, damage, hit_position, direction, weapon)
	return true


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")


func get_projectile_material(_shape_index: int = -1) -> String:
	return "flesh"
