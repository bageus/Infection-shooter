extends SceneTree
## Gameplay balance checks from the 2026-10-05 audit: melee has a cooldown,
## walls shelter from grenades, far enemies stop at walls, overlapping
## mutagen clouds do not stack, summoned infected drop nothing and drops expire.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const ENEMY := preload("res://game/features/infected/public/infected_capsule.tscn")
const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")
const GRENADE := preload("res://game/features/combat/public/grenade_explosion.gd")
const DROPS := preload("res://game/features/pickups/public/drop_table.gd")

var failures := 0
var stage: Node3D
var effects: Node3D


class Absorber:
	extends CharacterBody3D
	var absorbed := 0.0
	func absorb_mutagen(seconds: float) -> float:
		absorbed += seconds
		return seconds


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	effects = Node3D.new()
	stage.add_child(effects)
	_floor()
	await _test_melee_cooldown()
	await _test_grenade_shelter()
	await _test_far_enemy_wall()
	await _test_clouds_do_not_stack()
	await _test_drops()
	await _test_caps()
	stage.queue_free()
	await process_frame
	print("Balance tests: %d failure(s)." % failures)
	quit(failures)


func _test_melee_cooldown() -> void:
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	player.global_position = Vector3(0, 1, 0)
	var enemy := ENEMY.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	await physics_frame
	var forward := -(player.get_node("AimPivot") as Node3D).global_basis.z
	forward.y = 0.0
	enemy.global_position = player.global_position + forward.normalized() * 1.3
	enemy.set_physics_process(false) # a training dummy: it must not walk into the player
	player.set_physics_process(false)
	await physics_frame
	var effects_node: Node = player.get("mutation_effects")
	var health := float(enemy.get("health"))
	_expect(bool(effects_node.call("melee")), "A melee strike lands on an enemy in reach.")
	_expect(float(enemy.get("health")) < health, "The strike hurts.")
	_expect(not bool(effects_node.call("melee")), "A second strike right away is on cooldown.")
	await create_timer(0.55).timeout
	var gap := (enemy.global_position - player.global_position); gap.y = 0.0
	_expect(bool(effects_node.call("melee")), "After the cooldown the next strike lands (cd=%.2f, gap=%.2f, hp=%.0f)." % [float(effects_node.get("melee_cooldown")), gap.length(), float(enemy.get("health"))])
	enemy.queue_free()
	player.queue_free()
	await process_frame


func _test_grenade_shelter() -> void:
	var exposed := _target_dummy(Vector3(30, 1, 3))
	var hidden := _target_dummy(Vector3(30, 1, -3))
	_wall(Vector3(30, 1.5, -1.5), Vector3(4, 3, 0.3))
	await physics_frame
	await physics_frame
	var anchor := Node3D.new()
	effects.add_child(anchor)
	GRENADE.explode(anchor, Vector3(30, 0.2, 0), Vector3.UP, null, effects, null)
	_expect(float(exposed.get_meta("damage", 0.0)) > 0.0, "A grenade hurts what it can reach.")
	_expect(float(hidden.get_meta("damage", 0.0)) == 0.0, "A wall shelters from the blast.")
	await process_frame


func _test_far_enemy_wall() -> void:
	var target := Node3D.new()
	stage.add_child(target)
	target.global_position = Vector3(-80, 1, 0)
	_wall(Vector3(-40, 1.5, 0), Vector3(0.4, 3, 30))
	var enemy := ENEMY.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(-30, 1.0, 0)
	enemy.call("set_target", target)
	for i in 600:
		await physics_frame
	_expect(enemy.global_position.x > -40.0, "A far enemy stops at a wall instead of walking through (x=%.1f)." % enemy.global_position.x)
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_clouds_do_not_stack() -> void:
	var body := Absorber.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	body.add_child(shape)
	stage.add_child(body)
	body.global_position = Vector3(60, 1, 0)
	var clouds: Array[Area3D] = []
	for i in 3:
		var cloud := CLOUD.instantiate() as Area3D
		cloud.set("absorb_delay", 0.0)
		stage.add_child(cloud)
		cloud.global_position = Vector3(60, 0, 0)
		cloud.call("activate")
		clouds.append(cloud)
	await create_timer(0.5).timeout
	_expect(body.absorbed > 0.2 and body.absorbed < 0.75, "Three overlapping clouds feed no faster than one (%.2f s in 0.5 s)." % body.absorbed)
	for cloud in clouds:
		cloud.queue_free()
	body.queue_free()
	await process_frame


func _test_drops() -> void:
	var enemy := ENEMY.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(90, 1, 0)
	enemy.call("configure_world", effects, null)
	enemy.set_meta("summoned_by", 1)
	await physics_frame
	var before := get_nodes_in_group(DROPS.DROP_GROUP).size()
	for i in 10:
		var clone := ENEMY.instantiate() as CharacterBody3D
		stage.add_child(clone)
		clone.global_position = Vector3(90 + i, 1, 4)
		clone.call("configure_world", effects, null)
		clone.set_meta("summoned_by", 1)
		await physics_frame
		clone.call("take_damage", 9999.0)
	await physics_frame
	_expect(get_nodes_in_group(DROPS.DROP_GROUP).size() == before, "Infected summoned by a Horde drop nothing.")
	var table := DROPS.new()
	table.set("any_drop_chance", 1.0)
	effects.add_child(table)
	table.call("drop_for_enemy", effects, Vector3(95, 1, 8))
	var drops := get_nodes_in_group(DROPS.DROP_GROUP)
	_expect(drops.size() == before + 1, "An ordinary kill can drop an item.")
	if not drops.is_empty():
		(drops[drops.size() - 1] as Node).call("expire_after", 0.2)
		await create_timer(0.4).timeout
		_expect(get_nodes_in_group(DROPS.DROP_GROUP).size() == before, "An uncollected drop disappears after its lifetime.")
	enemy.queue_free()
	table.queue_free()
	await process_frame


func _test_caps() -> void:
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	player.set("effects_root", effects)
	player.global_position = Vector3(120, 1, 0)
	player.set_physics_process(false)
	for i in 40:
		player.call("_spawn_floor_blood", 30.0)
	var marks := (player.get("_floor_marks") as Array).size()
	_expect(marks <= 60, "Player blood on the floor is capped (%d marks)." % marks)
	player.queue_free()
	var clouds: Array[Area3D] = []
	for i in 14:
		var cloud := CLOUD.instantiate() as Area3D
		stage.add_child(cloud)
		cloud.global_position = Vector3(140 + i * 6, 0, 0)
		cloud.call("activate")
		clouds.append(cloud)
	var spent := clouds.filter(func(c: Area3D) -> bool: return float(c.get("_absorption_remaining")) <= 0.0).size()
	_expect(spent == 4, "Past ten death clouds the oldest dissipate early (%d)." % spent)
	for cloud in clouds:
		cloud.queue_free()
	await process_frame


func _target_dummy(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.set_script(_damage_script())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.6)
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.global_position = at
	return body


func _damage_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nfunc take_damage(amount: float) -> void:\n\tset_meta(\"damage\", float(get_meta(\"damage\", 0.0)) + amount)\n"
	script.reload()
	return script


func _wall(center: Vector3, size: Vector3) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	stage.add_child(wall)
	wall.global_position = center


func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 0.2, 400)
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.position.y = -0.1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
