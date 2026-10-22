extends Node3D

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const IMPACT_SOUNDS := {
	"metal": &"hit_metal", "wood": &"hit_wood", "light": &"hit_paper", "tech": &"hit_electronics",
	"glass": &"hit_glass", "flesh": &"flesh_hit", "concrete": &"hit_wall", "solid": &"hit_wall",
}

const MAX_HITS_PER_TICK := 5
const EXIT := preload("res://game/features/combat/penetration_exit.gd")
const EXIT_BURST := preload("res://game/features/combat/penetration_burst.gd")

const PROJECTILE_VISUAL := preload("res://game/features/combat/projectile_visual.gd")
const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")
const TRACE := preload("res://game/features/combat/public/explosion_trace.gd")

const SURFACE_ATLASES := preload("res://game/core/vfx/public/surface_atlases.gd")

var _direction := Vector3.ZERO
var _shooter: CollisionObject3D
var _speed: float = 32.0
var _damage: float = 20.0
var _range: float = 30.0
var _travelled: float = 0.0
var _weapon_name: String = "PISTOL"
var _collision_origin := Vector3.ZERO
var _first_step := true
var _initial_energy := 24.0
var _remaining_energy := 24.0
# A crowded segment can span several ticks; never skip its untested remainder.
var _pending_step := false
var _step_finish := Vector3.ZERO
var _step_distance := 0.0
var _step_excluded: Array[RID] = []
var _pending_exits: Array[Dictionary] = []

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func setup_projectile(
	direction: Vector3,
	shooter: CollisionObject3D,
	damage: float,
	speed: float,
	max_range: float,
	weapon_name: String = "PISTOL",
	collision_origin: Vector3 = Vector3.ZERO
) -> void:
	_direction = direction.normalized()
	_shooter = shooter
	_damage = damage
	_speed = speed
	_range = max_range
	_weapon_name = weapon_name
	_initial_energy = BALANCE.projectile_energy(weapon_name)
	_remaining_energy = _initial_energy
	var visual := PROJECTILE_VISUAL.new() as Node3D
	add_child(visual)
	visual.call("configure", weapon_name, _direction)
	_collision_origin = collision_origin if collision_origin != Vector3.ZERO else global_position


func _physics_process(delta: float) -> void:
	if _travelled >= _range:
		queue_free()
		return

	if not _pending_step:
		_step_distance = minf(_speed * delta, _range - _travelled)
		_step_finish = global_position + _direction * _step_distance
		# Straight flight never damages the same penetrated body twice.
		if is_instance_valid(_shooter) and not _step_excluded.has(_shooter.get_rid()):
			_step_excluded.append(_shooter.get_rid())

	var from_barrel := _first_step
	var remaining_start := _collision_origin if _first_step else global_position
	_first_step = false
	# Reserve a second ray for exit geometry before callbacks alter the body.
	var stride := 2 if is_instance_valid(effects_root) else 1
	for pass_index in range(0, MAX_HITS_PER_TICK - stride + 1, stride):
		var query := PhysicsRayQueryParameters3D.create(remaining_start, _step_finish, 7)
		query.exclude = _step_excluded
		query.hit_from_inside = from_barrel and pass_index == 0
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			_flush_exits(_step_finish)
			global_position = _step_finish
			_travelled += _step_distance
			_pending_step = false
			return

		var hit_position: Vector3 = hit.get("position")
		var normal: Vector3 = hit.get("normal")
		if normal.is_zero_approx():
			normal = -_direction
		var collider: Object = hit.get("collider")
		var shape_index := int(hit.get("shape", -1))
		var collider_rid: RID = collider.get_rid() if collider is CollisionObject3D else RID()
		var material := _hit_material(collider, shape_index)
		var energy_after := _remaining_energy - BALANCE.material_cost(material)
		var exit_surface: Dictionary = {}
		if energy_after >= 8.0 and is_instance_valid(effects_root):
			exit_surface = EXIT.surface(collider, shape_index, hit_position, _direction, _step_excluded)
		var stops_bullet := _handle_hit(collider, hit_position, normal, shape_index)
		_remaining_energy = energy_after
		if _remaining_energy < 8.0:
			stops_bullet = true
		if stops_bullet:
			_flush_exits(hit_position)
			global_position = hit_position
			queue_free()
			return

		if collider_rid.is_valid():
			_step_excluded.append(collider_rid)
		if not exit_surface.is_empty():
			exit_surface["material"] = material
			exit_surface["energy"] = _remaining_energy
			exit_surface["excluded"] = _step_excluded.duplicate()
			_pending_exits.append(exit_surface)
		remaining_start = hit_position

	# Only the checked prefix is safe. Keep its exclusions and original endpoint
	# until the remaining segment is resolved, even if the next delta differs.
	_flush_exits(remaining_start)
	global_position = remaining_start
	_pending_step = true


func _flush_exits(checked_position: Vector3) -> void:
	for index in range(_pending_exits.size() - 1, -1, -1):
		var entry := _pending_exits[index]
		if (checked_position - (entry.position as Vector3)).dot(_direction) < -0.0001:
			continue
		EXIT_BURST.spawn(effects_root, entry.position, _direction, entry.material, entry.energy)
		if entry.material == "flesh" and is_instance_valid(impact_pool):
			impact_pool.emit_signal("penetration_blood", entry.position, _direction, entry.energy, entry.excluded)
		_pending_exits.remove_at(index)


