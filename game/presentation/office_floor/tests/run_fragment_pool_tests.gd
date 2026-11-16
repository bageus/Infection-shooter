extends SceneTree
const QUALITY := preload("res://game/core/vfx/public/destruction_quality.gd")
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
var failures := 0

class Host extends Node3D:
	var effects_root: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	QUALITY.set_level(QUALITY.LOW) # These budgets are the Low-quality ones.
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
	_expect(runtime.active.size() <= QUALITY.piece_burst() and runtime.created_chunks <= 80, "Burst bounds active and fading generic allocations")
	# The hero kicks a loose piece it stands in, through the runtime's single poll.
	var hero := Node3D.new()
	hero.add_to_group("player")
	world.add_child(hero)
	var piece: RigidBody3D
	for child in world.get_children():
		if child is RigidBody3D and not DEBRIS.is_fading(child):
			piece = child
	hero.global_position = piece.global_position + Vector3(0.1, 0.0, 0.0)
	piece.call("set", "_kick_ready_msec", 0)
	piece.sleeping = true
	await physics_frame
	await physics_frame
	_expect(not piece.sleeping, "Hero walking into a resting piece wakes and kicks it")
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
