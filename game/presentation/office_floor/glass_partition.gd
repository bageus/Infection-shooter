extends StaticBody3D

const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")

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
	if node is MeshInstance3D and "glass" in node.name.to_lower() and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
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
	# Only GlassBody is disabled. The structural frame collision stays intact.
	# Frames/blinds were excluded from glass collision at build time, so the
	# opening becomes traversable without deleting the surrounding wall frame.
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
	var visual := get_parent().get_node_or_null("Visual") as Node3D
	var group: Node3D = DAMAGE.find_named(visual, "Glass_Shards") if visual != null else null
	if group != null:
		var shards: Array[MeshInstance3D] = DAMAGE.reveal_meshes(group)
		for index in mini(shards.size(), 12):
			DAMAGE.spawn_piece(self, shards[index], null, 0, index, Vector3.UP, hit_position)
		return
	# Older window models have a pane but no shard geometry.
	for index in 6:
		var source := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.12, 0.025)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.84, 0.95, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = material
		source.mesh = box
		get_parent().add_child(source)
		source.global_position = hit_position + Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), 0)
		DAMAGE.spawn_piece(self, source, null, 0, index, Vector3.UP, hit_position)
		source.queue_free()
