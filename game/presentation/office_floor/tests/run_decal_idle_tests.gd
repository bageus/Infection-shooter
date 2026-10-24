extends SceneTree
const BLOOD := preload("res://game/presentation/office_floor/blood_decal_prop.gd")
const COUNT := 300

class CountedFit extends "res://game/presentation/office_floor/biomass_fit.gd":
	var calls := 0
	func _process(delta: float) -> void:
		calls += 1
		super._process(delta)

class Piece extends Node3D:
	var own_shown := 0
	func biomass_frame() -> Transform3D:
		return global_transform
	func biomass_excluded() -> bool:
		return false
	func get_blood_attachment() -> Dictionary:
		return {}
	func biomass_cell() -> int:
		return 0
	func biomass_show_cell() -> void:
		own_shown += 1

class ProjectionPool extends Node:
	var calls := 0
	var triangle: ArrayMesh
	var receiver: MeshInstance3D
	func projected_geometry(anchor: Node3D, _frame: Transform3D, _size: Vector2, _depth: float, _flag: bool) -> Array:
		calls += 1
		return [{"anchor": anchor, "mesh": triangle}, {"anchor": receiver, "mesh": triangle}]

var failures := 0
var stage: Node3D


func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	if "--bench-only" in OS.get_cmdline_user_args():
		_blood_motion_and_cost()
		stage.free()
		await process_frame
		quit(0 if failures == 0 else 1)
		return
	await _fit_idle()
	_blood_motion_and_cost()
	await _worker_wake()
	stage.free()
	await process_frame
	print("Decal idle tests: %d failure(s)." % failures)
	quit(0 if failures == 0 else 1)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _sum(fits: Array[CountedFit]) -> int:
	var result := 0
	for fit in fits: result += fit.calls
	return result


func _fit_idle() -> void:
	var container := Node3D.new()
	stage.add_child(container)
	var fits: Array[CountedFit] = []
	for index in COUNT:
		var piece := Piece.new()
		piece.position.x = index * 3.0
		piece.set_meta("biomass_piece", true)
		container.add_child(piece)
		var fit := CountedFit.new()
		fit.name = "BiomassFit"
		piece.add_child(fit)
		fits.append(fit)
	await _frames(30)
	var before := _sum(fits)
	await _frames(60)
	var extra := _sum(fits) - before
	_expect(extra == 0, "Settled biomass does not run idle Fit callbacks (%d)" % extra)
	print("FIT_IDLE_METRICS pieces=%d frames=60 callbacks=%d" % [COUNT, extra])
	var first := fits[0]
	var own := (first.get_parent() as Piece).own_shown
	first.get_parent().position.y += 0.25
	await _frames(3)
	_expect(first.is_processing() and (first.get_parent() as Piece).own_shown > own, "Moving an idle piece wakes fitting and restores its relief")
	await _frames(60)
	_expect(not first.is_processing(), "Moved single piece returns to idle")
	container.position.z += 2
	await _frames(3)
	_expect(first.is_processing(), "Inherited parent movement also wakes fitting")
	await _frames(60)
	_expect(not first.is_processing(), "Inherited movement settles back to idle")
	first.release()
	_expect(first.is_processing(), "Explicit release wakes an idle Fit")
	container.free()
	await process_frame


func _triangle() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]:
		tool.set_normal(Vector3.BACK)
		tool.set_uv(Vector2(point.x, point.y))
		tool.add_vertex(point)
	return tool.commit()


func _blood_motion_and_cost() -> void:
	var container := Node3D.new()
	stage.add_child(container)
	var anchor := MeshInstance3D.new()
	anchor.mesh = BoxMesh.new()
	container.add_child(anchor)
	var other := MeshInstance3D.new()
	other.mesh = BoxMesh.new()
	container.add_child(other)
	var pool := ProjectionPool.new()
	pool.triangle = _triangle()
	pool.receiver = other
	container.add_child(pool)
	var pieces: Array[Node3D] = []
	for index in COUNT:
		var piece := BLOOD.new()
		piece.configure_blood("splatter_01", "object")
		piece.position = Vector3(index * 2, 1, 0)
		container.add_child(piece)
		piece.configure_world(container, pool)
		piece.attach_blood(anchor, "fixture_anchor")
		piece.set_process(false)
		piece.call("_process", 0.016)
		pieces.append(piece)
	var before := pool.calls
	var started := Time.get_ticks_usec()
	for frame in 60:
		for piece in pieces: piece.call("_process", 0.016)
	var elapsed := Time.get_ticks_usec() - started
	_expect(pool.calls == before, "Stationary blood reuses projected geometry")
	print("BLOOD_IDLE_METRICS pieces=%d frames=60 callback_usec=%d projections=%d" % [COUNT, elapsed, pool.calls - before])
	var piece: Node3D = pieces[0]
	var offset := anchor.global_transform.affine_inverse() * piece.global_transform
	anchor.rotation.y = 0.4
	anchor.position = Vector3(2, 0, 1)
	piece.call("_process", 0.016)
	_expect(piece.global_transform.is_equal_approx(anchor.global_transform * offset), "Blood follows a translated and rotated anchor")
	piece.position += Vector3(0.3, 0, 0.2)
	piece.call("_process", 0.016)
	offset = anchor.global_transform.affine_inverse() * piece.global_transform
	anchor.position.x += 2
	piece.call("_process", 0.016)
	_expect(piece.global_transform.is_equal_approx(anchor.global_transform * offset), "Planner edits update attachment offset while anchor is stationary")
	before = pool.calls
	other.position.z += 1
	piece.call("_process", 0.016)
	_expect(pool.calls == before + 1, "A secondary receiver moving still invalidates projection")
	anchor.hide()
	piece.call("_process", 0.016)
	_expect(not (piece.get("_visual") as Node3D).visible, "Hidden support hides attached blood")
	anchor.show()
	piece.call("_process", 0.016)
	_expect((piece.get("_visual") as Node3D).visible, "Showing support restores attached blood")
	anchor.free()
	piece.call("_process", 0.016)
	_expect(not piece.is_processing() and not (piece.get("_visual") as Node3D).visible, "Freed support hides blood and stops processing")
	container.free()


func _worker_wake() -> void:
	var container := Node3D.new()
	stage.add_child(container)
	var a := _real_piece(container, Vector3.ZERO)
	await _frames(30)
	var fit := a.get_node("BiomassFit")
	_expect(not fit.is_processing(), "Real single biomass Fit idles before a neighbor arrives")
	var b := _real_piece(container, Vector3(0.04, 0, 0))
	for frame in 360:
		if a.get("_fused") and not fit.is_processing(): break
		await process_frame
	_expect(a.get("_fused") and not fit.is_processing(), "A new neighbor wakes the idle leader, commits worker output, then idles")
	a.free()
	await _frames(3)
	_expect((b.get("_visual") as Node3D).visible, "Deleting a fused leader releases its follower")
	await _frames(30)
	_expect(not b.get_node("BiomassFit").is_processing(), "Released follower settles without idle polling")
	container.free()
	await process_frame


func _real_piece(parent: Node3D, at: Vector3) -> Node3D:
	var piece := BLOOD.new()
	piece.configure_blood("biomass_01", "floor")
	piece.scale = Vector3.ONE * 0.08
	piece.position = at
	parent.add_child(piece)
	return piece


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
