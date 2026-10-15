extends SceneTree
## Reproducible replacement for the unavailable external 90-enemy benchmark.
const ENEMY := preload("res://game/features/infected/public/infected_hunger.tscn")
var actors: Array[CharacterBody3D] = []
var stage: Node3D
var ticks := 0
var samples: Array[float] = []
var spawn_ms := 0.0
var memory_before := 0
var draw_samples: Array[int] = []
var report := {"snapshots": []}

func _initialize() -> void:
	call_deferred("_setup")

func _setup() -> void:
	seed(20261015)
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(960, 540)
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.look_at_from_position(Vector3(14, 32, -35), Vector3(14, 0, 12))
		camera.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-60, 20, 0)
		stage.add_child(sun)
	memory_before = OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	for i in 90:
		var actor := ENEMY.instantiate() as CharacterBody3D
		actor.position = Vector3(i % 10 * 3, 0, i / 10 * 3)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actors.append(actor)
	spawn_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_report("clean")
	if "--wounded" in OS.get_cmdline_user_args():
		for actor in actors:
			actor._parts.add_rest_wound(Vector3(0, 1, 0), 0.2)
		_report("wounded")

func _report(label: String) -> void:
	var materials := {}
	var surfaces := 0
	for actor in actors:
		for entry: Dictionary in actor._parts._entries:
			for material: Material in entry.materials:
				materials[material.get_instance_id()] = true
				surfaces += 1
	var snapshot := {"state": label, "actors": actors.size(), "surfaces": surfaces, "unique_materials": materials.size(), "spawn_ms": spawn_ms, "static_memory_bytes": OS.get_static_memory_usage(), "spawn_memory_delta_bytes": OS.get_static_memory_usage() - memory_before}
	report.snapshots.append(snapshot)
	print("MATERIAL_BENCH ", JSON.stringify(snapshot))

func _physics_process(delta: float) -> bool:
	if actors.is_empty():
		return false
	var started := Time.get_ticks_usec()
	for actor in actors:
		actor._physics_process(delta)
	samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
	if DisplayServer.get_name() != "headless" and ticks > 30:
		draw_samples.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	ticks += 1
	if ticks == 239:
		var total := 0.0
		for value in samples:
			total += value
		samples.sort()
		report.tick = {"ticks": ticks, "mean_ms": total / samples.size(), "p95_ms": samples[int(samples.size() * 0.95)], "draw_calls_measured": not draw_samples.is_empty(), "draw_calls": draw_samples}
		print("MATERIAL_TICKS ", JSON.stringify(report.tick))
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--output="):
				var file := FileAccess.open(arg.trim_prefix("--output="), FileAccess.WRITE)
				assert(file != null)
				file.store_string(JSON.stringify(report, "  "))
				file.flush()
		stage.queue_free()
		call_deferred("quit")
	return false
