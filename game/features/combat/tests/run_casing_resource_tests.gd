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
	await _check_landed_casing_freezes()
	await _check_landed_casing_bakes_onto_floor()
	print("Casing resource tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _check_landed_casing_freezes() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	stage.add_child(floor_body)
	var service := CASINGS.new()
	stage.add_child(service)
	service.configure_world(stage, null)
	service.spawn_casing(MODEL, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), .01, null, &"")
	var body: RigidBody3D = service.get("_casings")[0]
	# A rolling casing can take several seconds to slow under the threshold, so wait for the freeze with a bound.
	for frame in 1200:
		if body.freeze:
			break
		await physics_frame
	_check(body.freeze, "A casing that has landed and stopped freezes in place")
	_check(body.global_position.y < .05, "A frozen casing rests on the floor")
	stage.queue_free()
	await process_frame

func _check_landed_casing_bakes_onto_floor() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	stage.add_child(floor_body)
	var stub := GDScript.new()
	stub.source_code = "extends Node3D\nvar stamps := []\nfunc stamp_casing_debris(at: Vector2) -> bool:\n\tstamps.append(at)\n\treturn true\n"
	stub.reload()
	var floor_view: Node3D = stub.new()
	stage.add_child(floor_view)
	var service := CASINGS.new()
	stage.add_child(service)
	service.configure_world(stage, null)
	service.configure_floor_debris(floor_view)
	service.spawn_casing(MODEL, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), .01, null, &"")
	var body: RigidBody3D = service.get("_casings")[0]
	for frame in 1200:
		if (service.get("_casings") as Array).is_empty():
			break
		await physics_frame
	_check((service.get("_casings") as Array).is_empty(), "A landed casing leaves the live casing list once baked")
	_check(not is_instance_valid(body) or body.is_queued_for_deletion(), "A baked casing removes its physical body")
	_check((floor_view.get("stamps") as Array).size() == 1, "A baked casing stamps the floor exactly once")
	stage.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
