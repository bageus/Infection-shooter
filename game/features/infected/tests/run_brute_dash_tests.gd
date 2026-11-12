extends SceneTree
## Brute lunge: gated by distance band and cooldown, faster while active, cancelled by stun.

const BRUTE := preload("res://game/features/infected/public/infected_brute.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var target := Node3D.new()
	stage.add_child(target)
	var brute := BRUTE.instantiate()
	stage.add_child(brute)
	brute.set_physics_process(false)
	brute.set_target(target)
	brute.dash_chance_per_second = 1.0e9 # certain roll, so the tests stay deterministic
	_check(brute.has_method("is_dashing") and not brute.is_dashing(), "Brute scene uses the dash script")

	brute._dash_cooldown = 0.0
	brute._behaviour_tick(0.02, Vector3(0, 0, -6))
	_check(brute.is_dashing(), "Player inside the band triggers a lunge")
	_check(is_equal_approx(brute._chase_speed(5.0), brute.dash_speed), "Lunge runs at dash speed")
	_check(brute._dash_cooldown == brute.dash_cooldown, "Lunge starts the cooldown")

	brute._behaviour_tick(0.5, Vector3(0, 0, -6))
	brute._behaviour_tick(0.02, Vector3(0, 0, -6))
	_check(not brute.is_dashing(), "Cooldown blocks a second lunge")

	brute._dash_cooldown = 0.0
	brute._behaviour_tick(0.02, Vector3(0, 0, -1.5))
	_check(not brute.is_dashing(), "Too close to the player: no lunge")
	brute._behaviour_tick(0.02, Vector3(0, 0, -15))
	_check(not brute.is_dashing(), "Too far from the player: no lunge")

	brute._dash_cooldown = 0.0
	brute._pending_hit = 0.2
	brute._behaviour_tick(0.02, Vector3(0, 0, -6))
	_check(not brute.is_dashing(), "A pending attack blow blocks the lunge")
	brute._pending_hit = -1.0

	brute._start_dash()
	brute._behaviour_tick(0.2, Vector3(0, 0, -6))
	_check(brute.is_dashing(), "Lunge keeps running inside its duration")
	brute._behaviour_tick(0.3, Vector3(0, 0, -6))
	_check(not brute.is_dashing(), "Lunge ends after its duration")
	_check(not is_equal_approx(brute._chase_speed(5.0), brute.dash_speed), "Normal chase speed returns after the lunge")

	brute._dash_cooldown = 0.0
	brute._behaviour_tick(0.02, Vector3(0, 0, -6))
	brute._blast_stun_remaining = 1.0
	brute._behaviour_tick(0.02, Vector3(0, 0, -6))
	_check(not brute.is_dashing(), "Blast stun cancels the lunge")

	stage.queue_free()
	await process_frame
	print("Brute dash tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	print(("PASS: " if condition else "FAIL: ") + message)
