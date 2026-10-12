extends SceneTree
## Wall signs fall and vanish when shot or when their glass pane breaks;
## a desk lamp stops shining once it is damaged.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const WALL := preload("res://game/presentation/office_floor/public/structural/glass_wall_full.tscn")
const SIGN := "res://models/objects/enviroments/13/13_wall_exit_lit.glb"
const LAMP := "res://models/objects/enviroments/05/05_lamp.glb"
var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	await _shot_sign()
	await _sign_on_glass()
	await _lamp()
	stage.queue_free()
	await process_frame
	print("Wall sign and lamp tests: %d failure(s)." % failures)
	quit(failures)


func _make(path: String, at: Vector3) -> RigidBody3D:
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", path)
	stage.add_child(prop)
	prop.global_position = at
	return prop


func _shoot(prop: Node, times: int) -> void:
	for i in times:
		if is_instance_valid(prop):
			prop.call("take_projectile_hit", 28.0, prop.global_position, Vector3.BACK, Vector3.FORWARD, "AK")


func _shot_sign() -> void:
	var wall_sign := _make(SIGN, Vector3(0, 1.5, 0))
	await physics_frame
	_check(wall_sign.freeze, "Sign hangs on the wall")
	_shoot(wall_sign, 20)
	_check(not wall_sign.freeze, "Shot sign falls off the wall")
	await create_timer(1.3).timeout
	_check(not is_instance_valid(wall_sign) or wall_sign.is_queued_for_deletion(), "Fallen sign disappears after about a second")


func _sign_on_glass() -> void:
	var wall := WALL.instantiate() as Node3D
	stage.add_child(wall)
	wall.position = Vector3(0, 0, 20)
	await physics_frame
	var glass: MeshInstance3D
	for mesh: MeshInstance3D in wall.find_children("*", "MeshInstance3D", true, false):
		if "glass" in mesh.name.to_lower() and mesh.visible and mesh.mesh != null:
			glass = mesh
			break
	if glass == null:
		_check(false, "Glass wall has a pane")
		return
	var center := glass.global_transform * glass.get_aabb().get_center()
	var wall_sign := _make(SIGN, center)
	await physics_frame
	var pane := wall.find_children("*", "StaticBody3D", true, false).filter(func(n): return n.has_method("take_melee_hit"))
	_check(not pane.is_empty(), "Glass pane body found")
	if pane.is_empty():
		return
	pane[0].call("_break_glass", center, Vector3.FORWARD)
	_check(not wall_sign.freeze, "Sign on glass falls when the glass breaks")


func _lamp() -> void:
	var lamp := _make(LAMP, Vector3(30, 0.1, 0))
	await physics_frame
	var glow := lamp.find_child("BudgetLight", true, false)
	_check(glow != null and glow.call("is_wanted"), "Intact lamp is meant to shine")
	_shoot(lamp, 1)
	_check(glow != null and not glow.call("is_wanted"), "Damaged lamp stops shining")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
