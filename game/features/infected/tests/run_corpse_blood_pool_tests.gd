extends SceneTree
const WATCHER := preload("res://game/features/infected/corpse_blood_pool.gd")

class Body:
	extends CharacterBody3D
	signal blood_pool_ready(point: Vector3, excluded: Array[RID], death_id: int)

class Parts:
	extends Node
	var skeleton: Skeleton3D

var failures := 0
var reports: Array[Dictionary] = []
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	await _moving_corpse()
	await _pause_and_fallback()
	await _early_removal()
	await _timeout()
	stage.queue_free()
	await process_frame
	print("Corpse blood pool tests: %d failures" % failures)
	quit(1 if failures else 0)


func _body() -> Body:
	var body := Body.new()
	stage.add_child(body)
	body.blood_pool_ready.connect(func(point: Vector3, excluded: Array[RID], death_id: int) -> void:
		reports.append({"point": point, "excluded": excluded, "death_id": death_id}))
	return body


func _moving_corpse() -> void:
	reports.clear()
	var body := _body()
	var parts := Parts.new()
	body.add_child(parts)
	parts.skeleton = Skeleton3D.new()
	body.add_child(parts.skeleton)
	parts.skeleton.add_bone("Hips")
	parts.skeleton.add_bone("Chest")
	WATCHER.start(body, parts, Vector3(-20, 1, 0))
	for i in 8:
		parts.skeleton.set_bone_pose_position(0, Vector3(i * 0.3, 0.3, 0))
		parts.skeleton.set_bone_pose_position(1, Vector3(i * 0.3 + 0.4, 0.3, 0))
		await create_timer(0.11).timeout
	_expect(reports.is_empty(), "Moving corpse cannot report an early pool at its predicted landing")
	await create_timer(0.5).timeout
	_expect(reports.size() == 1, "Settled body reports exactly one pool")
	if not reports.is_empty():
		_expect((reports[0].point as Vector3).distance_to(Vector3(2.3, 0.3, 0)) < 0.01, "Pool uses actual hips/chest centre after movement")
		_expect(reports[0].excluded == [body.get_rid()] and reports[0].death_id == body.get_instance_id(), "Pool fact preserves death identity and body exclusion")
	body.queue_free()
	await process_frame
	_expect(reports.size() == 1, "Teardown cannot duplicate the settled pool")


func _pause_and_fallback() -> void:
	reports.clear()
	var body := _body()
	WATCHER.start(body, null, Vector3(3, 1, 4))
	paused = true
	await create_timer(0.7, true).timeout
	_expect(reports.is_empty(), "Paused physics cannot advance landing observation")
	paused = false
	await create_timer(0.7).timeout
	_expect(reports.size() == 1 and reports[0].point == Vector3(3, 1, 4), "Rigless legacy body uses fallback after the delay")
	body.queue_free()
	await process_frame


func _early_removal() -> void:
	reports.clear()
	var body := _body()
	WATCHER.start(body, null, Vector3(7, 1, 8))
	body.queue_free()
	await process_frame
	_expect(reports.size() == 1 and reports[0].point == Vector3(7, 1, 8), "Early deletion retains one last pool position without retaining the body")


func _timeout() -> void:
	reports.clear()
	var body := _body()
	var parts := Parts.new()
	body.add_child(parts)
	parts.skeleton = Skeleton3D.new()
	body.add_child(parts.skeleton)
	parts.skeleton.add_bone("Hips")
	WATCHER.start(body, parts, Vector3.ZERO)
	for i in 25:
		parts.skeleton.set_bone_pose_position(0, Vector3(i * 0.4, 0.3, 0))
		await create_timer(0.11).timeout
	_expect(reports.size() == 1, "A continuously moving ragdoll still reports once within the bounded observation window")
	body.queue_free()
	await process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
