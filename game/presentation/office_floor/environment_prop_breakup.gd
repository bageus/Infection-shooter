extends RefCounted
## Presents prop breakup: localized facade chips, staged fragments and glass shards.
## The root owns durability and supplies its geometry and effects container.

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const GEOMETRY := preload("res://game/presentation/office_floor/environment_prop_geometry.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")


# A cabinet piece with an edge at least this long (m) is split further when a blast breaks it.
const BLAST_SPLIT_EDGE := 0.3
const BLAST_SPLIT_DELAY := 0.15


static func chip_facade(body: RigidBody3D, geometry: GEOMETRY, hit_position: Vector3, direction: Vector3) -> bool:
	var nearest: MeshInstance3D
	var nearest_distance := 0.8
	for mesh in DAMAGE.reveal_meshes(geometry.stages[0]):
		if mesh.visible and mesh.name.begins_with("Facade_Chip"):
			var distance := (mesh.global_transform * mesh.get_aabb()).get_center().distance_to(hit_position)
			if distance < nearest_distance:
				nearest = mesh
				nearest_distance = distance
	if nearest == null:
		return false
	DAMAGE.spawn_piece(body, nearest, null, geometry.stages.size(), 0, direction, hit_position)
	nearest.hide()
	return true


static func spawn_stage(body: RigidBody3D, geometry: GEOMETRY, stage_index: int, prefix: String, hit_position: Vector3, direction: Vector3, blast: bool = false, from_piece: RigidBody3D = null) -> bool:
	if stage_index >= geometry.stages.size() or not geometry.ensure_group(geometry.stages[stage_index]):
		return false
	var meshes: Array[MeshInstance3D] = DAMAGE.reveal_meshes(geometry.stages[stage_index])
	if not prefix.is_empty():
		meshes = meshes.filter(func(mesh: MeshInstance3D) -> bool:
			return _piece_id(mesh.name) == _piece_id(prefix) or _piece_id(mesh.name).begins_with(_piece_id(prefix) + "_"))
		# Some authored stages retain an unsplittable pedestal/body verbatim.
		if meshes.size() == 1 and _piece_id(meshes[0].name) == _piece_id(prefix): return false
	var spawned := 0
	var frame := _continuation_frame(geometry, from_piece)
	for mesh in meshes:
		var fragment: RigidBody3D = DAMAGE.spawn_piece(body, mesh, body, stage_index, spawned, direction, hit_position, blast, false, frame, from_piece)
		if fragment != null:
			fragment.set("breakable", stage_index + 1 < geometry.stages.size())
			spawned += 1
			if blast and _is_blast_split(body, mesh):
				_split_later(body, geometry, fragment, hit_position, direction)
	return spawned > 0


static func _is_blast_split(body: Node3D, mesh: MeshInstance3D) -> bool:
	if "cabinet" not in str(body.get("model_path")).get_file():
		return false
	var size := (mesh.global_transform * mesh.get_aabb()).size
	return maxf(size.x, maxf(size.y, size.z)) >= BLAST_SPLIT_EDGE


