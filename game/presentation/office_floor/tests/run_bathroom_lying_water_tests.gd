extends SceneTree
## A toilet, urinal or sink lying on its side breaks without spilling water; upright ones still spill.

const BATHROOM := preload("res://game/presentation/office_floor/public/props/bathroom_fixture.tscn")
const VIEW := preload("res://game/presentation/office_floor/water_spray_view.gd")
const TOILET := "res://models/objects/enviroments/02/02_toilet_new.glb"
var failures := 0
var stage: Node3D
var effects: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	await _check_hit(false)
	await _check_hit(true)
	stage.queue_free()
	await process_frame
	print("Bathroom lying water tests: %d failure(s)." % failures)
	quit(failures)


func _check_hit(laid: bool) -> void:
	var before := _sprays()
	var fixture := BATHROOM.instantiate() as RigidBody3D
	fixture.set("model_path", TOILET)
	fixture.set("effects_root", effects)
	fixture.position = Vector3(0, 0.5, 0)
	if laid:
		fixture.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	stage.add_child(fixture)
	await process_frame
	_check(fixture.call("is_laid_down") == laid, "is_laid_down() is %s for laid=%s" % [laid, laid])
	fixture.call("take_projectile_hit", 10.0, fixture.global_position, Vector3.UP, Vector3.FORWARD, "PISTOL")
	await process_frame
	await process_frame
	var spawned := _sprays() - before
	_check(spawned == (0 if laid else 1), "laid=%s spawns %d water spray(s)" % [laid, spawned])
	for child in effects.get_children():
		child.queue_free()
	await process_frame


func _sprays() -> int:
	var count := 0
	for child in effects.get_children():
		if child.get_script() == VIEW:
			count += 1
	return count


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failures += 1
