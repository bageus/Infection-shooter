extends SceneTree
## Real movement and leg clocks, isolated from the full office layout.
const PLAYER := preload("res://game/features/player/public/player.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
var failures := 0

class Stage extends Node3D:
	var player: CharacterBody3D
	func set_walk_tuning(speed: float, animation: float) -> void:
		player.call("set_walk_tuning", speed, animation)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	current_scene = stage
	stage.player = PLAYER.instantiate() as CharacterBody3D
	stage.player.get_node("AnimationDriver").set("leg_playback_multiplier", 0.75)
	stage.add_child(stage.player)
	var player := stage.player
	player.set_physics_process(false)
	player.set("gravity_acceleration", 0.0)
	await process_frame
	await process_frame
	_check(player.get_node("AnimationDriver").get("legs").get("playback_multiplier") == 0.75, "Tuning set before skeleton attachment survives initialization")
	_test_config()
	await _test_movement(player)
	_test_leg_clocks(player)
	current_scene = null
	stage.queue_free()
	await process_frame
	await process_frame
	print("Walk tuning tests: %d failures" % failures)
	quit(failures)


func _test_config() -> void:
	var had := FileAccess.file_exists(PREFS.FILE)
	var original := FileAccess.get_file_as_bytes(PREFS.FILE) if had else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("interface_v1", "language", "en")
	_check(config.save(PREFS.FILE) == OK, "Legacy config fixture is written")
	var legacy := PREFS.new()
	legacy.load_settings()
	_check(legacy.values.walk_speed_multiplier == 1.0 and legacy.values.walk_animation_multiplier == 1.0, "Older configs preserve original movement and animation")
	config.set_value("interface_v1", "walk_speed_multiplier", -10.0)
	config.set_value("interface_v1", "walk_animation_multiplier", 100.0)
	config.save(PREFS.FILE)
	var bounded := PREFS.new()
	bounded.load_settings()
	_check(bounded.values.walk_speed_multiplier == 0.5 and bounded.values.walk_animation_multiplier == 2.0, "Loaded tuning stays inside supported ranges")
	config.set_value("interface_v1", "walk_speed_multiplier", "fast")
	config.set_value("interface_v1", "walk_animation_multiplier", "slow")
	config.save(PREFS.FILE)
	var typed := PREFS.new()
	typed.load_settings()
	_check(typed.values.walk_speed_multiplier == 1.0 and typed.values.walk_animation_multiplier == 1.0, "Invalid types retain defaults")
	if had:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(PREFS.FILE)


func _test_movement(player: CharacterBody3D) -> void:
	var prefs := PREFS.new()
	var authored_walk: float = player.get("move_speed")
	var sprint: float = player.get("sprint_speed")
	var dodge: float = player.get("roll_speed")
	Input.action_press("move_up")
	for multiplier in [0.5, 1.0, 1.5]:
		prefs.values.walk_speed_multiplier = multiplier
		for repeat in 3:
			prefs.apply_to_game(self)
		var actual := await _settled_speed(player)
		_check(is_equal_approx(actual, authored_walk * multiplier), "Actual walking speed follows tuning without compounding: %s" % multiplier)
		_check(player.get("move_speed") == authored_walk, "Authored movement speed is never overwritten")
	Input.action_press("sprint")
	_check(is_equal_approx(await _settled_speed(player, true), sprint), "Walking slider leaves actual sprint speed unchanged")
	Input.action_release("sprint")
	prefs.values.walk_animation_multiplier = 2.0
	prefs.apply_to_game(self)
	_check(is_equal_approx(await _settled_speed(player), authored_walk * 1.5), "Animation slider never changes movement speed")
	player.set("_roll_direction", Vector3.RIGHT)
	player.set("_roll_pace", dodge)
	player.set("_roll_remaining", 0.4)
	await physics_frame
	player.call("_update_move", 0.1)
	_check(is_equal_approx(Vector2(player.velocity.x, player.velocity.z).length(), dodge), "Walking tuning leaves actual dodge speed unchanged")
	player.set("_roll_remaining", 0.0)
	Input.action_release("move_up")
	prefs.reset()
	prefs.apply_to_game(self)
	_check(player.get("_walk_speed_multiplier") == 1.0, "Reset applies the original walk multiplier")


func _settled_speed(player: CharacterBody3D, sprinting: bool = false) -> float:
	# Applying preferences rebuilds InputMap; press after that, as actual play does.
	Input.action_press("move_up")
	if sprinting:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	player.velocity = Vector3.ZERO
	for tick in 12:
		await physics_frame
		player.call("_update_move", 0.1)
	return Vector2(player.velocity.x, player.velocity.z).length()


func _test_leg_clocks(player: CharacterBody3D) -> void:
	var driver: Node = player.get_node("AnimationDriver")
	driver.set_process(false)
	var legs: SkeletonModifier3D = driver.get("legs")
	_check(legs != null, "Player owns the retargeted leg clips")
	if legs == null:
		return
	legs.active = false
	player.velocity = Vector3(0, 0, 3)
	legs.call("_process_modification_with_delta", 0.0)
	var upper_rate: float = driver.get("animation_player").speed_scale
	var increments: Array[float] = []
	for multiplier in [0.5, 2.0]:
		player.call("set_walk_tuning", 1.0, multiplier)
		legs.set("phase", 0.1)
		legs.set("travel_angle", 0.0)
		legs.set("weight", 1.0)
		legs.call("_apply_run", legs.get_skeleton(), 0.01)
		increments.append(float(legs.get("phase")) - 0.1)
		_check(driver.get("animation_player").speed_scale == upper_rate, "Leg tuning leaves the upper-body clock unchanged")
		_check(player.velocity == Vector3(0, 0, 3), "Leg tuning is presentation-only")
		_check(driver.call("play_dodge", Vector3.FORWARD, 0.55), "Dodge clip remains playable")
		legs.call("_process_modification_with_delta", 0.1)
		_check(is_equal_approx(float(legs.get("_dodge_time")), 0.1), "Leg tuning does not scale the dodge clock")
		legs.call("cancel_dodge")
	_check(increments[0] > 0.0 and is_equal_approx(increments[1] / increments[0], 4.0), "2x leg cycles advance four times as far as 0.5x at the same velocity")
	player.call("set_walk_tuning", NAN, NAN)
	_check(player.get("_walk_speed_multiplier") == 1.0 and driver.get("leg_playback_multiplier") == 1.0, "Non-finite tuning restores safe defaults")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
