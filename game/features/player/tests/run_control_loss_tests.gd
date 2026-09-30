extends SceneTree

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
	player.set("gravity_acceleration", 0.0)
	player.call("_select_weapon", 1)
	var runtime := player.get_node("InfectionRuntime")
	runtime.call("absorb_mutagen", 6.2)
	_expect(bool(runtime.call("is_control_lost")), "Player runtime has entered normal stage-one loss.")
	var before := player.global_position
	var weapon := player.call("get_current_weapon") as Node3D
	var ammo: int = weapon.call("get_magazine_ammo")
	Input.action_press("move_right")
	Input.action_press("roll")
	for frame in range(4):
		await physics_frame
	_expect(player.global_position.distance_to(before) > 0.001, "Mutation moves the player without controlled commands.")
	_expect(int(weapon.call("get_magazine_ammo")) < ammo, "Mutation fires without the fire action being held.")
	var control: RefCounted = player.get("_mutation_control")
	_expect((player.call("_move_direction") as Vector3).distance_to(control.get("direction")) < 0.001, "Movement follows mutation direction rather than held player input.")
	_expect(not bool(player.call("select_weapon_slot", 2)), "HUD slot commands are blocked during loss.")
	runtime.call("add_control_ampule")
	runtime.call("_physics_process", 5.0)
	_expect(not bool(runtime.call("is_control_lost")), "Control returns after its existing duration.")
	for frame in range(4):
		await physics_frame
	_expect(player.global_position.distance_to(before) > 0.001, "Held movement resumes after recovery.")
	_expect((control.get("direction") as Vector3).is_zero_approx(), "Uncontrolled direction resets after recovery.")
	for action in ["move_right", "fire", "roll"]:
		Input.action_release(action)
	stage.queue_free()
	print("Player control-loss tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
