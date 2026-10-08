extends SceneTree
## Exports the live posed meshes for deterministic contact preview without a GPU.
const PLAYER := preload("res://game/features/player/public/player.tscn")
var _actor: Node3D
var _out := ""

func _initialize() -> void:
	_out = OS.get_cmdline_user_args()[0]
	call_deferred("_capture")

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	_actor = PLAYER.instantiate()
	root.add_child(_actor)
	_actor.set_physics_process(false)
	_actor.get_node("Body").rotation = Vector3.ZERO
	_actor.get_node("AimPivot").rotation.y = PI
	_actor.call("configure_weapon_drop", func(_index: int, _point: Vector3) -> bool: return true)
	_actor.set("_aim_point", Vector3.INF)
	_actor.get_node("WeaponMount").get("equipment_pose").set("capture_pose", true)
	for index in [4, 5, 6, 7]:
		_actor.call("pickup_weapon", index)
		_actor.get_node("AnimationDriver").call("configure_clip_selector", _actor.get("_animation_selection").select_clip)
		await process_frame
		await process_frame
		await process_frame
		var pose: Node = _actor.get_node("WeaponMount").get("equipment_pose")
		var skeleton: Skeleton3D = _actor.get_node("WeaponMount").get("skeleton")
		var gun: Node3D = _actor.call("get_current_weapon")
		_actor.get_node("WeaponMount").call("sync_weapon", gun)
		print("ERROR_DISTANCE ", pose.hand_error, " lengths ", pose.arm_geometry)
		print("POSE ", gun.name, " left hand ", skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin, " grip ", (gun.find_child("Grip_L", true, false) as Node3D).global_position, " right ", gun.global_position)
		var scene := Node3D.new()
		for source in _actor.find_children("*", "MeshInstance3D", true, false):
			var mesh := source as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
			var baked := _bake(mesh)
			scene.add_child(baked)
		var state := GLTFState.new()
		var document := GLTFDocument.new()
		var err := document.append_from_scene(scene, state)
		if err == OK: err = document.write_to_filesystem(state, _out.path_join(str(index) + ".glb"))
		assert(err == OK)
		scene.free()
	_actor.queue_free()
	await process_frame
	await process_frame
	quit()

func _bake(source: MeshInstance3D) -> MeshInstance3D:
	var baked := MeshInstance3D.new()
	baked.name = source.name
	var mesh := ArrayMesh.new()
	var skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
	var skin := source.skin
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		for i in vertices.size():
			var point := vertices[i]
			var normal := normals[i]
			if skeleton != null and skin != null and not bones.is_empty():
				point = Vector3.ZERO
				normal = Vector3.ZERO
				for j in 4:
					var bind := bones[i * 4 + j]
					var bone := skin.get_bind_bone(bind)
					if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
					var transform: Transform3D = skeleton.global_transform * (_actor.get_node("WeaponMount").get("equipment_pose").posed_bones[bone]) * skin.get_bind_pose(bind)
					point += (transform * vertices[i]) * weights[i * 4 + j]
					normal += (transform.basis * normals[i]) * weights[i * 4 + j]
			else:
				point = source.global_transform * point
				normal = source.global_basis * normal
			vertices[i] = point
			normals[i] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, source.get_active_material(surface))
	baked.mesh = mesh
	return baked
