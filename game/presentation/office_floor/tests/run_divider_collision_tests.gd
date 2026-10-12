extends SceneTree
## Office dividers keep their desk open between the walls: a single box around
## the flattened mesh left an invisible lid at panel height, so body parts and
## props came to rest hanging above the desk instead of on it.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const ROOT := "res://models/objects/enviroments/08/"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	for model in ["08_divider_full_H_desk", "08_divider_full_U_desk"]:
		var desk := PROP.instantiate() as RigidBody3D
		desk.set("model_path", ROOT + model + ".glb")
		stage.add_child(desk)
		desk.freeze = true
		await physics_frame
		await physics_frame
		var space := desk.get_world_3d().direct_space_state
		var wall := _top(space, desk.global_position + Vector3(0.93, 0, 0.3))
		var seat := _top(space, desk.global_position + Vector3(0, 0, 0.3))
		_check(wall > 1.2, "%s side wall is solid (%.2f m)." % [model, wall])
		_check(seat > 0.4 and seat < wall - 0.3, "%s desk top is reachable between the walls (%.2f m, wall %.2f m)." % [model, seat, wall])
		desk.queue_free()
		await process_frame
	stage.queue_free()
	await process_frame
	print("Divider collision tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


# Highest collision under a point, measured from the desk origin height.
func _top(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at - Vector3.UP * 5.0, 0xFFFFFFFF))
	return float(hit["position"].y) if not hit.is_empty() else -99.0


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
