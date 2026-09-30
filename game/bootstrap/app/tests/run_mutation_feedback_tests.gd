extends SceneTree

const CANVAS := preload("res://game/bootstrap/app/mutation_tree_canvas.gd")
const DNA := preload("res://game/bootstrap/app/test_dna_pickup.gd")

class FakeRuntime:
	extends Node
	var threshold := 30.0
	func add_control_ampule() -> float:
		threshold = minf(95.0, threshold + 5.0)
		return threshold

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var canvas := CANVAS.new()
	var values: Array[float] = [40, 70, 25, 55, 25, 40, 55, 70, 85, 85]
	var opened: Array[bool] = [true, true, true, true, true, true, true, true, true, true]
	canvas.configure_progression(values, 95.0, opened)
	_expect(canvas.branch_origin(8) != canvas.branch_origin(9), "Late passive roots are distinct.")
	_expect(CANVAS.HYBRID_PARENTS.size() == 5, "Only adjacent passive branches have hybrids.")
	for branch in range(10):
		for rank in range(3):
			var position := canvas.skill_position(branch, rank)
			_expect(position.x - 22 >= 0 and position.x + 59 < CANVAS.DESIGN_SIZE.x, "Skill and right-side lock fit the design width.")
			_expect(position.y - 22 >= 0 and position.y + 22 < CANVAS.DESIGN_SIZE.y, "All circles fit the design height.")
	for index in range(5):
		var parents: Array = CANVAS.HYBRID_PARENTS[index]
		var position := canvas.hybrid_position(index)
		_expect(position.x > canvas.skill_position(parents[0], 2).x and position.x < canvas.skill_position(parents[1], 2).x, "Hybrid lies between its adjacent parents.")
	canvas.free()
	var stage := Node3D.new()
	root.add_child(stage)
	var player := Node3D.new()
	stage.add_child(player)
	var runtime := FakeRuntime.new()
	stage.add_child(runtime)
	var pickup := DNA.new()
	pickup.configure(player, runtime)
	stage.add_child(pickup)
	pickup.call("_collect", stage)
	_expect(runtime.threshold == 30.0, "Non-player bodies cannot take test DNA.")
	pickup.call("_collect", player)
	pickup.call("_collect", player)
	_expect(runtime.threshold == 35.0, "DNA awards once while hidden.")
	await create_timer(1.0).timeout
	_expect(bool(pickup.get("_waiting")), "DNA is still hidden before the two-second deadline.")
	await create_timer(1.2).timeout
	_expect(not bool(pickup.get("_waiting")), "DNA respawns after two seconds.")
	pickup.call("_collect", player)
	_expect(runtime.threshold == 40.0, "Respawn permits the next +5 grant.")
	stage.queue_free()
	print("Mutation feedback tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
