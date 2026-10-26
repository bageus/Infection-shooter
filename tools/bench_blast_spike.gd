extends SceneTree
## Main-thread cost of one grenade in the densest corner of the real base_office_layout at High
## destruction quality. Physics is paused after the blast so the frame times are the script/scene work
## only (the headless physics step of 3.6k bodies would hide it). Wall-clock, not Performance monitors.
## godot --headless --path . -s tools/bench_blast_spike.gd
const MAP := preload("res://game/presentation/office_floor/public/base_office_layout.tscn")
const WORLD_BINDINGS := preload("res://game/bootstrap/app/world_bindings.gd")
const QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
func _initialize() -> void:
	call_deferred("_run")
func _props(n: Node, out: Array) -> void:
	if n.has_method("take_projectile_hit") and n is RigidBody3D: out.append(n)
	for c in n.get_children(): _props(c, out)
func _run() -> void:
	QUALITY.set_level(2)
	var stage := Node3D.new(); root.add_child(stage)
	var effects := Node3D.new(); stage.add_child(effects)
	var m := MAP.instantiate(); stage.add_child(m)
	WORLD_BINDINGS.new(effects, null, null, Callable()).bind_scene(m)
	for i in 10: await physics_frame
	var props: Array = []
	_props(m, props)
	var best: Node3D = null; var bn := -1
	for p in props:
		var c := 0
		for q in props:
			if (p.global_position - q.global_position).length() < 4.0: c += 1
		if c > bn: bn = c; best = p
	for i in 5: await process_frame
	var proj := Node3D.new(); stage.add_child(proj)
	var t0 := Time.get_ticks_usec()
	EXPLOSION.explode(proj, best.global_position + Vector3(0, 0.5, 0), Vector3.UP, null, stage, null)
	var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	PhysicsServer3D.set_active(false)
	var worst := 0.0; var total := 0.0; var line := ""
	var last := Time.get_ticks_usec()
	for f in 60:
		await process_frame
		var now := Time.get_ticks_usec()
		var d := (now - last) / 1000.0
		last = now
		worst = maxf(worst, d); total += d
		if f < 20: line += " %.0f" % d
	PhysicsServer3D.set_active(true)
	print("CPU explode() %.1f ms | worst frame %.1f ms | total 60 frames %.0f ms | pieces %d | frames:%s" % [sync_ms, worst, total, get_nodes_in_group("fallen_environment_fragment").size(), line])
	quit()
