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

	var far := PROP.instantiate() as RigidBody3D
	far.set("model_path", DESK)
	stage.add_child(far)
	far.global_position = Vector3(BLAST.EXTINGUISHER_RADIUS + 3.5, 0.05, 0.0)
	far.call("configure_world", effects, null)

	var behind := PROP.instantiate() as RigidBody3D
	behind.set("model_path", DESK)
	stage.add_child(behind)
	behind.global_position = Vector3(0.0, 0.05, 2.6)
	behind.call("configure_world", effects, null)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4.0, 3.0, 0.2)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	stage.add_child(wall)
	wall.global_position = Vector3(0.0, 1.5, 1.6)

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
	_check(is_instance_valid(prop) and not prop.is_queued_for_deletion() and effects.get_child_count() > 0, "The broken desk leaves debris instead of vanishing")
	_check(is_instance_valid(far) and not bool(far.get("_broken")), "A desk outside the blast radius is untouched")
	_check(is_instance_valid(behind) and not bool(behind.get("_broken")), "A wall shelters a desk from the blast")
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
