extends SceneTree
## Enemy speed tuning: the multipliers are clamped, default to 1.0, and a live change
## reaches an enemy that is already on the map through its locomotion pace.

const TUNING := preload("res://game/features/infected/public/enemy_tuning.gd")
const ZOMBIE := preload("res://game/features/infected/public/infected_capsule.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_clamp()
	await _test_animation_follows_live()
	_test_movement_scale_follows_setting()
	TUNING.move_multiplier = 1.0
	TUNING.animation_multiplier = 1.0
	print("Enemy tuning tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _test_clamp() -> void:
	_check(TUNING.clamp_multiplier(0.1) == 0.5, "Speeds below 0.5 clamp to 0.5")
	_check(TUNING.clamp_multiplier(9.0) == 2.0, "Speeds above 2.0 clamp to 2.0")
	_check(TUNING.clamp_multiplier(NAN) == 1.0, "A non-finite speed restores 1.0")
	_check(TUNING.clamp_multiplier(1.25) == 1.25, "A supported speed is kept")


func _test_movement_scale_follows_setting() -> void:
	var enemy := ZOMBIE.instantiate()
	var authoring = enemy.get("_authoring")
	_check(is_equal_approx(authoring.movement_scale(), 1.0), "Movement scale defaults to 1.0")
	TUNING.move_multiplier = 0.5
	_check(is_equal_approx(authoring.movement_scale(), 0.5), "Movement scale follows the setting")
	TUNING.move_multiplier = 1.0
	enemy.free()


func _test_animation_follows_live() -> void:
	var enemy := ZOMBIE.instantiate()
	root.add_child(enemy)
	await process_frame
	var driver: Node = enemy.get_node("AnimationDriver")
	var authored := float(driver.get("locomotion_speed_multiplier"))
	_check(is_equal_approx(TUNING.animation_multiplier, 1.0), "Animation tuning defaults to 1.0")
	TUNING.animation_multiplier = 1.5
	TUNING.drive_live_enemies(self)
	_check(is_equal_approx(float(driver.get("locomotion_speed_multiplier")), authored * 1.5), "A live change scales the authored pace")
	TUNING.drive_live_enemies(self)
	_check(is_equal_approx(float(driver.get("locomotion_speed_multiplier")), authored * 1.5), "Repeated changes do not compound")
	TUNING.animation_multiplier = 1.0
	TUNING.drive_live_enemies(self)
	_check(is_equal_approx(float(driver.get("locomotion_speed_multiplier")), authored), "Returning to 1.0 restores the authored pace")
	enemy.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
