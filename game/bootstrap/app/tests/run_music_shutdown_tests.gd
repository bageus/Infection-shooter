extends SceneTree
## A scene can be freed on the next frame: no Vorbis playback may survive exit.
## CI treats engine resource-leak ERROR output as a failure, even when quit is 0.
const MUSIC := preload("res://game/bootstrap/app/mission_music.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var music := MUSIC.new()
	stage.add_child(music)
	await process_frame
	stage.queue_free()
	await process_frame
	if is_instance_valid(music):
		push_error("Mission music outlived its scene")
		quit(1)
		return
	print("Music shutdown tests: 0 failures")
	quit()
