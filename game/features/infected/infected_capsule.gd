extends CharacterBody3D

@export var max_health: float = 50.0
@export var move_speed: float = 4.5
@export var attack_range: float = 1.2
@export var attack_damage: float = 15.0
@export var attack_interval: float = 1.0
@export var gravity_acceleration: float = 24.0
@export var push_decay: float = 10.0
@export var max_push_speed: float = 6.0
@export var obstacle_damage: float = 34.0
@export var obstacle_attack_interval: float = 0.45

@onready var body_mesh: MeshInstance3D = $Body
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_cloud: Area3D = $DeathCloud

var health: float
var _target: Node3D
var _attack_cooldown: float = 0.0
var _obstacle_cooldown: float = 0.0
var _dead: bool = false
var _push_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	health = max_health
	death_cloud.depleted.connect(_on_death_cloud_depleted)


func set_target(target: Node3D) -> void:
	_target = target


func apply_player_push(direction: Vector3, strength: float) -> void:
	if _dead or strength <= 0.0:
		return
	_push_velocity += direction.normalized() * strength
	if _push_velocity.length() > max_push_speed:
		_push_velocity = _push_velocity.normalized() * max_push_speed


func take_projectile_damage(
	amount: float,
	hit_position: Vector3,
	direction: Vector3,
	weapon_name: String = "PISTOL"
) -> void:
	_spawn_air_blood(hit_position, direction, weapon_name)
	_spawn_surface_splatter(hit_position, direction, weapon_name)
	take_damage(amount)


func take_damage(amount: float) -> void:
	if amount <= 0.0 or _dead:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector3.ZERO
		return

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_obstacle_cooldown = maxf(0.0, _obstacle_cooldown - delta)
	var desired := _desired_velocity()
	velocity.x = desired.x + _push_velocity.x
	velocity.z = desired.z + _push_velocity.z
	_push_velocity = _push_velocity.move_toward(Vector3.ZERO, push_decay * delta)
	_apply_gravity(delta)
	move_and_slide()
	_try_break_blocking_props()


func _desired_velocity() -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return Vector3.ZERO
	var offset: Vector3 = _target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= attack_range:
		_try_attack()
		return Vector3.ZERO
	var direction := offset.normalized()
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction, Vector3.UP)
	return direction * move_speed


func _try_break_blocking_props() -> void:
	if _obstacle_cooldown > 0.0:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if collider != null and collider.has_method("take_melee_hit"):
			collider.call(
				"take_melee_hit",
				obstacle_damage,
				collision.get_position(),
				-global_transform.basis.z
			)
			_obstacle_cooldown = obstacle_attack_interval
			return


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity_acceleration * delta


func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	if _target != null and _target.has_method("take_damage"):
		_target.call("take_damage", attack_damage)
	_attack_cooldown = attack_interval


func _spawn_air_blood(hit_position: Vector3, direction: Vector3, weapon_name: String) -> void:
	var count := 11 if weapon_name == "SHOTGUN" else 6
	var spread := 0.72 if weapon_name == "SHOTGUN" else 0.34
	for i in count:
		var drop := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = randf_range(0.018, 0.048)
		mesh.height = mesh.radius * randf_range(1.5, 3.8)
		mesh.material = _blood_material()
		drop.mesh = mesh
		get_tree().current_scene.add_child(drop)
		drop.global_position = hit_position
		var target := hit_position + direction * randf_range(0.25, 0.9)
		target += Vector3(randf_range(-spread, spread), randf_range(-0.2, 0.28), randf_range(-spread, spread))
		var tween := drop.create_tween()
		tween.tween_property(drop, "global_position", target, randf_range(0.1, 0.24))
		tween.tween_callback(drop.queue_free)


func _spawn_surface_splatter(hit_position: Vector3, direction: Vector3, weapon_name: String) -> void:
	var rays := 16 if weapon_name == "SHOTGUN" else 6
	var reach := 4.0 if weapon_name == "SHOTGUN" else 2.4
	var spread := 0.9 if weapon_name == "SHOTGUN" else 0.35
	for i in rays:
		var ray_direction := direction.normalized()
		ray_direction += Vector3(randf_range(-spread, spread), randf_range(-0.55, 0.2), randf_range(-spread, spread))
		_cast_blood_ray(hit_position, ray_direction.normalized(), reach, weapon_name == "SHOTGUN")
	for i in (5 if weapon_name == "SHOTGUN" else 2):
		var floor_start := hit_position + Vector3(randf_range(-0.8, 0.8), 0.35, randf_range(-0.8, 0.8))
		_cast_blood_ray(floor_start, Vector3.DOWN, 3.0, weapon_name == "SHOTGUN")


func _cast_blood_ray(origin: Vector3, direction: Vector3, reach: float, heavy: bool) -> void:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * reach, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal")
	if normal.y < -0.55:
		return
	_spawn_splatter_mark(hit.get("position"), normal, heavy)


func _spawn_splatter_mark(hit_position: Vector3, normal: Vector3, heavy: bool) -> void:
	var mark := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _blood_material()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var points := 14 if heavy else 9
	var width := randf_range(0.18, 0.42) if heavy else randf_range(0.1, 0.24)
	var height := width * randf_range(0.45, 1.45)
	for i in points:
		var a0 := TAU * float(i) / points
		var a1 := TAU * float(i + 1) / points
		var r0 := randf_range(0.45, 1.15)
		var r1 := randf_range(0.45, 1.15)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(cos(a0) * width * r0, sin(a0) * height * r0, 0))
		mesh.surface_add_vertex(Vector3(cos(a1) * width * r1, sin(a1) * height * r1, 0))
	mesh.surface_end()
	mark.mesh = mesh
	get_tree().current_scene.add_child(mark)
	mark.global_position = hit_position + normal * 0.014
	mark.global_basis = _basis_for_normal(normal)
	if heavy:
		_spawn_satellite_drops(hit_position, normal, mark.global_basis)


func _spawn_satellite_drops(hit_position: Vector3, normal: Vector3, surface_basis: Basis) -> void:
	for i in randi_range(3, 7):
		var dot := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		var radius := randf_range(0.025, 0.075)
		mesh.size = Vector2(radius, radius * randf_range(0.7, 1.8))
		mesh.material = _blood_material()
		dot.mesh = mesh
		get_tree().current_scene.add_child(dot)
		var local_offset := Vector3(randf_range(-0.55, 0.55), randf_range(-0.45, 0.45), 0)
		dot.global_position = hit_position + surface_basis * local_offset + normal * 0.016
		dot.global_basis = surface_basis


func _basis_for_normal(normal: Vector3) -> Basis:
	var z := normal.normalized()
	var helper := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.92 else Vector3.FORWARD
	var x := helper.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func _blood_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.33, 0.0, 0.012, 0.96)
	material.roughness = 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _die() -> void:
	_dead = true
	collision_layer = 0
	collision_mask = 0
	collision_shape.disabled = true
	body_mesh.visible = false
	death_cloud.call("activate")


func _on_death_cloud_depleted() -> void:
	queue_free()
