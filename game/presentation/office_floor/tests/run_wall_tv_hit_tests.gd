extends SceneTree
## A wall TV buried in the thick collision of a wall or column is slid out so bullets reach it.
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const SUPPORTS := [
	"res://game/presentation/office_floor/public/structural/wall_straight.tscn",
	"res://game/presentation/office_floor/public/structural/column.tscn",
]
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for support_path: String in SUPPORTS:
		for model in ["05_wall_TV_frameless_destructible.glb", "05_wall_TV_destructible.glb"]:
			await _case(support_path, "res://models/objects/enviroments/05/" + model)
	print("Wall TV hit tests: %d failures" % failures)
	quit(1 if failures else 0)


func _case(support_path: String, model: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var support := (load(support_path) as PackedScene).instantiate() as Node3D
	support.rotation_degrees.y = 90.0 if "wall" in support_path else 0.0
	stage.add_child(support)
	await physics_frame
	var space := stage.get_world_3d().direct_space_state
	var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-5, 1.0, 0), Vector3(5, 1.0, 0), 7))
	if face.is_empty():
		failures += 1
		push_error("Support has no collision: " + support_path)
		stage.queue_free()
		return
	var tv := PROP.instantiate() as Node3D
	tv.set("model_path", model)
	tv.rotation_degrees.y = -90.0 # Facing -X, like the authored wall TVs.
	tv.position = Vector3(face.position.x + 0.03, 1.0, face.position.z)
	stage.add_child(tv)
	for i in 6:
		await physics_frame
	var shot := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-5, 1.0, face.position.z), Vector3(5, 1.0, face.position.z), 7))
	var label := support_path.get_file() + " / " + model.get_file()
	if shot.is_empty() or shot.collider != tv:
		failures += 1
		push_error("Bullet does not reach the buried TV: " + label)
	else:
		tv.call("take_projectile_hit", 80.0, shot.position, shot.normal, Vector3.RIGHT, "UZI")
		if tv.get("_damage").health >= 65.0:
			failures += 1
			push_error("Shot TV takes no damage: " + label)
	stage.queue_free()
	await process_frame
