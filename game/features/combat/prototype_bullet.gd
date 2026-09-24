extends Node3D

const EFFECTS_SCRIPT = preload("res://game/features/combat/public/impact_effects.gd")

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
		var query := PhysicsRayQueryParameters3D.create(remaining_start, remaining_finish, 3)
		query.exclude = excluded
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			global_position = finish
			_travelled += step
			return

		var hit_position: Vector3 = hit.get("position")
		var normal: Vector3 = hit.get("normal")
		var collider: Object = hit.get("collider")
		var stops_bullet := _handle_hit(collider, hit_position, normal, int(hit.get("shape", -1)))
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

	var falloff := clampf(1.0 - _travelled / maxf(_range, 0.01), 0.35, 1.0)
	var hit_damage := _damage * falloff
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
			collider.call("take_projectile_damage", hit_damage, position, _direction, _weapon_name)
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


func _spawn_impact_decal(collider: Object, hit_position: Vector3, normal: Vector3) -> void:
	if normal.is_zero_approx():
		normal = -_direction if not _direction.is_zero_approx() else Vector3.UP
	var mark := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var texture_index := 1 if randi() % 4 == 0 else 0
	quad.size = Vector2.ONE * (0.5 if texture_index == 1 else 0.3)
	var material := StandardMaterial3D.new()
	var pool := get_parent().get_node_or_null("ImpactEffects")
	if pool == null:
		pool = Node3D.new()
		pool.name = "ImpactEffects"
		pool.set_script(EFFECTS_SCRIPT)
		get_parent().add_child(pool)
	material.albedo_texture = pool.call("texture_for", IMPACT_TEXTURES[texture_index]) as Texture2D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 1
	quad.material = material
	mark.mesh = quad
	var parent: Node3D = collider as Node3D
	if parent == null:
		parent = get_tree().current_scene as Node3D
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
