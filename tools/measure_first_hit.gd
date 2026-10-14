extends SceneTree
## Frame cost of the first extinguisher hit. Run with a renderer:
## xvfb-run -a godot --path . --script res://tools/measure_first_hit.gd [-- warm]
const FX := preload("res://game/presentation/office_floor/extinguisher_hit_fx.tscn")
const WARM := preload("res://game/presentation/office_floor/public/hit_effect_warmup.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")


func _initialize() -> void:
	call_deferred("_run")


func _frame(label: String, frames := 4) -> void:
	for i in frames:
		var t := Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		print("%s frame %d: %.1f ms" % [label, i, (Time.get_ticks_usec() - t) / 1000.0])


func _run() -> void:
	var warm := OS.get_cmdline_user_args().has("warm")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 1, 2)
	var effects := Node3D.new()
	root.add_child(effects)
	if warm:
		var w := WARM.new()
		w.setup(root)
		await _frame("warmup", 8)
	await _frame("idle", 3)
	var body := RigidBody3D.new()
	root.add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	body.add_child(mesh)
	var fx := FX.instantiate()
	body.add_child(fx)
	fx.call("configure", body, [mesh] as Array[MeshInstance3D])
	fx.call("configure_world", effects, null)
	await _frame("setup", 2)
	var t0 := Time.get_ticks_usec()
	fx.call("start", Vector3.ZERO, Vector3.FORWARD)
	print("start() call: %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	await _frame("after start", 6)
	if OS.get_cmdline_user_args().has("parts"):
		var BURST := load("res://game/presentation/office_floor/extinguisher_burst.tscn")
		var t1 := Time.get_ticks_usec()
		var b: Node3D = BURST.instantiate()
		b.call("configure_world", effects, null)
		effects.add_child(b)
		print("burst instantiate+add: %.1f ms" % [(Time.get_ticks_usec() - t1) / 1000.0])
		t1 = Time.get_ticks_usec()
		b.set("muted", true)
		b.call("start", 3.0, 3.6, 110)
		print("burst start(muted): %.1f ms" % [(Time.get_ticks_usec() - t1) / 1000.0])
		await _frame("burst", 4)
		quit()
		return
	var t2 := Time.get_ticks_usec()
	fx.call("_rupture")
	print("_rupture() call: %.1f ms" % [(Time.get_ticks_usec() - t2) / 1000.0])
	await _frame("rupture", 8)
	print("done")
	quit()
