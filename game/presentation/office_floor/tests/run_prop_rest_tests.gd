extends SceneTree
const PHYSICAL := preload("res://game/presentation/office_floor/physical_prop.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const REST := preload("res://game/presentation/office_floor/prop_rest.gd")
const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
const BOX := "res://models/objects/enviroments/04/04_cardboard_box_closed.glb"
var failures := 0
class Grenade extends Node3D:
	var damage_multiplier := .01

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _commands()
	await _stack()
	await _falling_neighbor()
	await _wake_before_impact()
	await _resting_contact()
	await _planner_and_anchor()
	await _destroy_support()
	print("Prop rest tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, .2, 30)
	collider.shape = shape
	collider.position.y = -.1
	floor_body.add_child(collider)
	stage.add_child(floor_body)
	return stage

func _box(stage: Node3D, at: Vector3, size := Vector3.ONE) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(PHYSICAL)
	body.set("max_health", 5000.0)
	body.set("breakable", false)
	body.mass = 3.0
	body.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	stage.add_child(body)
	return body

func _settle(body: RigidBody3D, limit := 360) -> bool:
	for tick in limit:
		await physics_frame
		if bool(body.get_meta(REST.FROZEN, false)):
			return true
	return false

func _commands() -> void:
	var stage := _stage()
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", BOX)
	prop.position = Vector3(0, 1.0, 0)
	stage.add_child(prop)
	_check(await _settle(prop), "A naturally sleeping environment prop becomes statically frozen")
	prop.call("push_from_character", Vector3(-2, 0, 0), Vector3(6, 0, 0), 1.0)
	await physics_frame
	await physics_frame
	_check(not prop.freeze and prop.linear_velocity.x > .01, "Character push wakes and moves frozen furniture")
	_check(prop.get_node("ImpactSound").is_physics_processing(), "Wake resumes impact sound tracking")
	_check(await _settle(prop), "Pushed furniture can settle again")
	prop.call("take_projectile_hit", 1.0, prop.position, Vector3.UP, Vector3.RIGHT, "PISTOL")
	await physics_frame
	await physics_frame
	_check(not prop.freeze and prop.linear_velocity.x > .01, "Actual environment bullet command wakes and shoves frozen furniture")
	_check(await _settle(prop), "Shot furniture can settle again")
	var grenade := Grenade.new()
	stage.add_child(grenade)
	grenade.position = prop.position + Vector3(-1, 0, 0)
	EXPLOSION.explode(grenade, grenade.position, Vector3.UP, null, stage, null)
	_check(not prop.freeze and not prop.sleeping, "Actual grenade radius query wakes frozen furniture")
	await physics_frame
	await physics_frame
	_check(bool(prop.get("_broken")), "A grenade retains the existing destruction response of the environment prop")
	await _dispose(stage)
	stage = _stage()
	var body := _box(stage, Vector3(0, .52, 0))
	_check(await _settle(body), "Nonbreaking blast fixture is frozen")
	grenade = Grenade.new()
	stage.add_child(grenade)
	grenade.position = Vector3(-1, .5, 0)
	EXPLOSION.explode(grenade, grenade.position, Vector3.UP, null, stage, null)
	await physics_frame
	await physics_frame
	_check(not body.freeze and body.linear_velocity.x > .01, "Actual grenade applies a physical impulse to frozen nonbreaking furniture")
	await _dispose(stage)

func _stack() -> void:
	var stage := _stage()
	var boxes: Array[RigidBody3D] = []
	for index in 3:
		boxes.append(_box(stage, Vector3(0, .52 + index * 1.02, 0)))
	var all_resting := false
	for tick in 600:
		await physics_frame
		all_resting = boxes.all(func(body: RigidBody3D) -> bool: return body.freeze or body.sleeping)
		for body in boxes:
			if bool(body.get_meta(REST.FROZEN, false)):
				_check(body.linear_velocity.length() < .02, "A moving stack body cannot be frozen")
		if all_resting:
			break
	_check(all_resting, "A stable three-body stack rests without changing its mass response")
	var heights: Array[float] = []
	for body in boxes:
		heights.append(body.position.y)
	for tick in 120:
		await physics_frame
	for index in boxes.size():
		_check(absf(boxes[index].position.y - heights[index]) < .01, "Frozen stack remains settled without falling apart")
	boxes[0].queue_free()
	for tick in 90:
		await physics_frame
	_check(not bool(boxes[1].get_meta(REST.FROZEN, false)) or boxes[1].position.y < heights[1] - .5, "Removing support wakes the upper stack")
	_check(boxes[1].position.y < heights[1] - .5 and boxes[2].position.y < heights[2] - .5, "Unsupported stack falls instead of hanging in the air")
	await _dispose(stage)

func _falling_neighbor() -> void:
	var stage := _stage()
	var resting := _box(stage, Vector3(0, .52, 0))
	_check(await _settle(resting), "Collision fixture has frozen furniture")
	var falling := _box(stage, Vector3(.35, 3, 0))
	var woke := false
	for tick in 120:
		await physics_frame
		if not bool(resting.get_meta(REST.FROZEN, false)):
			woke = true
			break
	_check(woke and falling.position.y < 2.0, "A falling neighbor wakes frozen furniture through its impact contact")
	await _dispose(stage)

func _wake_before_impact() -> void:
	var stage := _stage()
	var target := _box(stage, Vector3(0, .52, 0))
	_check(await _settle(target), "Predictive impact fixture has frozen furniture")
	var incoming := _box(stage, Vector3(-2, .52, 0))
	incoming.linear_velocity = Vector3(6, 0, 0)
	var early := false
	for tick in 90:
		await physics_frame
		if not bool(target.get_meta(REST.FROZEN, false)):
			early = incoming.position.distance_to(target.position) > 1.01
			break
	_check(early, "A fast neighboring prop wakes furniture before physical contact")
	await _dispose(stage)

func _resting_contact() -> void:
	var stage := _stage()
	var support := _box(stage, Vector3(0, .52, 0))
	var item := _box(stage, Vector3(0, 1.2, 0), Vector3(.3, .3, .3))
	item.set_meta("kickable_prop", true)
	for tick in 180:
		await physics_frame
	_check(not bool(support.get_meta(REST.FROZEN, false)), "Desk supporting a small item retains native sleeping instead of a mass-changing freeze")
	for tick in 5:
		await physics_frame
	item.call("take_projectile_hit", 1.0, item.position, Vector3.UP, Vector3.RIGHT, "PISTOL")
	_check(not support.freeze, "A shot on an already touching item preserves dynamic support physics")
	await _dispose(stage)

func _planner_and_anchor() -> void:
	var stage := _stage()
	var body := _box(stage, Vector3(0, .52, 0))
	_check(await _settle(body), "Planner fixture has frozen furniture")
	paused = true
	body.position = Vector3(2, 3, 0)
	body.scale = Vector3.ONE * 1.1
	for frame in 4:
		await process_frame
	_check(not bool(body.get_meta(REST.FROZEN, false)) and not body.freeze, "Paused planner transform removes only the optimization freeze")
	_check(body.position.is_equal_approx(Vector3(2, 3, 0)), "Planner edit stays exactly where authored while paused")
	paused = false
	for tick in 60:
		await physics_frame
	_check(body.position.y < 2.0, "Edited furniture resumes physics after leaving the planner")
	var anchor := _box(stage, Vector3(5, .5, 0))
	anchor.freeze = true
	anchor.set_meta("planning_wall_mount", true)
	await process_frame
	REST.wake(anchor)
	anchor.call("push_from_character", Vector3(4, 0, 0), Vector3(6, 0, 0), 3.2)
	_check(anchor.freeze, "Wake never releases a wall-mounted or otherwise authored anchor")
	await _dispose(stage)

func _destroy_support() -> void:
	var stage := _stage()
	var support := _box(stage, Vector3(0, .5, 0))
	support.freeze = true
	var top := _box(stage, Vector3(0, 1.52, 0))
	_check(await _settle(top), "Furniture can rest on an authored static support")
	# The anchored body survives while its collision is removed, as a damaged prop does.
	REST.wake_supported(support)
	support.collision_layer = 0
	for child in support.get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	for tick in 60:
		await physics_frame
	_check(top.position.y < 1.0, "Disabling support collision also releases furniture before the support node is deleted")
	await _dispose(stage)

func _dispose(stage: Node3D) -> void:
	stage.queue_free()
	await process_frame
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
