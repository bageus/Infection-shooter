extends SceneTree

const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const COLOSSUS := preload("res://game/features/infected/public/infected_colossus.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as CharacterBody3D
	stage.add_child(player)
	var impacts := Node3D.new()
	impacts.set_script(IMPACTS)
	stage.add_child(impacts)
	player.call("configure_world", stage, impacts)
	var colossus := COLOSSUS.instantiate() as Node3D
	stage.add_child(colossus)
	colossus.global_position = player.global_position + Vector3(1.0, 0.0, 0.0)
	colossus.set("_target", player)
	colossus.set("attack_damage", 200.0)
	var full: float = player.get("health")
	player.set("armor", 30.0)
	colossus.call("_deliver_attack")
	_expect(is_equal_approx(float(player.get("health")), full), "A Colossus hit never pierces armor, even when it exceeds it.")
	_expect(is_zero_approx(float(player.get("armor"))), "The armor takes the whole Colossus hit.")
	colossus.call("_deliver_attack")
	_expect(float(player.get("health")) < full, "Without armor a Colossus hit still hurts.")
	player.set("health", full)
	player.set("armor", 30.0)
	player.call("take_damage", 200.0)
	_expect(float(player.get("health")) < full, "Other damage still pierces armor.")
	stage.queue_free()
	print("Colossus armor tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
