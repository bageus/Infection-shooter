extends SceneTree
## A real infected chases a player 20 m away (the mid-range 14-32 m band) over a
## flat floor and a 15 degree slope: it must arrive, never sink, and stay on the floor.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SETTLE_TICKS := 30
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _scenario("flat", 0.0)
	await _scenario("slope15", deg_to_rad(15.0))
	print("Chase real enemy slope tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _scenario(label: String, angle: float) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	# Slab whose top face passes through the origin and rises along +x at `angle`.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.rotation.z = angle
	floor_body.position = Vector3(sin(angle), -cos(angle), 0) * 0.5
	var slope := tan(angle)
	var player := Node3D.new()
	stage.add_child(player)
	var run := 20.0 * cos(angle)
	player.position = Vector3(run, run * slope + 1.0, 0)
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.position = Vector3(0, 0.1, 0)
	enemy.call("set_target", player)
	var capsule := (enemy.get("collision_shape") as CollisionShape3D)
	var radius := (capsule.shape as CapsuleShape3D).radius
	var base := capsule.position.y - (capsule.shape as CapsuleShape3D).height * 0.5
	var rest := radius / cos(angle) - radius
	var reached := -1.0
	var frames := 0
	var on_floor := 0
	var sunk := 0
	var hover := 0.0
	for tick in 1200:
		await physics_frame
		# Height of the capsule's lowest point over the floor, resting contact being radius/cos(angle) lower.
		var gap := enemy.position.y + base - enemy.position.x * slope - rest
		if tick >= SETTLE_TICKS:
			frames += 1
			if enemy.is_on_floor():
				on_floor += 1
				hover = maxf(hover, gap)
			if gap < -0.05:
				sunk += 1
		var flat := Vector2(enemy.position.x - player.position.x, enemy.position.z - player.position.z)
		if flat.length() <= 2.0:
			reached = float(tick) / 60.0
			break
	var share := float(on_floor) / maxf(frames, 1.0)
	print("%s: reached %.2f s, on floor %.1f%% of %d frames, sunk %d, max hover %.3f m" % [label, reached, share * 100.0, frames, sunk, hover])
	_check(reached >= 0.0, "%s: infected reaches the player within 20 s" % label)
	_check(sunk == 0, "%s: infected never sinks below the floor (%d frames)" % [label, sunk])
	_check(share >= 0.9, "%s: infected is on the floor in >= 90%% of frames (%.1f%%)" % [label, share * 100.0])
	_check(hover <= 0.15, "%s: infected hovers at most 0.15 m above the floor (%.3f)" % [label, hover])
	stage.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
