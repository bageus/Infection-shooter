extends Node3D

const PIECE_SCRIPT = preload("res://game/presentation/office_floor/table_piece.gd")
const EFFECTS_SCRIPT = preload("res://game/features/combat/public/impact_effects.gd")
const LEG_IDS := ["Leg_BL", "Leg_BR", "Leg_FL", "Leg_FR"]
const WOOD_MARKS := [
	"res://models/objects/textures/Splintered Wood Fracture Decal.png",
	"res://models/objects/textures/Flat tan wood scuff decal.png"
]

@export var fragment_impulse := 1.8
@export var fragment_lifetime := 24.0

var _intact: Node3D
var _modular: Node3D
var _fragments: Node3D
var _secondary: Node3D
var _parts: Dictionary = {}
var _active: Dictionary = {}
var _started := false
var _effects: Node3D
var _retained: Array[RigidBody3D] = []
var _retention_target := 2


func take_projectile_hit(_damage: float, _position: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
	_switch_to_modular()
	return true


func take_melee_hit(_damage: float, _position: Vector3, _direction: Vector3) -> void:
	_switch_to_modular()


func _ready() -> void:
	_effects = _locate_effects()
	_retention_target = randi_range(1, 3)
	var visual := get_node("Visual")
	_intact = _find(visual, "Intact")
	_modular = _find(visual, "Modular")
	_fragments = _find(visual, "Fragments")
	_secondary = _find(visual, "TopSecondary")
	if _intact == null or _modular == null or _fragments == null or _secondary == null:
		push_error("07_table.glb is missing a destruction group")
		return
	_modular.hide()
	_fragments.hide()
	_secondary.hide()
	for group in [_modular, _fragments, _secondary]:
		_collect_parts(group)
	for name in ["Top"] + LEG_IDS:
		var modular_mesh: MeshInstance3D = _parts.get(name)
		if modular_mesh != null:
			modular_mesh.scale = Vector3.ONE
	for name in ["Top"] + LEG_IDS:
		_add_modular_body(name)


func hit_piece(name: String, hit_position: Vector3, direction: Vector3) -> void:
	if not _active.has(name):
		return
	if not _started:
		_switch_to_modular()
		return
	var body: RigidBody3D = _active[name]
	_active.erase(name)
	call_deferred("_transition_piece", name, body, hit_position, direction)


func _switch_to_modular() -> void:
	if _started or _intact == null:
		return
	_started = true
	_intact.hide()
	_modular.show()
	var intact_body := get_node("IntactBody") as StaticBody3D
	intact_body.collision_layer = 0
	intact_body.get_node("CollisionShape3D").set_deferred("disabled", true)
	for name in ["Top"] + LEG_IDS:
		if _active.has(name):
			(_active[name] as RigidBody3D).collision_layer = 1


func _transition_piece(name: String, body: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	var original: MeshInstance3D = _parts[name]
	var original_transform := _mesh_transform(original)
	var current_transform := body.global_transform
	body.queue_free()
	original.hide()
	if name == "Top":
		for index in range(1, 9):
			_spawn_piece("Top_%02d" % index, original_transform, current_transform, hit_position, direction, false)
	elif name.begins_with("Leg_"):
		_spawn_piece(name + "_lower", original_transform, current_transform, hit_position, direction, true)
		_spawn_piece(name + "_upper", original_transform, current_transform, hit_position, direction, true)
	elif name.begins_with("Top_"):
		_spawn_piece(name + "_A", original_transform, current_transform, hit_position, direction, true)
		_spawn_piece(name + "_B", original_transform, current_transform, hit_position, direction, true)


func _add_modular_body(name: String) -> void:
	var mesh: MeshInstance3D = _parts.get(name)
	if mesh == null:
		push_error("07_table.glb is missing modular part " + name)
		return
	var body := _make_body(mesh, name, false)
	body.collision_layer = 0
	add_child(body)
	body.global_transform = _mesh_transform(mesh)
	_active[name] = body


func _spawn_piece(name: String, original: Transform3D, current: Transform3D, hit_position: Vector3, direction: Vector3, final_stage: bool) -> void:
	var mesh: MeshInstance3D = _parts.get(name)
	if mesh == null:
		push_error("07_table.glb is missing fragment " + name)
		return
	var target := current * original.affine_inverse() * _mesh_transform(mesh)
	var body := _make_body(mesh, name, final_stage)
	get_parent().add_child(body)
	body.global_transform = target
	var copy := mesh.duplicate() as MeshInstance3D
	body.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	copy.show()
	_active[name] = body
	_add_fracture_marks(body, mesh, hit_position)
	var offset := body.global_position - hit_position
	var away := (direction.normalized() + offset.normalized() * 0.5 + Vector3.UP * 0.5).normalized()
	body.apply_impulse(away * fragment_impulse, hit_position - body.global_position)
	var body_ref: WeakRef = weakref(body)
	var table_ref: WeakRef = weakref(self)
	get_tree().create_timer(fragment_lifetime if final_stage else fragment_lifetime * 2.0).timeout.connect(
		func() -> void:
			var live_body: RigidBody3D = body_ref.get_ref() as RigidBody3D
			var live_table: Node3D = table_ref.get_ref() as Node3D
			if live_body != null and live_table != null:
				live_table.call("_settle_piece", live_body)
	)


func _settle_piece(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	for index in range(_retained.size() - 1, -1, -1):
		if not is_instance_valid(_retained[index]) or _retained[index].is_queued_for_deletion():
			_retained.remove_at(index)
	if _retained.size() >= _retention_target:
		body.queue_free()
		return
	_retained.append(body)
	if _effects != null:
		_effects.call("register_retained", body)
	var body_ref: WeakRef = weakref(body)
	get_tree().create_timer(35.0).timeout.connect(func() -> void:
		var live_body: RigidBody3D = body_ref.get_ref() as RigidBody3D
		if live_body != null:
			live_body.queue_free()
	)


func _add_fracture_marks(body: RigidBody3D, mesh: MeshInstance3D, hit_position: Vector3) -> void:
	var tint := Color.WHITE
	if mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material != null:
			tint = material.albedo_color
	var normal := (body.global_position - hit_position).normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	for index in 2:
		var mark := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 0.2 * randf_range(0.7, 1.2)
		var material := StandardMaterial3D.new()
		material.albedo_texture = _effects.call("texture_for", WOOD_MARKS[randi() % WOOD_MARKS.size()]) as Texture2D
		material.albedo_color = tint.lerp(Color.WHITE, 0.25)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.render_priority = 1
		quad.material = material
		mark.mesh = quad
		body.add_child(mark)
		mark.global_position = body.global_position + normal * 0.02 + Vector3.UP * float(index) * 0.025
		var up := Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP
		mark.global_basis = Basis.looking_at(-normal, up) * Basis(Vector3.FORWARD, randf() * TAU)
		if _effects != null:
			_effects.call("register_mark", mark)


func _mesh_transform(mesh: MeshInstance3D) -> Transform3D:
	# The GLB deliberately stores hidden pieces at zero scale; preserve only their orientation and origin.
	return Transform3D(mesh.get_parent().global_basis.orthonormalized(), mesh.global_position)


func _locate_effects() -> Node3D:
	var ancestor: Node = self
	var host: Node3D = self
	while ancestor != null:
		var pool := ancestor.get_node_or_null("ImpactEffects") as Node3D
		if pool != null:
			return pool
		if ancestor is Node3D:
			host = ancestor as Node3D
		ancestor = ancestor.get_parent()
	var local_pool := Node3D.new()
	local_pool.set_script(EFFECTS_SCRIPT)
	local_pool.name = "ImpactEffects"
	host.add_child(local_pool)
	return local_pool


func _make_body(mesh: MeshInstance3D, name: String, final_stage: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(PIECE_SCRIPT)
	body.name = name
	body.set("table", self)
	body.set("piece_id", name)
	body.set("last_stage", final_stage)
	body.mass = 1.0 if name.begins_with("Top") else 0.4
	body.freeze = name == "Top" or name in LEG_IDS
	body.collision_layer = 1
	body.collision_mask = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bounds := mesh.get_aabb()
	box.size = bounds.size
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	return body


func _collect_parts(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_parts[child.name] = child
		_collect_parts(child)


func _find(node: Node, name: String) -> Node3D:
	if node.name == name:
		return node as Node3D
	for child in node.get_children():
		var result := _find(child, name)
		if result != null:
			return result
	return null
