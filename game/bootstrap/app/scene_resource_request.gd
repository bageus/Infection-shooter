extends RefCounted
## One issued request: consume only terminal jobs, retaining scripts until then.
var path: String
var fraction := 0.0
var _background: bool
var _retained: RefCounted
var _foreground: Resource
var _started := 0
var _issued := false
var _taken := false
var _draining := false


func _init(source: String, background: bool, retained: RefCounted) -> void:
	path = source
	_background = background
	_retained = retained


func start() -> Error:
	if _issued or _taken: return ERR_ALREADY_IN_USE
	_started = _now_usec()
	# Do not join a possibly stalled job from an earlier cancelled attempt.
	if _already_loading(): return ERR_BUSY
	var error := OK
	if _background: error = _request_native()
	else: _foreground = ResourceLoader.load(path, "PackedScene")
	_issued = error == OK
	return error


func status() -> int:
	return _status_native() if _background else ResourceLoader.THREAD_LOAD_LOADED


func interruption(state: int, timeout_msec: int, check: Callable) -> String:
	if not allowed(check): return "loading cancelled: " + path
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS and elapsed_usec() >= timeout_msec * 1000:
		return "scene load timed out after %d ms: %s (status=%d, progress=%.3f)" % [elapsed_usec() / 1000.0, path, state, fraction]
	return ""


func elapsed_usec() -> int: return maxi(_now_usec() - _started, 0)


func take() -> Resource:
	if _taken or not _issued: return null
	var state := status()
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return null
	_taken = true
	var result: Resource
	if state != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		result = _take_native() if _background else _foreground
	_foreground = null
	_retained = null
	return result


func abandon(tree: SceneTree) -> void:
	if _taken or not _issued: return
	if status() != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		take()
	elif not _draining:
		_draining = true
		# The signal's bound request keeps only this job/scripts alive, not its UI owner.
		tree.process_frame.connect(_drain.bind(tree, self))


func _drain(tree: SceneTree, _keepalive: RefCounted) -> void:
	if status() == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	take()
	tree.process_frame.disconnect(_drain.bind(tree, self))
	_draining = false


static func allowed(check: Callable) -> bool:
	return check.is_null() or (check.is_valid() and bool(check.call()))


func _request_native() -> Error:
	return ResourceLoader.load_threaded_request(path, "PackedScene", false)


func _already_loading() -> bool:
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS


func _status_native() -> int:
	var progress: Array = []
	var state := ResourceLoader.load_threaded_get_status(path, progress)
	if not progress.is_empty(): fraction = float(progress[0])
	return state


func _take_native() -> Resource: return ResourceLoader.load_threaded_get(path)


func _now_usec() -> int: return Time.get_ticks_usec()
