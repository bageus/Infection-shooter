extends SceneTree
## Enemy bumps leave a sleeping prop asleep unless the shove is real, and a prop takes one enemy push per few frames.
const CONTACT := preload("res://game/presentation/office_floor/prop_contact.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var script := GDScript.new()
	script.source_code = "extends RigidBody3D\nvar model_path := \"09_mug.glb\"\n"
	script.reload()
	var body: RigidBody3D = script.new()
	root.add_child(body)
	body.sleeping = true
	var weak := CONTACT.push(body, 10.0, Vector3(-1, 0, 0), Vector3(0.05, 0, 0), 0.1, &"enemy")
	_check(not weak and body.sleeping, "A weak enemy bump leaves a sleeping prop asleep")
	var first := CONTACT.push(body, 10.0, Vector3(-1, 0, 0), Vector3(1, 0, 0), 3.0, &"enemy")
	_check(first, "A real enemy shove wakes a sleeping prop")
	var again := CONTACT.push(body, 10.0, Vector3(-1, 0, 0), Vector3(1, 0, 0), 3.0, &"enemy")
	_check(not again, "A second enemy push within a few frames is skipped")
	body.free()
	print("Enemy prop push tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
