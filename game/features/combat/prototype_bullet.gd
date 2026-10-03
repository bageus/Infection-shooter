extends Node3D

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const IMPACT_SOUNDS := {
	"metal": &"hit_metal", "wood": &"hit_wood", "light": &"hit_paper", "tech": &"hit_electronics",
	"glass": &"hit_glass", "flesh": &"flesh_hit", "concrete": &"hit_wall", "solid": &"hit_wall",
}

const PROJECTILE_VISUAL := preload("res://game/features/combat/projectile_visual.gd")
const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")

const IMPACT_TEXTURES := [
	"res://models/objects/textures/Minimal dark bullet impact decal.png",
	"res://models/objects/textures/Minimal transparent bullet impact decal.png"
]

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

	var step := minf(_speed * delta, _range - _travelled)
	var finish := global_position + _direction * step
	var excluded: Array[RID] = []
	if _shooter != null:
		excluded.append(_shooter.get_rid())

	var remaining_start := _collision_origin if _first_step else global_position
	_first_step = false
	var remaining_finish := finish
	for pass_index in 5:
		var query := PhysicsRayQueryParameters3D.create(remaining_start, remaining_finish, 7)
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = finish
			_travelled += step
			return

		var hit_position: Vector3 = hit.get("position")
		var normal: Vector3 = hit.get("normal")
		var collider: Object = hit.get("collider")
		var shape_index := int(hit.get("shape", -1))
		var stops_bullet := _handle_hit(collider, hit_position, normal, shape_index)
		var material := _hit_material(collider, shape_index)
		_remaining_energy -= BALANCE.material_cost(material)
		if _remaining_energy < 8.0:
			stops_bullet = true
		if stops_bullet:
			global_position = hit_position
			queue_free()
			return

		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		remaining_start = hit_position + _direction * 0.04

	global_position = finish
	_travelled += step


func _handle_hit(collider: Object, hit_position: Vector3, normal: Vector3, shape_index: int = -1) -> bool:
	if collider == null:
		return true
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
		if collider.has_method("take_projectile_damage"):
			collider.call("take_projectile_damage", hit_damage, hit_position, _direction, _weapon_name)
		else:
			collider.call("take_damage", hit_damage)
		return true

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
	var event: StringName = IMPACT_SOUNDS.get(_hit_material(collider, shape_index), &"hit_wall")
	SFX.play(effects_root, event, hit_position, -4.0 if _weapon_name == "SHOTGUN" else 0.0)


func _hit_material(collider: Object, shape_index: int) -> String:
	if collider != null and collider.has_method("get_projectile_material"):
		return str(collider.call("get_projectile_material", shape_index))
	return "solid"


func _spawn_impact_decal(collider: Object, hit_position: Vector3, normal: Vector3) -> void:
	if normal.is_zero_approx():
		normal = -_direction if not _direction.is_zero_approx() else Vector3.UP
	if not is_instance_valid(effects_root) or not is_instance_valid(impact_pool):
		return
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var texture_index := 1 if randi() % 4 == 0 else 0
	quad.size = Vector2.ONE * (0.5 if texture_index == 1 else 0.3)
	var material := StandardMaterial3D.new()
	var pool := impact_pool
	material.albedo_texture = pool.call("texture_for", IMPACT_TEXTURES[texture_index]) as Texture2D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	quad.material = material
	mark.mesh = quad
	var parent: Node3D = collider as Node3D
	if parent == null:
		parent = effects_root
	if parent == null:
		return
	parent.add_child(mark)
	mark.global_position = hit_position + normal * 0.018
	var up := Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
	mark.global_basis = Basis.looking_at(-normal, up)
	if pool != null:
		pool.call("register_mark", mark)
	var mark_ref: WeakRef = weakref(mark)
	get_tree().create_timer(24.0).timeout.connect(func() -> void:
		var live_mark: MeshInstance3D = mark_ref.get_ref() as MeshInstance3D
		if live_mark != null:
			live_mark.queue_free()
	)
