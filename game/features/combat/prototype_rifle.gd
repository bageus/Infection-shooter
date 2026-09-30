extends Node3D
const MUZZLE_FLASH := preload("res://game/features/combat/muzzle_flash.tscn")
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
@export var casing_scene: PackedScene
@export var casing_radius: float = 0.012
@export var environment_damage_multiplier: float = 1.0
@onready var muzzle: Marker3D = $Muzzle
@onready var ejection_port: Marker3D = get_node_or_null("EjectionPort") as Marker3D
var _cooldown_remaining: float = 0.0
var _reload_remaining: float = 0.0
var _magazine_ammo: int
var _reserve_ammo: int
var _reloading: bool = false
var _burst_shots: int = 0
var _last_shot_time: float = -100.0
var effects_root: Node3D
var impact_pool: Node


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
	return try_fire_at(muzzle.global_position - muzzle.global_transform.basis.z * bullet_range)



# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func try_fire_at(target_point: Vector3) -> bool:
	if _cooldown_remaining > 0.0 or _reloading or bullet_scene == null or not is_instance_valid(effects_root): return false
	if _magazine_ammo <= 0:
		return false
	var shooter := get_parent().get_parent() as CollisionObject3D
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_shot_time > maxf(0.34, 2.5 / maxf(shots_per_second, 0.01)):
		_burst_shots = 0
	var effective_spread := spread_degrees
	if wants_continuous_fire():
		# A short burst stays tight; sustained fire gradually loses accuracy.
		effective_spread *= lerpf(0.42, 1.65, clampf(float(_burst_shots) / 11.0, 0.0, 1.0))
	var forward := -global_transform.basis.z.normalized()
	forward.y = 0.0
	forward = forward.normalized()
	var muzzle_position := muzzle.global_position
	var aim_offset := target_point - muzzle_position
	var horizontal := Vector3(aim_offset.x, 0.0, aim_offset.z)
	if horizontal.length_squared() < 0.04 or horizontal.dot(forward) < 0.0:
		horizontal = forward * 8.0
	# Ray hits high surfaces near the camera must not send bullets into the sky.
	var rise := clampf(aim_offset.y, -horizontal.length() * 0.22, horizontal.length() * 0.22)
	var base_direction := (horizontal + Vector3.UP * rise).normalized()
	for pellet in pellets_per_shot:
		var bullet := bullet_scene.instantiate()
		bullet.call("configure_world", effects_root, impact_pool)
		effects_root.add_child(bullet)
		bullet.global_transform = muzzle.global_transform
		var shot_direction := _spread_direction(base_direction, effective_spread)
		var collision_origin := muzzle_position
		bullet.call("setup_projectile", shot_direction, shooter, bullet_damage * environment_damage_multiplier, bullet_speed, bullet_range, weapon_name, collision_origin)
	_magazine_ammo -= 1
	_show_muzzle_flash()
	_last_shot_time = now
	_burst_shots += 1
	_cooldown_remaining = 1.0 / maxf(shots_per_second, 0.01)
	if casing_scene != null and ejection_port != null:
		var casing_pool := get_parent().get_node_or_null("SpentCasings")
		if casing_pool != null:
			casing_pool.call("spawn_casing", casing_scene, ejection_port.global_transform, casing_radius, shooter)
	return true


func _show_muzzle_flash() -> void:
	muzzle.add_child(MUZZLE_FLASH.instantiate())


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
func add_magazine_ammo(amount: int) -> int:
	var before := _magazine_ammo
	_magazine_ammo = mini(magazine_size, _magazine_ammo + maxi(0, amount))
	return _magazine_ammo - before
func _spread_direction(base: Vector3, cone_degrees: float) -> Vector3:
	var yaw := deg_to_rad(randf_range(-cone_degrees, cone_degrees))
	var pitch := deg_to_rad(randf_range(-cone_degrees, cone_degrees))
	var turned := base.rotated(Vector3.UP, yaw)
	var right := turned.cross(Vector3.UP).normalized()
	return turned.rotated(right, pitch).normalized()
