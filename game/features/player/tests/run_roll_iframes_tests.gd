extends SceneTree

const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const PLAYER := preload("res://game/features/player/public/player.tscn")
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
	player.set("gravity_acceleration", 0.0)
	_expect(is_equal_approx(float(player.get("move_speed")), 5.4), "Walk speed is 10 % below the old 6.0.")
	_expect(is_equal_approx(float(player.get("sprint_speed")), 8.1), "Sprint speed is 10 % below the old 9.0.")
	player.set("armor", 0.0)
	var health: float = player.get("health")
	player.call("take_damage", 5.0)
	_expect(float(player.get("health")) < health, "Damage lands outside a roll.")
	health = player.get("health")
	player.set("_iframes_remaining", 0.35)
	player.call("take_damage", 5.0)
	_expect(is_equal_approx(float(player.get("health")), health), "No damage lands during roll i-frames.")
	player.set("_iframes_remaining", 0.0)
	player.call("take_damage", 5.0)
	_expect(float(player.get("health")) < health, "Damage lands again once i-frames end.")
	Input.action_press("move_right")
	Input.action_press("roll")
	await physics_frame
	await physics_frame
	_expect(float(player.get("_iframes_remaining")) > 0.0, "A manual roll grants i-frames.")
	Input.action_release("move_right")
	Input.action_release("roll")
	player.set("_roll_remaining", 0.0)
	player.set("_roll_cooldown_remaining", 0.0)
	player.set("_iframes_remaining", 0.0)
	player.set("input_locked", true)
	Input.action_press("move_right")
	Input.action_press("roll")
	await physics_frame
	await physics_frame
	_expect(float(player.get("_iframes_remaining")) == 0.0, "A locked hero cannot roll.")
	_expect(player.call("_move_direction") == Vector3.ZERO, "A locked hero ignores movement input.")
	_expect(player.is_physics_processing(), "Death lock keeps physics (gravity) running.")
	Input.action_release("move_right")
	Input.action_release("roll")
	stage.queue_free()
	print("Roll i-frame tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
