extends SceneTree
## Inject a stalled native request, not a real unkillable worker, into real queue/UI flows.
const REQUEST := preload("res://game/bootstrap/app/scene_resource_request.gd")
const QUEUE := preload("res://game/bootstrap/app/scene_resource_queue.gd")
const PREPARATION := preload("res://game/bootstrap/app/scene_resource_preparation.gd")
const MISSION := preload("res://game/bootstrap/app/menu/mission_loader.gd")
const LAYOUT := preload("res://game/bootstrap/app/planning_layout_loader.gd")
const ASSET := "res://game/bootstrap/app/tests/fixtures/layout_object.tscn"
const OTHER := "res://game/bootstrap/app/tests/fixtures/queue_model.tscn"
const THIRD := "res://game/bootstrap/app/tests/fixtures/invalid_layout_object.tscn"
const PACKED := preload("res://game/bootstrap/app/tests/fixtures/layout_object.tscn")
var failures := 0

class State extends RefCounted:
	var clock := 0
	var status := ResourceLoader.THREAD_LOAD_IN_PROGRESS
	var fraction := 0.375
	var issued := 0
	var taken := 0
	var blocked_gets := 0
	var error := OK
	var busy := false
	var payload: Resource = PACKED

class FakeRequest extends REQUEST:
	var state: State
	func _init(path: String, background: bool, retained: RefCounted, control: State) -> void:
		super(path, background, retained)
		state = control
	func _request_native() -> Error:
		state.issued += 1
		return state.error
	func _already_loading() -> bool: return state.busy
	func _status_native() -> int:
		fraction = state.fraction
		return state.status
	func _take_native() -> Resource:
		state.taken += 1
		if state.status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: state.blocked_gets += 1
		return state.payload
	func _now_usec() -> int: return state.clock

class FakeQueue extends QUEUE:
	var states := {}
	func _init() -> void:
		_background_loading = true
		concurrency_limit = 2
	func _new_request(path: String) -> REQUEST:
		return FakeRequest.new(path, true, _scripts, states[path])

class FakeMission extends MISSION:
	var fixture: FakeQueue
	func _new_resource_queue() -> QUEUE: return fixture

class Owner extends Node:
	func alive() -> bool: return true

class Editor extends Node:
	var session := {}
	var catalog := Catalog.new()
	var geometry: Variant
	var controls: Variant

