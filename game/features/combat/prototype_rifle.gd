extends Node3D

@export var shots_per_second: float = 5.0
@export var magazine_size: int = 24
@export var starting_reserve_ammo: int = 96
@export var bullet_scene: PackedScene

@onready var muzzle: Marker3D = $Muzzle

var _cooldown_remaining: float = 0.0
var _magazine_ammo: int = 24
var _reserve_ammo: int = 96


func _ready() -> void:
	_magazine_ammo = magazine_size
	_reserve_ammo = starting_reserve_ammo


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)


func try_fire() -> bool:
	if _cooldown_remaining > 0.0 or bullet_scene == null:
		return false
	if _magazine_ammo <= 0:
		_reload()
		return false

	var shooter := get_parent().get_parent() as CollisionObject3D
	var bullet := bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_transform = muzzle.global_transform
	bullet.call("setup", -muzzle.global_transform.basis.z, shooter)

	_magazine_ammo -= 1
	_cooldown_remaining = 1.0 / maxf(shots_per_second, 0.01)
	return true


func get_magazine_ammo() -> int:
	return _magazine_ammo


func get_reserve_ammo() -> int:
	return _reserve_ammo


func _reload() -> void:
	if _reserve_ammo <= 0 or _magazine_ammo >= magazine_size:
		return
	var needed := magazine_size - _magazine_ammo
	var loaded := mini(needed, _reserve_ammo)
	_magazine_ammo += loaded
	_reserve_ammo -= loaded
