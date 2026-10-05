extends Node
## Bootstrap-owned visual mode. Injected actors/world, no gameplay mutations.
const SUBJECT := preload("res://game/bootstrap/app/occlusion_subject.gd")
const WALLS := preload("res://game/bootstrap/app/occlusion_wall_materials.gd")
const HERO_COLOR := Color(0.2, 0.85, 1.0, 0.9)
const ENEMY_COLOR := Color(1.0, 0.24, 0.28, 0.9)
const ITEM_COLOR := Color(1.0, 0.78, 0.22, 0.9)
const HOLE_RADIUS := 2.0
const CHECK_INTERVAL := 0.1
var mode := 0
var runtime_enabled := true
var player: Node3D
var camera: Camera3D
var world: Node3D
var subjects: Array[RefCounted] = []
var walls := WALLS.new()
var _dirty := true
var _elapsed := 0.0
var _hero_blocked := false


func setup(actor: Node3D, view: Camera3D, scene: Node3D) -> void:
	player = actor
	camera = view
	world = scene
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_scene_changed)
	get_tree().node_removed.connect(_scene_changed)


func set_mode(value: int) -> void:
	var selected := clampi(value, 0, 1)
	if selected == mode:
		return
	_clear()
	mode = selected
	_dirty = true


func set_runtime_enabled(value: bool) -> void:
	runtime_enabled = value
	_clear()
	_dirty = true


func _scene_changed(node: Node) -> void:
	if node.has_meta("occlusion_copy") or not node is Node3D:
		return
	if _is_classified(node):
		_dirty = true
	elif node.is_inside_tree():
		# weapon_pickups registers in _ready, after node_added.
		call_deferred("_check_added_root", weakref(node))


func _is_classified(node: Node) -> bool:
	return node == player or node.is_in_group("camera_occluder") or node.is_in_group("infected") or node.is_in_group("occlusion_items") or node.is_in_group("weapon_pickups")


func _check_added_root(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node
	if node != null and _is_classified(node):
		_dirty = true


func _physics_process(delta: float) -> void:
	if not runtime_enabled or not is_instance_valid(player) or not is_instance_valid(camera):
		return
	if _dirty:
		_rebuild()
	_elapsed += delta
	if _elapsed >= CHECK_INTERVAL:
		_elapsed = 0.0
		_check_subjects()


func _process(_delta: float) -> void:
	if runtime_enabled and mode == 1 and is_instance_valid(player) and is_instance_valid(camera):
		_update_hole()


func _rebuild() -> void:
	# Changes include loaded maps, streamed geometry and newly summoned actors.
	_clear()
	_collect(world)
	_dirty = false
	_elapsed = CHECK_INTERVAL


func _collect(node: Node) -> void:
	if node.has_meta("occlusion_copy"):
		return
	if node is Node3D:
		if mode == 1 and node.is_in_group("camera_occluder"):
			walls.add_root(node)
		elif mode == 0:
			if node == player:
				subjects.append(SUBJECT.new(node, HERO_COLOR))
			elif node.is_in_group("infected"):
				subjects.append(SUBJECT.new(node, ENEMY_COLOR))
			elif node.is_in_group("occlusion_items") or node.is_in_group("weapon_pickups"):
				subjects.append(SUBJECT.new(node, ITEM_COLOR))
	for child in node.get_children():
		_collect(child)


func _check_subjects() -> void:
	if mode == 1:
		_hero_blocked = _blocked(player)
		return
	for subject in subjects:
		var node := subject.target.get_ref() as Node3D
		var live := node != null and node.is_visible_in_tree()
		if live and node.has_method("is_dead"):
			live = not bool(node.call("is_dead"))
		subject.set_revealed(live and _blocked(node))


func _blocked(node: Node3D) -> bool:
	if camera.is_position_behind(node.global_position) or camera.global_position.distance_to(node.global_position) > 45.0:
		return false
	var screen := camera.unproject_position(node.global_position)
	if not get_viewport().get_visible_rect().grow(100.0).has_point(screen):
		return false
	for height in [0.2, 0.8, 1.4] if node == player or node.is_in_group("infected") else [0.15]:
		if _ray_blocked(node.global_position + Vector3.UP * height, node):
			return true
	return false


func _ray_blocked(point: Vector3, target: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point, 3)
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append(player.get_rid())
	if target is CollisionObject3D:
		excluded.append(target.get_rid())
	# Pass through actors/furniture, only structural roots trigger this effect.
	for attempt in 8:
		query.exclude = excluded
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider := hit.collider as Node
		var ancestor := collider
		while ancestor != null and ancestor != world:
			if ancestor.is_in_group("camera_occluder") and (ancestor as Node3D).is_visible_in_tree():
				return true
			ancestor = ancestor.get_parent()
		excluded.append(hit.rid)
	return false


func _update_hole() -> void:
	var point := player.global_position + Vector3.UP * 0.6
	var center := camera.unproject_position(point)
	var side := camera.unproject_position(point + camera.global_basis.x * HOLE_RADIUS)
	var size := get_viewport().get_visible_rect().size
	var depth := -(camera.global_transform.affine_inverse() * point).z
	walls.update_hole(center / size, size, center.distance_to(side) if _hero_blocked else 0.0, depth)


func _clear() -> void:
	for subject in subjects:
		subject.clear()
	subjects.clear()
	walls.clear()
	_hero_blocked = false


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_scene_changed):
		get_tree().node_added.disconnect(_scene_changed)
		get_tree().node_removed.disconnect(_scene_changed)
	_clear()
