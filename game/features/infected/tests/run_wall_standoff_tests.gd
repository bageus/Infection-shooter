extends SceneTree
## A chasing infected stops far enough from a wall that its arms stay outside, and still fits through a 1.2 m gap.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _box(stage: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.position = at


func _walk(gap: float) -> float:
	var stage := Node3D.new()
	root.add_child(stage)
	_box(stage, Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	var half := gap * 0.5
	if gap > 0.0:
		_box(stage, Vector3(10, 3, 0.2), Vector3(-half - 5.0, 1.5, -3.0))
		_box(stage, Vector3(10, 3, 0.2), Vector3(half + 5.0, 1.5, -3.0))
	else:
		_box(stage, Vector3(20, 3, 0.2), Vector3(0, 1.5, -3.0))
	var player := Node3D.new()
	stage.add_child(player)
	player.position = Vector3(0.1, 1, -9)
	var enemy := HUNGER.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	enemy.position = Vector3(0.1, 0.1, 0)
	enemy.call("set_target", player)
	for tick in 240:
		await physics_frame
	var z := enemy.position.z
	stage.queue_free()
	await physics_frame
	return z


func _run() -> void:
	var z := await _walk(0.0)
	var distance := (z - (-3.0)) - 0.1  # body axis to the wall face
	print("distance to wall %.3f m" % distance)
	_check(distance >= 0.45 * 1.3 - 0.03, "stops with arm reach (>= 0.55 m) from the wall")
	_check(distance < 0.9, "still walks up to the wall")
	var z_gap := await _walk(1.2)
	print("1.2 m gap: z %.2f" % z_gap)
	_check(z_gap < -3.5, "passes through a 1.2 m gap")
	print("Wall standoff tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
