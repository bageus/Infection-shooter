extends SceneTree
const LOG := preload("res://game/bootstrap/app/frame_spike_log.gd")
var failures := 0


func _initialize() -> void:
	var log := LOG.new()
	log._path = "user://frame_spikes_test.log"
	if FileAccess.file_exists(log._path):
		DirAccess.remove_absolute(log._path)
	_check(not log.tick(0.016, self), "A normal frame is not logged")
	_check(log.tick(0.12, self), "A 120 ms frame is logged")
	_check(log.spikes == 1 and is_equal_approx(log.worst_msec, 120.0), "Spike count and worst frame are tracked")
	var text := FileAccess.get_file_as_string(log._path)
	_check(text.contains("frame=120ms") and text.contains("resources=") and text.contains("rigid=") and text.contains("awake=") and text.contains("frozen=") and text.contains("monitored=") and text.contains("player="), "The log line carries the frame time and context")
	_check(log.summary().contains("worst 5 s 120 ms"), "The overlay summary shows the worst frame of the window")
	DirAccess.remove_absolute(log._path)
	print("Frame spike log tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
