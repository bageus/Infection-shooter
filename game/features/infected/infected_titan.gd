extends "res://game/features/infected/infected_capsule.gd"
## Titan: now and then it rips a rock out of the floor (leaving a damage decal
## where it stood) and hurls it at the spot the player occupies at release.

const ROCK := preload("res://game/features/infected/titan_rock.gd")

@export var throw_min_distance := 5.0
@export var throw_max_distance := 14.0
@export var throw_cooldown := 14.0
@export_range(0.1, 0.9) var throw_grab_fraction := 0.35
@export_range(0.1, 0.95) var throw_release_fraction := 0.62
@export var throw_flight_seconds := 0.85
@export var throw_damage := 30.0

var _throw_cooldown := 6.0
var _throw_elapsed := -1.0
var _throw_length := 0.0
var _rock: Node3D


func _behaviour_tick(delta: float, target_offset: Vector3) -> void:
	_throw_cooldown = maxf(0.0, _throw_cooldown - delta)
	if _throw_elapsed >= 0.0:
		_tick_throw(delta)
		return
	var distance := target_offset.length()
	if _throw_cooldown <= 0.0 and _pending_hit < 0.0 and _blast_stun_remaining <= 0.0 and distance >= throw_min_distance and distance <= throw_max_distance and _clear_line():
		_start_throw()


func _start_throw() -> void:
	_throw_cooldown = throw_cooldown
	_throw_length = _play_animation(&"throw")
	if _throw_length <= 0.0:
		return
	_attack_cooldown = maxf(_attack_cooldown, attack_interval)
	audio.growl(1.5)
	_throw_elapsed = 0.0
	_cached_desired = Vector3.ZERO


func _tick_throw(delta: float) -> void:
	_cached_desired = Vector3.ZERO
	if _blast_stun_remaining > 0.0:
		_cancel_throw()
		return
	var before := _throw_elapsed
	_throw_elapsed += delta
	var grab_at := _throw_length * throw_grab_fraction
	var release_at := _throw_length * throw_release_fraction
	if before < grab_at and _throw_elapsed >= grab_at:
		_grab_rock()
	if is_instance_valid(_rock) and _throw_elapsed < release_at:
		_rock.global_position = _hand_position()
	if _throw_elapsed >= release_at:
		_release_rock()
	if _throw_elapsed >= _throw_length:
		_throw_elapsed = -1.0


func _grab_rock() -> void:
	var ground := _ground_point(-global_transform.basis.z * 1.1)
	_stamp_crater(ground)
	_rock = ROCK.new()
	_rock.name = "TitanRock"
	_rock.set("damage", throw_damage * get_damage_percent() / 100.0)
	var parent: Node = effects_root if is_instance_valid(effects_root) else get_parent()
	parent.add_child(_rock)
	_rock.global_position = ground


func _release_rock() -> void:
	if not is_instance_valid(_rock):
		_throw_elapsed = -1.0
		return
	var aim := _target.global_position if is_instance_valid(_target) else _rock.global_position
	_rock.call("launch", _rock.global_position, aim, throw_flight_seconds)
	_rock = null
	audio.call("play", &"colossus_slam")


func _cancel_throw() -> void:
	_throw_elapsed = -1.0
	if is_instance_valid(_rock):
		_rock.queue_free()
	_rock = null


func _hand_position() -> Vector3:
	return global_position + Vector3.UP * 1.1 - global_transform.basis.z * 0.9


func _ground_point(offset: Vector3) -> Vector3:
	var from := global_position + offset
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (_half_height() + 1.0), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", from + Vector3.DOWN * _half_height())


# The rock is ripped out of the floor: a blast-style crater mark where it lay.
func _stamp_crater(point: Vector3) -> void:
	if impact_pool == null or not impact_pool.has_method("bake_surface_hit"):
		return
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.3, point + Vector3.DOWN * 0.5, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node3D
	if collider == null:
		return
	var surface: Dictionary = impact_pool.call("resolve_surface", collider, point, Vector3.DOWN)
	impact_pool.call("bake_surface_hit", collider, point, Vector3.UP, "GRENADE", surface.get("anchor") as MeshInstance3D)


# Walls (layer 1) between the Titan and the player block the throw.
func _clear_line() -> bool:
	if not is_instance_valid(_target):
		return false
	var skip: Array[RID] = [get_rid()]
	if _target is CollisionObject3D:
		skip.append((_target as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, _target.global_position + Vector3.UP * 0.8, 1, skip)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# The swipe waits while the throw animation owns the body.
func _try_attack() -> void:
	if _throw_elapsed >= 0.0:
		return
	super._try_attack()


func _die() -> void:
	_cancel_throw()
	super._die()


func _half_height() -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	return capsule.height * 0.5 if capsule != null else 1.0
