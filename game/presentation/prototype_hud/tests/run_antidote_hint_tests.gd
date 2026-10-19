extends SceneTree
const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const FRAME := preload("res://game/presentation/prototype_hud/antidote_hint_frame.gd")
var failures := 0


class PlayProbe extends Control:
	var calls: Array[int] = []

	func play(_target: Rect2, repeats: int) -> void:
		calls.append(repeats)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_frame_motion()
	await _check_loss_counting()
	print("Antidote hint tests: %d failures" % failures)
	quit(1 if failures else 0)


# One pass starts at the screen edges, lands on the target, holds, fades and hides.
func _check_frame_motion() -> void:
	var frame := FRAME.new() as Control
	root.add_child(frame)
	var target := Rect2(100, 100, 40, 40)
	frame.call("play", target, 1)
	await process_frame
	await process_frame
	_check(frame.visible and int(frame.get("passes_started")) == 1, "The frame shows its first pass within two frames")
	var screen := frame.get_viewport().get_visible_rect().grow(-4.0)
	frame.call("_set_focus", 0.0)
	_check(frame.position.distance_to(screen.position) < 0.01 and frame.size.distance_to(screen.size) < 0.01, "Progress zero is the inset screen edge")
	frame.call("_set_focus", 1.0)
	_check(frame.position.distance_to(Vector2(96, 96)) < 0.01 and frame.size.distance_to(Vector2(48, 48)) < 0.01, "Progress one is the grown antidote cell")
	await create_timer(FRAME.FOCUS_SECONDS + 0.1).timeout
	_check(frame.position.distance_to(Vector2(96, 96)) < 1.0 and frame.size.distance_to(Vector2(48, 48)) < 1.0, "The frame snaps onto the antidote cell")
	await create_timer(FRAME.HOLD_SECONDS + FRAME.FADE_SECONDS + 0.2).timeout
	_check(not frame.visible, "The frame fades out and hides after its pass")
	frame.queue_free()


# The Nth control loss plays N passes; losses after the third play nothing.
func _check_loss_counting() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	player.set_physics_process(false)
	player.set("antidotes", 10)
	var infection := player.get_node("InfectionRuntime")
	infection.set_physics_process(false)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	hud.set_process(false)
	var probe := PlayProbe.new()
	hud.set("_antidote_hint", probe)
	hud.call("_process", 0.0)
	for loss in 4:
		infection.call("absorb_mutagen", 6.2)
		hud.call("_process", 0.0)
		_check(bool(infection.call("is_control_lost")), "Loss %d starts through the real runtime" % (loss + 1))
		_end_loss(infection)
		hud.call("_process", 0.0)
		_restore_mutation(infection)
	_check(probe.calls == [1, 2, 3], "Losses one to three play one, two and three passes (got %s)" % str(probe.calls))
	player.set("antidotes", 0)
	infection.call("absorb_mutagen", 6.2)
	hud.call("_process", 0.0)
	_check(probe.calls == [1, 2, 3], "A loss without antidotes plays no hint")
	stage.queue_free()
	await process_frame
	await process_frame


func _end_loss(infection: Node) -> void:
	var guard := 0
	while bool(infection.call("is_control_lost")) and guard < 200:
		infection.call("_physics_process", 0.5)
		guard += 1


func _restore_mutation(infection: Node) -> void:
	var threshold: float = infection.call("get_critical_threshold")
	var guard := 0
	while float(infection.call("get_mutation")) > threshold and guard < 50:
		infection.call("use_antidote")
		guard += 1


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
	else:
		print("PASS ", message)
