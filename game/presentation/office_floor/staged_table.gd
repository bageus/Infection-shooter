extends Node3D

const PIECE_SCRIPT = preload("res://game/presentation/office_floor/table_piece.gd")
const ASSEMBLY_SCRIPT = preload("res://game/presentation/office_floor/table_assembly.gd")
const EFFECTS_SCRIPT = preload("res://game/features/combat/public/impact_effects.gd")
const LEG_IDS := ["Leg_BL", "Leg_BR", "Leg_FL", "Leg_FR"]
const WOOD_MARKS := [
	"res://models/objects/textures/Splintered Wood Fracture Decal.png",
	"res://models/objects/textures/Flat tan wood scuff decal.png"
]

@export var fragment_impulse := 1.8
@export var fragment_lifetime := 24.0
@export var one_leg_tilt_impulse := 1.2
@export var two_leg_tilt_impulse := 6.0

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
var _assembly: RigidBody3D
var _part_shapes: Dictionary = {}
var _rest_transforms: Dictionary = {}
var _broken_legs: Array[String] = []


func take_projectile_hit(_damage: float, position: Vector3, _normal: Vector3, direction: Vector3, _weapon: String) -> bool:
	_switch_to_modular()
	hit_piece(_part_at(position), position, direction)
	return true


func take_melee_hit(_damage: float, position: Vector3, direction: Vector3) -> void:
	_switch_to_modular()
	hit_piece(_part_at(position), position, direction)


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
	for name in _parts:
		_rest_transforms[name] = _mesh_transform(_parts[name])
	for name in ["Top"] + LEG_IDS:
		var modular_mesh: MeshInstance3D = _parts.get(name)
		if modular_mesh != null:
			modular_mesh.scale = Vector3.ONE
	_build_assembly()


func _part_at(position: Vector3) -> String:
	var local_hit := to_local(position)
	if local_hit.y > 0.65:
		return "Top"
	var x := "R" if local_hit.x < 0.0 else "L"
	var z := "F" if local_hit.z < 0.0 else "B"
	return "Leg_" + z + x


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
	_assembly.collision_layer = 1


