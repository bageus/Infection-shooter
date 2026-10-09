extends RefCounted
## Presents prop breakup: localized facade chips, staged fragments and glass shards.
## The root owns durability and supplies its geometry and effects container.

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const GEOMETRY := preload("res://game/presentation/office_floor/environment_prop_geometry.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")


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


static func spawn_stage(body: RigidBody3D, geometry: GEOMETRY, stage_index: int, prefix: String, hit_position: Vector3, direction: Vector3, blast: bool = false) -> bool:
	if stage_index >= geometry.stages.size():
		return false
	var meshes: Array[MeshInstance3D] = DAMAGE.reveal_meshes(geometry.stages[stage_index])
	var spawned := 0
	for mesh in meshes:
		if not prefix.is_empty() and mesh.name != prefix and not mesh.name.begins_with(prefix + "_"):
			continue
		if spawned >= 32:
			break
		var fragment: RigidBody3D = DAMAGE.spawn_piece(body, mesh, body, stage_index, spawned, direction, hit_position, blast)
		if fragment != null:
			spawned += 1
	return spawned > 0


static func hit_fragment(body: RigidBody3D, geometry: GEOMETRY, fragment: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	var name_part: String = fragment.get("piece_name")
	var next_stage: int = int(fragment.get("stage_index")) + 1
	while next_stage < geometry.stages.size():
		if spawn_stage(body, geometry, next_stage, name_part, hit_position, direction):
			fragment.queue_free()
			return
		next_stage += 1
	# A single-piece stage (a knocked-over plant pot) shatters into the whole next stage.
	var stage_index := int(fragment.get("stage_index"))
	if stage_index + 1 < geometry.stages.size() and DAMAGE.reveal_meshes(geometry.stages[stage_index]).size() == 1:
		if spawn_stage(body, geometry, stage_index + 1, "", hit_position, direction, true):
			fragment.queue_free()
			return
	fragment.apply_central_impulse(direction.normalized() * 0.6)


static func shatter_glass(body: RigidBody3D, geometry: GEOMETRY, hit_position: Vector3, direction: Vector3) -> void:
	SFX.play(body, &"glass_break", hit_position)
	var glass_bounds := AABB()
	var found := false
	for i in geometry.meshes.size():
		var mesh := geometry.meshes[i]
		if not is_instance_valid(mesh) or not GEOMETRY.is_glass_mesh(mesh):
			continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		glass_bounds = bounds if not found else glass_bounds.merge(bounds)
		found = true
		if "glass" in mesh.name.to_lower() or "mirror" in mesh.name.to_lower() or mesh.mesh.get_surface_count() == 1:
			mesh.hide()
			geometry.shapes[i].set_deferred("disabled", true)
	if not found:
		return
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
			DAMAGE.spawn_piece(body, meshes[index], body, geometry.stages.size(), index, direction, hit_position)
		for hidden in hidden_parents:
			hidden.scale = Vector3.ZERO
	else:
		_spawn_fallback_glass(body, geometry, glass_bounds, hit_position, direction)


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
		DAMAGE.spawn_piece(body, part, null, geometry.stages.size(), i, direction, hit_position)
		part.queue_free()
