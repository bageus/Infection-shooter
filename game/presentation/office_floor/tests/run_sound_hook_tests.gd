extends SceneTree
## Gameplay sound hooks (ADR-0018): weapons, casings, bullet impacts per
## material, infected hits/attacks/death/dismemberment/steps, doors, glass,
## falling props and pickups.

const PISTOL := preload("res://game/features/combat/public/pistol.tscn")
const SHOTGUN := preload("res://game/features/combat/public/shotgun.tscn")
const CASINGS := preload("res://game/features/combat/public/spent_casings.gd")
const ZOMBIE := preload("res://game/features/infected/public/infected_capsule.tscn")
const DOOR := preload("res://game/presentation/office_floor/interactive_door.gd")
const GLASS := preload("res://game/presentation/office_floor/glass_partition.gd")
const WATCHER := preload("res://game/presentation/office_floor/impact_sound_watcher.gd")
const MEDKIT := preload("res://game/features/pickups/public/medkit_pickup.tscn")

class Surface:
	extends StaticBody3D
	var material := "metal"
	func get_projectile_material(_shape_index: int = -1) -> String:
		return material

class Collector:
	extends CharacterBody3D
	var events: Array[StringName] = []
	func heal(amount: float) -> float:
		return amount
	func play_item_sound(event: StringName) -> void:
		events.append(event)

class FakeTarget:
	extends Node3D
	func take_damage(_amount: float, _kind: String = "") -> void:
		pass

var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.5
	await _test_weapons()
	await _test_impacts()
	await _test_infected()
	await _test_doors_and_glass()
	await _test_falling_prop()
	await _test_pickup()
	stage.queue_free()
	await process_frame
	print("Sound hook tests: %d failure(s)." % failures)
	quit(failures)


func _voices(event: StringName) -> int:
	return get_nodes_in_group(StringName("sfx_" + String(event))).size()


# True once a voice of `event` is seen within `seconds`.
func _heard(event: StringName, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if _voices(event) > 0:
			return true
		await process_frame
	return _voices(event) > 0


func _armed(scene: PackedScene, at: Vector3) -> Node3D:
	var shooter := CharacterBody3D.new()
	stage.add_child(shooter)
	shooter.global_position = at
	var pivot := Node3D.new()
	shooter.add_child(pivot)
	var casings := Node.new()
	casings.name = "SpentCasings"
	casings.set_script(CASINGS)
	pivot.add_child(casings)
	casings.call("configure_world", stage, null)
	var weapon := scene.instantiate() as Node3D
	pivot.add_child(weapon)
	weapon.call("configure_world", stage, null)
	return weapon


func _test_weapons() -> void:
	var pistol := _armed(PISTOL, Vector3(0, 1, 0))
	await process_frame
	_expect(bool(pistol.call("try_fire")), "The pistol fires.")
	_expect(_voices(&"pistol_fire") >= 1, "A pistol shot is heard.")
	_expect(await _heard(&"casing_brass", 0.8), "The ejected casing clinks on the floor.")
	pistol.set("_magazine_ammo", 0)
	pistol.set("_cooldown_remaining", 0.0)
	pistol.call("try_fire")
	_expect(_voices(&"dry_fire") >= 1, "An empty gun dry-clicks.")
	pistol.call("start_reload")
	_expect(_voices(&"pistol_reload") == 1, "Reloading is heard.")
	pistol.call("cancel_reload")
	await process_frame
	_expect(_voices(&"pistol_reload") == 0, "Switching away stops the reload sound.")
	var shotgun := _armed(SHOTGUN, Vector3(4, 1, 0))
	await process_frame
	shotgun.set("_magazine_ammo", 1)
	shotgun.call("start_reload")
	_expect(_voices(&"shotgun_shell_load") >= 1, "Each shotgun shell is pushed in audibly.")


func _test_impacts() -> void:
	var expected := {"metal": &"hit_metal", "wood": &"hit_wood", "light": &"hit_paper", "tech": &"hit_electronics", "concrete": &"hit_wall", "glass": &"hit_glass"}
	var x := 10.0
	for material: String in expected:
		var gun := _armed(PISTOL, Vector3(x, 1, 0))
		await process_frame
		var muzzle := gun.get_node("Muzzle") as Node3D
		var forward := -muzzle.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var target := Surface.new()
		target.material = material
		target.collision_layer = 1
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2, 2, 2)
		collider.shape = box
		target.add_child(collider)
		stage.add_child(target)
		target.global_position = muzzle.global_position + forward * 3.0
		await physics_frame
		gun.call("try_fire_at", muzzle.global_position + forward * 6.0)
		_expect(await _heard(expected[material], 0.5), "A bullet into %s sounds like %s." % [material, expected[material]])
		target.queue_free()
		x += 6.0


