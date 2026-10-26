extends SceneTree
## A grenade used to break every prop of a crowded corner in one frame. The destruction budget runs the
## queued breakups a few milliseconds per frame, and the pieces of a breakup no longer cast shadows when
## they are chips or thin sheets.
const BUDGET := preload("res://game/presentation/office_floor/destruction_budget.gd")
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const JOB_USEC := 2000

var failures := 0
var _frames_seen: Array[int] = []
var _order: Array[int] = []


class Host extends Node3D:
	var effects_root: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	QUALITY.set_level(QUALITY.HIGH)
	await _budget()
	await _unbound_job()
	await _piece_shadows()
	await _fifo_times()
	print("Destruction budget tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _busy(index: int) -> void:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < JOB_USEC:
		pass
	_order.append(index)
	_frames_seen.append(Engine.get_process_frames())


func _budget() -> void:
	var effects := Node3D.new()
	root.add_child(effects)
	await process_frame
	for index in 20:
		BUDGET.enqueue(effects, Callable(self, "_busy").bind(index))
	var doomed := Node.new()
	root.add_child(doomed)
	BUDGET.enqueue(effects, Callable(doomed, "queue_free"))
	doomed.free()
	var queue := effects.get_node(BUDGET.NAME)
	_expect(queue.call("pending") == 21, "Every breakup is queued, none runs in the frame of the blast")
	_expect(_order.is_empty(), "Nothing ran before the next frame")
	var guard := 0
	while queue.call("pending") > 0 and guard < 60:
		await process_frame
		guard += 1
	_expect(_order.size() == 20, "All queued breakups run (%d of 20)" % _order.size())
	_expect(_order == range(20), "Breakups run oldest first")
	var per_frame := {}
	for frame in _frames_seen:
		per_frame[frame] = int(per_frame.get(frame, 0)) + 1
	var worst := 0
	for frame in per_frame:
		worst = maxi(worst, per_frame[frame])
	var allowed := BUDGET.BUDGET_USEC / JOB_USEC + 1
	_expect(per_frame.size() > 1 and worst <= allowed, "A frame runs at most %d jobs of %d us (ran %d, over %d frames)" % [allowed, JOB_USEC, worst, per_frame.size()])
	_expect(not queue.is_processing(), "An empty queue stops processing")
	effects.queue_free()
	await process_frame


func _unbound_job() -> void:
	var state := {"ran": false}
	BUDGET.enqueue(null, func() -> void: state.ran = true)
	_expect(not state.ran, "A job without an effects root does not run inline")
	await process_frame
	_expect(state.ran, "A job without an effects root still runs on the next idle call")


func _piece(host: Host, size: Vector3) -> RigidBody3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	host.add_child(mesh)
	var piece := DAMAGE.spawn_piece(host, mesh, null, 1, 1, Vector3.UP, Vector3.ZERO)
	mesh.queue_free()
	return piece


func _piece_shadows() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var host := Host.new()
	host.effects_root = world
	world.add_child(host)
	var chip := _piece(host, Vector3(0.2, 0.1, 0.3))
	var sheet := _piece(host, Vector3(1.2, 0.02, 0.8))
	var solid := _piece(host, Vector3(0.6, 0.3, 0.9))
	_expect(_shadow_of(chip) == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "A chip casts no shadow")
	_expect(_shadow_of(sheet) == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "A thin sheet casts no shadow")
	_expect(_shadow_of(solid) == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "A solid piece keeps its shadow")
	world.queue_free()
	await process_frame


func _shadow_of(piece: RigidBody3D) -> int:
	for child in piece.get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).cast_shadow
	return -1


# A big blast registers hundreds of pieces; rebuilding the FIFO on every registration lost each piece's
# birth time (so fresh pieces were no longer spared) and cost a full pass per piece.
func _fifo_times() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var runtime := DEBRIS.runtime_for(world)
	var bodies: Array[RigidBody3D] = []
	for index in 400:
		var body := RigidBody3D.new()
		world.add_child(body)
		bodies.append(body)
		runtime.register(body)
	var timed := 0
	for record: Dictionary in runtime._fifo:
		if record.has("time"):
			timed += 1
	_expect(runtime.active.size() == 400, "All pieces stay registered")
	_expect(timed == runtime._fifo.size() and runtime._fifo.size() >= 400, "Registration keeps the birth time of every piece (%d of %d)" % [timed, runtime._fifo.size()])
	for body in bodies:
		body.free()
	runtime.active.clear()
	world.queue_free()
	await process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
