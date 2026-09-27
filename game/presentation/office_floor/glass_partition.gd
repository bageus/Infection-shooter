extends StaticBody3D

const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")

@export var max_health := 28.0
@export var hide_with_glass: PackedStringArray = PackedStringArray()
@export var blinds_pass_through := false

var _health := 0.0
var _broken := false
var _glass_nodes: Array[Node3D] = []
var _blinds: Array[Node3D] = []
var _blinds_rest: Array[Basis] = []
var _player: Node3D
var _player_near_blinds := false
var _sway_strength := 0.0
var _sway_time := 0.0


func _ready() -> void:
	_health = max_health
	_collect_glass(get_parent().get_node_or_null("Visual"))
	if blinds_pass_through:
		_collect_blinds(get_parent().get_node_or_null("Visual"))
	set_physics_process(blinds_pass_through)


func _physics_process(delta: float) -> void:
	if not _broken or _blinds.is_empty():
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var near := false
	var partition := get_parent() as Node3D
	if _player != null and partition != null:
		var local_player: Vector3 = partition.to_local(_player.global_position)
		near = absf(local_player.x) < 0.85 and absf(local_player.z) < 0.55 and local_player.y > -0.5 and local_player.y < 3.2
	if near and not _player_near_blinds:
		_sway_strength = 0.16
	_player_near_blinds = near
	_sway_time += delta * 8.0
	_sway_strength = move_toward(_sway_strength, 0.0, delta * 0.055)
	for i in _blinds.size():
		if is_instance_valid(_blinds[i]):
			_blinds[i].basis = _blinds_rest[i].rotated(Vector3.RIGHT, sin(_sway_time + float(i) * 0.3) * _sway_strength)


func _collect_blinds(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and "blinds" in node.name.to_lower() and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
		var blind := node as Node3D
		_blinds.append(blind)
		_blinds_rest.append(blind.basis)
	for child in node.get_children():
		_collect_blinds(child)


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
		if str(token).to_lower() == "lower_panel":
			_drop_lower_panel(hit_position)
		else:
			_hide_named(get_parent().get_node_or_null("Visual"), str(token).to_lower())
	_disable_collision_recursive(self)
	# Only GlassBody is disabled. The structural frame collision stays intact.
	# Frames/blinds were excluded from glass collision at build time, so the
	# opening becomes traversable without deleting the surrounding wall frame.
	_spawn_fragments(hit_position)


func _drop_lower_panel(hit_position: Vector3) -> void:
	var frame: MeshInstance3D = _find_visible_frame(get_parent().get_node_or_null("Visual"))
	if frame == null or frame.mesh.get_surface_count() < 2:
		return
	var panel_mesh := ArrayMesh.new()
	panel_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, frame.mesh.surface_get_arrays(1))
	var panel_material := frame.get_active_material(1)
	if panel_material != null:
		panel_mesh.surface_set_material(0, panel_material)
	var panel := MeshInstance3D.new()
	panel.mesh = panel_mesh
	get_parent().add_child(panel)
	panel.global_transform = frame.global_transform
	DAMAGE.spawn_piece(self, panel, null, 0, 0, Vector3.DOWN, hit_position)
	panel.queue_free()
	var invisible := StandardMaterial3D.new()
	invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invisible.albedo_color = Color(0, 0, 0, 0)
	frame.set_surface_override_material(1, invisible)
	var frame_body := get_parent().get_node_or_null("Body") as StaticBody3D
	if frame_body != null:
		for child in frame_body.get_children():
			if child is CollisionShape3D and child.name == "BreakawayPanel":
				(child as CollisionShape3D).set_deferred("disabled", true)


func _find_visible_frame(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D and "frame" in node.name.to_lower() and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_visible_frame(child)
		if found != null:
			return found
	return null


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
		group.hide()
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
