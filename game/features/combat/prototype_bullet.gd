extends Node3D

const IMPACT_TEXTURES := [
	preload("res://models/objects/textures/Minimal dark bullet impact decal.png"),
	preload("res://models/objects/textures/Minimal transparent bullet impact decal.png")
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
		var stops_bullet := _handle_hit(collider, hit_position, normal)
		if stops_bullet:
			global_position = hit_position
			queue_free()
			return

		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		remaining_start = hit_position + _direction * 0.04

	global_position = finish
	_travelled += step


func _handle_hit(collider: Object, hit_position: Vector3, normal: Vector3) -> bool:
	if collider == null:
		return true
	_spawn_impact_decal(collider, hit_position, normal)

	var falloff := clampf(1.0 - _travelled / maxf(_range, 0.01), 0.35, 1.0)
	var hit_damage := _damage * falloff

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
	var mark := Decal.new()
	mark.texture_albedo = IMPACT_TEXTURES[randi() % IMPACT_TEXTURES.size()]
	mark.size = Vector3(0.18, 0.12, 0.18)
	mark.modulate = Color(0.65, 0.65, 0.65) if mark.texture_albedo == IMPACT_TEXTURES[1] else Color.WHITE
	var parent: Node3D = collider as Node3D
	if parent == null:
		parent = get_tree().current_scene as Node3D
	if parent == null:
		return
	var previous_marks: Array[Node] = []
	for child in parent.get_children():
		if child is Decal and child.get_meta("bullet_mark", false):
			previous_marks.append(child)
	if previous_marks.size() >= 12:
		previous_marks[0].queue_free()
	mark.set_meta("bullet_mark", true)
	parent.add_child(mark)
	mark.global_position = hit_position + normal * 0.015
	mark.global_basis = Basis(Quaternion(Vector3.UP, normal))
	get_tree().create_timer(24.0).timeout.connect(func() -> void:
		if is_instance_valid(mark):
			mark.queue_free()
	)
