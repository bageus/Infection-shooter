extends SceneTree
## Replacement microbenchmark; the owner's external crowd_bench.gd is unavailable.
const ENEMY := preload("res://game/features/infected/public/infected_hunger.tscn")
var frames := 0
var samples: Array[float] = []
var stage: Node3D
var actors: Array[CharacterBody3D] = []

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	seed(20261014)
	var args := OS.get_cmdline_user_args()
	var mask := int(args[0]) if args.size() > 0 else 1
	var count := int(args[1]) if args.size() > 1 else 90
	var radius := float(args[2]) if args.size() > 2 else 14.0
	var unaware := args.size() < 4 or args[3] == "unaware"
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	# Opaque cover keeps the player unseen even when a wander turns toward them.
	var cover := StaticBody3D.new()
	var cover_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.0
	cylinder.height = 4.0
	cover_shape.shape = cylinder
	cover_shape.position.y = 2.0
	cover.add_child(cover_shape)
	stage.add_child(cover)
	var target := Node3D.new()
	stage.add_child(target)
	for i in count:
		var enemy := ENEMY.instantiate()
		var angle := TAU * i / count
		enemy.position = Vector3(cos(angle), 0, sin(angle)) * radius + Vector3.UP * 0.1
		# Face away from the player; perception still runs normally.
		enemy.rotation.y = atan2(-cos(angle), -sin(angle))
		enemy.collision_mask = mask
		stage.add_child(enemy)
		enemy.set_physics_process(false)
		actors.append(enemy)
		if unaware:
			enemy.watch_target(target)
		else:
			enemy.set_target(target)

func _physics_process(delta: float) -> bool:
	if stage == null:
		return false
	var started := Time.get_ticks_usec()
	for actor in actors:
		actor._physics_process(delta)
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	frames += 1
	if frames > 30:
		samples.append(elapsed)
	if frames == 239:
		var total := 0.0
		for value in samples:
			total += value
		samples.sort()
		print("CROWD_BENCH ticks=239 warmup=30 samples=%d mean_ms=%.4f median_ms=%.4f p95_ms=%.4f" % [samples.size(), total / samples.size(), samples[samples.size()/2], samples[int(samples.size()*0.95)]])
		var alerted := 0
		for actor in actors:
			if actor.is_alerted():
				alerted += 1
		print("CROWD_BENCH alerted=%d" % alerted)
		stage.queue_free()
		call_deferred("quit")
	return false
