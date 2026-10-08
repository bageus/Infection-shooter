extends Node3D
const BARREL_GUARD := preload("res://game/features/combat/weapon_barrel_guard.gd")
const AIM_GEOMETRY := preload("res://game/features/combat/weapon_aim_geometry.gd")
const MUZZLE_FLASH := preload("res://game/features/combat/muzzle_flash.tscn")
const ART_SETUP := preload("res://game/features/combat/weapon_art_setup.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
# Sound events per weapon (ADR-0018): [fire, reload, casing].
const WEAPON_SOUNDS := {
	"PISTOL": [&"pistol_fire", &"pistol_reload", &"casing_brass"],
	"UZI": [&"uzi_fire", &"uzi_reload", &"casing_brass"],
	"SHOTGUN": [&"shotgun_fire", &"shotgun_shell_load", &"casing_shell"],
	"SNIPER RIFLE": [&"rifle_fire", &"rifle_reload", &"casing_brass"],
	"AK": [&"rifle_fire", &"rifle_reload", &"casing_brass"],
	"M4": [&"assault_rifle_fire", &"rifle_reload", &"casing_brass"],
	"MINIGUN": [&"assault_rifle_fire", &"rifle_reload", &"casing_brass"],
	"RIFLE": [&"rifle_fire", &"rifle_reload", &"casing_brass"],
	"ASSAULT RIFLE": [&"assault_rifle_fire", &"rifle_reload", &"casing_brass"],
	"GRENADE LAUNCHER": [&"launcher_fire", &"launcher_reload", &"casing_heavy"],
}
@export var direct_reserve_feed := false
@export var casing_size_multiplier := 1.0
@export var camera_distance_bonus := 0.0
@export var scope_magnification := 0.0
@export var align_authored_grip := false
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
var _authored_muzzle: Node3D
var _reload_sound: AudioStreamPlayer3D
var _barrel_cluster: Node3D
var _barrel_angle := 0.0


func _ready() -> void:
	_magazine_ammo = magazine_size
	_reserve_ammo = starting_reserve_ammo
	var model := get_node_or_null("Body") as Node3D
	if model != null:
		_authored_muzzle = ART_SETUP.configure(self, model, weapon_name in ["SHOTGUN", "GRENADE LAUNCHER", "AK", "M4", "SNIPER RIFLE", "MINIGUN"])
		if weapon_name == "MINIGUN":
			_barrel_cluster = model.find_child("BarrelCluster", true, false) as Node3D
func _process(delta: float) -> void:
	if _barrel_cluster != null and visible and _cooldown_remaining > 0.0:
		_barrel_angle = fmod(_barrel_angle + 35.0 * delta, TAU)
		var turn := Basis(Vector3.RIGHT, _barrel_angle)
		var center := Vector3(0, .103, 0)
		_barrel_cluster.transform = Transform3D(turn, center - turn * center)
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if not _reloading: return
	_reload_remaining -= delta
	if _reload_remaining > 0.0: return
	if shotgun_shell_reload:
		if _reserve_ammo > 0 and _magazine_ammo < magazine_size:
			_magazine_ammo += 1
			_reserve_ammo -= 1
			_reload_remaining = reload_time
			if _reserve_ammo > 0 and _magazine_ammo < magazine_size:
				_play_reload_sound()
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


# Public weapon_aim_v1: aligns the model, authored flash and gameplay muzzle.
func aim_at(target_point: Vector3) -> void:
	AIM_GEOMETRY.aim(self, muzzle, target_point)


func try_fire_at(target_point: Vector3) -> bool:
	# A shell-by-shell reload is interrupted by firing once a shell is in.
	if _reloading and shotgun_shell_reload and _magazine_ammo > 0:
		cancel_reload()
	if _cooldown_remaining > 0.0 or _reloading or bullet_scene == null or not is_instance_valid(effects_root): return false
	if (_reserve_ammo if direct_reserve_feed else _magazine_ammo) <= 0:
		_dry_fire()
		# The click of an empty gun starts a reload when there is ammo to load.
		start_reload()
		return false
	var shooter := get_parent().get_parent() as CollisionObject3D
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_shot_time > maxf(0.34, 2.5 / maxf(shots_per_second, 0.01)):
		_burst_shots = 0
	var effective_spread := spread_degrees
	if wants_continuous_fire():
		# A short burst stays tight; sustained fire gradually loses accuracy.
		effective_spread *= lerpf(0.42, 1.65, clampf(float(_burst_shots) / 11.0, 0.0, 1.0))
	aim_at(target_point)
	var base_direction := -muzzle.global_basis.z.normalized()
	var obstruction := BARREL_GUARD.obstruction(self, muzzle, shooter)
	for pellet in pellets_per_shot:
		var bullet := bullet_scene.instantiate()
		bullet.call("configure_world", effects_root, impact_pool)
		effects_root.add_child(bullet)
		bullet.global_transform = muzzle.global_transform
		var shot_direction := _spread_direction(base_direction, effective_spread)
		var collision_origin := AIM_GEOMETRY.collision_origin(self, muzzle)
		bullet.call("setup_projectile", shot_direction, shooter, bullet_damage * environment_damage_multiplier, bullet_speed, bullet_range, weapon_name, collision_origin)
		if not obstruction.is_empty():
			bullet.call("_handle_hit", obstruction["collider"], obstruction["position"], obstruction["normal"], int(obstruction.get("shape", -1)))
			bullet.queue_free()
	if direct_reserve_feed:
		_reserve_ammo -= 1
	else:
		_magazine_ammo -= 1
	_show_muzzle_flash()
	_last_shot_time = now
	_burst_shots += 1
	_cooldown_remaining = 1.0 / maxf(shots_per_second, 0.01)
	if casing_scene != null and ejection_port != null:
		var casing_pool := get_parent().get_node_or_null("SpentCasings")
		if casing_pool != null:
			casing_pool.call("spawn_casing", casing_scene, ejection_port.global_transform, casing_radius, shooter, sound_event(2), casing_size_multiplier)
	SFX.play(self, sound_event(0), muzzle.global_position)
	return true


# Fire, reload or casing sound event of this weapon (0, 1, 2).
func sound_event(kind: int) -> StringName:
	var sounds: Array = WEAPON_SOUNDS.get(weapon_name, WEAPON_SOUNDS["PISTOL"])
	return sounds[kind]


func _dry_fire() -> void:
	if _cooldown_remaining > 0.0:
		return
	_cooldown_remaining = 0.3
	SFX.play(self, &"dry_fire", muzzle.global_position)


func _play_reload_sound() -> void:
	_reload_sound = SFX.play(self, sound_event(1))


func _show_muzzle_flash() -> void:
	var flash := MUZZLE_FLASH.instantiate()
	var anchor := _authored_muzzle if is_instance_valid(_authored_muzzle) else muzzle
	# Authored art uses +X; legacy gameplay-only scenes keep their -Z marker.
	flash.set("barrel_axis", Vector3.RIGHT if anchor == _authored_muzzle else Vector3.FORWARD)
	anchor.add_child(flash)


func start_reload() -> void:
	if direct_reserve_feed or _reloading or _reserve_ammo <= 0 or _magazine_ammo >= magazine_size: return
	_reloading = true
	_reload_remaining = reload_time
	_play_reload_sound()
func cancel_reload() -> void:
	_reloading = false
	if is_instance_valid(_reload_sound):
		_reload_sound.queue_free()
func get_weapon_name() -> String: return weapon_name
func get_magazine_ammo() -> int: return _reserve_ammo if direct_reserve_feed else _magazine_ammo
func get_reserve_ammo() -> int: return 0 if direct_reserve_feed else _reserve_ammo
func is_reloading() -> bool: return _reloading
func add_reserve_ammo(amount: int) -> int:
	var previous := _reserve_ammo
	_reserve_ammo = mini(max_reserve_ammo, _reserve_ammo + maxi(amount, 0))
	return _reserve_ammo - previous
func add_magazine_ammo(amount: int) -> int:
	if direct_reserve_feed:
		return add_reserve_ammo(amount)
	var before := _magazine_ammo
	_magazine_ammo = mini(magazine_size, _magazine_ammo + maxi(0, amount))
	return _magazine_ammo - before
func _spread_direction(base: Vector3, cone_degrees: float) -> Vector3:
	var yaw := deg_to_rad(randf_range(-cone_degrees, cone_degrees))
	var pitch := deg_to_rad(randf_range(-cone_degrees, cone_degrees))
	var turned := base.rotated(Vector3.UP, yaw)
	var right := turned.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	return turned.rotated(right, pitch).normalized()
