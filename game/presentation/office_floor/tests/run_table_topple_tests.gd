extends SceneTree
## A broken table does not leave its legs standing, and its pieces never pass through each other.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const STAGED := preload("res://game/presentation/office_floor/public/props/07_table.tscn")
const MODEL_DIR := "res://models/objects/enviroments/07/"
const FLOOR_TOP := 0.0135
const MAX_OVERLAP := 0.05
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for model in ["07_table_circular", "07_table_square_tall", "07_round_dining_table", "07_table_longest"]:
		await _environment_table(model)
	for legs in [["Leg_BL"], ["Leg_BL", "Leg_BR"], ["Leg_BL", "Leg_FR"]]:
		await _staged_table(legs)
	print("Table topple tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _stage() -> Node3D:
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	ground.collision_layer = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	shape.position.y = FLOOR_TOP - 0.5
	ground.add_child(shape)
	stage.add_child(ground)
	return stage


func _environment_table(model: String) -> void:
	var stage := _stage()
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", MODEL_DIR + model + ".glb")
	stage.add_child(prop)
	prop.position.y = FLOOR_TOP
	prop.call("configure_world", effects, null)
	for frame in 5:
		await physics_frame
	for shot in 8:
		prop.call("take_projectile_hit", 400.0, Vector3(0, 0.5, 0), Vector3.UP, Vector3.FORWARD, "GRENADE")
		if prop.get("_damage").transition_pending:
			prop.call("_apply_damage", Vector3(0, 0.5, 0), Vector3.FORWARD)
	for frame in 300:
		await physics_frame
	var tall := 0
	var upright := 0
	var worst := 0.0
	var pieces: Array[RigidBody3D] = []
	for child in effects.get_children():
		if child is RigidBody3D:
			pieces.append(child)
	_expect(not pieces.is_empty(), "%s breaks into pieces" % model)
	for piece in pieces:
		var size := _local_size(piece)
		if size.y >= 0.5 and size.y >= 1.8 * maxf(size.x, size.z):
			tall += 1
			if piece.global_basis.y.angle_to(Vector3.UP) < deg_to_rad(45.0):
				upright += 1
		if maxf(size.x, maxf(size.y, size.z)) >= 0.3:
			_expect(piece.collision_mask & 16 != 0 and piece.collision_layer & 16 != 0, "%s: large piece %s collides with other pieces" % [model, piece.name])
		worst = maxf(worst, _deepest_overlap(piece))
	_expect(upright == 0, "%s: %d of %d tall slender pieces (legs, pedestal) are still standing" % [model, upright, tall])
	_expect(worst <= MAX_OVERLAP, "%s: pieces overlap by %.2f m (they pass through each other)" % [model, worst])
	stage.queue_free()
	await process_frame


func _staged_table(legs: Array) -> void:
	var stage := _stage()
	var table := STAGED.instantiate()
	stage.add_child(table)
	table.position.y = FLOOR_TOP
	for frame in 5:
		await physics_frame
	table.call("_switch_to_modular")
	for frame in 3:
		await physics_frame
	for leg: String in legs:
		table.call("hit_piece", leg, Vector3(0, 0.3, 0), Vector3.FORWARD, 999.0, "AK")
		for frame in 3:
			await physics_frame
	for frame in 150:
		await physics_frame
	var assembly := table.get("_assembly") as RigidBody3D
	var label := "Staged table without " + ", ".join(legs)
	_expect(assembly != null, label + " keeps its assembly")
	if assembly != null:
		var tilt := rad_to_deg(assembly.global_basis.y.angle_to(Vector3.UP))
		_expect(tilt > 20.0, label + " tips over (tilt %.1f deg)" % tilt)
	stage.queue_free()
	await process_frame


func _local_size(piece: RigidBody3D) -> Vector3:
	for child in piece.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			return ((child as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO


## Deepest contact between this piece's box and any other piece on the piece layer.
func _deepest_overlap(piece: RigidBody3D) -> float:
	if piece.collision_mask & 16 == 0:
		return 0.0
	var query := PhysicsShapeQueryParameters3D.new()
	for child in piece.get_children():
		if child is CollisionShape3D:
			query.shape = (child as CollisionShape3D).shape
			query.transform = (child as CollisionShape3D).global_transform
	query.collision_mask = 16
	query.exclude = [piece.get_rid()]
	var contacts := piece.get_world_3d().direct_space_state.collide_shape(query, 32)
	var deepest := 0.0
	for index in range(0, contacts.size() - 1, 2):
		deepest = maxf(deepest, contacts[index].distance_to(contacts[index + 1]))
	return deepest


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
