extends Node3D
## Turns only naturally sleeping furniture into static collision; owns wake dependencies.
## Kickable items retain dynamic contact reporting for feet under Jolt.
const FROZEN := &"prop_rest_frozen"
const DEPENDENTS := &"prop_rest_dependents"
var _body: RigidBody3D
var _connections: Array[Dictionary] = []
var _supports: Array[WeakRef] = []
var _rest_transform := Transform3D.IDENTITY
var _exiting := false
var _local_bounds := AABB()
var _probe := BoxShape3D.new()

static func watch(body: RigidBody3D) -> void:
	var rest := new()
	rest.name = "PropRest"
	body.add_child(rest)

func _ready() -> void:
	_body = get_parent() as RigidBody3D
	set_process(false)
	set_physics_process(false)
	call_deferred("_setup")

func _setup() -> void:
	if _body == null or _body.freeze or bool(_body.get_meta(&"kickable_prop", false)) or not _body.can_sleep:
		queue_free()
		return
	_local_bounds = body_bounds(_body)
	_body.sleeping_state_changed.connect(_sleep_changed)
	_body.body_exited.connect(_contact_left)
	_sleep_changed()

static func body_bounds(body: RigidBody3D) -> AABB:
	var result := AABB()
	var found := false
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			var bounds: AABB = child.transform * _shape_bounds(child.shape)
			result = bounds if not found else result.merge(bounds)
			found = true
	return result

static func _shape_bounds(shape: Shape3D) -> AABB:
	var size := Vector3.ZERO
	if shape is BoxShape3D:
		size = shape.size
	elif shape is SphereShape3D:
		size = Vector3.ONE * shape.radius * 2.0
	elif shape is CapsuleShape3D:
		size = Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0)
	else:
		return shape.get_debug_mesh().get_aabb()
	return AABB(-size * .5, size)

func _sleep_changed() -> void:
	if _body.sleeping:
		call_deferred("_try_freeze")
	elif not bool(_body.get_meta(FROZEN, false)):
		_clear_supports()

func _contact_left(_other: Node) -> void:
	if _body.sleeping and not _body.freeze:
		call_deferred("_try_freeze")

func _try_freeze() -> void:
	if _exiting or not _body.is_inside_tree() or _body.is_queued_for_deletion():
		return
	if _body.freeze or not _body.sleeping or get_tree().paused or not _body.can_process():
		return
	if bool(_body.get_meta(&"planning_wall_mount", false)) or _body.collision_layer == 0:
		return
	_clear_supports()
	var contacts := _contacts(false)
	if contacts.is_empty():
		return # Never create a floating static body from a forced sleep in mid-air.
	for support in _contacts(true):
		_register_support(support)
	for support in contacts:
		if support is RigidBody3D and (not support.freeze or bool(support.get_meta(FROZEN, false))):
			return # Keep coupled stacks in native sleep: static conversion changes their mass response.
	_rest_transform = _body.global_transform
	_body.set_meta(FROZEN, true) # Mark before Jolt changes sleeping during the mode switch.
	_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_body.freeze = true
	_body.contact_monitor = false
	set_notify_transform(true)
	var watcher := _body.get_node_or_null("ImpactSound")
	if watcher != null:
		watcher.set_physics_process(false)

func _contacts(supports_only: bool) -> Array[Node]:
	# One query on a sleep transition; no contact-monitor callback for every resting prop.
	var bounds: AABB = _body.global_transform * _local_bounds
	_probe.size = Vector3(maxf(bounds.size.x, .02) + .04, .06 if supports_only else maxf(bounds.size.y, .02) + .04, maxf(bounds.size.z, .02) + .04)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform.origin = Vector3(bounds.get_center().x, bounds.position.y if supports_only else bounds.get_center().y, bounds.get_center().z)
	query.collision_mask = _body.collision_mask
	query.exclude = [_body.get_rid()]
	var contacts: Array[Node] = []
	for hit in _body.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var collider := hit.get("collider") as Node
		if collider != null and not contacts.has(collider):
			contacts.append(collider)
	return contacts

func _register_support(support: Node) -> void:
	_supports.append(weakref(support))
	var dependents: Dictionary = support.get_meta(DEPENDENTS, {})
	dependents[get_instance_id()] = weakref(self)
	support.set_meta(DEPENDENTS, dependents)
	_link(support, &"tree_exiting", _support_removed)

func _link(source: Node, signal_name: StringName, callback: Callable) -> void:
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)
		_connections.append({"source": weakref(source), "signal": signal_name, "callback": callback})

func _support_removed() -> void:
	if not _exiting:
		wake_later(_body)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree() and _body != null:
		if bool(_body.get_meta(FROZEN, false)) and not _body.global_transform.is_equal_approx(_rest_transform):
			# Planner transforms are allowed while paused; remove only our own freeze.
			wake_later(_body)

static func wake_later(body: RigidBody3D) -> void:
	_wake_ref.call_deferred(weakref(body))

static func _wake_ref(reference: WeakRef) -> void:
	var body := reference.get_ref() as RigidBody3D
	if body != null:
		wake(body)

static func wake(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if body.freeze and not bool(body.get_meta(FROZEN, false)):
		return # Authored anchors are outside this optimization.
	body.remove_meta(FROZEN)
	var rest := body.get_node_or_null("PropRest")
	if rest != null:
		rest.set_notify_transform(false)
		rest.call("_clear_supports")
	body.freeze = false
	body.sleeping = false
	var watcher := body.get_node_or_null("ImpactSound")
	if watcher != null:
		watcher.set_physics_process(true)
	wake_supported(body)
	# A kicked/shot book may already touch its frozen desk: no new contact event follows.
	if body.contact_monitor:
		for contact in body.get_colliding_bodies():
			if contact is RigidBody3D and bool(contact.get_meta(FROZEN, false)):
				wake(contact)

static func wake_supported(support: Node) -> void:
	if not is_instance_valid(support) or not support.has_meta(DEPENDENTS):
		return
	var dependents: Dictionary = support.get_meta(DEPENDENTS)
	# Clear before recursion: touching furniture can form cycles.
	support.remove_meta(DEPENDENTS)
	for ref: WeakRef in dependents.values():
		var rest := ref.get_ref() as Node
		if rest != null and not rest.is_queued_for_deletion():
			var body := rest.get_parent() as RigidBody3D
			if body != null:
				wake(body)

func _clear_supports() -> void:
	for connection in _connections:
		var source := connection.source.get_ref() as Node
		if source != null and source.is_connected(connection.signal, connection.callback):
			source.disconnect(connection.signal, connection.callback)
	_connections.clear()
	for ref in _supports:
		var support := ref.get_ref() as Node
		if support != null and support.has_meta(DEPENDENTS):
			var dependents: Dictionary = support.get_meta(DEPENDENTS)
			dependents.erase(get_instance_id())
			if dependents.is_empty():
				support.remove_meta(DEPENDENTS)
	_supports.clear()

func _exit_tree() -> void:
	_exiting = true
	_clear_supports()
