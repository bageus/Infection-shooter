extends SceneTree
## New authored two-part props must use the real catalogue and damage commands.
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const PLACEMENT := preload("res://game/bootstrap/app/planning_surface_placement.gd")
const COOLER := "res://models/objects/enviroments/02/02_water_cooler_bottle_attached_destructible.glb"
const EMPTY_COOLER := "res://models/objects/enviroments/02/02_water_cooler_destructible.glb"
const MICROWAVE := "res://models/objects/enviroments/02/02_microwave_destructible.glb"
const FRIDGE := "res://models/objects/enviroments/02/02_frige_dented.glb"
const WALL_BOARD := "res://models/objects/enviroments/09/09_white_board_stand.glb"
const FLOOR_BOARD := "res://models/objects/enviroments/09/09_board_stand_white.glb"
const CASE_OPEN := "res://models/objects/enviroments/09/09_case_with_money_open.glb"
const CASE_CLOSED := "res://models/objects/enviroments/09/09_case_with_money_close.glb"
var failures := 0
var stage: Node3D
var effects: Node3D
var catalog := CATALOG.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	for model in [COOLER, MICROWAVE]:
		await _retained(model, true)
		await _retained(model, false)
	await _empty_cooler()
	for model in [CASE_OPEN, CASE_CLOSED, FLOOR_BOARD]:
		await _two_parts(model)
	await _fixed_fridge()
	await _wall_board()
	stage.queue_free()
	await _ticks()
	print("Updated prop model tests: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _ticks() -> void:
	for i in 4:
		await physics_frame
		await process_frame


func _prop(model: String) -> RigidBody3D:
	var prop: RigidBody3D = catalog.call("_instantiate_asset", model)
	stage.add_child(prop)
	prop.call("configure_world", effects, null)
	return prop


func _pieces() -> Array:
	return effects.get_children().filter(func(node: Node) -> bool: return node is RigidBody3D)


func _cleanup(prop: Node) -> void:
	prop.queue_free()
	for node in effects.get_children():
		node.queue_free()
	await _ticks()


func _retained(model: String, targeted: bool) -> void:
	var prop := _prop(model)
	if model == COOLER:
		_check(prop.freeze, "Cooler body is anchored")
	prop.freeze = true # Isolate the damage/shape contract from free-fall in this fixture.
	var meshes: Array = prop.get("_shape_meshes")
	_check(meshes.size() == 2, model + ": separate body and attachment collision")
	var wanted := "Bottle_01" if model == COOLER else "Door_01"
	var attachment: MeshInstance3D
	var body: MeshInstance3D
	var index := -1
	for i in meshes.size():
		if str(meshes[i].name) == wanted:
			attachment = meshes[i]
			index = i
		elif str(meshes[i].name) == "Body_Whole":
			body = meshes[i]
	_check(attachment != null and body != null, model + ": authored parts resolve")
	if attachment == null or body == null:
		await _cleanup(prop)
		return
	var position: Vector3 = attachment.global_transform * attachment.get_aabb().get_center()
	if targeted:
		prop.call("take_projectile_hit_at_shape", 28.0, position, Vector3.BACK, Vector3.FORWARD, "AK", index)
	else:
		prop.call("take_projectile_hit", 1000.0, position, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	await _ticks()
	_check(not attachment.visible and body.is_visible_in_tree(), model + ": only the attachment disappears")
	_check(prop.collision_layer != 0 and prop.get("_visual").visible, model + ": body stays collidable and visible")
	var pieces := _pieces()
	_check(pieces.size() == 1, model + ": exactly one detached rigid body")
	if pieces.size() == 1:
		_check(str(pieces[0].get("piece_name")) == wanted and not pieces[0].get("breakable"), model + ": intact terminal attachment")
		prop.call("hit_environment_fragment", pieces[0], position, Vector3.FORWARD)
	prop.call("take_projectile_hit", 1000.0, position, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	await _ticks()
	_check(_pieces().size() == 1 and body.is_visible_in_tree(), model + ": repeated damage cannot fragment the body or duplicate attachment")
	_check(effects.get_node_or_null("BottleSplash") == null, "Attached cooler no longer uses the old bottle-burst path")
	await _cleanup(prop)


func _empty_cooler() -> void:
	var prop := _prop(EMPTY_COOLER)
	var original := prop.transform
	for i in 5:
		prop.call("take_projectile_hit", 1000.0, prop.position, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	await _ticks()
	_check(prop.freeze and prop.transform.is_equal_approx(original) and not prop.get("_broken"), "Empty cooler remains whole and fixed")
	_check(_pieces().is_empty() and prop.collision_layer != 0, "Empty cooler does not generate a body fragment")
	await _cleanup(prop)


func _two_parts(model: String) -> void:
	var prop := _prop(model)
	_check(not prop.get_meta("planning_wall_mount", false), model + ": freestanding prop")
	prop.call("take_projectile_hit", 1000.0, prop.position, Vector3.BACK, Vector3.FORWARD, "GRENADE")
	await _ticks()
	var pieces := _pieces()
	_check(pieces.size() == 2, model + ": exactly two physical pieces")
	var names: Array = pieces.map(func(piece: Node) -> String: return str(piece.get("piece_name")))
	var expected := ["Board_01", "Stand_01"] if model == FLOOR_BOARD else ["Lower_Half", "Upper_Half"]
	for wanted in expected:
		_check(names.has(wanted), model + ": includes " + wanted)
	for piece in pieces:
		_check(not piece.get("breakable"), model + ": terminal pieces cannot split further")
	_check(prop.collision_layer == 0, model + ": original collider retired")
	await _cleanup(prop)


func _fixed_fridge() -> void:
	var prop := _prop(FRIDGE)
	var original := prop.transform
	_check(prop.freeze, "Fridge starts anchored")
	for i in 6:
		prop.call("take_projectile_hit", 1000.0, prop.position, Vector3.BACK, Vector3.FORWARD, "AK")
		await _ticks()
		prop.call("push_from_character", Vector3.LEFT, Vector3.RIGHT * 5.0, 20.0)
		_check(prop.freeze and prop.transform.is_equal_approx(original), "Fridge remains anchored across all damage variants")
	_check(int(prop.get("_damage").variant_index) == 2, "Fridge damage variants still advance")
	_check(_pieces().is_empty(), "Fridge never becomes debris")
	await _cleanup(prop)


func _wall_board() -> void:
	var prop := _prop(WALL_BOARD)
	_check(prop.freeze and prop.get_meta("planning_wall_mount", false), "White board stand is a wall fixture")
	var bounds := AABB()
	for mesh: MeshInstance3D in prop.get("_shape_meshes"):
		var box: AABB = prop.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	prop.position = Vector3(0, 1.6, 0)
	PLACEMENT.mount(prop, bounds, Vector3.BACK)
	var back := INF
	for i in 8:
		back = minf(back, (prop.global_transform * bounds.get_endpoint(i)).z)
	_check(absf(back - PLACEMENT.WALL_CLEARANCE) < 0.001, "Wall board back plane is placed flush against wall")
	await _cleanup(prop)
