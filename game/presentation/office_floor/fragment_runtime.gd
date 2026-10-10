extends Node
## Effects-root-local FIFO and bounded storage of reusable generic box fragments.
const MAX_FRAGMENTS := 40
const MAX_POOLED := 40
const FRAGMENT_PATH := "res://game/presentation/office_floor/environment_fragment.gd"
var active: Dictionary = {}
var _fifo: Array[Dictionary] = []
var _head := 0
var _pool: Array[RigidBody3D] = []
var created_chunks := 0
var reused_chunks := 0
var _allocated: Array[WeakRef] = []


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


func _exit_tree() -> void:
	for body in _pool:
		body.free()
	_pool.clear()
	active.clear()
	_fifo.clear()
	_allocated.clear()
	_head = 0
