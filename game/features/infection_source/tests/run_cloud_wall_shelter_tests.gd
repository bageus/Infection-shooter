extends SceneTree
## N03: exhausting ignored furniture never proves that the rest of a ray is clear.
const FIELD := preload("res://game/features/infection_source/cloud_wall_field.gd")
const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")

class Prop extends RigidBody3D:
	var model_path := ""

class Absorber extends CharacterBody3D:
	var absorbed := 0.0
	var healed := 0.0
	func absorb_mutagen(seconds: float) -> float:
		absorbed += seconds
		return seconds * 5.0
	func heal(amount: float) -> float:
		healed += amount
		return amount

var failures := 0
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for count in [0, 7, 8, 9, 16, 64]:
		for side in [-1.0, 1.0]:
			for kind in ["static", "structural"]:
				await _chain(count, side, kind, true)
				await _chain(count, side, kind, false)
	await _ignored()
	await _doorway()
	await _mask()
	for permanent in [false, true]:
		for wall in [false, true]:
			await _absorption(permanent, wall)
	print("Cloud wall shelter tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _start() -> void:
	FIELD._cache.clear()
	stage = Node3D.new()
	root.add_child(stage)


func _chain(count: int, side: float, kind: String, with_wall: bool) -> void:
	_start()
	var target := Absorber.new()
	_box(target, Vector3(side * 3, 0, 0), Vector3(.1, 2, .1))
	if with_wall:
		var barrier: PhysicsBody3D = StaticBody3D.new() if kind == "static" else Prop.new()
		if barrier is Prop:
			barrier.model_path = "res://models/objects/enviroments/01/01_wall_straight.glb"
			barrier.gravity_scale = 0.0
		_box(barrier, Vector3(side * 2, 1, 0), Vector3(.05, 3, 3))
	for index in count:
		var prop := Prop.new()
		prop.freeze = index % 2 == 0
		prop.gravity_scale = 0.0
		_box(prop, Vector3(side * lerpf(.1, 1.8, float(index) / maxi(1, count - 1)), 1, 0), Vector3(.01, 2, .2))
	var cloud := Area3D.new()
	stage.add_child(cloud)
	await _sync()
	var ignored: Array[RID] = [target.get_rid()]
	var distance := FIELD.barrier_distance(stage.get_world_3d(), Vector3(0, FIELD.HEIGHT, 0), Vector3(side * 3, FIELD.HEIGHT, 0), ignored)
	var expected := 1.975 if with_wall else 3.0
	_check(is_equal_approx(distance, expected), "%s, %d props, side %.0f, wall=%s: distance %.3f == %.3f" % [kind, count, side, with_wall, distance, expected])
	_check(FIELD.clear_to(cloud, target) != with_wall, "clear_to agrees with the actual barrier, never an attempt cap")
	await _clear()


func _ignored() -> void:
	_start()
	var excluded := StaticBody3D.new()
	_box(excluded, Vector3(.5, 1, 0), Vector3(.05, 2, .2))
	_box(StaticBody3D.new(), Vector3(2, 1, 0), Vector3(.05, 3, 3))
	var ignored: Array[RID] = [excluded.get_rid()]
	await _sync()
	var distance := FIELD.barrier_distance(stage.get_world_3d(), Vector3(0, .8, 0), Vector3(3, .8, 0), ignored)
	_check(is_equal_approx(distance, 1.975), "Caller-supplied excluded RID stays excluded")
	_check(ignored.size() == 1 and ignored[0] == excluded.get_rid(), "Query never mutates the caller's exclusions")
	await _clear()


func _doorway() -> void:
	_start()
	# Two jambs and a lintel, with a real unobstructed opening at x=0.
	for x in [-1.5, 1.5]:
		_box(StaticBody3D.new(), Vector3(x, 1.5, 0), Vector3(1, 3, .1))
	_box(StaticBody3D.new(), Vector3(0, 2.75, 0), Vector3(2, .5, .1))
	var cloud := Area3D.new()
	stage.add_child(cloud)
	cloud.position.z = -1.4
	var target := Absorber.new()
	_box(target, Vector3(0, 0, 1.4), Vector3(.1, 2, .1))
	var props: Array[Prop] = []
	for index in 10:
		var prop := Prop.new()
		prop.freeze = true
		_box(prop, Vector3(0, 1, lerpf(-1.3, -.2, float(index) / 9)), Vector3(.1, 2, .01))
		props.append(prop)
	await _sync()
	_check(FIELD.clear_to(cloud, target), "Ten props do not turn an open doorway into a wall")
	cloud.position.x = 1.5
	target.position.x = 1.5
	for prop in props:
		prop.position.x = 1.5
	await _sync()
	_check(not FIELD.clear_to(cloud, target), "The same doorway's jamb blocks the ray beyond furniture")
	await _clear()


func _mask() -> void:
	# Read the CPU image used by the real texture builder, even on headless Dummy.
	for side in [-1.0, 1.0]:
		_start()
		var wall := StaticBody3D.new()
		_box(wall, Vector3(side * 1.5, 1, 0), Vector3(.05, 3, 4))
		for index in 8:
			var prop := Prop.new()
			prop.freeze = true
			_box(prop, Vector3(side * lerpf(.1, 1.35, float(index) / 7), 1, 0), Vector3(.01, 2, 4))
		var cloud := Area3D.new()
		stage.add_child(cloud)
		await _sync()
		var index := 12 if side > 0.0 else 0
		var angle := (float(index) + .5) * TAU / float(FIELD.RAYS) - PI
		var expected := 1.475 / absf(cos(angle)) / FIELD.RADIUS
		var image := FIELD._build_image(cloud)
		_check(image.get_width() == FIELD.RAYS and image.get_height() == 1, "Mask retains its 24 by 1 samples")
		_check(absf(image.get_pixel(index, 0).r - expected) < .001, "Mask ray stops at the real wall behind eight props")
		var texture := FIELD.texture_for(cloud)
		_check(texture != null and FIELD.texture_for(cloud) == texture, "The existing recent-spot texture cache is still shared")
		wall.collision_layer = 0
		await _sync()
		var open_image := FIELD._build_image(cloud)
		_check(is_equal_approx(open_image.get_pixel(index, 0).r, 1.0), "Fresh mask ray opens after the wall is disabled")
		await _clear()


func _absorption(permanent: bool, with_wall: bool) -> void:
	_start()
	var cloud := CLOUD.instantiate() as Area3D
	cloud.set("permanent", permanent)
	cloud.set("heals_visitors", not permanent)
	cloud.set("absorb_delay", 0.0)
	stage.add_child(cloud)
	cloud.set_physics_process(false)
	var target := Absorber.new()
	_box(target, Vector3(1.4, .7, 0), Vector3(.2, 1, .2))
	var wall := StaticBody3D.new()
	_box(wall, Vector3(.95, 1, 0), Vector3(.05, 3, 3))
	wall.collision_layer = 1 if with_wall else 0
	for index in 8:
		var prop := Prop.new()
		prop.freeze = true
		_box(prop, Vector3(lerpf(.1, .8, float(index) / 7), 1, 0), Vector3(.01, 2, .3))
	await _sync()
	cloud.call("activate")
	var material := (cloud.get_node("Visual") as GeometryInstance3D).material_override as ShaderMaterial
	_check(material.get_shader_parameter("wall_mask") == FIELD.texture_for(cloud), "Activation installs the actual cached wall mask in the smoke material")
	await _sync()
	_check(cloud.get_overlapping_bodies().has(target), "Recipient truly overlaps the cloud Area, even across the wall")
	var budget := float(cloud.get("_absorption_remaining"))
	cloud.call("_physics_process", .1)
	_check((target.absorbed > 0.0) != with_wall, "Real cloud feeds an overlapping recipient only with a clear path")
	if not permanent:
		_check((target.healed > 0.0) != with_wall, "Devourer healing also respects the wall beyond eight props")
		var expected := budget if with_wall else budget - .1
		_check(is_equal_approx(float(cloud.get("_absorption_remaining")), expected), "Blocked cloud never spends its absorption budget")
	wall.collision_layer = 0 if with_wall else 1
	await _sync()
	var previous := target.absorbed
	cloud.call("_physics_process", .1)
	_check((target.absorbed > previous) == with_wall, "Absorption queries see a newly disabled/enabled barrier on the next physics frame")
	await _clear()


func _box(body: PhysicsBody3D, at: Vector3, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	(collision.shape as BoxShape3D).size = size
	body.add_child(collision)
	body.collision_layer = 1
	body.collision_mask = 0
	stage.add_child(body)
	body.position = at


func _sync() -> void:
	await physics_frame
	await physics_frame


func _clear() -> void:
	stage.queue_free()
	await process_frame
	await physics_frame
	FIELD._cache.clear()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
