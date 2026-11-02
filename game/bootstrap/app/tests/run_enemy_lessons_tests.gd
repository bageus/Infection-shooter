extends SceneTree
## Enemy lessons: every enemy has a text step with a live idle preview, the blast lesson states its numbers.
const LESSONS := preload("res://game/bootstrap/app/tutorial/tutorial_enemy_lessons.gd")
const PREVIEW := preload("res://game/bootstrap/app/tutorial/tutorial_enemy_preview.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for lesson in LESSONS.ids():
		var step: Dictionary = LESSONS.step(lesson)
		_check(not str(step.get("title", "")).is_empty() and not str(step.get("text", "")).is_empty(), "%s has a title and a text" % lesson)
		_check(str(step.get("mode", "")) == "click", "%s is a click step" % lesson)
		if not step.has("preview"):
			continue
		var container := PREVIEW.build(str(step.preview))
		_check(container != null, "%s builds a preview" % lesson)
		if container == null:
			continue
		var view := container.get_child(0) as SubViewport
		var player := view.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_check(player != null and player.current_animation == "Idle", "%s plays its Idle clip" % lesson)
		_check(view.find_children("*", "Camera3D", true, false).size() == 1, "%s has one camera" % lesson)
		container.free()
	var blast: Dictionary = LESSONS.step("blast_extinguisher")
	_check("радиус 3 м" in str(blast.text) and "до 14 по" in str(blast.text) and "до 5 секунд" in str(blast.text), "The blast text states radius 3 m, damage 14 and stun up to 5 s")
	_check(PREVIEW.build("res://missing.tscn") == null, "A missing enemy scene gives no preview")
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
