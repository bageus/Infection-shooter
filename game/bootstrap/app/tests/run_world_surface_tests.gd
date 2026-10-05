extends SceneTree
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const DOOR := preload("res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn")
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BLOOD := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const BLOOD_PLACEMENT := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const CHUNKS := preload("res://game/bootstrap/app/chunk_streamer.gd")
const VISIBILITY := preload("res://game/bootstrap/app/visibility_manager.gd")
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
	var chunks := CHUNKS.new()
	var visibility := VISIBILITY.new()
	stage.add_child(chunks)
	stage.add_child(visibility)
	chunks.setup(actor, [structure])
	visibility.setup(actor, [structure])
	chunks.set_runtime_enabled(true)
	visibility.set_runtime_enabled(true)
	await physics_frame
	_check(wall.visible and not shape.disabled, "Remote walls keep visuals and collision")
	shape.disabled = true
	chunks.rebuild()
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
	var entries: Array = planner.get("catalog").get("active_catalog")
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
	planner.call("exit")
	stage.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
