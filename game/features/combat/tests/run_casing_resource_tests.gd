extends SceneTree

const CASINGS := preload("res://game/features/combat/public/spent_casings.gd")
const MODEL := preload("res://models/objects/enviroments/12/12_pistol_casing.glb")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var service := CASINGS.new()
	stage.add_child(service)
	service.configure_world(stage, null)
	_check(not service.is_processing(), "Empty casing service has no cleanup callback")
	service.spawn_casing(MODEL, Transform3D.IDENTITY, .01, null, &"")
	var first: RigidBody3D = service.get("_casings")[0]
	var shape: Shape3D = first.get_child(0).shape
	var surface := first.physics_material_override
	service.spawn_casing(MODEL, Transform3D.IDENTITY, .01, null, &"")
	var second: RigidBody3D = service.get("_casings")[1]
	_check(first != second and first.get_child(1) != second.get_child(1), "Each live casing retains independent body and visual state")
	_check(second.get_child(0).shape == shape and second.physics_material_override == surface, "Identical casings reuse immutable collision and physical material resources")
	service.spawn_casing(MODEL, Transform3D.IDENTITY, .01, null, &"", .7)
	var small: RigidBody3D = service.get("_casings")[2]
	_check(small.get_child(0).shape != shape and is_equal_approx(small.get_child(0).shape.radius, .021), "Scaled casing gets its own correct cached shape")
	_check(is_equal_approx((shape as SphereShape3D).radius, .03), "Scaled spawn never changes an existing shared shape")
	var started := Time.get_ticks_usec()
	for index in 100:
		service.spawn_casing(MODEL, Transform3D.IDENTITY, .01, null, &"")
	var duration := Time.get_ticks_usec() - started
	_check((service.get("_casings") as Array).size() == 40, "Casing cap remains forty after a burst")
	_check((service.get("_shapes") as Dictionary).size() == 2, "A repeated burst does not allocate more collision shapes")
	print("Casing sample: 100 spawns %d us, retained 40, cached shapes 2; CI CPU sample, not target FPS" % duration)
	await process_frame
	for body: RigidBody3D in service.get("_casings"):
		body.queue_free()
	await process_frame
	service.call("_cleanup")
	_check(not service.is_processing(), "Removing every casing stops cleanup updates")
	stage.queue_free()
	await process_frame
	await process_frame
	print("Casing resource tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
