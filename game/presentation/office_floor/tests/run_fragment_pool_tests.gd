extends SceneTree
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
var failures := 0

class Host extends Node3D:
	var effects_root: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _chunks()
	print("Fragment pool tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _chunks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var host := Host.new()
	host.effects_root = world
	world.add_child(host)
	DEBRIS.spawn_chunks(host, AABB(Vector3.ZERO, Vector3.ONE), Color.RED, 8, Vector3.UP, Vector3.ZERO)
	await process_frame
	var runtime := world.get_node("FragmentRuntime")
	var first: Array[int] = []
	for child in world.get_children():
		if child is RigidBody3D:
			first.append(child.get_instance_id())
			child.call("expire_fast")
			_expect(child.freeze and child.collision_mask == 0 and not child.is_physics_processing(), "Fade stops all fragment physics immediately")
	await create_timer(DEBRIS.FAST_FADE_SECONDS + 0.1).timeout
	_expect(runtime.active.is_empty(), "Retired fragments leave the active FIFO")
	DEBRIS.spawn_chunks(host, AABB(Vector3.ZERO, Vector3.ONE), Color.BLUE, 8, Vector3.UP, Vector3.ZERO)
	await process_frame
	_expect(runtime.created_chunks == 8 and runtime.reused_chunks == 8, "Second burst reuses bodies, shapes and meshes")
	for child in world.get_children():
		if child is RigidBody3D:
			_expect(first.has(child.get_instance_id()) and not DEBRIS.is_fading(child), "Reused identity has a fresh lifecycle")
	# Reused IDs must not match old FIFO tombstones and evict newer fragments.
	DEBRIS.spawn_chunks(host, AABB(Vector3.ZERO, Vector3.ONE), Color.BLUE, 500, Vector3.UP, Vector3.ZERO)
	await process_frame
	_expect(runtime.active.size() <= runtime.BURST_FRAGMENTS and runtime.created_chunks <= 80, "Burst bounds active and fading generic allocations")
	var other := Node3D.new()
	root.add_child(other)
	_expect(DEBRIS.runtime_for(other) != runtime, "Effects containers own independent pools")
	other.free()
	world.free()
	await process_frame


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
