extends RefCounted
## Finds the enemy scenes in the game and loads each enemy's body with the clips the game plays on it.
## The list comes from the folder, so a new infected_*.tscn appears in the viewer without editing it.

const SCENE_DIR := "res://game/features/infected/public/"


## Paths of every enemy scene, sorted by file name.
static func enemy_scene_paths() -> Array[String]:
	var paths: Array[String] = []
	for file in DirAccess.get_files_at(SCENE_DIR):
		var name := file.trim_suffix(".remap")
		if name.begins_with("infected_") and name.ends_with(".tscn"):
			paths.append(SCENE_DIR + name)
	paths.sort()
	return paths


## Display name from the scene path: infected_brute.tscn -> "Brute".
static func enemy_name(scene_path: String) -> String:
	return scene_path.get_file().trim_suffix(".tscn").trim_prefix("infected_").capitalize()


## The enemy's Body, detached from its scene, with the driver's extra clips merged into its AnimationPlayer.
## Returns null when the enemy has no animated body.
static func load_body(scene_path: String) -> Node3D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var enemy := packed.instantiate()
	var body := enemy.get_node_or_null("Body") as Node3D
	var player := find_player(body) if body != null else null
	if player == null:
		enemy.free()
		return null
	_merge_extra_clips(enemy, player)
	_hide_cut_tissue(body)
	enemy.remove_child(body)
	enemy.free()
	return body


# A whole enemy in the game draws only its skin (surface 0, see body_parts.gd); the cut tissue at
# the part joints shows only once a part is shot off. The page keeps the same skin-only surface,
# copied with its stored LODs.
static func _hide_cut_tissue(body: Node3D) -> void:
	for mesh_instance: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_instance.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() < 2:
			continue
		var skin := ArrayMesh.new()
		skin.set("_surfaces", [(mesh.get("_surfaces") as Array)[0]])
		skin.surface_set_material(0, mesh_instance.get_active_material(0))
		mesh_instance.mesh = skin


static func find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := find_player(child)
		if found != null:
			return found
	return null


# Same merge as CharacterAnimationDriver._apply_animation_library, so the viewer shows the clips the game plays.
static func _merge_extra_clips(enemy: Node, player: AnimationPlayer) -> void:
	var driver := enemy.get_node_or_null("AnimationDriver")
	if driver == null or not player.has_animation_library(&""):
		return
	var extra := driver.get("extra_clips") as AnimationLibrary
	if extra == null:
		return
	var merged := player.get_animation_library(&"").duplicate(false) as AnimationLibrary
	for clip_name in extra.get_animation_list():
		if merged.has_animation(clip_name):
			merged.remove_animation(clip_name)
		merged.add_animation(clip_name, extra.get_animation(clip_name))
	player.remove_animation_library(&"")
	player.add_animation_library(&"", merged)
