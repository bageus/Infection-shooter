extends SceneTree

const PART := preload("res://game/features/infected/severed_part.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var decor := PART.new()
	decor.lifetime = INF
	decor.bleeding = false
	decor.freeze = true
	stage.add_child(decor)
	_check(not decor.is_physics_processing(), "Permanent non-bleeding decoration has no script physics callback")
	_check(not decor.is_in_group(PART.GROUP), "Permanent decoration stays outside the combat debris budget")
	var piece := PART.new()
	piece.lifetime = .15
	piece.bleeding = false
	piece.freeze = true
	stage.add_child(piece)
	var reference: WeakRef = weakref(piece)
	_check(not piece.is_physics_processing(), "Expiry timer works without a per-frame script callback")
	paused = true
	await create_timer(.25).timeout
	_check(not piece.get("_fading"), "Paused mission does not consume part lifetime")
	paused = false
	await create_timer(.25).timeout
	_check(piece.get("_fading") and piece.collision_layer == 0, "Timer expires finite part and removes hit collision")
	await create_timer(1.0).timeout
	_check(reference.get_ref() == null, "Expired part completes its fade and releases the timer")
	_check(is_instance_valid(decor) and not decor.get("_fading"), "Permanent decoration survives finite-part cleanup")
	var bloody := PART.new()
	bloody.lifetime = 10
	bloody.freeze = true
	stage.add_child(bloody)
	_check(bloody.is_physics_processing(), "Bleeding parts still report motion during their effect window")
	bloody.call("_physics_process", 7.0)
	_check(not bloody.is_physics_processing(), "Completed bleeding stops script updates even before expiry")
	_check(not bloody.get("_fading"), "Stopping blood updates does not expire the physical object")
	stage.queue_free()
	await process_frame
	await process_frame
	print("Part lifetime tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
