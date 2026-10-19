extends SceneTree
## An extinguisher rupture breaks the props and glass in its blast, while the
## enemies in the blast take their damage once through their own path.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BLAST := preload("res://game/presentation/office_floor/blast_effect.gd")
const DESK := "res://models/objects/enviroments/08/08_office_desk_2.glb"

class Part extends StaticBody3D:
	var hits := 0
	func take_projectile_hit(_damage: float, _at: Vector3, _normal: Vector3, _direction: Vector3, _weapon: String) -> bool:
		hits += 1
		return false

class Enemy extends Node3D:
	var damage := 0.0
	func take_damage(amount: float) -> void:
		damage += amount

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var effects := Node3D.new()
	stage.add_child(effects)
	var host := Node3D.new()
	stage.add_child(host)
	host.global_position = Vector3.ZERO

	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", DESK)
	stage.add_child(prop)
	prop.global_position = Vector3(2.0, 0.05, 0.0)
	prop.call("configure_world", effects, null)

	var enemy := Enemy.new()
	enemy.add_to_group("infected")
	stage.add_child(enemy)
	enemy.global_position = Vector3(-2.0, 0.0, 0.0)
	var part := Part.new()
	enemy.add_child(part)
	var part_shape := CollisionShape3D.new()
	part_shape.shape = BoxShape3D.new()
	part.add_child(part_shape)
	part.global_position = Vector3(-2.0, 1.0, 0.0)

	for i in 5:
		await physics_frame
	BLAST.detonate(host, Vector3.ZERO, 5.0, false)
	for i in 5:
		await physics_frame

	_check(not is_instance_valid(prop) or bool(prop.get("_broken")), "The extinguisher blast breaks a nearby desk")
	_check(enemy.damage > 0.0, "The extinguisher blast damages an enemy in range")
	_check(part.hits == 0, "An enemy's body part is not hit a second time")
	stage.queue_free()
	await process_frame
	print("Extinguisher blast tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
