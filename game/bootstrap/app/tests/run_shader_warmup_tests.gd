extends SceneTree
## Mission start draws every spatial shader once and then removes the quads.
const WARMUP := preload("res://game/bootstrap/app/shader_warmup.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths := WARMUP.spatial_shader_paths()
	_check(paths.has("res://game/core/vfx/public/flipbook.gdshader"), "Flipbook shader is warmed")
	_check(paths.has("res://game/features/player/berserk_aura.gdshader"), "Feature shaders are warmed")
	_check(not paths.has("res://game/bootstrap/app/blast_feedback.gdshader"), "Canvas shaders are left out")
	var app := MAIN.instantiate()
	root.add_child(app)
	current_scene = app
	var camera := (app.get("player") as Node).get("camera") as Camera3D
	var warmup := camera.get_node_or_null("ShaderWarmup")
	_check(warmup != null and warmup.get_child_count() == paths.size(), "One quad per spatial shader under the camera")
	for i in 5:
		await process_frame
	_check(camera.get_node_or_null("ShaderWarmup") == null, "Warm-up quads are freed after a few frames")
	app.queue_free()
	await process_frame
	print("Shader warmup tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
