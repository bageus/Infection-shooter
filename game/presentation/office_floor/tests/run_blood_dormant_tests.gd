extends SceneTree

const SURFACES := preload("res://game/presentation/office_floor/blood_surface_query.gd")
const EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const LIBRARY := preload("res://game/presentation/office_floor/blood_texture_library.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 128
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, -0.1, 0)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 1.5, 0)
	camera.look_at(Vector3(0, 0, -1))
	camera.make_current()
	var query := SURFACES.new()
	stage.add_child(query)
	var effects := EFFECTS.instantiate() as Node3D
	effects.set("preload_textures", false)
	effects.set("floor_bake_enabled", false)
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.02, 0.01, 0.8))
	var texture := ImageTexture.create_from_image(image)
	var entries: Dictionary = {}
	for category in LIBRARY.CATEGORIES:
		entries[category] = [{"texture": texture, "aspect": 2.0, "variant": 1}]
	(effects.get("_library") as RefCounted).set("entries", entries)
	stage.add_child(effects)
	effects.call("configure_environment", [stage] as Array[Node])
	await physics_frame
	var budget := effects.get("_budget") as Node3D
	budget.set("unload_distance", 6.0)
	budget.set("load_distance", 4.0)
	await physics_frame
	effects.call("small_stain", Vector3(0, 0.0, -1.0), [] as Array[RID])
	await create_timer(0.5).timeout
	_expect(budget.call("statistics")["marks"] == 1, "A stain near the camera is drawn")
	camera.position = Vector3(0, 1.5, 20)
	await create_timer(0.5).timeout
	_expect(budget.call("statistics")["marks"] == 0 and budget.call("statistics")["dormant"] == 1, "A far stain leaves the scene and stays as data")
	camera.position = Vector3(0, 1.5, 0)
	await create_timer(0.5).timeout
	_expect(budget.call("statistics")["marks"] == 1 and budget.call("statistics")["dormant"] == 0, "Returning to the stain draws it again")
	budget.call("clear_marks")
	print("Dormant blood tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
