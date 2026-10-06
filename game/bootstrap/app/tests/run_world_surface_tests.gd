extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const DOOR := preload("res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BLOOD := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const BLOOD_PLACEMENT := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const ACTIVATION := preload("res://game/bootstrap/app/world_activation.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var pool := IMPACTS.new()
	stage.add_child(pool)
	await _door(stage, pool)
	await _projection(stage, pool)
	await _streaming(stage)
	stage.queue_free()
	await process_frame
	await _planner_blood()
	print("World surface tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _door(stage: Node3D, pool: Node) -> void:
	var door := DOOR.instantiate() as Node3D
	stage.add_child(door)
	var pane: StaticBody3D = door.get_node("GlassBody")
	pane.call("configure_world", stage, pool)
	var controller: Node3D = door.get_node("DoorController")
	controller.set_physics_process(false)
	var meshes: Array = pane.get("_glass_nodes")
	_check(not meshes.is_empty(), "Actual glass door has a pane")
	var mesh := meshes[0] as MeshInstance3D
	var point: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
	var normal := mesh.global_basis.y.normalized()
	pane.call("take_projectile_hit", 1, point, normal, -normal, "PISTOL")
	var marks: Array = pane.get("_crack_marks")
	_check(marks.size() == 1, "Glass hit creates one crack, no separate floating bullet mark")
	var mark := marks[0] as Node3D
	var before := mark.global_position
	controller.set("_open_amount", 1.0)
	controller.set("_swing_side", 1.0)
	# The controller needs its injected player to apply a physics pose.
	var actor := Node3D.new()
	stage.add_child(actor)
	actor.position = Vector3(100, 0, 100)
	controller.call("configure_player", actor)
	controller.call("_physics_process", 0.0)
	await physics_frame
	_check(mark.global_position.distance_to(before) > .1, "Existing decal follows the opening leaf")
	for child in pane.get_children():
		if child is CollisionShape3D:
			_check(not child.disabled, "Open glass leaf retains projectile collision")
	point = mesh.global_transform * mesh.get_aabb().get_center()
	normal = mesh.global_basis.y.normalized()
	pane.call("take_projectile_hit", 1, point, normal, -normal, "PISTOL")
	_check(pane.call("crack_count") == 2, "Opened door can still be damaged")
	pane.call("take_projectile_hit", 100, point, normal, -normal, "GRENADE")
	await process_frame
	_check(pane.call("crack_count") == 0 and not is_instance_valid(mark), "Shattering removes all glass decals")
	door.queue_free()
	actor.queue_free()
	await process_frame


func _projection(stage: Node3D, pool: Node) -> void:
	for model in ["10_couch_red_destructible", "10_armchair_green_destructible"]:
		var prop := PROP.instantiate() as Node3D
		prop.set("model_path", "res://models/objects/enviroments/10/" + model + ".glb")
		stage.add_child(prop)
		prop.set("freeze", true)
		var meshes := prop.find_children("*", "MeshInstance3D", true, false)
		var found := false
		for node in meshes:
			var mesh := node as MeshInstance3D
			if not mesh.is_visible_in_tree() or absf(mesh.global_basis.determinant()) < .0001:
				continue
			var bounds := mesh.global_transform * mesh.get_aabb()
			var point := bounds.get_center() + Vector3(0, 0, bounds.size.z / 2 + .04)
			var hit: Dictionary = pool.call("resolve_surface", prop, point, Vector3.FORWARD)
			if not hit.is_empty():
				found = true
				_check(hit["anchor"] is MeshInstance3D, "Furniture impact attaches to a visible mesh")
				_check((hit["position"] as Vector3).z < point.z, "Furniture hit projects inward from the broad collision box")
				break
		_check(found, "Actual furniture has a projected surface: " + model)
		prop.queue_free()
	await process_frame


func _streaming(stage: Node3D) -> void:
	var actor := Node3D.new()
	stage.add_child(actor)
	var structure := Node3D.new()
	stage.add_child(structure)
	var wall := StaticBody3D.new()
	structure.add_child(wall)
	wall.position = Vector3(200, 0, 0)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	wall.add_child(shape)
	var activation := ACTIVATION.new()
	stage.add_child(activation)
	activation.setup([structure])
	await physics_frame
	_check(wall.visible and not shape.disabled, "Remote walls keep visuals and collision")
	shape.disabled = true
	activation.rebuild()
	await physics_frame
	_check(shape.disabled, "Retired streaming never resurrects genuinely destroyed collision")


func _planner_blood() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	stage.call("_on_planning_pressed")
	var planner: Node = stage.get("planning_mode")
	var controls: Node = planner.get("controls")
	controls.call("_show_blood_catalog")
	var _entries: Array = planner.get("catalog").get("active_catalog")
	var objects: Node = planner.get("objects")
	objects.call("_on_palette_selected", 0)
	var preview: Node3D = objects.get("preview")
	var camera: Camera3D = planner.get("camera")
	var screen := camera.unproject_position(Vector3.ZERO)
	var geometry: RefCounted = planner.get("geometry")
	var point: Vector3 = geometry.call("_screen_to_surface", screen, preview)
	_check(point.is_finite() and point.y >= .0135, "Blood probe lands above rendered floor, not underneath its tiles")
	var mark := BLOOD.instantiate() as Node3D
	(planner.get("root") as Node3D).add_child(mark)
	mark.global_position = point
	_check((mark.get_node("BloodQuad") as Node3D).global_position.y > .0135, "Floor blood is above the visible floor")
	mark.queue_free()
	await _blood_roundtrip(planner, objects)
	planner.call("exit")
	stage.queue_free()
	await process_frame


func _blood_roundtrip(planner: Node, objects: Node) -> void:
	var model := "res://models/objects/enviroments/10/10_couch_red_destructible.glb"
	var prop := planner.call("_instantiate_asset", model) as Node3D
	(planner.get("root") as Node3D).add_child(prop)
	prop.set_meta("planning_scene_path", model)
	prop.set_meta("planning_object_id", "surface_test_couch")
	(objects.get("placed") as Array).append(prop)
	var anchor: MeshInstance3D
	for node in prop.find_children("*", "MeshInstance3D", true, false):
		if node.is_visible_in_tree() and absf(node.global_basis.determinant()) > .00001:
			anchor = node
			break
	_check(anchor != null, "Attachment uses an actual authored mesh")
	if anchor == null:
		return
	var mark := BLOOD.instantiate() as Node3D
	mark.call("configure_blood", "smear_04", "object")
	(planner.get("root") as Node3D).add_child(mark)
	mark.set_meta("planning_scene_path", "res://game/presentation/office_floor/public/props/blood_decal.tscn")
	mark.call("configure_blood_normal", Vector3.BACK)
	mark.position = Vector3(0, .6, .3)
	mark.call("attach_blood", anchor, "surface_test_couch")
	(objects.get("placed") as Array).append(mark)
	var offset := prop.global_transform.affine_inverse() * mark.global_position
	prop.position.x += 2
	prop.rotation.y = .5
	await process_frame
	await process_frame
	_check(mark.global_position.distance_to(prop.global_transform * offset) < .001, "Object blood follows translation and rotation")
	var storage: RefCounted = planner.get("storage")
	var data: Dictionary = storage.call("_collect_layout_data")
	objects.call("_apply_layout_data", data)
	await process_frame
	var restored: Dictionary = storage.call("_collect_layout_data")
	_check(restored["objects"].size() == data["objects"].size(), "Blood/object record count survives reload")
	for i in range(mini(data["objects"].size(), restored["objects"].size())):
		for key in data["objects"][i]:
			var expected: Variant = data["objects"][i][key]
			var actual: Variant = restored["objects"][i].get(key)
			var matches: bool = is_equal_approx(float(expected), float(actual)) if expected is float else expected == actual
			_check(matches, "Blood/object roundtrip field: " + key)
	for item: Node3D in objects.get("placed"):
		if item.has_method("get_blood_config"):
			_check(item.get("_anchor") != null, "Loaded blood restores its mesh anchor")
			var reference: WeakRef = item.get("_anchor")
			var restored_anchor := reference.get_ref() as Node3D
			restored_anchor.queue_free()
			await process_frame
			await process_frame
			_check(not item.get_node("BloodQuad").visible, "Deleted object never leaves floating blood")
	objects.call("_apply_layout_data", {"version": 6, "objects": [{"scene": "res://game/presentation/office_floor/public/props/blood_decal.tscn", "blood_texture": "smear_04", "blood_surface": "wall"}]})
	for item: Node3D in objects.get("placed"):
		if item.has_method("get_blood_config"):
			_check((item.get("surface_normal") as Vector3).is_equal_approx(Vector3.BACK), "Legacy wall blood stays vertical")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
