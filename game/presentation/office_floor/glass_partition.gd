extends StaticBody3D

@export var max_health := 28.0
@export var hide_with_glass: PackedStringArray = PackedStringArray()
@export var blinds_pass_through := false

var _health := 0.0
var _broken := false
var _glass_nodes: Array[Node3D] = []


func _ready() -> void:
	_health = max_health
	_collect_glass(get_parent().get_node_or_null("Visual"))


func take_projectile_hit(damage: float, hit_position: Vector3, _hit_normal: Vector3, _direction: Vector3, _weapon_name: String) -> bool:
	if _broken:
		return false
	_health -= maxf(damage, 0.0)
	if _health <= 0.0:
		_break_glass(hit_position)
	return false


func take_melee_hit(damage: float, hit_position: Vector3, _direction: Vector3) -> void:
	if _broken:
		return
	_health -= maxf(damage, 0.0)
	if _health <= 0.0:
		_break_glass(hit_position)


func _collect_glass(node: Node) -> void:
	if node == null:
		return
	if node is Node3D and "glass" in node.name.to_lower():
		_glass_nodes.append(node as Node3D)
	for child in node.get_children():
		_collect_glass(child)


func _break_glass(hit_position: Vector3) -> void:
	if _broken:
		return
	_broken = true
	for glass in _glass_nodes:
		if is_instance_valid(glass):
			glass.visible = false
	for token in hide_with_glass:
		_hide_named(get_parent().get_node_or_null("Visual"), str(token).to_lower())
	_disable_collision_recursive(self)
	var owner_root := get_parent()
	var static_body := owner_root.get_node_or_null("Body") as StaticBody3D
	if static_body != null:
		_disable_glass_named_collision(static_body)
	_spawn_fragments(hit_position)


func _disable_collision_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).set_deferred("disabled", true)
	for child in node.get_children():
		_disable_collision_recursive(child)


func _disable_glass_named_collision(body: StaticBody3D) -> void:
	for child in body.get_children():
		if child is CollisionShape3D and ("glass" in child.name.to_lower() or "door" in child.name.to_lower()):
			(child as CollisionShape3D).set_deferred("disabled", true)


func _hide_named(node: Node, token: String) -> void:
	if node == null:
		return
	if node is Node3D and token in node.name.to_lower():
		(node as Node3D).visible = false
	for child in node.get_children():
		_hide_named(child, token)


func _spawn_fragments(hit_position: Vector3) -> void:
	for i in 10:
		var shard := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.03,0.12),randf_range(0.05,0.2),0.025)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55,0.9,1.0,0.65)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = material
		shard.mesh = mesh
		get_tree().current_scene.add_child(shard)
		shard.global_position = hit_position
		var tween := shard.create_tween()
		tween.tween_property(shard,"global_position",hit_position + Vector3(randf_range(-0.7,0.7),randf_range(0.1,0.8),randf_range(-0.7,0.7)),0.3)
		tween.tween_callback(shard.queue_free)