func _handle_hit(collider: Object, hit_position: Vector3, normal: Vector3, shape_index: int = -1) -> bool:
	if collider == null:
		return true
	if not TRACE.enabled() or collider.has_method("take_projectile_damage"):
		return _dispatch_hit(collider, hit_position, normal, shape_index)
	TRACE.begin("bullet_hit %s (%s)" % [collider.get("model_path") if collider.get("model_path") != null else collider.get_class(), _weapon_name])
	var result := _dispatch_hit(collider, hit_position, normal, shape_index)
	TRACE.mark("hit handled (decal, sound, prop reaction)")
	return result


func _dispatch_hit(collider: Object, hit_position: Vector3, normal: Vector3, shape_index: int) -> bool:
	# Bullet holes belong on surfaces, not on the infected or their limbs.
	if not collider.has_method("take_projectile_damage") and _hit_material(collider, shape_index) not in ["flesh", "glass"]:
		_spawn_impact_decal(collider, hit_position, normal)
	_play_impact(collider, hit_position, shape_index)

	var distance := _collision_origin.distance_to(hit_position)
	var hit_damage := _damage * BALANCE.distance_multiplier(_weapon_name, distance, _range) * (_remaining_energy / _initial_energy)
	if collider.has_method("take_projectile_hit_at_shape"):
		return bool(collider.call(
			"take_projectile_hit_at_shape",
			hit_damage, hit_position, normal, _direction, _weapon_name, shape_index
		))

	if collider.has_method("take_projectile_hit"):
		return bool(collider.call(
			"take_projectile_hit",
			hit_damage,
			hit_position,
			normal,
			_direction,
			_weapon_name
		))

	if collider.has_method("take_damage"):
		var penetrable_body: bool = collider is Node and collider.is_in_group("infected_alive")
		if collider.has_method("take_projectile_damage"):
			collider.call("take_projectile_damage", hit_damage, hit_position, _direction, _weapon_name)
		else:
			collider.call("take_damage", hit_damage)
		return not penetrable_body

	var parent := (collider as Node).get_parent() if collider is Node else null
	if parent != null and parent.has_method("take_projectile_hit"):
		return bool(parent.call(
			"take_projectile_hit",
			hit_damage,
			hit_position,
			normal,
			_direction,
			_weapon_name
		))

	return true


# Surface sound of a bullet hit (ADR-0018); infected play their own flesh hits.
func _play_impact(collider: Object, hit_position: Vector3, shape_index: int) -> void:
	if not is_instance_valid(effects_root) or collider.has_method("take_projectile_damage"):
		return
	var sound_material := str(collider.call("get_impact_sound_material", shape_index)) if collider.has_method("get_impact_sound_material") else _hit_material(collider, shape_index)
	var event: StringName = IMPACT_SOUNDS.get(sound_material, &"hit_wall")
	SFX.play(effects_root, event, hit_position, -4.0 if _weapon_name == "SHOTGUN" else 0.0)


func _hit_material(collider: Object, shape_index: int) -> String:
	if collider is Node and collider.is_in_group("infected_alive"):
		return "flesh"
	if collider != null and collider.has_method("get_projectile_material"):
		return str(collider.call("get_projectile_material", shape_index))
	return "solid"


func _spawn_impact_decal(collider: Object, hit_position: Vector3, normal: Vector3) -> void:
	if normal.is_zero_approx():
		normal = -_direction if not _direction.is_zero_approx() else Vector3.UP
	if not is_instance_valid(effects_root) or not is_instance_valid(impact_pool):
		return
	var surface: Dictionary = {"position": hit_position, "normal": normal, "anchor": effects_root}
	if collider is Node3D:
		surface = impact_pool.call("resolve_surface", collider, hit_position, _direction if not _direction.is_zero_approx() else -normal)
	if surface.is_empty():
		# Procedural floors have collision geometry and a separate MultiMesh renderer.
		surface = {"position": hit_position, "normal": normal, "anchor": collider}
	hit_position = surface["position"]
	normal = surface["normal"]
	if collider is Node3D and impact_pool.has_method("bake_surface_hit") and impact_pool.call("bake_surface_hit", collider, hit_position, normal, _weapon_name, surface.get("anchor") as MeshInstance3D):
		impact_pool.call("spawn_bullet_smoke", hit_position, normal)
		return
	var up := Vector3.FORWARD if absf(normal.y) > .9 else Vector3.UP
	var projector := Transform3D(Basis.looking_at(-normal, up), hit_position)
	var material := SURFACE_ATLASES.material(SURFACE_ATLASES.BULLET, randi_range(0, 4))
	var marks: Array = impact_pool.call("project_surface", collider, projector, Vector2.ONE * randf_range(.12, .24), material, .08, true)
	for mark in marks:
		impact_pool.call("register_mark", mark)
		get_tree().create_timer(24.0).timeout.connect(mark.queue_free)
	if not marks.is_empty():
		impact_pool.call("spawn_bullet_smoke", hit_position, normal)