func _transition_piece(name: String, body: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	var original: MeshInstance3D = _parts[name]
	var original_transform := _current_mesh_transform(original, body)
	if body == _assembly:
		(_part_shapes[name] as CollisionShape3D).set_deferred("disabled", true)
	else:
		body.queue_free()
	original.hide()
	if name == "Top":
		for index in range(1, 9):
			_spawn_piece("Top_%02d" % index, name, original_transform, hit_position, direction, false)
		_drop_remaining_legs(hit_position, direction)
	elif name.begins_with("Leg_"):
		_spawn_piece(name + "_lower", name, original_transform, hit_position, direction, true)
		_spawn_piece(name + "_upper", name, original_transform, hit_position, direction, true)
		if body == _assembly:
			_on_leg_lost(name, hit_position)
	elif name.begins_with("Top_"):
		_spawn_piece(name + "_A", name, original_transform, hit_position, direction, true)
		_spawn_piece(name + "_B", name, original_transform, hit_position, direction, true)


func _build_assembly() -> void:
	_assembly = RigidBody3D.new()
	_assembly.set_script(ASSEMBLY_SCRIPT)
	_assembly.set("table", self)
	_assembly.name = "Assembly"
	_assembly.mass = 18.0
	_assembly.freeze = true
	_assembly.collision_layer = 0
	_assembly.collision_mask = 1
	add_child(_assembly)
	_modular.reparent(_assembly, true)
	for name in ["Top"] + LEG_IDS:
		var mesh: MeshInstance3D = _parts.get(name)
		if mesh == null:
			push_error("07_table.glb is missing modular part " + name)
			continue
		var bounds := mesh.get_aabb()
		var shape := CollisionShape3D.new()
		shape.name = name
		var box := BoxShape3D.new()
		box.size = bounds.size
		shape.shape = box
		_assembly.add_child(shape)
		shape.transform = _assembly.global_transform.affine_inverse() * _mesh_transform(mesh)
		shape.position += shape.basis * bounds.get_center()
		_part_shapes[name] = shape
		_active[name] = _assembly


func _on_leg_lost(name: String, hit_position: Vector3) -> void:
	_broken_legs.append(name)
	var tilt := Vector3.ZERO
	for missing in _broken_legs:
		var corner: Vector3 = (_part_shapes[missing] as CollisionShape3D).position
		tilt += _assembly.global_basis * Vector3(corner.x, 0.0, corner.z)
	# Opposite corners cancel; in that case favor the last leg that was removed.
	if tilt.length_squared() < 0.01:
		var corner: Vector3 = (_part_shapes[name] as CollisionShape3D).position
		tilt = _assembly.global_basis * Vector3(corner.x, 0.0, corner.z)
	tilt = tilt.normalized()
	var strength := one_leg_tilt_impulse if _broken_legs.size() == 1 else two_leg_tilt_impulse
	_assembly.angular_damp = 3.0 if _broken_legs.size() == 1 else 0.15
	_assembly.freeze = false
	_assembly.sleeping = false
	_assembly.apply_torque_impulse(Vector3.UP.cross(tilt) * strength)
	_assembly.apply_impulse(Vector3.DOWN * strength * 0.25, tilt * 0.5)
	_wake_tabletop_items(tilt, strength)


func _drop_remaining_legs(hit_position: Vector3, direction: Vector3) -> void:
	_wake_tabletop_items(direction, two_leg_tilt_impulse)
	for name in LEG_IDS:
		if not _active.has(name):
			continue
		var mesh: MeshInstance3D = _parts[name]
		var current := _mesh_transform(mesh)
		var body := _make_body(mesh, name, false)
		get_parent().add_child(body)
		var center := mesh.get_aabb().get_center()
		body.global_transform = current * Transform3D(Basis.IDENTITY, center)
		var copy := mesh.duplicate() as MeshInstance3D
		body.add_child(copy)
		copy.transform = Transform3D(Basis.IDENTITY, -center)
		copy.show()
		mesh.hide()
		_active[name] = body
		body.apply_impulse((direction.normalized() + Vector3.DOWN * 0.4).normalized() * fragment_impulse)
		_schedule_settle(body, fragment_lifetime * 2.0)
	_modular.reparent(get_node("Visual"), true)
	_modular.hide()
	_assembly.collision_layer = 0
	_assembly.queue_free()
	_assembly = null


func _wake_tabletop_items(direction: Vector3, strength: float) -> void:
	var top: MeshInstance3D = _parts.get("Top")
	if top == null or _assembly == null:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.55, 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(_assembly.global_basis, _mesh_transform(top).origin + _assembly.global_basis * Vector3.UP * 0.25)
	query.collision_mask = 1
	query.exclude = [_assembly.get_rid()]
	for result in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var item := result.get("collider") as RigidBody3D
		if item == null or item == _assembly:
			continue
		item.freeze = false
		item.sleeping = false
		item.apply_impulse((direction.normalized() + Vector3.UP * 0.15).normalized() * minf(strength * 0.25, 1.5))


func _current_mesh_transform(mesh: MeshInstance3D, body: RigidBody3D) -> Transform3D:
	if body == _assembly:
		return _mesh_transform(mesh)
	return body.global_transform * Transform3D(Basis.IDENTITY, -mesh.get_aabb().get_center())


func _spawn_piece(name: String, source_name: String, source_current: Transform3D, hit_position: Vector3, direction: Vector3, final_stage: bool) -> void:
	var mesh: MeshInstance3D = _parts.get(name)
	if mesh == null:
		push_error("07_table.glb is missing fragment " + name)
		return
	var target: Transform3D = source_current * (_rest_transforms[source_name] as Transform3D).affine_inverse() * (_rest_transforms[name] as Transform3D)
	var body := _make_body(mesh, name, final_stage)
	get_parent().add_child(body)
	var center := mesh.get_aabb().get_center()
	body.global_transform = target * Transform3D(Basis.IDENTITY, center)
	var copy := mesh.duplicate() as MeshInstance3D
	body.add_child(copy)
	copy.transform = Transform3D(Basis.IDENTITY, -center)
	copy.show()
	_active[name] = body
	_add_fracture_marks(body, mesh, hit_position)
	var offset := body.global_position - hit_position
	var away := (direction.normalized() + offset.normalized() * 0.5 + Vector3.UP * 0.5).normalized()
	body.apply_impulse(away * fragment_impulse, (hit_position - body.global_position).limit_length(0.3))
	_schedule_settle(body, fragment_lifetime if final_stage else fragment_lifetime * 2.0)


func _schedule_settle(body: RigidBody3D, duration: float) -> void:
	var body_ref: WeakRef = weakref(body)
	var table_ref: WeakRef = weakref(self)
	get_tree().create_timer(duration).timeout.connect(
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
	# The few pieces left on the floor are visual only and never obstruct movement.
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
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
	shape.position = Vector3.ZERO
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
