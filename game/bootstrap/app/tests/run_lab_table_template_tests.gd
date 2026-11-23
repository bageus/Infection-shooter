extends SceneTree
## The lab table draws lab bench setups from its own pool; office tables keep the computer setups.
const WORKSTATIONS := preload("res://game/bootstrap/app/workstation_templates.gd")
const LAB_TABLE := "res://models/objects/enviroments/07/07_table_lab.glb"
const OFFICE_TABLE := "res://models/objects/enviroments/07/07_table_longest.glb"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := _generate(LAB_TABLE)
	_check(lab.any(func(path: String) -> bool: return "/05/medical/Laboratory_Microscope.glb" in path), "A lab table gets a microscope")
	_check(lab.any(func(path: String) -> bool: return "/05/medical/Test_Tube_Rack.glb" in path), "A lab table gets a test tube rack")
	var office := _generate(OFFICE_TABLE)
	_check(not office.any(func(path: String) -> bool: return "/medical/" in path), "An office table gets no lab equipment")
	print("Lab table template tests: %d failure(s)." % failures)
	quit(failures)


# Returns the model paths placed on the desk, mouse and phone included.
func _generate(desk_path: String) -> Array[String]:
	var desk := Node3D.new()
	var parent := Node3D.new()
	root.add_child(parent)
	parent.add_child(desk)
	var created: Array[Node3D] = WORKSTATIONS.generate(desk, desk_path, parent, [] as Array[Node3D], _asset)
	var paths: Array[String] = []
	for node in created:
		paths.append(str(node.get_meta("path", "")))
	parent.queue_free()
	return paths


func _asset(path: String) -> Node3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3.ONE * 0.1 # Small stand-in so neighbours do not overlap the desk layout.
	mesh.set_meta("path", path)
	return mesh


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
