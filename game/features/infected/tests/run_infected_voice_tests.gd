extends SceneTree
## Infected voices (ADR-0018): every growl family has a call-out scream, an
## infected calls out once when it first spots the player and then only
## growls, and a group that spots the player together gives one call-out.

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const AUDIO := preload("res://game/features/infected/infected_audio.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for growl: StringName in SFX.EVENTS:
		if String(growl).begins_with("growl_"):
			_expect(SFX.EVENTS.has(AUDIO.SCREAMS.get(growl, &"scream_zombie")), "Growl family has a call-out: " + String(growl))
	var stage := Node3D.new()
	root.add_child(stage)
	var first := _infected(stage, &"growl_zombie")
	var second := _infected(stage, &"growl_brute")
	_expect(first.scream_sound == &"scream_zombie" and second.scream_sound == &"roar_heavy", "Heavy infected call out with a roar.")
	AUDIO._last_call_out_ms = -100000
	first.tick(0.016, false, false)
	_expect(_count(first.body, &"scream_zombie") == 0 and not first.spotted, "No call-out before the player is near.")
	first.tick(0.016, false, true)
	_expect(_count(first.body, &"scream_zombie") == 1 and first.spotted, "The first sighting calls out once.")
	second.tick(0.016, true, true)
	_expect(_count(second.body, &"roar_heavy") == 0 and second.spotted, "A group spotting together gives one call-out.")
	first._growl_wait = 0.0
	for i in 30:
		first.tick(0.016, i % 2 == 0, true)
		first._growl_wait = 0.0
	_expect(_count(first.body, &"scream_zombie") == 1, "After the call-out only growls follow.")
	_expect(_count(first.body, &"growl_zombie") >= 1, "Hunting growls continue.")
	stage.queue_free()
	await process_frame
	print("Infected voice tests: %d failure(s)." % failures)
	quit(failures)


func _infected(stage: Node3D, growl: StringName) -> AUDIO:
	var body := CharacterBody3D.new()
	body.set_script(load("res://game/features/infected/tests/voice_test_body.gd"))
	body.set("growl_sound", growl)
	stage.add_child(body)
	var audio := AUDIO.new()
	body.add_child(audio)
	audio.setup(body, 1.0)
	return audio


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
