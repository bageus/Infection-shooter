extends SceneTree
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const REVENANT := preload("res://game/features/infected/public/infected_revenant.tscn")
const HORDE := preload("res://game/features/infected/public/infected_horde.tscn")
const COLOSSUS := preload("res://game/features/infected/public/infected_colossus.tscn")
const WAVE := preload("res://game/features/infected/ground_shockwave.gd")
const META := &"enemy_gameplay_modes_v1"
class Target extends Node3D:
	var received := 0.0
	func take_damage(amount: float) -> void:
		received += amount
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(80, 1, 80)
	floor_body.add_child(shape)
	floor_body.position.y = -.5
	stage.add_child(floor_body)
	var target := Target.new()
	target.add_to_group("player")
	stage.add_child(target)
	for scene: PackedScene in [HUNGER, REVENANT, HORDE, COLOSSUS]:
		await _ignore(stage, target, scene)
	await _damage(stage, target)
	stage.free()
	await process_frame
	print("Enemy gameplay modes tests: %d failures" % failures)
	quit(failures)

func _ignore(stage: Node3D, target: Target, scene: PackedScene) -> void:
	target.set_meta(META, {"ignore_player": true, "no_damage": false})
	var enemy := scene.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.position = Vector3(0, .05, 1.0)
	enemy.set_target(target) # Forced spawn must also stay unaware.
	enemy.get("_senses").set("_wander_wait", 0.0)
	var health_before := float(enemy.get("health"))
	enemy.take_damage(1.0)
	enemy.hear_noise(target.global_position, 50.0)
	enemy.hear_alert(target.global_position, 50.0)
	var start := enemy.position
	for frame in 240: # Wandering can start later than 90 frames; the window must allow for it.
		await physics_frame
	_check(not enemy.is_alerted(), "Sight/hits/noise/alerts/forced spawn stay ignored: " + scene.resource_path)
	_check(float(enemy.get("health")) < health_before, "Player can still damage an ignoring enemy")
	_check(Vector2(enemy.position.x - start.x, enemy.position.z - start.z).length() > .05, "Ignoring enemies still wander: " + scene.resource_path)
	target.set_meta(META, {"ignore_player": false, "no_damage": true})
	await physics_frame
	await physics_frame
	_check(enemy.is_alerted(), "Disabling ignore restores summoned chase")
	enemy.set("_pending_hit", .01)
	target.received = 0.0
	target.set_meta(META, {"ignore_player": true, "no_damage": false})
	await physics_frame
	await physics_frame
	_check(not enemy.is_alerted() and target.received == 0.0, "Live ignore cancels chase and queued attacks")
	enemy.free()

func _damage(stage: Node3D, target: Target) -> void:
	var enemy := REVENANT.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.set_target(target)
	enemy.set_physics_process(false)
	var horde := HORDE.instantiate() as CharacterBody3D
	stage.add_child(horde)
	horde.set_target(target)
	horde.set_physics_process(false)
	var wave := WAVE.new()
	stage.add_child(wave)
	wave.set_physics_process(false)
	wave.player_damage = 32.0
	for policy in [{"ignore_player": false, "no_damage": true}, {"ignore_player": true, "no_damage": false}, {}]:
		target.set_meta(META, policy)
		target.received = 0.0
		enemy.call("_deliver_attack")
		horde.set("_ram_struck", false)
		horde.call("_tick_ram", .1, Vector3.ZERO)
		wave.call("_strike", target, 0, Vector3.ZERO)
		_check((target.received > 0.0) == policy.is_empty(), "Melee, ram and in-flight wave obey current flags; ordinary defaults deal damage")
	wave.free()
	horde.free()
	enemy.free()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
