extends SceneTree
## Runtime checks for ADR-0017 blood presentation: denser hit splatter,
## the severed-limb burst and planner blood decals on floor and wall.

const EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const DECAL_SCRIPT := preload("res://game/presentation/office_floor/blood_decal_prop.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1
	var effects := EFFECTS.instantiate() as Node3D
	stage.add_child(effects)
	var roots: Array[Node] = [stage]
	effects.call("configure_environment", roots)
	await physics_frame
	await physics_frame
	_expect(int(effects.get("splatters_per_hit")) >= 5, "Each hit sprays at least five splatter marks.")
	_expect(int(effects.get("max_marks")) >= 200, "The blood budget allows a heavily stained floor.")
	var excluded: Array[RID] = []
	effects.call("severed_burst", Vector3(0, 1, 0), Vector3(1, 0, 0), excluded)
	for i in 4:
		await physics_frame
	var container := (effects.get("_budget") as Node).get("container") as Node3D
	_expect(container.get_child_count() >= 5, "A severed limb leaves a burst of blood (%d marks)." % container.get_child_count())
	_expect(DECAL_SCRIPT.texture_ids().size() == 44, "Planner blood uses the 44 in-game atlas frames.")
	for texture_id in ["splatter_01", "pool_08", "pool_09", "drops_09"]:
		_expect(not DECAL_SCRIPT.texture_entry(texture_id).is_empty(), "Blood texture loads: " + texture_id)
	var sliced := 0
	for texture_id: String in DECAL_SCRIPT.texture_ids():
		var frame: Dictionary = DECAL_SCRIPT.texture_entry(texture_id)
		if not frame.is_empty() and float(frame.aspect) > 0.1 and float(frame.aspect) < 10.0:
			sliced += 1
	_expect(sliced == 44, "Every atlas frame is sliced and trimmed (%d of 44)." % sliced)
	var on_floor := DECAL.instantiate() as Node3D
	on_floor.call("configure_blood", "pool_02", "floor")
	stage.add_child(on_floor)
	var floor_quad := on_floor.get_node("BloodQuad") as MeshInstance3D
	_expect(not bool(on_floor.get_meta("planning_wall_mount", false)), "Floor blood is not wall mounted.")
	_expect(floor_quad.global_basis.z.dot(Vector3.UP) > 0.99, "Floor blood lies flat facing up.")
	var on_wall := DECAL.instantiate() as Node3D
	on_wall.call("configure_blood", "smear_04", "wall")
	stage.add_child(on_wall)
	on_wall.rotation.y = PI * 0.5
	var wall_quad := on_wall.get_node("BloodQuad") as MeshInstance3D
	_expect(bool(on_wall.get_meta("planning_wall_mount", false)), "Wall blood mounts on walls in the planner.")
	_expect(absf(wall_quad.global_basis.z.y) < 0.01, "Wall blood stands upright against the wall.")
	_expect(on_wall.call("get_blood_config") == {"texture": "smear_04", "surface": "wall", "normal": [0.0, 0.0, 1.0]}, "Blood decal reports its saved configuration.")
	on_wall.call("configure_blood", "smear_04", "floor")
	await process_frame
	_expect(not bool(on_wall.get_meta("planning_wall_mount", false)), "Switching surface rebuilds the decal.")
	stage.queue_free()
	await process_frame
	print("Blood decor tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
