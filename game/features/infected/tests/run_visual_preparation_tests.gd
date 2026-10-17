extends SceneTree
const BUDGET := preload("res://game/features/infected/public/visual_preparation_budget.gd")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	var budget := BUDGET.new()
	budget.camera = camera
	stage.add_child(budget)
	var actors: Array[Node3D] = []
	for index in 8:
		var actor := HUNGER.instantiate() as Node3D
		actor.position = Vector3(100 + index * 2, 0, 0)
		actor.call("configure_visual_preparation", budget)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actors.append(actor)
	await process_frame
	_check(budget.phases_completed == 0, "Far rigs defer expensive preparation")
	_check(actors[0].get("_parts") == null, "Damage geometry is deferred")
	_check(actors[0].get_node("AnimationDriver").get("animation_player") == null, "Animation indexing/modifiers are deferred")
	_check(actors[0].collision_layer != 0 and actors[0].is_in_group("infected_alive"), "Deferred enemies keep gameplay collision and life state")
	actors[1].call("_play_animation", &"attack")
	_check(actors[1].get_node("AnimationDriver").get("animation_player") != null, "Forced attack prepares authored timing")
	actors[0].call("take_projectile_damage", 1.0, actors[0].global_position + Vector3.UP, Vector3.FORWARD, "PISTOL")
	_check(actors[0].get("_parts") != null, "Distant hit prepares exact body-part damage first")
	_check(is_equal_approx(float(actors[0].get("health")), float(actors[0].get("max_health")) - 1.0), "Deferred shot preserves damage rules")
	camera.position.x = 100
	for frame in 25:
		var count := budget.phases_completed
		await process_frame
		_check(budget.phases_completed - count <= 1, "Camera approach prepares at most one phase/frame")
	for actor in actors:
		_check(actor.get("_parts") != null, "Nearby enemy is fully prepared")
		_check(actor.get_node("AnimationDriver").get("animation_player") != null, "Nearby animation is ready")
	var removed := HUNGER.instantiate()
	removed.call("configure_visual_preparation", budget)
	removed.free()
	await process_frame
	print("Visual preparation phases: %d; slowest: %d usec" % [budget.phases_completed, budget.max_phase_usec])
	stage.queue_free()
	await process_frame
	print("Visual preparation tests: %d failures" % failures)
	quit(failures)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
