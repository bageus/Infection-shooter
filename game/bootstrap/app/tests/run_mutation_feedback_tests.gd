extends SceneTree

const CANVAS := preload("res://game/bootstrap/app/mutation_tree_canvas.gd")
const PICKUP_ART := preload("res://game/features/combat/public/launcher_visual.gd")
const DNA := preload("res://game/bootstrap/app/test_dna_pickup.gd")
const SKILL_ICONS := preload("res://game/bootstrap/app/mutation_skill_icons.gd")
const INFECTION := preload("res://game/features/infection/public/infection_runtime.gd")

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
	_expect(canvas.trunk_available_x() == canvas.branch_origin(9).x, "The trunk ends at the last open root, with no available tail.")
	var initial: Array[bool] = [false, false, true, false, true, false, false, false, false, false]
	canvas.configure_progression(values, 95.0, initial)
	_expect(canvas.trunk_available_x() == canvas.branch_origin(4).x, "High mutation cannot expose a connector toward a closed branch.")
	canvas.set_mutation(0.0)
	_expect(canvas.trunk_available_x() == canvas.branch_origin(4).x, "Mutation changes cannot partially fill or retract the central connector.")
	initial[0] = true
	initial[5] = true
	canvas.configure_progression(values, 0.0, initial)
	_expect(canvas.trunk_available_x() == canvas.branch_origin(5).x, "Opening the next branches exposes their entire connector at once.")
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
	var player := CharacterBody3D.new()
	player.collision_layer = 1
	player.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	player.add_child(shape)
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
	_expect(runtime.threshold == 40.0, "Standing in the area collects respawned DNA once after two seconds.")
	player.position.x = 3.0
	await create_timer(2.2).timeout
	_expect(not bool(pickup.get("_waiting")), "DNA remains visible when the player leaves.")
	_expect(runtime.threshold == 40.0, "Visible DNA does not award remotely.")
	player.position.x = 0.0
	await physics_frame
	await physics_frame
	await physics_frame
	_expect(runtime.threshold == 45.0, "Reentering the area collects DNA through physics overlap.")
	paused = true
	await create_timer(2.2, true).timeout
	_expect(bool(pickup.get("_waiting")), "Gameplay pause stops DNA respawn.")
	_expect(runtime.threshold == 45.0, "Paused DNA cannot award again.")
	paused = false
	await create_timer(2.2).timeout
	_expect(runtime.threshold == 50.0, "Unpausing resumes recurring DNA pickup.")
	for index in range(4):
		var art := PICKUP_ART.make_pickup_visual(index)
		_expect(not art.find_children("*", "MeshInstance3D", true, false).is_empty(), "Each weapon pickup has its authored GLB geometry.")
		art.free()
	stage.queue_free()
	_check_skill_icons()
	_check_branch_labels()
	print("Mutation feedback tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _check_skill_icons() -> void:
	var infection := INFECTION.new()
	var regions: Array[Rect2] = []
	for row in infection.skill_catalog():
		var icon := SKILL_ICONS.for_skill(str(row[0])) as AtlasTexture
		_expect(icon != null, "Skill %s has an atlas icon." % row[0])
		if icon != null:
			_expect(not regions.has(icon.region), "Skill %s has its own atlas cell." % row[0])
			_expect(Rect2(Vector2.ZERO, icon.atlas.get_size()).encloses(icon.region), "Skill %s icon lies inside the atlas." % row[0])
			regions.append(icon.region)
	var cell := SKILL_ICONS.ATLAS.get_size() / SKILL_ICONS.GRID
	_expect(Rect2(Vector2.ZERO, cell).encloses((SKILL_ICONS.for_skill("muscle_memory") as AtlasTexture).region), "Atlas cell 1 is Muscle Memory.")
	_expect(Rect2(cell * 5, cell).encloses((SKILL_ICONS.for_skill("berserk") as AtlasTexture).region), "Atlas cell 36 is Berserk.")
	var claws: Rect2 = (SKILL_ICONS.for_skill("claws") as AtlasTexture).region
	_expect(is_equal_approx(claws.size.x, claws.size.y) and claws.size.x < cell.x, "Icons are trimmed to a square around the glyph.")
	infection.free()


func _check_branch_labels() -> void:
	var canvas := CANVAS.new()
	var values: Array[float] = [40, 70, 25, 55, 25, 40, 55, 70, 85, 85]
	var opened: Array[bool] = [true, true, true, true, true, true, true, true, true, true]
	canvas.configure_progression(values, 95.0, opened)
	for index in CANVAS.BRANCHES.size():
		var area: Rect2 = canvas.label_rect(index)
		var middle := (canvas.skill_position(index, 0).x + canvas.skill_position(index, 2).x) * 0.5
		_expect(is_equal_approx(area.get_center().x, middle), "Branch %d title is centred over its circles." % index)
		for other in range(index + 1, CANVAS.BRANCHES.size()):
			if (other < 4) == (index < 4):
				var next: Rect2 = canvas.label_rect(other)
				_expect(area.end.x <= next.position.x or next.end.x <= area.position.x, "Branch titles %d and %d do not overlap." % [index, other])
	canvas.free()
