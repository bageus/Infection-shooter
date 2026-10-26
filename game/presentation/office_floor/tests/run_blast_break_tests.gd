extends SceneTree
## A grenade blast breaks every breakable prop in its radius, even when floor
## tiles own hundreds of collision shapes and would fill a single shape query.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
const MODELS := [
	"res://models/objects/enviroments/08/08_office_desk_2.glb",
	"res://models/objects/enviroments/06/06_office_chair.glb",
	"res://models/objects/enviroments/05/05_monitor_destructible.glb",
	"res://models/objects/enviroments/03/03_file_cabinet_largest.glb",
]
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	stage.add_child(floor_body)
	for i in 400:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.4, 0.2, 0.4)
		shape.shape = box
		shape.position = Vector3(float(i % 20) * 0.5 - 5.0, -0.1, float(i / 20) * 0.5 - 5.0)
		floor_body.add_child(shape)
	var effects := Node3D.new()
	stage.add_child(effects)
	var props: Array[RigidBody3D] = []
	var x := -3.5
	for path in MODELS:
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", path)
		stage.add_child(prop)
		prop.global_position = Vector3(x, 0.05, 2.0)
		prop.call("configure_world", effects, null)
		props.append(prop)
		x += 2.2
	for i in 5:
		await physics_frame
	var projectile := Node3D.new()
	stage.add_child(projectile)
	EXPLOSION.explode(projectile, Vector3(0.0, 0.6, 0.0), Vector3.UP, null, stage, null)
	# The destruction budget spreads the breakup over a few frames; every prop must still break promptly.
	for i in 60:
		await process_frame
		var pending := false
		for prop in props:
			pending = pending or (is_instance_valid(prop) and not bool(prop.get("_broken")))
		if not pending:
			break
	for prop in props:
		var broken: bool = not is_instance_valid(prop) or bool(prop.get("_broken"))
		_check(broken, "Blast breaks %s" % String(prop.get("model_path")).get_file() if is_instance_valid(prop) else "Blast breaks a prop")
	stage.queue_free()
	await process_frame
	print("Blast break tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
