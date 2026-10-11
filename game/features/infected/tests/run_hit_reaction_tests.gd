extends SceneTree
## Runtime checks for the upper-body hit reaction and the charge/walk pace
## (ADR-0038): a shot to one side of the torso swings that shoulder back while
## hips and legs keep the clip, the body is never moved as a whole, the torso
## settles again; charges come in bursts with walks between them, the final
## approach is always a charge and pace changes are eased.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const PACE := preload("res://game/features/infected/chase_pace.gd")
const BONES := ["Hips", "L_Thigh", "R_Shin", "L_Shoulder", "R_Shoulder", "Head"]

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pace_bursts()
	_test_pace_lunge_and_easing()
	var stage := Node3D.new()
	root.add_child(stage)
	await _test_torso_twists_toward_hit_side(stage, 1.0)
	await _test_torso_twists_toward_hit_side(stage, -1.0)
	await _test_blast_rocks_torso_back(stage)
	stage.queue_free()
	await process_frame
	print("Hit reaction tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _test_pace_bursts() -> void:
	var pace := PACE.new(7)
	var dt := 1.0 / 60.0
	var speeds: Array[float] = []
	for i in 600:
		speeds.append(pace.tick(dt, 20.0, 9.0, 5.0, 0.4))
	_expect(absf(speeds.max() - 2.0) < 0.001, "Out of charge range the pace is a steady walk.")
	var charge_frames := 0
	var walk_frames := 0
	var switches := 0
	var was_charging := false
	for i in 1200:
		pace.tick(dt, 6.0, 9.0, 5.0, 0.4)
		if pace.charging != was_charging:
			switches += 1
			was_charging = pace.charging
		if pace.speed > 4.99:
			charge_frames += 1
		elif pace.speed < 2.01:
			walk_frames += 1
	_expect(switches >= 4, "In charge range the infected alternates sprints and walks (%d switches in 20 s)." % switches)
	_expect(charge_frames > 300 and walk_frames > 100, "It spends time both sprinting and walking (%d / %d frames)." % [charge_frames, walk_frames])
	pace.tick(dt, 9.8, 9.0, 5.0, 0.4)
	_expect(pace.get("_in_range"), "Just beyond the charge edge the infected still counts as in range.")
	var always := PACE.new(1)
	_expect(is_equal_approx(always.tick(dt, 30.0, 0.0, 5.0, 0.4), 5.0), "charge_distance 0 always charges.")


func _test_pace_lunge_and_easing() -> void:
	var pace := PACE.new(3)
	var dt := 1.0 / 60.0
	var lunge_walk := false
	var biggest_step := 0.0
	var previous := pace.tick(dt, 6.0, 9.0, 5.0, 0.4)
	for i in 1200:
		var speed := pace.tick(dt, 2.5, 9.0, 5.0, 0.4)
		if i > 60 and speed < 4.99:
			lunge_walk = true
		biggest_step = maxf(biggest_step, absf(speed - previous))
		previous = speed
	_expect(not lunge_walk, "Close to the prey the infected never drops to a walk.")
	for i in 1200:
		var speed := pace.tick(dt, 6.0, 9.0, 5.0, 0.4)
		biggest_step = maxf(biggest_step, absf(speed - previous))
		previous = speed
	_expect(biggest_step <= 5.0 * 1.4 * dt + 0.001, "Walk and run blend through eased speed changes (largest step %.3f m/s)." % biggest_step)


# side 1.0 shoots the infected's right flank, -1.0 its left.
func _test_torso_twists_toward_hit_side(stage: Node3D, side: float) -> void:
	var hit := await _spawn(stage, Vector3(-2, 1, 0))
	var twin := await _spawn(stage, Vector3(2, 1, 0))
	var hit_skeleton := _skeleton(hit)
	var twin_skeleton := _skeleton(twin)
	var body_before := (hit.get_node("Body") as Node3D).transform
	# Infected face -Z; their right is +X. The shot comes from the front.
	var chest := hit_skeleton.global_transform * hit_skeleton.get_bone_global_pose(hit_skeleton.find_bone("Chest")).origin
	hit.call("take_projectile_damage", 5.0, chest + Vector3(0.22 * side, 0.0, -0.1), Vector3(0, 0, 1), "PISTOL")
	var peak := 0.0
	var legs_kept := true
	for i in 10:
		var a := await _sample(hit_skeleton)
		var b := await _sample(twin_skeleton)
		var flank := "R_Shoulder" if side > 0.0 else "L_Shoulder"
		# Positive: the shot flank went back (+Z), relative to the untouched twin.
		peak = maxf(peak, (a[flank] as Vector3).z - (b[flank] as Vector3).z)
		for bone in ["Hips", "L_Thigh", "R_Shin"]:
			if (a[bone] as Vector3 - Vector3(-4, 0, 0)).distance_to(b[bone]) > 0.002:
				legs_kept = false
	var label := "right" if side > 0.0 else "left"
	_expect(peak > 0.03, "A shot to the %s of the torso swings that shoulder back (%.3f m)." % [label, peak])
	_expect(legs_kept, "Hips and legs keep the clip during a %s hit reaction." % label)
	_expect((hit.get_node("Body") as Node3D).transform.is_equal_approx(body_before), "The whole body is not moved by a hit.")
	await _physics(90)
	var a := await _sample(hit_skeleton)
	var b := await _sample(twin_skeleton)
	_expect((a["Head"] as Vector3 - Vector3(-4, 0, 0)).distance_to(b["Head"]) < 0.01, "The torso settles after the %s hit." % label)
	hit.queue_free()
	twin.queue_free()
	await process_frame


func _test_blast_rocks_torso_back(stage: Node3D) -> void:
	var hit := await _spawn(stage, Vector3(-2, 1, 0))
	var twin := await _spawn(stage, Vector3(2, 1, 0))
	hit.call("take_blast_damage", 12.0, hit.global_position + Vector3(0, 0, -4))
	var peak := 0.0
	for i in 10:
		var a := await _sample(_skeleton(hit))
		var b := await _sample(_skeleton(twin))
		peak = maxf(peak, (a["Head"] as Vector3).z - (b["Head"] as Vector3).z)
	_expect(peak > 0.03, "A blast in front rocks the torso back (%.3f m)." % peak)
	hit.queue_free()
	twin.queue_free()
	await process_frame


func _spawn(stage: Node3D, at: Vector3) -> CharacterBody3D:
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.global_position = at
	await process_frame
	return enemy


func _skeleton(enemy: Node) -> Skeleton3D:
	return enemy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


# World bone positions once this frame's modifiers have run.
func _sample(skeleton: Skeleton3D) -> Dictionary:
	await skeleton.skeleton_updated
	var result := {}
	for bone: String in BONES:
		result[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
	return result


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
