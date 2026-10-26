extends RefCounted

const FRAGMENT_SCRIPT = preload("res://game/presentation/office_floor/environment_fragment.gd")


# Pieces thinner than this (m) get continuous collision detection.
const THIN_PIECE := 0.1
# A piece whose two smaller dimensions are both under this (a slat, a rail) does not collide with other pieces.
const STICK_THICKNESS := 0.15
const STICK_MIN_LENGTH := 1.5
# A chip (largest edge under SMALL_SHADOW_EDGE, m) or a sheet (thinner than SHEET_SHADOW_THICKNESS) casts no
# shadow: hundreds of them would each be drawn again in every shadow pass for a shadow nobody sees.
const SMALL_SHADOW_EDGE := 0.4
const SHEET_SHADOW_THICKNESS := 0.05


static func find_named(node: Node, wanted: String) -> Node3D:
	if node is Node3D and (node.name.to_lower() == wanted.to_lower() or node.name.to_lower().begins_with(wanted.to_lower() + ".")):
		return node as Node3D
	for child in node.get_children():
		var found := find_named(child, wanted)
		if found != null:
			return found
	return null


static func reveal_meshes(group: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	_collect(group, meshes)
	return meshes


static func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is Node3D:
		var part := node as Node3D
		if part.scale.length_squared() < 0.000001:
			part.scale = Vector3.ONE
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, meshes)


static func spawn_piece(host: Node3D, mesh: MeshInstance3D, owner: Node3D, stage: int, index: int, direction: Vector3, hit_point: Vector3, blast: bool = false, glass: bool = false, frame: Transform3D = Transform3D.IDENTITY, motion: RigidBody3D = null) -> RigidBody3D:
	if not is_instance_valid(host.get("effects_root")):
		return null
	var world := frame * mesh.global_transform
	var local_bounds := mesh.get_aabb()
	var size := local_bounds.size * world.basis.get_scale().abs()
	var bounds := AABB(world * local_bounds.get_center() - size * .5, size)
	if bounds.size.length_squared() < 0.000001:
		return null
	var fragment := RigidBody3D.new()
	fragment.set_script(FRAGMENT_SCRIPT)
	fragment.name = "Fragment_" + mesh.name
	if glass:
		fragment.set_meta(&"glass_debris", true)
	fragment.set("source", weakref(owner) if owner != null else null)
	fragment.set("piece_name", mesh.name)
	fragment.set("stage_index", stage)
	fragment.set("kickable", index % 3 == 0)
	fragment.set("blast_motion", blast)
	fragment.mass = clampf(bounds.size.length() * 0.3, 0.1, 3.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
	shape.shape = box
	fragment.add_child(shape)
	# A thin panel thrown at a few m/s moves further per physics step than it is thick and would
	# sink into the floor before the contact is resolved; sweep it so it stops on the surface.
	fragment.continuous_cd = minf(box.size.x, minf(box.size.y, box.size.z)) < THIN_PIECE
	var copy := MeshInstance3D.new()
	copy.mesh = mesh.mesh
	copy.material_override = mesh.material_override
	for surface in mesh.get_surface_override_material_count():
		copy.set_surface_override_material(surface, mesh.get_surface_override_material(surface))
	if maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) <= SMALL_SHADOW_EDGE or minf(bounds.size.x, minf(bounds.size.y, bounds.size.z)) <= SHEET_SHADOW_THICKNESS:
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fragment.add_child(copy)
	(host.get("effects_root") as Node3D).add_child(fragment)
	fragment.global_transform = Transform3D(world.basis.orthonormalized(), bounds.get_center())
	copy.global_transform = world
	var away := fragment.global_position - hit_point
	away.y = maxf(away.y, 0.1)
	var impulse := (away.normalized() * 0.75 + direction.normalized() * 0.25 + Vector3.UP * 0.35).normalized() * fragment.mass * randf_range(1.5, 3.0) if blast else Vector3.ZERO
	fragment.apply_impulse(impulse, (hit_point - fragment.global_position).limit_length(0.3))
	_inherit_motion(motion if motion != null else host, fragment, blast)
	if not glass and maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) >= FRAGMENT_SCRIPT.PIECE_MIN_EDGE:
		# Slats and rails (thin in two dimensions) skip piece contacts: dozens of long sticks would
		# otherwise wedge on each other and hang at an angle instead of lying on the floor.
		var sorted := [bounds.size.x, bounds.size.y, bounds.size.z]
		sorted.sort()
		if sorted[1] > STICK_THICKNESS or sorted[2] <= STICK_MIN_LENGTH:
			fragment.enable_piece_contacts()
		else:
			fragment.lie_down = blast
		if blast: fragment.topple_from(bounds.size, hit_point, direction)
	return fragment


# A baked piece becomes a body again at the transform it was baked with; it falls to rest and, like
# any other piece, may be pushed or shot. It belongs to no object, so a hit only moves it.
static func spawn_loose(effects: Node3D, mesh: Mesh, material: Material, shadow: int, world: Transform3D) -> RigidBody3D:
	var bounds: AABB = world * mesh.get_aabb()
	if bounds.size.length_squared() < 0.000001:
		return null
	var fragment := RigidBody3D.new()
	fragment.set_script(FRAGMENT_SCRIPT)
	fragment.name = "Fragment_Woken"
	fragment.set("piece_name", "Woken")
	fragment.set("stage_index", 99)
	fragment.set("kickable", true)
	fragment.mass = clampf(bounds.size.length() * 0.3, 0.1, 3.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(bounds.size.x, 0.02), maxf(bounds.size.y, 0.02), maxf(bounds.size.z, 0.02))
	shape.shape = box
	fragment.add_child(shape)
	fragment.continuous_cd = minf(box.size.x, minf(box.size.y, box.size.z)) < THIN_PIECE
	var copy := MeshInstance3D.new()
	copy.mesh = mesh
	copy.material_override = material
	copy.cast_shadow = shadow as GeometryInstance3D.ShadowCastingSetting
	fragment.add_child(copy)
	effects.add_child(fragment)
	fragment.global_position = bounds.get_center()
	copy.global_transform = world
	return fragment


# Pieces of a moving or tipping object keep its motion instead of starting from rest,
# plus a little tumble so they do not slide flat across the floor.
static func _inherit_motion(host: Node3D, fragment: RigidBody3D, blast: bool) -> void:
	if host is RigidBody3D:
		var body := host as RigidBody3D
		var lever := fragment.global_position - body.global_position
		fragment.linear_velocity += body.linear_velocity + body.angular_velocity.cross(lever)
		fragment.angular_velocity += body.angular_velocity
	if not blast: return
	var tumble := 2.5 / (0.6 + fragment.mass)
	fragment.angular_velocity += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * tumble
