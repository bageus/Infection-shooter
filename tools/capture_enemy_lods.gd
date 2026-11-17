extends SceneTree
## Every enemy at each skin LOD (forced, close framing) and as the game picks LODs at 9/16/24 m.
##   xvfb-run -a godot --path . --audio-driver Dummy --rendering-method gl_compatibility --script tools/capture_enemy_lods.gd -- <out dir>
## Writes <out>/<name>_lod<i>.png and <name>_auto<m>m.png (game camera: fov 50, 1080p, crop).
const GAME_DIR := "res://models/objects/characters/enemy/game/"
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]
const DISTANCES := [9.0, 16.0, 24.0]
const SIZE := Vector2i(480, 640)
var output := "user://enemy_lods"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(output)
	for enemy: String in NAMES:
		var rig := (load(GAME_DIR + enemy + "_rig.tscn") as PackedScene).instantiate() as Node3D
		for player: AnimationPlayer in rig.find_children("*", "AnimationPlayer", true, false):
			player.autoplay = ""
		var mesh_instance := rig.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var full := mesh_instance.mesh as ArrayMesh
		var levels := _levels(full)
		var line := "%s skin:" % enemy
		for level in levels.size():
			mesh_instance.mesh = levels[level]
			line += " lod%d=%d" % [level, (levels[level].surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3]
			await _shot(rig, full.get_aabb(), 0.0, 0.0, "%s_lod%d" % [enemy.to_lower(), level])
		mesh_instance.mesh = full
		for distance: float in DISTANCES:
			await _shot(rig, full.get_aabb(), distance, 1.0, "%s_auto%dm" % [enemy.to_lower(), int(distance)])
		print(line)
		rig.free()
	quit()


# Skin-only meshes drawing LOD 0, 1, 2... of surface 0 as their main index buffer.
func _levels(mesh: ArrayMesh) -> Array[ArrayMesh]:
	var stored := RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var stride := RenderingServer.mesh_surface_get_format_index_stride(stored.format, stored.vertex_count)
	var arrays := mesh.surface_get_arrays(0)
	var result: Array[ArrayMesh] = []
	var lists: Array = [arrays[Mesh.ARRAY_INDEX]]
	for lod: Dictionary in stored.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var indices := PackedInt32Array()
		indices.resize(bytes.size() / stride)
		for i in indices.size():
			indices[i] = bytes.decode_u16(i * stride) if stride == 2 else bytes.decode_u32(i * stride)
		lists.append(indices)
	for indices: PackedInt32Array in lists:
		var copy := arrays.duplicate()
		copy[Mesh.ARRAY_INDEX] = indices
		var level := ArrayMesh.new()
		level.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, copy, [], {}, mesh.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		level.surface_set_material(0, mesh.surface_get_material(0))
		result.append(level)
	return result


func _shot(model: Node3D, aabb: AABB, distance: float, lod_threshold: float, file: String) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	root.mesh_lod_threshold = lod_threshold
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
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
	var height := maxf(aabb.size.y, aabb.size.x * float(SIZE.y) / float(SIZE.x))
	var camera := Camera3D.new()
	camera.fov = 50.0
	stage.add_child(camera)
	if distance <= 0.0:
		distance = height * 0.6 / tan(deg_to_rad(25.0))
	# Game-like view: from the front and 50 degrees above, as the top-down camera sees enemies.
	camera.position = centre + Vector3(0, sin(deg_to_rad(50.0)), cos(deg_to_rad(50.0))) * distance
	camera.look_at(centre)
	camera.current = true
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var crop_h := int(image.get_height() * height * 1.2 / (2.0 * distance * tan(deg_to_rad(25.0))))
	var crop_w := crop_h * SIZE.x / SIZE.y
	image = image.get_region(Rect2i(image.get_width() / 2 - crop_w / 2, image.get_height() / 2 - crop_h / 2, crop_w, crop_h))
	image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_NEAREST if lod_threshold > 0.0 else Image.INTERPOLATE_BILINEAR)
	image.save_png(output.path_join(file + ".png"))
	stage.remove_child(model)
	stage.queue_free()
	await process_frame