func _test_infected() -> void:
	var enemy := ZOMBIE.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = Vector3(-10, 1, 0)
	await process_frame
	enemy.call("take_projectile_damage", 5.0, enemy.global_position + Vector3(0, 0.3, -0.4), Vector3(0, 0, 1), "PISTOL")
	_expect(_voices(&"flesh_hit") >= 1, "Shots into an infected sound like flesh.")
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, -1.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	_expect(_voices(&"attack_swing") >= 1, "An attack starts with a swing.")
	await create_timer(0.6).timeout
	_expect(_voices(&"attack_hit") + _voices(&"attack_bite") >= 1, "A landed blow is heard.")
	target.global_position = enemy.global_position + Vector3(0, 0, -6.0)
	var walked := false
	for i in 90:
		await physics_frame
		if _voices(&"step_light") > 0:
			walked = true
			break
	_expect(walked, "A charging infected's footsteps are heard.")
	var parts: Node = enemy.get("_parts")
	parts.sever(&"arm_l", Vector3.RIGHT)
	_expect(_voices(&"dismember") >= 1, "Shooting off a limb sounds gory.")
	enemy.call("_apply_damage", 1000.0, false)
	_expect(_voices(&"enemy_death") >= 1, "Death is voiced.")
	_expect(await _heard(&"body_part_fall", 2.5), "The severed arm thuds when it lands.")
	enemy.queue_free()
	target.queue_free()


func _test_doors_and_glass() -> void:
	var visitor := Node3D.new()
	stage.add_child(visitor)
	var door := Node3D.new()
	door.set_script(DOOR)
	stage.add_child(door)
	door.global_position = Vector3(20, 0, 10)
	door.call("configure_player", visitor)
	visitor.global_position = door.global_position
	await create_timer(0.2).timeout
	_expect(_voices(&"door_open") >= 1, "A door is heard opening.")
	visitor.global_position = door.global_position + Vector3(20, 0, 0)
	_expect(await _heard(&"door_close", 2.5), "It thuds shut once closed.")
	var glass := StaticBody3D.new()
	glass.set_script(GLASS)
	stage.add_child(glass)
	glass.call("_break_glass", Vector3(20, 1, 12))
	_expect(_voices(&"glass_break") >= 1, "Breaking glass shatters audibly.")


func _test_falling_prop() -> void:
	var prop := RigidBody3D.new()
	prop.collision_mask = 3
	prop.mass = 4.0
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	prop.add_child(collider)
	stage.add_child(prop)
	prop.global_position = Vector3(-20, 2.5, 10)
	WATCHER.watch(prop, 0.0, &"fall_metal")
	var heard := false
	for i in 90:
		await physics_frame
		if _voices(&"fall_metal") > 0:
			heard = true
			break
	_expect(heard, "A dropped object lands with a sound.")


func _test_pickup() -> void:
	var collector := Collector.new()
	var collider := CollisionShape3D.new()
	collider.shape = CapsuleShape3D.new()
	collector.add_child(collider)
	stage.add_child(collector)
	collector.global_position = Vector3(-30, 1, -10)
	var medkit := MEDKIT.instantiate() as Node3D
	stage.add_child(medkit)
	medkit.global_position = collector.global_position
	for i in 20:
		await physics_frame
	await create_timer(0.3).timeout
	_expect(collector.events.has(&"medkit_pickup") and collector.events.has(&"medkit_use"), "Picking up a medkit is heard and it is applied (%s)." % [collector.events])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
