extends SceneTree
## A grenade stuns the infected it hurts but does not kill, and a killed horde's hitboxes stay uniform in scale.
const BLAST := preload("res://game/features/combat/public/grenade_explosion.gd")
const HORDE := preload("res://game/features/infected/public/infected_horde.tscn")
var failures := 0
var stage: Node3D


func _init() -> void: call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(40, 1, 40)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.5
	var horde := HORDE.instantiate() as CharacterBody3D
	stage.add_child(horde)
	horde.position = Vector3(2, 0.05, 0)
	horde.set_physics_process(false)
	horde.set("max_health", 5000.0)
	horde.set("health", 5000.0)
	await physics_frame
	await physics_frame
	var anchor := Node3D.new()
	stage.add_child(anchor)
	BLAST.explode(anchor, Vector3(0, 0.5, 0), Vector3.UP, null, stage, null)
	_expect(float(horde.get("health")) < 5000.0, "grenade hurt the horde")
	_expect(float(horde.get("_blast_stun_remaining")) > 0.0, "surviving horde is stunned")
	var chaser := HORDE.instantiate() as CharacterBody3D
	stage.add_child(chaser)
	chaser.position = Vector3(10, 0.05, 0)
	var target := Node3D.new()
	stage.add_child(target)
	target.position = Vector3(-15, 0, 0)
	chaser.set("max_health", 5000.0)
	chaser.set("health", 5000.0)
	chaser.call("set_target", target)
	chaser.call("alert") if chaser.has_method("alert") else null
	for _frame in 30:
		await physics_frame
	var before := chaser.position.x
	for _frame in 30:
		await physics_frame
	var speed := before - chaser.position.x
	_expect(speed > 0.5, "test enemy chases before the blast (%.2f)" % speed)
	BLAST.explode(anchor, chaser.position + Vector3(2, 0.5, 0), Vector3.UP, null, stage, null)
	_expect(float(chaser.get("_blast_stun_remaining")) > 0.5 and float(chaser.get("health")) > 0.0, "surviving chaser is stunned")
	var x0 := chaser.position.x
	for _frame in 30:
		await physics_frame
	_expect(absf(x0 - chaser.position.x) < 0.05, "stunned chaser stands still")
	horde.set("health", 1.0)
	BLAST.explode(anchor, Vector3(0, 0.5, 0), Vector3.UP, null, stage, null)
	for _frame in 5:
		await physics_frame
	var bad := 0
	for node in horde.find_children("*", "CollisionObject3D", true, false):
		var scale := (node as Node3D).global_transform.basis.get_scale()
		if node is StaticBody3D and (absf(scale.x - scale.y) > 0.01 or absf(scale.x - scale.z) > 0.01):
			bad += 1
	_expect(bad == 0, "corpse hitboxes have uniform scale (%d bad)" % bad)
	print("Grenade stun tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
