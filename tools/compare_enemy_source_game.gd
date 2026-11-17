extends SceneTree
## Source GLB vs what the game draws, per enemy, in the same rest pose and camera.
##   xvfb-run -a godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tools/compare_enemy_source_game.gd -- <out dir>
## Writes <out>/<name>_<view>_<stage>.png and prints triangle counts of every stage.
## Stages: source (GLB parts as authored), game_lod0 (rig mesh, LOD forced off),
## game_9m (rig mesh as the game picks LODs at the 9 m minimum camera distance).
const SOURCE_DIR := "res://models/objects/characters/enemy/"
const GAME_DIR := "res://models/objects/characters/enemy/game/"
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]
const SIZE := Vector2i(640, 900)
var output := "user://enemy_source_vs_game"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(output)
	for enemy: String in NAMES:
		await _enemy(enemy)
	quit()


func _enemy(enemy: String) -> void:
	var source := (load(SOURCE_DIR + enemy + ".glb") as PackedScene).instantiate() as Node3D
	var rig := (load(GAME_DIR + enemy + "_rig.tscn") as PackedScene).instantiate() as Node3D
	var source_tris := 0
	for node: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		for s in node.mesh.get_surface_count():
			source_tris += (node.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var game_mesh := load(GAME_DIR + enemy + "_game.res") as ArrayMesh
	var rig_mesh := load(GAME_DIR + enemy + "_rig_mesh.res") as ArrayMesh
	print("%s source=%d game=%s rig=%s" % [enemy, source_tris, _describe(game_mesh), _describe(rig_mesh)])
	for player: AnimationPlayer in rig.find_children("*", "AnimationPlayer", true, false):
		player.autoplay = ""
	var aabb := _aabb(source)
	for view: String in ["front", "back"]:
		await _shot(source, aabb, view, enemy.to_lower() + "_" + view + "_source", 0.0)
		await _shot(rig, aabb, view, enemy.to_lower() + "_" + view + "_game_lod0", 0.0)
		await _shot(rig, aabb, view, enemy.to_lower() + "_" + view + "_game_9m", 1.0)
	source.free()
	rig.free()


func _describe(mesh: ArrayMesh) -> String:
	var parts: Array = []
	var stored: Array = mesh.get("_surfaces")
	for s in mesh.get_surface_count():
		var tris := (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var surface: Dictionary = stored[s]
		var index_bytes := 2 if int(surface.get("vertex_count", 0)) <= 65535 else 4
		var raw: Array = surface.get("lods", [])
		var lod_text: Array = []
		for i in range(0, raw.size(), 2):
			lod_text.append("%.3f:%d" % [float(raw[i]), (raw[i + 1] as PackedByteArray).size() / index_bytes / 3])
		parts.append("s%d %d tris lods[%s]" % [s, tris, ", ".join(lod_text)])
	return "; ".join(parts)


func _aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh_instance.global_transform * mesh_instance.get_aabb() if mesh_instance.is_inside_tree() else _relative(mesh_instance, node) * mesh_instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _relative(node: Node3D, top: Node) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != top:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


func _shot(model: Node3D, aabb: AABB, view: String, file: String, lod_threshold: float) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	root.mesh_lod_threshold = lod_threshold
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25 if view == "front" else 155, 0)
	stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.13, 0.15)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	stage.add_child(environment)
	stage.add_child(model)
	var centre := aabb.get_center()
	var camera := Camera3D.new()
	stage.add_child(camera)
	var height := maxf(aabb.size.y, aabb.size.x * float(SIZE.y) / float(SIZE.x))
	var direction := Vector3(0, 0, 1) if view == "front" else Vector3(0, 0, -1)
	if lod_threshold > 0.0:
		# Game camera: fov 50, 9 m away (player_movement camera_min_distance), 1080p; cropped afterwards.
		camera.fov = 50.0
		camera.position = centre + direction * 9.0
	else:
		camera.fov = 50.0
		camera.position = centre + direction * (height * 0.6 / tan(deg_to_rad(25.0)))
	camera.look_at(centre)
	camera.current = true
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var distance := camera.position.distance_to(centre)
	if true:
		var crop_h := int(1080.0 * height * 1.2 / (2.0 * distance * tan(deg_to_rad(25.0))))
		var crop_w := crop_h * SIZE.x / SIZE.y
		image = image.get_region(Rect2i(960 - crop_w / 2, 540 - crop_h / 2, crop_w, crop_h))
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_NEAREST if lod_threshold > 0.0 else Image.INTERPOLATE_BILINEAR)
	image.save_png(output.path_join(file + ".png"))
	stage.remove_child(model)
	stage.queue_free()
	await process_frame
