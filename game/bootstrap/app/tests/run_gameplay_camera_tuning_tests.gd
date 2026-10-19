extends SceneTree

const PLAYER := preload("res://game/features/player/public/player.tscn")
const TUNING := preload("res://game/bootstrap/app/gameplay_camera_tuning.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", message)


func _run() -> void:
	var old := FileAccess.get_file_as_bytes(TUNING.FILE) if FileAccess.file_exists(TUNING.FILE) else PackedByteArray()
	DirAccess.remove_absolute(TUNING.FILE)
	var player = PLAYER.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var tuning := TUNING.new()
	root.add_child(tuning)
	tuning.setup(player)
	tuning.set_process(false)
	var initial: Dictionary = player.get_camera_adjustment()
	check(tuning._previous == initial, "Absent preference preserves authored view")
	player.set_camera_adjustment({"yaw": 33.25, "pitch": -57.5, "distance": 18.0})
	var alt := InputEventKey.new()
	alt.keycode = KEY_ALT
	alt.pressed = true
	Input.parse_input_event(alt.duplicate())
	Input.flush_buffered_events()
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	Input.parse_input_event(button.duplicate())
	Input.flush_buffered_events()
	var weapon: Node3D = player.get_current_weapon()
	var ammunition: int = weapon.get("_magazine_ammo")
	Input.action_press("fire")
	player._physics_process(0.016)
	Input.action_release("fire")
	check(weapon.get("_magazine_ammo") == ammunition, "Alt camera adjustment blocks held fire")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10.0, -5.0)
	var before_drag: Dictionary = player.get_camera_adjustment()
	player._unhandled_input(motion)
	var dragged: Dictionary = player.get_camera_adjustment()
	check(absf(dragged.yaw - before_drag.yaw + rad_to_deg(0.08)) < 0.001, "Alt+LMB uses planner horizontal sensitivity")
	check(absf(dragged.pitch - before_drag.pitch - rad_to_deg(0.04)) < 0.001, "Alt+LMB uses planner vertical sensitivity")
	button.pressed = false
	Input.parse_input_event(button.duplicate())
	Input.flush_buffered_events()
	player.set_camera_adjustment(before_drag)
	tuning._process(0.0)
	check(tuning.readout.visible and tuning._dirty, "Alt shows parameters and tracks camera changes")
	check(tuning.readout.text.contains("33.25") and tuning.readout.text.contains("57.50"), "Readout exposes reproducible angles")
	paused = true
	tuning._process(0.0)
	check(not tuning.readout.visible and not tuning._dirty, "Paused game hides overlay and flushes pending setting")
	paused = false
	alt.pressed = false
	Input.parse_input_event(alt.duplicate())
	Input.flush_buffered_events()
	var wanted: Dictionary = player.get_camera_adjustment()
	tuning.free()
	player.set_camera_adjustment(initial)
	tuning = TUNING.new()
	root.add_child(tuning)
	tuning.setup(player)
	tuning.set_process(false)
	var restored: Dictionary = player.get_camera_adjustment()
	check(absf(restored.yaw - wanted.yaw) < 0.001 and absf(restored.pitch - wanted.pitch) < 0.001 and restored.distance == wanted.distance, "New mission restores saved view")
	tuning.free()
	player.queue_free()
	await process_frame
	if old.is_empty():
		DirAccess.remove_absolute(TUNING.FILE)
	else:
		var file := FileAccess.open(TUNING.FILE, FileAccess.WRITE)
		file.store_buffer(old)
		file.close()
	await process_frame
	print("Gameplay camera tuning tests: %d failures" % failures)
	quit(1 if failures else 0)
