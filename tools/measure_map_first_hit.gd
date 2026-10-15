extends SceneTree
## Frame cost of the first extinguisher hit in the real mission (front-end start).
## xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/measure_map_first_hit.gd
const BULLET := preload("res://game/features/combat/public/prototype_bullet.tscn")
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
var frames := 0


func _initialize() -> void:
	call_deferred("_run")


func _frame(label: String, count := 4) -> void:
	for i in count:
		var t := Time.get_ticks_usec()
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		print("%s %d: %.1f ms proc %.1f phys %.1f ms active %d pairs %d" % [label, i, (Time.get_ticks_usec() - t) / 1000.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])


func _find(node: Node, found: Array) -> void:
	if node is RigidBody3D and str(node.get("model_path")).contains("fire_extinguisher"):
		found.append(node)
	for child in node.get_children():
		_find(child, found)


func _run() -> void:
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	frontend.call("_action", "start")
	while current_scene == frontend or current_scene == null or not current_scene.scene_file_path.ends_with("main.tscn"):
		await process_frame
	var stage := current_scene
	await _frame("load", 6)
	await create_timer(20.0).timeout
	var list := []
	_find(stage, list)
	if OS.get_cmdline_user_args().has("kinematic"):
		for each in list:
			each.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		await create_timer(3.0).timeout
	await _frame("settled", 6)
	print("extinguishers: ", list.size(), " frozen: ", list.filter(func(b): return b.freeze).size())
	var body: RigidBody3D = list[0]
	var mode := "bullet"
	for arg in OS.get_cmdline_user_args():
		if arg != "kinematic":
			mode = arg
	print("mode: ", mode)
	if mode == "other":
		for candidate in stage.get("mission_objects").get_children():
			if candidate is RigidBody3D and str(candidate.get("model_path")).contains("desk") and not candidate.freeze:
				body = candidate
				break
	var normal: Vector3 = body.get_meta("planning_wall_normal", Vector3.BACK)
	var direction := -normal.normalized()
	var bullet := BULLET.instantiate() as Node3D
	stage.get("mission_objects").add_child(bullet)
	bullet.global_position = body.global_position + normal.normalized() * 1.5 + Vector3.UP * 0.2
	bullet.call("configure_world", stage.get("mission_objects"), stage.get("impact_pool"))
	bullet.call("setup_projectile", (body.global_position + Vector3.UP * 0.2 - bullet.global_position).normalized(), null, 20.0, 60.0, 10.0, "PISTOL", bullet.global_position)
	var t0 := Time.get_ticks_usec()
	if mode == "unfreeze":
		bullet.queue_free()
		body.freeze = false
		body.sleeping = false
	if mode == "direct":
		bullet.queue_free()
		body.call("take_projectile_hit", 10.0, body.global_position, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	print("hit call: %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	await _frame("after hit", 40)
	print("done")
	quit()
