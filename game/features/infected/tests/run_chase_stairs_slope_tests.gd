extends SceneTree
const ROUTE := preload("res://game/features/infected/chase_route.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Slope: 15 degree ramp from x=-4 up to a plateau; step: a 0.1 m kerb at x=-4.
	await _scenario("slope", deg_to_rad(15.0), 0.0)
	await _scenario("step", 0.0, 0.1)
	print("Chase stairs slope tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


# Floor height under x for the scenario geometry (ground 0, ramp or kerb, plateau).
func _floor_y(x: float, angle: float, step_h: float) -> float:
	if angle > 0.0:
		var run := 6.0 * cos(angle)
		return clampf((x + 4.0) * tan(angle), 0.0, 6.0 * sin(angle)) if x < -4.0 + run else 6.0 * sin(angle)
	return step_h if x >= -4.0 else 0.0


func _scenario(label: String, angle: float, step_h: float) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := _box(stage, Vector3(80, 1, 20), Vector3(0, -.5, 0), 0.0)
	var top := 6.0 * sin(angle) if angle > 0.0 else step_h
	if angle > 0.0:
		# Ramp slab whose upper face starts at (-4, 0) and rises at `angle`.
		var run := 6.0 * cos(angle)
		var slab := _box(stage, Vector3(6, 1, 10), Vector3.ZERO, angle)
		slab.position = Vector3(-4.0 + run * .5, top * .5, 0) + Vector3(sin(angle), -cos(angle), 0) * .5
		_box(stage, Vector3(40, 1, 20), Vector3(-4.0 + run + 20.0, top - .5, 0), 0.0)
	else:
		_box(stage, Vector3(40, 1, 20), Vector3(16.0, step_h - .5, 0), 0.0)
	var actor := CharacterBody3D.new()
	var body := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .35
	capsule.height = 1.8
	body.shape = capsule
	actor.add_child(body)
	stage.add_child(actor)
	actor.position = Vector3(-12, .91, 0)
	var target := Node3D.new()
	stage.add_child(target)
	target.position = Vector3(8, top + .91, 0)
	await physics_frame
	var route := ROUTE.new()
	var reached := -1.0
	var bad := 0
	for tick in 1200:
		await physics_frame
		var dir: Vector3 = route.direction(actor, target, .35)
		actor.velocity.x = dir.x * 3.0
		actor.velocity.z = dir.z * 3.0
		if actor.is_on_floor():
			actor.velocity.y = 0.0
		else:
			actor.velocity.y -= 20.0 / 60.0
		actor.move_and_slide()
		var gap := actor.position.y - .9 - _floor_y(actor.position.x, angle, step_h)
		if not actor.is_on_floor() and (gap < -.05 or gap > .1):
			bad += 1
		if actor.position.distance_to(target.position) <= 1.5:
			reached = float(tick) / 60.0
			break
	print("%s: reached %.2f s, off-floor ticks %d, actor %s" % [label, reached, bad, actor.position])
	_check(reached >= 0.0 and reached <= 20.0, "%s: enemy reaches the target within 20 s" % label)
	_check(bad == 0, "%s: enemy stays on the floor while chasing (%d bad ticks)" % [label, bad])
	stage.queue_free()
	await process_frame


func _box(parent: Node3D, size: Vector3, pos: Vector3, tilt: float) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	s.shape = box
	b.add_child(s)
	parent.add_child(b)
	b.position = pos
	b.rotation.z = tilt
	return b


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
