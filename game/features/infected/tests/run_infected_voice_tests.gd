extends SceneTree
## Infected voices (ADR-0018): every growl family has a matching scream, a
## new charge screams once, then rests, and only the light infected howl.

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const AUDIO := preload("res://game/features/infected/infected_audio.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for growl: StringName in SFX.EVENTS:
		if String(growl).begins_with("growl_"):
			_expect(SFX.EVENTS.has(AUDIO.SCREAMS.get(growl, &"")), "Growl family has a scream: " + String(growl))
	_expect(SFX.EVENTS.has(&"howl_infected"), "The infected howl exists.")
	var stage := Node3D.new()
	root.add_child(stage)
	var body := CharacterBody3D.new()
	body.set_script(load("res://game/features/infected/tests/voice_test_body.gd"))
	stage.add_child(body)
	var audio := AUDIO.new()
	body.add_child(audio)
	audio.setup(body, 1.0)
	_expect(audio.scream_sound == &"roar_heavy" and not audio._howls, "Heavy infected roar and do not howl.")
	audio._growl_wait = 99.0
	# The alert scream is a 70% roll; retry fresh charges until one screams,
	# then stop so the rest it started is still running below.
	for attempt in 40:
		audio._alert_wait = 0.0
		audio.tick(0.016, false, true)
		audio.tick(0.016, true, true)
		if audio._alert_wait > 0.0:
			break
	_expect(_count(body, &"roar_heavy") >= 1, "Starting a charge screams.")
	_expect(audio._alert_wait > 0.0, "An alert scream starts a rest.")
	var rest: float = audio._alert_wait
	audio.tick(0.016, false, true)
	audio.tick(0.016, true, true)
	_expect(audio._alert_wait < rest, "No new alert scream while resting.")
	stage.queue_free()
	await process_frame
	print("Infected voice tests: %d failure(s)." % failures)
	quit(failures)


func _count(parent: Node, event: StringName) -> int:
	var count := 0
	for child in parent.get_children():
		if child.is_in_group(StringName("sfx_" + String(event))):
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
