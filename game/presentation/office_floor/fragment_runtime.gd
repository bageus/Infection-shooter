extends Node
## Effects-root-local FIFO and bounded storage of reusable generic box fragments.
const MAX_FRAGMENTS := 40
const MAX_POOLED := 40
const SETTLED := preload("res://game/presentation/office_floor/settled_debris.gd")
# A piece left to rest folds into the settled batch after this long at rest,
# or after SETTLE_FAR_SECONDS once the player has walked away from it.
const SETTLE_CHECK_SECONDS := 0.5
const SETTLE_NEAR_SECONDS := 10.0
const SETTLE_FAR_SECONDS := 5.0
const SETTLE_FAR_DISTANCE := 8.0
const FRAGMENT_PATH := "res://game/presentation/office_floor/environment_fragment.gd"
var active: Dictionary = {}
var _fifo: Array[Dictionary] = []
var _head := 0
var _pool: Array[RigidBody3D] = []
var created_chunks := 0
var reused_chunks := 0
var _allocated: Array[WeakRef] = []
var _settled: Node3D
var _settle_clock := 0.0


func _ready() -> void:
	_settled = SETTLED.new()
	_settled.name = "SettledPieces"
	add_child(_settled)


func _process(delta: float) -> void:
	_settle_clock += delta
	if _settle_clock < SETTLE_CHECK_SECONDS:
		return
	_settle_clock = 0.0
	settle_resting(SETTLE_CHECK_SECONDS)


func register(body: RigidBody3D) -> void:
	var id := body.get_instance_id()
	var reference: WeakRef = weakref(body)
	active[id] = reference
	_fifo.append({"id": id, "reference": reference})
	while active.size() > MAX_FRAGMENTS:
		var oldest := _pop_oldest()
		if oldest != null:
			oldest.call("expire_fast")
	_compact()


func unregister(body: RigidBody3D) -> void:
	active.erase(body.get_instance_id())
	if active.is_empty():
		_fifo.clear()
		_head = 0


func _pop_oldest() -> RigidBody3D:
	while _head < _fifo.size():
		var record := _fifo[_head]
		var id: int = record.id
		_head += 1
		if not active.has(id) or active[id] != record.reference:
			continue
		var body := active[id].get_ref() as RigidBody3D
		active.erase(id)
		if body != null and not body.is_queued_for_deletion():
			return body
	return null


func _compact() -> void:
	if _head >= 128:
		_fifo = _fifo.slice(_head)
		_head = 0
	# Directly freed fragments can leave tombstones without overflowing the budget.
	if _fifo.size() > 256:
		_fifo.clear()
		for id: int in active:
			_fifo.append({"id": id, "reference": active[id]})
		_head = 0


func acquire(size: Vector3, tint: Color) -> RigidBody3D:
	var body: RigidBody3D
	if not _pool.is_empty():
		body = _pool.pop_back()
		reused_chunks += 1
		body.request_ready()
	else:
		_allocated = _allocated.filter(func(reference: WeakRef) -> bool: return reference.get_ref() != null)
		# Bound simultaneous active + fading allocations during a destruction burst.
		if _allocated.size() >= MAX_FRAGMENTS + MAX_POOLED:
			return null
		body = _make_chunk()
		_allocated.append(weakref(body))
		created_chunks += 1
	body.set("pool_owner", self)
	if body.has_meta("debris_fading"):
		body.remove_meta("debris_fading")
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.scale = Vector3.ONE
	body.set("rest_time", 0.0)
	body.visible = true
	body.process_mode = Node.PROCESS_MODE_INHERIT
	var shape := body.get_node("Shape") as CollisionShape3D
	(shape.shape as BoxShape3D).size = size
	var visual := body.get_node("Visual") as MeshInstance3D
	visual.scale = Vector3.ONE
	(visual.mesh as BoxMesh).size = size
	(visual.material_override as StandardMaterial3D).albedo_color = tint
	return body


func _make_chunk() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(load(FRAGMENT_PATH))
	body.mass = 0.15
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.9
	visual.material_override = material
	body.add_child(visual)
	return body


func recycle(body: RigidBody3D) -> void:
	unregister(body)
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_physics_process(false)
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.visible = false
	body.source = null
	body.get_parent().remove_child(body)
	if _pool.size() < MAX_POOLED and not is_queued_for_deletion():
		_pool.append(body)
	else:
		body.queue_free()


# Adds `step` seconds to every resting piece and folds the ones that have rested
# long enough into the settled batch. Pieces are recycled as if they expired.
func settle_resting(step: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for id in active.keys():
		var body := active[id].get_ref() as RigidBody3D
		if body == null or body.is_queued_for_deletion() or body.has_meta("debris_fading"):
			continue
		if not body.sleeping:
			body.set("rest_time", 0.0)
			continue
		body.set("rest_time", float(body.get("rest_time")) + step)
		if not _rested_enough(body, player):
			continue
		if not _fold_into_batch(body):
			return


func _rested_enough(body: RigidBody3D, player: Node3D) -> bool:
	var rest: float = body.get("rest_time")
	if rest >= SETTLE_NEAR_SECONDS:
		return true
	var far := player == null or body.global_position.distance_to(player.global_position) > SETTLE_FAR_DISTANCE
	return far and rest >= SETTLE_FAR_SECONDS


func _fold_into_batch(body: RigidBody3D) -> bool:
	var visual := body.get_node("Visual") as MeshInstance3D
	var size := (visual.mesh as BoxMesh).size
	var piece_basis := visual.global_basis * Basis.from_scale(size)
	var tint := (visual.material_override as StandardMaterial3D).albedo_color
	if not _settled.call("add", Transform3D(piece_basis, visual.global_position), size, tint):
		return false
	body.call("retire_from_budget")
	recycle(body)
	return true


func _exit_tree() -> void:
	for body in _pool:
		body.free()
	_pool.clear()
	active.clear()
	_fifo.clear()
	_allocated.clear()
	_head = 0
