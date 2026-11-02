extends RefCounted
## Live preview for enemy lessons: the enemy's own body (mesh, rig and idle clip) in a small SubViewport,
## framed to its bounds. The body is taken from the enemy scene, so the preview matches the game.

const IDLE := &"Idle"
const SIZE := Vector2(300, 250)
const FOV := 28.0
const FRAMING := 1.35 # room around the body so head and feet stay in view


## A container with a rendered, idling copy of the enemy at `scene_path`; null if it has no body.
static func build(scene_path: String) -> SubViewportContainer:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var enemy := packed.instantiate() as Node3D
	var body := enemy.get_node_or_null("Body") as Node3D if enemy != null else null
	if body == null:
		if enemy != null:
			enemy.free()
		return null
	enemy.remove_child(body)
	enemy.free()
	var container := SubViewportContainer.new()
	container.custom_minimum_size = SIZE
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(view)
	view.add_child(_environment())
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	view.add_child(light)
	view.add_child(body)
	var boxes: Array[AABB] = []
	_collect(body, Transform3D.IDENTITY, boxes)
	view.add_child(_camera(_merge(boxes)))
	var player := _find_player(body)
	if player != null and player.has_animation(IDLE):
		player.play(IDLE)
	return container


static func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.78, 0.74)
	env.ambient_light_energy = 0.9
	var node := WorldEnvironment.new()
	node.environment = env
	return node


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


# Mesh bounds in the body's space, gathered from the transforms alone (no tree needed).
static func _collect(node: Node3D, parent_to_body: Transform3D, boxes: Array[AABB]) -> void:
	var local := parent_to_body * node.transform
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		boxes.append(local * mesh.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect(child, local, boxes)


static func _merge(boxes: Array[AABB]) -> AABB:
	if boxes.is_empty():
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 2.0, 1.0))
	var result := boxes[0]
	for box in boxes:
		result = result.merge(box)
	return result


# The camera looks down -Z, so it sits straight in front of the body's centre at a distance that fits its height.
static func _camera(bounds: AABB) -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = FOV
	var center := bounds.get_center()
	var distance := bounds.size.y * 0.5 / tan(deg_to_rad(FOV) * 0.5) * FRAMING
	camera.position = Vector3(center.x, center.y, center.z - distance)
	camera.rotation_degrees = Vector3(0, 180, 0)
	camera.current = true
	return camera
