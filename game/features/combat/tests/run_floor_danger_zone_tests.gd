extends SceneTree
## Runtime checks for the floor warning under a blast: it lies flat on the floor
## under the impact, appears only after its delay and removes itself when done.

const ZONE := preload("res://game/features/combat/public/floor_danger_zone.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(20, 0.2, 20)
	floor_shape.shape = slab
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.1, 0)
	stage.add_child(floor_body)
	var desk := StaticBody3D.new()
	var desk_shape := CollisionShape3D.new()
	var top := BoxShape3D.new()
	top.size = Vector3(2, 0.8, 2)
	desk_shape.shape = top
	desk.add_child(desk_shape)
	desk.position = Vector3(2.0, 0.4, 0.0)
	stage.add_child(desk)
	await physics_frame
	await physics_frame

	ZONE.spawn(stage, root.get_world_3d(), Vector3(2.0, 1.2, 0.0), 3.0, 0.3, 1.6)
	var zone := stage.get_child(stage.get_child_count() - 1) as Node3D
	var meshes := zone.get_children().filter(func(child: Node) -> bool: return child is MeshInstance3D)
	_expect(meshes.size() == 1, "The zone is one shaded surface")
	_expect(absf(zone.global_position.y - ZONE.LIFT) < 0.01 and absf(zone.global_position.x - 2.0) < 0.01, "The zone lies on the floor, not on a desk under the impact (%s)" % zone.global_position)
	var surface := meshes[0] as MeshInstance3D
	_expect(surface.get_aabb().size.y < 0.2 and absf(surface.get_aabb().size.x - 6.0) < 0.01, "The surface is flat and spans the blast radius")

	await create_timer(0.1).timeout
	_expect(is_instance_valid(zone) and _fade(surface) < 0.01, "The zone stays hidden before its delay")
	await create_timer(0.8).timeout
	_expect(is_instance_valid(zone) and _fade(surface) > 0.99, "The zone is fully visible after the delay")
	await create_timer(1.0).timeout
	_expect(not is_instance_valid(zone), "The zone removes itself when its lifetime ends")

	stage.queue_free()
	await process_frame
	print("Floor danger zone tests: %d failure(s)." % failures)
	quit(failures)


func _fade(surface: MeshInstance3D) -> float:
	return float(surface.get_instance_shader_parameter(&"fade"))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