# Later, not now, so the next stage loads after the blast frame and the first transition stays cheap.
static func _split_later(body: RigidBody3D, geometry: GEOMETRY, fragment: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	var body_ref: WeakRef = weakref(body)
	var fragment_ref: WeakRef = weakref(fragment)
	body.get_tree().create_timer(BLAST_SPLIT_DELAY).timeout.connect(func() -> void:
		var live_body: RigidBody3D = body_ref.get_ref() as RigidBody3D
		var live_fragment: RigidBody3D = fragment_ref.get_ref() as RigidBody3D
		if live_body != null and live_fragment != null and not live_fragment.is_queued_for_deletion():
			hit_fragment(live_body, geometry, live_fragment, hit_position, direction, true))


static func hit_fragment(body: RigidBody3D, geometry: GEOMETRY, fragment: RigidBody3D, hit_position: Vector3, direction: Vector3, blast: bool = false) -> void:
	blast = blast or bool(fragment.get("blast_hit"))
	var name_part: String = fragment.get("piece_name")
	var next_stage: int = int(fragment.get("stage_index")) + 1
	while next_stage < geometry.stages.size():
		if spawn_stage(body, geometry, next_stage, name_part, hit_position, direction, blast, fragment):
			fragment.queue_free()
			return
		next_stage += 1
	# A single-piece stage (a knocked-over plant pot) shatters into the whole next stage.
	var stage_index := int(fragment.get("stage_index"))
	if stage_index + 1 < geometry.stages.size() and DAMAGE.reveal_meshes(geometry.stages[stage_index]).size() == 1:
		if spawn_stage(body, geometry, stage_index + 1, "", hit_position, direction, blast, fragment):
			fragment.queue_free()
			return
	fragment.set("breakable", false)
	fragment.apply_central_impulse(direction.normalized() * fragment.mass * (2.0 if blast else 0.08))


# Blender suffixes distinguish imported nodes, not the authored part hierarchy.
static func _piece_id(value: String) -> String:
	var suffix := value.get_extension()
	return value.get_basename() if suffix.is_valid_int() else value


static func _continuation_frame(geometry: GEOMETRY, piece: RigidBody3D) -> Transform3D:
	if piece == null: return Transform3D.IDENTITY
	var stage := int(piece.get("stage_index"))
	for mesh in DAMAGE.reveal_meshes(geometry.stages[stage]):
		if _piece_id(mesh.name) != _piece_id(str(piece.get("piece_name"))): continue
		for child in piece.get_children():
			if child is MeshInstance3D:
				return child.global_transform * mesh.global_transform.affine_inverse()
	return Transform3D.IDENTITY


static func shatter_glass(body: RigidBody3D, geometry: GEOMETRY, hit_position: Vector3, direction: Vector3) -> void:
	SFX.play(body, &"glass_break", hit_position)
	var glass_bounds := AABB()
	var found := false
	var panes: Array[MeshInstance3D] = []
	for i in geometry.meshes.size():
		var mesh := geometry.meshes[i]
		if not is_instance_valid(mesh) or not GEOMETRY.is_glass_mesh(mesh):
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		glass_bounds = bounds if not found else glass_bounds.merge(bounds)
		found = true
		panes.append(mesh)
		if "glass" in mesh.name.to_lower() or "mirror" in mesh.name.to_lower() or mesh.mesh.get_surface_count() == 1:
			mesh.hide()
			geometry.shapes[i].set_deferred("disabled", true)
	if not found:
		return
	var floor_view := body.get("glass_debris_floor") as Node3D
	if is_instance_valid(floor_view):
		floor_view.call("scatter_glass_debris", panes, direction)
	var shards: Node3D = DAMAGE.find_named(geometry.visual, "Glass_Shards")
	if shards != null:
		# Vending machines keep their shard group below a hidden damage variant.
		# Reveal its parents only while copying shard geometry.
		var hidden_parents: Array[Node3D] = []
		var ancestor := shards.get_parent() as Node3D
		while ancestor != null and ancestor != geometry.visual:
			if ancestor.scale.length_squared() < 0.000001:
				hidden_parents.append(ancestor)
				ancestor.scale = Vector3.ONE
			ancestor = ancestor.get_parent() as Node3D
		var meshes: Array[MeshInstance3D] = DAMAGE.reveal_meshes(shards)
		for index in mini(meshes.size(), 12):
			DAMAGE.spawn_piece(body, meshes[index], body, geometry.stages.size(), index, direction, hit_position, false, true)
		for hidden in hidden_parents:
			hidden.scale = Vector3.ZERO
	elif _nothing_visible(geometry):
		# A drinking glass is only its pane: with the pane hidden nothing stands, so the pane itself breaks.
		for index in panes.size():
			DAMAGE.spawn_piece(body, panes[index], body, geometry.stages.size(), index, direction, hit_position, false, true)
		body.collision_layer = 0
		body.freeze = true
	else:
		_spawn_fallback_glass(body, geometry, glass_bounds, hit_position, direction)


static func _nothing_visible(geometry: GEOMETRY) -> bool:
	for mesh in geometry.meshes:
		if is_instance_valid(mesh) and mesh.is_visible_in_tree():
			return false
	return true


static func _spawn_fallback_glass(body: RigidBody3D, geometry: GEOMETRY, bounds: AABB, hit_position: Vector3, direction: Vector3) -> void:
	for i in 6:
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.12, 0.025)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.84, 0.95, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = material
		part.mesh = box
		geometry.visual.add_child(part)
		part.global_position = bounds.position + Vector3(randf() * bounds.size.x, randf() * bounds.size.y, randf() * bounds.size.z)
		DAMAGE.spawn_piece(body, part, null, geometry.stages.size(), i, direction, hit_position, false, true)
		part.queue_free()