class Catalog extends RefCounted:
	var created := 0
	func _migrate_scene_path(path: String) -> String: return path
	func _create_asset(_path: String) -> Node3D:
		created += 1
		return PACKED.instantiate()


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	printerr("Loading test: timeout")
	await _timeout_partial()
	printerr("Loading test: owner")
	await _cancel_and_owner_lifetime()
	printerr("Loading test: retry")
	await _errors_and_retry()
	printerr("Loading test: retained")
	await _retained_lifetime()
	printerr("Loading test: layout")
	await _layout_cancel()
	printerr("Loading test: mission")
	await _mission_cancel(false)
	await _mission_cancel(true)
	await _mission_timeout()
	printerr("Loading test: real")
	await _real_request()
	print("Loading deadline tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _progress(_value: float, _phase: String) -> void: pass


func _queue() -> FakeQueue:
	var queue := FakeQueue.new()
	for path: String in [ASSET, OTHER, THIRD]: queue.states[path] = State.new()
	queue.timeout_msec = 500
	return queue


func _advance(state: State) -> void:
	await process_frame
	state.clock = 1000000


func _cancel(life: Dictionary) -> void:
	await process_frame
	life.alive = false


func _finish(queue: FakeQueue) -> void:
	for state: State in queue.states.values(): state.status = ResourceLoader.THREAD_LOAD_LOADED
	await process_frame
	await process_frame
	for state: State in queue.states.values():
		_check(state.blocked_gets == 0, "Never call native get while it can block")
		if state.error == OK: _check(state.taken == state.issued, "Every issued request is consumed exactly once")


func _timeout_partial() -> void:
	var queue := _queue()
	queue.states[ASSET].status = ResourceLoader.THREAD_LOAD_LOADED
	_advance(queue.states[OTHER])
	var paths: Array[String] = [ASSET, OTHER, THIRD]
	var problem := await queue.load_all(paths, self, _progress)
	_check(problem.contains("timed out") and problem.contains(OTHER) and problem.contains("status=1") and problem.contains("0.375"), "Deadline identifies path, native state and progress")
	_check(queue.resources.is_empty() and queue.stats.loaded == 1, "Timeout discards partial payload without publishing it")
	_check(queue.states[THIRD].issued == 0, "Do not enqueue more work after an outstanding request expires")
	_check(queue.states[OTHER].taken == 0, "Timed-out worker is detached without blocking get")
	await _finish(queue)
	_check(queue.states[OTHER].taken == 1, "Late completion is consumed exactly once")


func _cancel_and_owner_lifetime() -> void:
	var queue := _queue()
	var life := {"alive": true}
	_cancel(life)
	var paths: Array[String] = [ASSET, OTHER, THIRD]
	var problem := await queue.load_all(paths, self, _progress, func() -> bool: return life.alive)
	_check(problem.contains("cancelled") and queue.resources.is_empty(), "Cancellation unwinds a pending queue")
	_check(queue.stats.peak_in_flight == 2 and queue.states[THIRD].issued == 0, "Cancellation preserves two-request cap and stops new work")
	await _finish(queue)
	var owner := Owner.new()
	var callback := owner.alive
	owner.free()
	queue = _queue()
	problem = await queue.load_all(paths, self, _progress, callback)
	_check(problem.contains("cancelled") and queue.states[ASSET].issued == 0, "A freed callback owner cancels before issuing work")
	var preparation := PREPARATION.new()
	_check(not await preparation.prepare(ASSET, self, callback), "Main-thread script preparation respects owner lifetime")


func _errors_and_retry() -> void:
	var queue := _queue()
	queue.states[ASSET].status = ResourceLoader.THREAD_LOAD_FAILED
	queue.states[ASSET].payload = null
	var paths: Array[String] = [ASSET, OTHER, THIRD]
	var problem := await queue.load_all(paths, self, _progress)
	_check(problem.contains("cannot load") and queue.resources.is_empty() and queue.states[THIRD].issued == 0, "Terminal failure stops the batch without waiting for another stalled request")
	await _finish(queue)
	queue.states[ASSET].status = ResourceLoader.THREAD_LOAD_LOADED
	queue.states[ASSET].payload = PACKED
	var one: Array[String] = [ASSET, ASSET]
	problem = await queue.load_all(one, self, _progress)
	_check(problem.is_empty() and queue.resources.size() == 1, "Same queue can retry successfully and still deduplicates")
	queue.resources.clear()
	queue = _queue()
	queue.states[ASSET].error = ERR_CANT_OPEN
	problem = await queue.load_all(one, self, _progress)
	_check(problem.contains("cannot request") and queue.states[ASSET].taken == 0, "Rejected requests are never consumed")
	queue = _queue()
	queue.states[ASSET].busy = true
	problem = await queue.load_all(one, self, _progress)
	_check(problem.contains("still loading") and queue.states[ASSET].issued == 0, "Retry does not join or multiply an outstanding native request")


func _retained_lifetime() -> void:
	var retained := RefCounted.new()
	var retained_ref: WeakRef = weakref(retained)
	var state := State.new()
	var request := FakeRequest.new(ASSET, true, retained, state)
	request.start()
	var request_ref: WeakRef = weakref(request)
	request.abandon(self)
	retained = null
	request = null
	_check(request_ref.get_ref() != null and retained_ref.get_ref() != null, "Detached job retains script preparation until worker termination")
	state.status = ResourceLoader.THREAD_LOAD_LOADED
	await process_frame
	await process_frame
	_check(state.taken == 1 and request_ref.get_ref() == null and retained_ref.get_ref() == null, "Completion releases the signal-bound job and retained scripts")


func _layout_cancel() -> void:
	var editor := Editor.new()
	var layout := LAYOUT.new(editor)
	var queue := _queue()
	layout.resource_queue = queue
	var life := {"alive": true}
	_cancel(life)
	var data := {"version": 8, "objects": [{"scene": ASSET}]}
	var result := await layout.prepare_async(data, self, _progress, func() -> bool: return life.alive)
	_check(result.has("error") and str(result.error).contains("cancelled") and editor.catalog.created == 0, "Layout forwards cancellation into resource wait before creating nodes")
	await _finish(queue)
	editor.free()


func _mission_cancel(was_paused: bool) -> void:
	var previous := Node3D.new()
	root.add_child(previous)
	current_scene = previous
	var body := StaticBody3D.new()
	body.collision_layer = 3
	body.collision_mask = 7
	previous.add_child(body)
	var loader := FakeMission.new()
	loader.fixture = _queue()
	loader.scene_path = ASSET
	previous.add_child(loader)
	var completed: Array[bool] = []
	loader.completed.connect(func(success: bool) -> void: completed.append(success))
	paused = was_paused
	loader.start()
	await _until(func() -> bool: return loader.fixture.states[ASSET].issued == 1)
	_check(loader.cancel.visible and not loader.back.visible and not previous.visible and body.collision_layer == 0, "Cancel is available during resource wait; error Back keeps its existing meaning")
	var queue := loader.fixture
	var loader_id := loader.get_instance_id()
	if was_paused: loader.back.pressed.emit()
	else: loader.cancel.pressed.emit()
	await _until(func() -> bool: return not is_instance_id_valid(loader_id))
	_check(completed == [false] and current_scene == previous and previous.visible and paused == was_paused, "Cancel rolls back the previous scene/pause state and reports failure once")
	_check(body.collision_layer == 3 and body.collision_mask == 7, "Cancel restores old-world collision masks")
	paused = false
	await _finish(queue)
	_check(current_scene == previous and completed == [false], "A late resource cannot activate a cancelled mission")
	previous.free()
	current_scene = null


func _mission_timeout() -> void:
	var previous := Node3D.new()
	root.add_child(previous)
	current_scene = previous
	var loader := FakeMission.new()
	loader.fixture = _queue()
	loader.resource_timeout_msec = 500
	loader.scene_path = ASSET
	previous.add_child(loader)
	loader.start()
	await _until(func() -> bool: return loader.fixture.states[ASSET].issued == 1)
	loader.fixture.states[ASSET].clock = 1000000
	await _until(func() -> bool: return loader.back.visible)
	_check(not loader.cancel.visible and not paused and loader.pending == null and previous.visible, "Timeout restores rollback state and exposes Back")
	_check(loader.label.text.contains("timed out") and loader.label.text.contains(ASSET), "Timeout UI identifies the failed resource")
	var queue := loader.fixture
	loader.back.pressed.emit()
	await process_frame
	await _finish(queue)
	previous.free()
	current_scene = null


func _real_request() -> void:
	var request := REQUEST.new(ASSET, true, RefCounted.new())
	_check(request.start() == OK, "A real native scene request starts")
	_check(request.start() == ERR_ALREADY_IN_USE, "One request cannot be issued twice")
	await _until(func() -> bool: return request.status() != ResourceLoader.THREAD_LOAD_IN_PROGRESS)
	_check(request.status() == ResourceLoader.THREAD_LOAD_LOADED and request.take() is PackedScene, "Real native completion returns the packed scene")
	_check(request.take() == null, "A request is consumed once")


func _until(condition: Callable) -> void:
	for frame in 120:
		if condition.call(): return
		await process_frame
	_check(false, "Bounded fixture wait completed")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
