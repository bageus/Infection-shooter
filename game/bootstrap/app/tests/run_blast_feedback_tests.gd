extends SceneTree

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const EXPLOSION := preload("res://game/features/combat/public/grenade_explosion.gd")
var failures := 0
var app: Node3D
var player: Node3D
var feedback: CanvasLayer
var original_volume: float


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = MAIN.instantiate()
	root.add_child(app)
	current_scene = app
	await process_frame
	player = app.get("player")
	feedback = app.get_node("BlastFeedback")
	original_volume = AudioServer.get_bus_volume_db(0)
	player.set_physics_process(false)
	_test_lifecycle()
	await _render_checks()
	await _test_explosion()
	app.free()
	paused = false
	await process_frame
	await create_timer(0.15).timeout
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), original_volume), "exit restores audio")
	print("Blast feedback tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_lifecycle() -> void:
	_check(not feedback.overlay.visible and not feedback.is_processing(), "idle pass has no screen work")
	player.call("apply_blast_stun", 4.0, 0.8)
	_check(feedback.overlay.visible and is_equal_approx(feedback.peak, 0.8), "accepted stun drives visual strength")
	_check(feedback.layer == -1 and feedback.overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "feedback precedes HUD and does not intercept input")
	var ringing := player.get("_stun_ringing") as AudioStreamPlayer
	_check(ringing != null and ringing.playing and ringing.stream is AudioStreamWAV, "tinnitus starts")
	var tone := ringing.stream as AudioStreamWAV
	_check(tone.loop_end == 11025 and tone.data.size() == 22050, "tone loops continuously")
	var crossings := 0
	for sample in range(1, 11025):
		if tone.data.decode_s16(sample * 2) >= 0 and tone.data.decode_s16((sample - 1) * 2) < 0:
			crossings += 1
	_check(crossings > 1000 and crossings < 1800, "tinnitus is a high-pitched tone")
	feedback.set_process(false)
	feedback.call("_process", 3.5)
	_check(float(feedback.material.get_shader_parameter("strength")) < 0.8, "last second fades")
	player.call("apply_blast_stun", 2.0, 0.4)
	_check(is_equal_approx(feedback.remaining, float(player.get("_stun_remaining"))), "repeat hit follows authoritative remaining duration")
	player.set("_stun_remaining", 0.01)
	player.call("_physics_process", 0.02)
	_check(not feedback.overlay.visible and not ringing.playing, "natural expiry clears visual and tone")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), original_volume), "natural expiry restores audio")
	player.call("apply_blast_stun", 4.0, 1.0)
	paused = true
	_check(not feedback.overlay.visible and not ringing.playing, "pause clears screen/tinnitus")
	paused = false
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), original_volume), "pause restores mix")


func _render_checks() -> void:
	if DisplayServer.get_name() == "headless":
		return
	app.hide()
	app.get("gameplay").process_mode = Node.PROCESS_MODE_DISABLED
	var fixture := _render_fixture()
	var hud := CanvasLayer.new()
	hud.layer = 150
	app.add_child(hud)
	var square := ColorRect.new()
	square.color = Color(0.2, 0.95, 0.25)
	square.position = Vector2(20, 20)
	square.size = Vector2(40, 40)
	hud.add_child(square)
	await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	player.call("apply_blast_stun", 4.0, 1.0)
	feedback.set_process(false)
	feedback.phase = 0.1
	feedback.call("_update_material")
	await process_frame
	await RenderingServer.frame_post_draw
	var first := root.get_texture().get_image()
	feedback.phase = 0.75
	feedback.call("_update_material")
	await process_frame
	await RenderingServer.frame_post_draw
	var second := root.get_texture().get_image()
	_check(_difference(before, first) > 0.0002, "rendered blur/ghost/glitch changes scene")
	_check(_difference(first, second) > 0.00005, "ghosts converge/diverge over time")
	_check(first.get_pixel(30, 30).is_equal_approx(before.get_pixel(30, 30)), "HUD remains sharp and unchanged")
	player.call("_end_blast_stun")
	await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	_check(not feedback.overlay.visible, "rendered pass hides after recovery")
	_check(_difference(before, after) < 0.00001, "recovered image exactly matches static baseline")
	_capture(before, "before")
	_capture(first, "ghosts")
	_capture(second, "glitch")
	_capture(after, "recovered")
	hud.queue_free()
	fixture.queue_free()
	app.show()
	app.get("gameplay").process_mode = Node.PROCESS_MODE_INHERIT
	(player.get("camera") as Camera3D).current = true


func _difference(left: Image, right: Image) -> float:
	var sum := 0.0
	for y in range(100, left.get_height() - 100, 8):
		for x in range(100, left.get_width() - 100, 8):
			var a := left.get_pixel(x, y)
			var b := right.get_pixel(x, y)
			sum += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	return sum / (left.get_width() * left.get_height() / 64.0)


func _test_explosion() -> void:
	player.call("_end_blast_stun")
	# Isolate the proximity/cover behavior from ongoing mission combat.
	player.global_position = Vector3(100, 1, 100)
	player.set("health", 1000.0)
	player.set("armor", 1000.0)
	var projectile := Node3D.new()
	app.add_child(projectile)
	await physics_frame
	await process_frame
	EXPLOSION.explode(projectile, player.global_position + Vector3(2, 0, 0), Vector3.UP, null, app, app.get("impact_pool"))
	_check(feedback.overlay.visible and feedback.peak > 0.0, "real close explosion triggers presentation")
	player.call("_end_blast_stun")
	EXPLOSION.explode(projectile, player.global_position + Vector3(12, 0, 0), Vector3.UP, null, app, app.get("impact_pool"))
	_check(not feedback.overlay.visible, "distant explosion does not stun")
	var wall := StaticBody3D.new()
	wall.collision_layer = 3
	app.add_child(wall)
	wall.global_position = player.global_position + Vector3(1, 0, 0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 5, 5)
	collision.shape = shape
	wall.add_child(collision)
	await physics_frame
	await process_frame
	EXPLOSION.explode(projectile, player.global_position + Vector3(2, 0, 0), Vector3.UP, null, app, app.get("impact_pool"))
	_check(not feedback.overlay.visible, "solid wall shelters from explosion")
	projectile.queue_free()
	wall.queue_free()


func _capture(image: Image, label: String) -> void:
	var directory := OS.get_environment("OCCLUSION_CAPTURE_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	image.save_png(directory.path_join("blast_" + RenderingServer.get_current_rendering_method() + "_" + label + ".png"))


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _render_fixture() -> Node3D:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var camera := Camera3D.new()
	fixture.add_child(camera)
	camera.position = Vector3(0, 0, 8)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	camera.current = true
	for y in 8:
		for x in 14:
			var mesh := MeshInstance3D.new()
			mesh.mesh = BoxMesh.new()
			mesh.mesh.size = Vector3(0.5, 0.5, 0.1)
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(0.8, 0.9, 0.9) if (x + y) % 2 == 0 else Color(0.15, 0.3, 0.5)
			mesh.material_override = material
			fixture.add_child(mesh)
			mesh.position = Vector3((x - 6.5) * 0.55, (y - 3.5) * 0.55, 0)
	return fixture
