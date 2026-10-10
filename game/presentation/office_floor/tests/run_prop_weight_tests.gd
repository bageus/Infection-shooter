extends SceneTree
## prop_weight_v1 (ADR-0032): item weights, walking pushes limited by weight
## and character strength, feet kicking light items aside instead of blocking,
## and every gunshot shoving loose items by their weight.

const WEIGHT := preload("res://game/presentation/office_floor/prop_weight.gd")
const BULLET_PUSH := preload("res://game/presentation/office_floor/bullet_push.gd")
const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := "res://models/objects/enviroments/"
const BOX := MODELS + "04/04_cardboard_box_closed.glb"
const CRATE := MODELS + "04/04_crate_large_broken.glb"
const VENDING := MODELS + "02/02_vending_automat_1_dented.glb"
const MUG := MODELS + "09/09_mug.glb"
const SMALL_BOX := MODELS + "04/04_cardboard_boxes_1.glb"
const CHAIR := MODELS + "06/06_simple_chair.glb"
const TRASH_BIN := MODELS + "09/09_trash_bin.glb"
const LONG_TABLE := MODELS + "07/07_table_longest.glb"

# Mirrors the player/infected contact loop: pushes use the intended motion.
class Walker:
	extends CharacterBody3D
	var walk := Vector3.ZERO
	var push_strength := 1.0
	func _physics_process(delta: float) -> void:
		velocity = Vector3(walk.x, velocity.y - 24.0 * delta, walk.z)
		if is_on_floor():
			velocity.y = 0.0
		var intended := Vector3(velocity.x, 0.0, velocity.z)
		move_and_slide()
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider()
			if collider != null and collider.has_method("push_from_character"):
				collider.call("push_from_character", global_position, intended, push_strength)

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rules()
	await _test_box_is_pushed()
	await _test_weight_slows_push()
	await _test_strength()
	await _test_heavy_blocks()
	await _test_kicks()
	await _test_shots_move_items()
	print("Prop weight tests: %d failure(s)." % failures)
	quit(failures)


func _test_rules() -> void:
	_expect(WEIGHT.weight_kg("04_cardboard_box_closed.glb", 1.0) < WEIGHT.weight_kg("04_military_crate.glb", 0.1), "Cardboard weighs less than a military crate.")
	_expect(is_equal_approx(WEIGHT.weight_kg("09_tablet.glb", 1.0), 0.6) and is_equal_approx(WEIGHT.weight_kg("09_toilet_paper_roll_v.glb", 1.0), 0.12), "Specific small items are not mistaken for tables or toilets.")
	_expect(is_equal_approx(WEIGHT.weight_kg("unknown_thing.glb", 0.5), 30.0), "Unknown models fall back to a volume estimate.")
	_expect(WEIGHT.push_speed(3.0, 1.0, 6.0) > WEIGHT.push_speed(12.0, 1.0, 6.0) * 2.0, "A light item slides much faster than a heavy one.")
	_expect(WEIGHT.push_speed(3.0, 1.0, 6.0) < 6.0 * 0.7, "Even a light box slows the walker down.")
	_expect(not WEIGHT.can_push(32.0, 1.0) and WEIGHT.can_push(32.0, 2.0), "A military crate needs a Brute's strength.")
	_expect(not WEIGHT.can_push(240.0, 3.2), "Nobody walks a vending machine across the floor.")
	_expect(WEIGHT.kick_speed(0.02, 1.0, 6.0) > WEIGHT.kick_speed(1.2, 1.0, 6.0), "Lighter items are kicked further.")
	_expect(WEIGHT.is_kickable(0.35, Vector3(0.14, 0.12, 0.14)), "A mug is kicked aside.")
	_expect(not WEIGHT.is_kickable(3.0, Vector3(0.43, 0.43, 0.4)), "A full cardboard box is pushed, not kicked.")


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3 # As the mission floor.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	return stage


func _prop(stage: Node3D, model: String, at: Vector3) -> RigidBody3D:
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", model)
	stage.add_child(prop)
	prop.global_position = at
	return prop


func _walker(stage: Node3D, at: Vector3, strength := 1.0) -> Walker:
	var walker := Walker.new()
	walker.collision_layer = 1
	walker.collision_mask = 3
	walker.push_strength = strength
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.8
	shape.shape = capsule
	walker.add_child(shape)
	stage.add_child(walker)
	walker.global_position = at
	return walker


# Lets the item settle, then walks toward +X for `seconds`; returns the item's travel.
func _walk_into(model: String, seconds: float, strength := 1.0, weight_override := -1.0) -> Dictionary:
	var stage := _stage()
	var prop := _prop(stage, model, Vector3(2.0, 0.05, 0))
	if weight_override > 0.0:
		prop.set("weight_kg", weight_override)
	for frame in 30:
		await physics_frame
	var walker := _walker(stage, Vector3(0, 0.92, 0), strength)
	var start := prop.global_position
	await physics_frame
	walker.walk = Vector3(5.0, 0, 0)
	await create_timer(seconds).timeout
	var result := {"moved": Vector2(prop.global_position.x - start.x, prop.global_position.z - start.z).length(), "walked": walker.global_position.x, "weight": float(prop.get("weight_kg"))}
	stage.queue_free()
	await process_frame
	return result


