extends Node
## Observe the short fall, then publish one corpse-centred blood-pool fact.
const MIN_WAIT := 0.5
const MAX_WAIT := 2.2
const STABLE_SECONDS := 0.3
var _body: WeakRef
var _skeleton: WeakRef
var _bones: Array[int] = []
var _point := Vector3.ZERO
var _previous := Vector3.ZERO
var _elapsed := 0.0
var _stable := 0.0
var _reported := false
var _excluded: Array[RID] = []
var _death_id := 0


static func start(body: CollisionObject3D, parts: Node, fallback: Vector3) -> void:
	var watcher = load("res://game/features/infected/corpse_blood_pool.gd").new()
	watcher._body = weakref(body)
	watcher._point = fallback
	watcher._previous = fallback
	var excluded: Array[RID] = [body.get_rid()]
	watcher._excluded = excluded
	watcher._death_id = body.get_instance_id()
	var skeleton := parts.get("skeleton") as Skeleton3D if parts != null else null
	if skeleton != null:
		watcher._skeleton = weakref(skeleton)
		for bone_name in ["Hips", "Chest"]:
			var index := skeleton.find_bone(bone_name)
			if index >= 0:
				watcher._bones.append(index)
	body.add_child(watcher)
	watcher._sample()


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()


func _sample() -> void:
	var skeleton := _skeleton.get_ref() as Skeleton3D if _skeleton != null else null
	if skeleton == null or _bones.is_empty():
		return
	_point = Vector3.ZERO
	for bone in _bones:
		_point += skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	_point /= _bones.size()


func _tick() -> void:
	_elapsed += 0.1
	_sample()
	_stable = _stable + 0.1 if _point.distance_to(_previous) < 0.025 else 0.0
	_previous = _point
	if (_elapsed >= MIN_WAIT and _stable >= STABLE_SECONDS) or _elapsed >= MAX_WAIT:
		_report()
		queue_free()


func _report() -> void:
	if _reported:
		return
	_reported = true
	var body := _body.get_ref() as Node if _body != null else null
	if body != null:
		body.emit_signal("blood_pool_ready", _point, _excluded, _death_id)


func _exit_tree() -> void:
	# Early removal still leaves the last sampled position, without retaining a body.
	_report()
