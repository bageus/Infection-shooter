## Crowd cost bench: N enemies chase a dummy target; prints physics/process ms and the per-script PhysicsCost split (ms per tick).
## Run: godot --headless --path . --audio-driver Dummy --script tools/bench_crowd_cost.gd -- <collision_mask 3> <count 25> <ring radius 6>. NOANIM=1 pauses animation. Container numbers compare before/after only.
extends SceneTree
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const HORDE := preload("res://game/features/infected/public/infected_horde.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.get_environment("NOANIM") == "1": Engine.set_meta("probe_no_animation", true)
	var mask := int(args[0]) if args.size() > 0 else 3
	var count := int(args[1]) if args.size() > 1 else 90
	var stage := Node3D.new()
	root.add_child(stage)
	var fb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.2, 80)
	cs.shape = box
	fb.add_child(cs)
	fb.position.y = -0.1
	stage.add_child(fb)
	var enemies := Node3D.new()
	stage.add_child(enemies)
	var player := Node3D.new()
	player.position = Vector3(0, 1, 0)
	stage.add_child(player)
	for i in count:
		var e := HUNGER.instantiate() as CharacterBody3D
		var a := TAU * i / count
		var base := float(args[2]) if args.size() > 2 else 12.0
		var r := base + 0.5 * (i % 12)
		e.position = Vector3(cos(a) * r, 1.0, sin(a) * r)
		e.collision_mask = mask
		enemies.add_child(e)
		if args.size() > 3 and args[3] == "unaware":
			e.call("watch_target", player)
		else:
			e.call("set_target", player)
	for i in 30:
		await physics_frame
	Engine.max_fps = 0
	pass
	PhysicsCost.by_script.clear()
	var f0 := Engine.get_physics_frames()
	var samples := 0
	var phys := 0.0
	var proc := 0.0
	var pairs := 0.0
	var t0 := Time.get_ticks_usec()
	for i in 240:
		await process_frame
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		pairs += Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
		samples += 1
	var ticks := Engine.get_physics_frames() - f0
	var wall := (Time.get_ticks_usec() - t0) / 1000.0 / maxi(ticks, 1)
	print("RESULT mask=%d n=%d phys_ms=%.3f proc_ms=%.3f pairs=%.1f wall_ms_per_tick=%.2f ticks=%d" % [mask, count, phys * 1000.0 / samples, proc * 1000.0 / samples, pairs / samples, wall, ticks])
	var ks := PhysicsCost.by_script.keys()
	ks.sort_custom(func(a, b): return PhysicsCost.by_script[a] > PhysicsCost.by_script[b])
	for k in ks.slice(0, 12): print("COST %s %.3f ms/tick" % [k, PhysicsCost.by_script[k] / 1000.0 / maxi(ticks, 1)])
	SFX.stop_all(self)
	quit(0)