func _test_box_is_pushed() -> void:
	var result := await _walk_into(BOX, 1.5)
	_expect(float(result["moved"]) > 1.0, "Walking into a cardboard box pushes it (moved %.2f m)." % float(result["moved"]))
	_expect(float(result["walked"]) > 2.0, "The box does not stop the walker dead (walked %.2f m)." % float(result["walked"]))
	_expect(float(result["walked"]) < 5.0 * 1.5 * 0.85, "Pushing a box is slower than walking freely (walked %.2f m)." % float(result["walked"]))


func _test_weight_slows_push() -> void:
	var light := await _walk_into(BOX, 1.5)
	var heavy := await _walk_into(CRATE, 1.5)
	_expect(float(heavy["weight"]) > float(light["weight"]), "The wooden crate is heavier than the box.")
	_expect(float(heavy["moved"]) < float(light["moved"]) * 0.75, "A heavier crate moves less (box %.2f m, crate %.2f m)." % [float(light["moved"]), float(heavy["moved"])])
	_expect(float(heavy["moved"]) > 0.15, "The player can still shift a 12 kg crate (moved %.2f m)." % float(heavy["moved"]))


func _test_strength() -> void:
	var player := await _walk_into(CRATE, 1.2, 1.0, 32.0)
	var brute := await _walk_into(CRATE, 2.0, 2.0, 32.0)
	_expect(float(player["moved"]) < 0.08, "The player cannot push a 32 kg crate (moved %.2f m)." % float(player["moved"]))
	_expect(float(brute["moved"]) > 0.15, "A Brute shoves the 32 kg crate (moved %.2f m)." % float(brute["moved"]))


func _test_heavy_blocks() -> void:
	var result := await _walk_into(VENDING, 1.0, 3.2)
	_expect(float(result["moved"]) < 0.05, "Even a Colossus cannot walk a vending machine away (moved %.2f m)." % float(result["moved"]))


func _test_kicks() -> void:
	for model in [MUG, SMALL_BOX]:
		var stage := _stage()
		var prop := _prop(stage, model, Vector3(1.2, 0.05, 0))
		for frame in 30:
			await physics_frame
		_expect(prop.collision_layer == 4 and bool(prop.get_meta(&"kickable_prop", false)), "%s is kickable and does not block characters." % model.get_file())
		var walker := _walker(stage, Vector3(0, 0.92, 0))
		var start := prop.global_position
		await physics_frame
		walker.walk = Vector3(5.0, 0, 0)
		await create_timer(0.8).timeout
		_expect(walker.global_position.x > 3.0, "%s does not stop the walker (walked %.2f m)." % [model.get_file(), walker.global_position.x])
		_expect(prop.global_position.distance_to(start) > 0.3, "%s is kicked away (moved %.2f m)." % [model.get_file(), prop.global_position.distance_to(start)])
		stage.queue_free()
		await process_frame


# Weight controls the initial push; collider shape/contact affects final travel.
func _test_shots_move_items() -> void:
	_expect(BULLET_PUSH.speed("PISTOL", 2.5) > BULLET_PUSH.speed("PISTOL", 4.5) and BULLET_PUSH.speed("PISTOL", 4.5) > BULLET_PUSH.speed("PISTOL", 150.0) * 10.0, "Shots push light items much further than heavy ones.")
	_expect(BULLET_PUSH.speed("PISTOL", 0.01) <= BULLET_PUSH.MAX_SPEED, "A single hit never launches an item faster than the cap.")
	_expect(BULLET_PUSH.speed("RIFLE", 4.5) > BULLET_PUSH.speed("UZI", 4.5), "A rifle round pushes harder than an Uzi round.")
	var stage := _stage()
	var chair := _prop(stage, CHAIR, Vector3(0, 0.05, 0))
	var bin := _prop(stage, TRASH_BIN, Vector3(4, 0.05, 0))
	var table := _prop(stage, LONG_TABLE, Vector3(10, 0.05, 0))
	for frame in 40:
		await physics_frame
	var starts := [chair.global_position, bin.global_position, table.global_position]
	var first_push: Array[float] = []
	for shot in 3:
		var speeds_before: Array[float] = []
		for item: RigidBody3D in [chair, bin, table]:
			speeds_before.append(item.linear_velocity.x)
			item.call("take_projectile_hit", 6.0, item.global_position + Vector3(0, 0.4, 0), Vector3.UP, Vector3(1, 0, 0), "PISTOL")
		if shot == 0:
			# apply_impulse is consumed by the next physics step.
			await physics_frame
			await physics_frame
			for index in 3:
				var item: RigidBody3D = [chair, bin, table][index]
				first_push.append(item.linear_velocity.x - speeds_before[index])
		await create_timer(0.15).timeout
	await create_timer(0.8).timeout
	var moved: Array[float] = []
	for index in 3:
		var item: RigidBody3D = [chair, bin, table][index]
		moved.append(Vector2(item.global_position.x - starts[index].x, item.global_position.z - starts[index].z).length())
	_expect(moved[0] > 0.05, "Pistol shots move a chair (%.2f m)." % moved[0])
	_expect(moved[1] > 0.05, "Pistol shots move a trash bin (%.2f m)." % moved[1])
	_expect(first_push[1] > first_push[0] and first_push[0] > first_push[2] * 10.0, "A hit gives a lighter prop more speed (bin %.2f, chair %.2f, table %.2f m/s)." % [first_push[1], first_push[0], first_push[2]])
	_expect(moved[2] < 0.1, "A long table barely creeps (%.2f m)." % moved[2])
	stage.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
	else:
		print("ok: ", message)
