extends Node3D

@export var shots_per_second: float = 5.0
@export var bullet_scene: PackedScene

@onready var muzzle: Marker3D = $Muzzle

var _cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)


func try_fire() -> bool:
	if _cooldown_remaining > 0.0 or bullet_scene == null:
		return false

	var shooter := get_parent().get_parent() as CollisionObject3D
	var bullet := bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = muzzle.global_transform
	bullet.call("setup", -muzzle.global_transform.basis.z, shooter)

	_cooldown_remaining = 1.0 / maxf(shots_per_second, 0.01)
	return true
