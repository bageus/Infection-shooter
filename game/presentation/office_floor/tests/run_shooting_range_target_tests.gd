extends SceneTree
## The shooting range target sits on the floor, shows its texture, and a shot drops it flat with a metal
## sound; the base stays in place, and the target stands up again after 10 seconds.

const TARGET := preload("res://game/presentation/office_floor/public/props/shooting_range_target.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var target := TARGET.instantiate() as Node3D
	root.add_child(target)
	target.global_position = Vector3(2, 0, 3)
	await process_frame
	var hinge := target.find_child("Hinge", false, false) as Node3D
	var base := target.find_child("Base", true, false) as Node3D
	_check(hinge != null and base != null, "hinge and base exist")
	_check(_lowest_point(target) < 0.01 and _lowest_point(target) > -0.01, "target stands on the floor (lowest point %.3f)" % _lowest_point(target))
	_check(_has_texture(target), "target face has its texture")
	var base_start := base.global_position
	var hit := _shoot(target)
	_check(hit == target, "a shot from the front hits the target body")
	_check(hit != null and hit.get_projectile_material() == "metal", "the post reports metal for the impact sound")
	if hit != null:
		hit.take_projectile_hit(10.0, hit.global_position, Vector3.BACK, Vector3.FORWARD, "AK")
	await create_timer(0.5).timeout
	_check(hinge.global_basis.y.dot(Vector3.UP) < 0.1, "post lies flat after the hit")
	_check(_lowest_point(target) > -0.01, "fallen post does not sink into the floor (lowest point %.3f)" % _lowest_point(target))
	_check(base.global_position.is_equal_approx(base_start), "base stays in place")
	if hit != null:
		hit.take_projectile_hit(10.0, hit.global_position, Vector3.BACK, Vector3.FORWARD, "AK")
	await create_timer(10.5).timeout
	_check(hinge.global_basis.y.dot(Vector3.UP) > 0.95, "post stands up again after 10 seconds")
	target.queue_free()
	await process_frame
	print("Shooting range target tests: %d failure(s)." % failures)
	quit(failures)


## A ray from in front of the target at post height, returning the body it hits.
func _shoot(target: Node3D) -> Node:
	var from := target.global_position + Vector3(0, 1.2, 2)
	var to := target.global_position + Vector3(0, 1.2, -2)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	return hit.collider if not hit.is_empty() else null


func _lowest_point(target: Node3D) -> float:
	var low := INF
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = target.global_transform.affine_inverse() * ((mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb())
		low = minf(low, box.position.y)
	return low


func _has_texture(target: Node3D) -> bool:
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if material != null and material.albedo_texture != null:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)
