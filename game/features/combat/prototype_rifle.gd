extends Node3D
@export var weapon_name: String = "PISTOL"
@export var fire_mode: String = "semi"
@export var shots_per_second: float = 4.0
@export var magazine_size: int = 15
@export var starting_reserve_ammo: int = 75
@export var max_reserve_ammo: int = 240
@export var reload_time: float = 1.15
@export var spread_degrees: float = 1.2
@export var pellets_per_shot: int = 1
@export var bullet_damage: float = 26.0
@export var bullet_speed: float = 36.0
@export var bullet_range: float = 34.0
@export var shotgun_shell_reload: bool = false
@export var bullet_scene: PackedScene
@export var environment_damage_multiplier: float = 1.0
@onready var muzzle: Marker3D = $Muzzle
var _cooldown_remaining: float = 0.0
var _reload_remaining: float = 0.0
var _magazine_ammo: int
var _reserve_ammo: int
var _reloading: bool = false
func _ready() -> void:
	_magazine_ammo = magazine_size
	_reserve_ammo = starting_reserve_ammo
func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if not _reloading: return
	_reload_remaining -= delta
	if _reload_remaining > 0.0: return
	if shotgun_shell_reload:
		if _reserve_ammo > 0 and _magazine_ammo < magazine_size:
			_magazine_ammo += 1
			_reserve_ammo -= 1
			_reload_remaining = reload_time
		else: _reloading = false
	else:
		var loaded := mini(magazine_size - _magazine_ammo, _reserve_ammo)
		_magazine_ammo += loaded
		_reserve_ammo -= loaded
		_reloading = false
func wants_continuous_fire() -> bool: return fire_mode == "auto"
func try_fire() -> bool:
	if _cooldown_remaining > 0.0 or _reloading or bullet_scene == null: return false
	if _magazine_ammo <= 0:
		return false
	var shooter := get_parent().get_parent() as CollisionObject3D
	for pellet in pellets_per_shot:
		var bullet := bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.global_transform = muzzle.global_transform
		var shot_direction := _spread_direction(-muzzle.global_transform.basis.z)
		var collision_origin := muzzle.global_position
		if shooter != null:
			collision_origin = shooter.global_position + Vector3.UP * 0.55
		bullet.call("setup_projectile", shot_direction, shooter, bullet_damage * environment_damage_multiplier, bullet_speed, bullet_range, weapon_name, collision_origin)
	_magazine_ammo -= 1
	_cooldown_remaining = 1.0 / maxf(shots_per_second, 0.01)
	return true
func start_reload() -> void:
	if _reloading or _reserve_ammo <= 0 or _magazine_ammo >= magazine_size: return
	_reloading = true
	_reload_remaining = reload_time
func cancel_reload() -> void: _reloading = false
func get_weapon_name() -> String: return weapon_name
func get_magazine_ammo() -> int: return _magazine_ammo
func get_reserve_ammo() -> int: return _reserve_ammo
func is_reloading() -> bool: return _reloading
func add_reserve_ammo(amount: int) -> int:
	var previous := _reserve_ammo
	_reserve_ammo = mini(max_reserve_ammo, _reserve_ammo + maxi(amount, 0))
	return _reserve_ammo - previous
func _spread_direction(base: Vector3) -> Vector3:
	var yaw := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
	var pitch := deg_to_rad(randf_range(-spread_degrees, spread_degrees))
	return base.rotated(Vector3.UP, yaw).rotated(global_transform.basis.x.normalized(), pitch).normalized()
