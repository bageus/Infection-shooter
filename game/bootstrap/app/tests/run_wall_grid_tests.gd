extends SceneTree
const SURFACE := preload("res://game/bootstrap/app/planning_surface_placement.gd")
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1,0,1).normalized()]:
		var point := Vector3(1.13, 1.62, 3.17)
		var snapped: Vector3 = SURFACE.wall_grid(point, normal)
		assert(is_equal_approx(snapped.dot(normal), point.dot(normal)))
		assert(is_equal_approx(snapped.y, 1.5))
		var tangent := Vector3(normal.z, 0, -normal.x)
		assert(is_equal_approx(snapped.dot(tangent), snappedf(point.dot(tangent), 0.25)))
		assert(SURFACE.wall_grid(snapped, normal).is_equal_approx(snapped))
	var wall := StaticBody3D.new()
	wall.set_meta("planning_scene_path", "test")
	root.add_child(wall)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 2, 2)
	visual.mesh = mesh
	wall.add_child(visual)
	var contact: Vector3 = SURFACE.visual_wall_point(Vector3(0, 0, 1.05), Vector3.BACK, wall)
	assert(is_equal_approx(contact.z, 1.0))
	var item := Node3D.new()
	root.add_child(item)
	item.position = contact
	SURFACE.mount(item, AABB(Vector3(-0.2,-0.2,-0.2), Vector3(0.4,0.4,0.4)), Vector3.BACK)
	assert(is_equal_approx(item.position.z - 0.2, 1.0005))
	item.free()
	wall.free()
	print("Wall grid and contact tests PASS")
	quit()
