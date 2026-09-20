extends StaticBody3D

@export var max_health: float = 60.0
@export var penetrable: bool = false
@export var break_on_first_hit: bool = false
@export var impact_marks: bool = true
@export var spark_on_hit: bool = false
@export var spark_height: float = 0.72
@export var break_effect: String = "debris"

var _health: float
var _broken: bool = false
var _blood_decals: Array[Node] = []


func _ready() -> void:
	_health = max_health


func take_projectile_hit(
	damage: float,
	hit_position: Vector3,
	hit_normal: Vector3,
	_direction: Vector3,
	weapon_name: String
) -> bool:
	if _broken:
		return false

	if impact_marks:
		_spawn_impact_mark(hit_position, hit_normal)

	if spark_on_hit and to_local(hit_position).y >= spark_height:
		_spawn_sparks(hit_position)

	var weapon_multiplier := 1.0
	if weapon_name == "SHOTGUN":
		weapon_multiplier = 1.35
	elif weapon_name == "UZI":
		weapon_multiplier = 0.9

	_health -= maxf(damage, 0.0) * weapon_multiplier
	if break_on_first_hit or _health <= 0.0:
		_break_prop(hit_position)

	return not penetrable


func take_melee_hit(damage: float, hit_position: Vector3, _direction: Vector3) -> void:
	if _broken:
		return
	_health -= maxf(damage, 0.0)
	if break_on_first_hit or _health <= 0.0:
		_break_prop(hit_position)


func _break_prop(hit_position: Vector3) -> void:
	if _broken:
		return
	_broken = true
	_clear_blood_decals()

	var owner_root := get_parent()
	var visual := owner_root.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.visible = false
	if break_effect == "glass":
		_spawn_replacement_frame(owner_root)

	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)

	if break_effect == "glass":
		_spawn_fragments(hit_position, Color(0.55, 0.9, 1.0, 0.78), 8)
	elif break_effect == "water":
		_spawn_fragments(hit_position, Color(0.25, 0.65, 1.0, 0.9), 10)
	else:
		_spawn_fragments(hit_position, Color(0.28, 0.2, 0.13, 1.0), 6)


func add_blood_decal(decal: Node) -> void:
	if decal == null:
		return
	_blood_decals.append(decal)


func _clear_blood_decals() -> void:
	for decal in _blood_decals:
		if is_instance_valid(decal):
			decal.queue_free()
	_blood_decals.clear()


func _spawn_replacement_frame(owner_root: Node3D) -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		return
	var size: Vector3 = (collision_shape.shape as BoxShape3D).size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.06, 0.09, 0.12, 1.0)
	material.metallic = 0.55
	material.roughness = 0.38
	var bar := 0.065
	_add_frame_bar(owner_root, Vector3(size.x, bar, maxf(size.z, 0.07)), Vector3(0, bar * 0.5, 0), material)
	_add_frame_bar(owner_root, Vector3(size.x, bar, maxf(size.z, 0.07)), Vector3(0, size.y - bar * 0.5, 0), material)
	_add_frame_bar(owner_root, Vector3(bar, size.y, maxf(size.z, 0.07)), Vector3(-size.x * 0.5 + bar * 0.5, size.y * 0.5, 0), material)
	_add_frame_bar(owner_root, Vector3(bar, size.y, maxf(size.z, 0.07)), Vector3(size.x * 0.5 - bar * 0.5, size.y * 0.5, 0), material)


func _add_frame_bar(owner_root: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	piece.mesh = mesh
	piece.position = position
	owner_root.add_child(piece)


func _spawn_impact_mark(position: Vector3, normal: Vector3) -> void:
	var mark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.028
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.035, 0.035, 1.0)
	material.roughness = 1.0
	mesh.material = material
	mark.mesh = mesh
	get_tree().current_scene.add_child(mark)
	mark.global_position = position + normal * 0.012
	_expire_node(mark, 24.0)


func _spawn_sparks(position: Vector3) -> void:
	for i in 6:
		var spark := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.025
		mesh.height = 0.05
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.72, 0.12, 1.0)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.35, 0.03, 1.0)
		material.emission_energy_multiplier = 4.0
		mesh.material = material
		spark.mesh = mesh
		get_tree().current_scene.add_child(spark)
		spark.global_position = position
		var target := position + Vector3(
			randf_range(-0.45, 0.45),
			randf_range(0.1, 0.7),
			randf_range(-0.45, 0.45)
		)
		var tween := spark.create_tween()
		tween.tween_property(spark, "global_position", target, randf_range(0.12, 0.28))
		tween.tween_callback(spark.queue_free)


func _spawn_fragments(position: Vector3, tint: Color, count: int) -> void:
	for i in count:
		var fragment := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(
			randf_range(0.04, 0.13),
			randf_range(0.04, 0.18),
			randf_range(0.02, 0.08)
		)
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if tint.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		mesh.material = material
		fragment.mesh = mesh
		get_tree().current_scene.add_child(fragment)
		fragment.global_position = position
		var target := position + Vector3(
			randf_range(-0.8, 0.8),
			randf_range(0.15, 0.95),
			randf_range(-0.8, 0.8)
		)
		var tween := fragment.create_tween()
		tween.tween_property(fragment, "global_position", target, randf_range(0.2, 0.45))
		tween.tween_callback(fragment.queue_free)


func _expire_node(node: Node, seconds: float) -> void:
	var timer := get_tree().create_timer(seconds)
	timer.timeout.connect(node.queue_free)
