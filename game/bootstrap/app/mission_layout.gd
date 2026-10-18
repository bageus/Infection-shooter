extends Node3D

const KEY := preload("res://game/bootstrap/app/mission_key.gd")
const WEAPON := preload("res://game/bootstrap/app/weapon_pickup.gd")
const FLOOR_HINT := preload("res://game/bootstrap/app/floor_hint_guide.gd")
const FLOOR_BOUNDS := Rect2(-40, -30, 80, 60)
const CUT_STEP := 0.5
const STAIR_REFRESH_SECONDS := 0.35

var _stage: Node3D
var _objects: Node
var _stairs: Dictionary[int, Dictionary] = {}
var _openings: Array[Rect2] = []
var _scan_remaining := 0.0
var _player: Node3D
var _key: Node3D
var _hints: Node3D


func setup(stage: Node3D, player: Node3D, _infection: Node) -> void:
	_stage = stage
	_player = player
	_objects = stage.get_node("PlanningObjects")
	_objects.child_entered_tree.connect(_on_planning_child_entered)
	_objects.child_exiting_tree.connect(_on_planning_child_exiting)
	# One initial discovery; subsequent furniture changes never rescan the map.
	for node in _objects.get_children():
		_register_stair(weakref(node))
	_refresh_stairs()
	var key := KEY.new()
	key.name = "EmergencyKey"
	add_child(key)
	key.global_position = Vector3(20, 0.25, 15)
	_key = key
	_hints = FLOOR_HINT.new()
	_hints.name = "FloorHints"
	_hints.player = player
	_hints.target_source = floor_hint_target
	add_child(_hints)


func set_floor_hints_enabled(enabled: bool) -> void:
	_hints.call("set_hints_enabled", enabled)


# Goal for the floor chevrons: the emergency key until it is taken, then the nearest exit opening.
func floor_hint_target() -> Vector3:
	if is_instance_valid(_key) and not (_player.has_method("has_emergency_key") and bool(_player.call("has_emergency_key"))):
		return _key.global_position
	var from := Vector2(_player.global_position.x, _player.global_position.z)
	var best := Vector3.INF
	var best_distance := INF
	for opening in _openings:
		var center := opening.get_center()
		var distance := center.distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = Vector3(center.x, 0.0, center.y)
	return best


func _process(delta: float) -> void:
	_scan_remaining -= delta
	if _scan_remaining <= 0.0:
		_scan_remaining = STAIR_REFRESH_SECONDS
		_refresh_stairs()


func spawn_weapon(index: int, world_position: Vector3) -> bool:
	if index < 0 or index > 7:
		return false
	var item := WEAPON.new()
	item.weapon_index = index
	item.name = ["DroppedPistol", "DroppedUzi", "DroppedShotgun", "DroppedLauncher", "DroppedAK", "DroppedM4", "DroppedSniper", "DroppedMinigun"][index]
	add_child(item)
	item.global_position = Vector3(world_position.x, 0.25, world_position.z)
	item.set("_base_position", item.global_position)
	return true


func goal_reached(location: Vector3) -> bool:
	if location.y >= -1.3:
		return false
	for opening in _openings:
		if opening.has_point(Vector2(location.x, location.z)):
			return true
	return false


func _on_planning_child_entered(node: Node) -> void:
	# Placement/loader assign planning_scene_path after add_child/_ready.
	if node is Node3D:
		_register_stair.call_deferred(weakref(node))


func _register_stair(reference: WeakRef) -> void:
	var node := reference.get_ref() as Node3D
	if node == null or node.is_queued_for_deletion() or node.get_parent() != _objects:
		return
	var asset_path := str(node.get_meta("planning_scene_path", ""))
	if asset_path.is_empty():
		asset_path = str(node.get("model_path"))
	if asset_path.get_file() not in ["01_stairs.glb", "01_stairs_2.glb"]:
		return
	var id := node.get_instance_id()
	if not _stairs.has(id):
		_stairs[id] = {"reference": reference}
		_scan_remaining = 0.0
		set_process(true)


func _on_planning_child_exiting(node: Node) -> void:
	if _stairs.erase(node.get_instance_id()):
		_scan_remaining = 0.0
		set_process(true) # Also clear the final opening when the last stair leaves.


func _tracked_stairs() -> Array[Node3D]:
	var stairs: Array[Node3D] = []
	for id: int in _stairs.keys():
		var stair := (_stairs[id].reference as WeakRef).get_ref() as Node3D
		if stair == null or stair.is_queued_for_deletion() or stair.get_parent() != _objects:
			_stairs.erase(id)
		else:
			stairs.append(stair)
	# Keep the old get_children() order, including explicit move_child edits.
	stairs.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.get_index() < b.get_index())
	return stairs


func _cached_openings(stair: Node3D) -> Array[Rect2]:
	var entry: Dictionary = _stairs[stair.get_instance_id()]
	var bounds := _visual_bounds(stair)
	var pose := stair.global_transform
	if not entry.has("pose") or pose != entry.pose or bounds != entry.bounds:
		entry.pose = pose
		entry.bounds = bounds
		var openings: Array[Rect2] = []
		# An upstairs flight needs the unbroken ground floor beneath it.
		if bounds.size.length_squared() >= 0.01 and bounds.position.y <= -0.4 and bounds.end.y >= -0.05:
			openings = _stair_openings(stair, bounds)
		entry.openings = openings
	return entry.openings


func _refresh_stairs() -> void:
	if not is_instance_valid(_stage):
		return
	var next_openings: Array[Rect2] = []
	for stair in _tracked_stairs():
		next_openings.append_array(_cached_openings(stair))
	set_process(not _stairs.is_empty())
	if next_openings == _openings:
		return
	_openings = next_openings
	_stage.get_node("Floor").call("set_stair_openings", _openings)
	_update_floor_collision(_stage.get_node("FloorBody") as StaticBody3D)


func _exit_tree() -> void:
	if is_instance_valid(_objects):
		_objects.child_entered_tree.disconnect(_on_planning_child_entered)
		_objects.child_exiting_tree.disconnect(_on_planning_child_exiting)
	_stairs.clear()


func _visual_bounds(stair: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for child in stair.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.has_meta("planning_selection_highlight"):
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	return bounds


func _stair_openings(stair: Node3D, bounds: AABB) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var first_x := maxi(0, floori((bounds.position.x - FLOOR_BOUNDS.position.x) / CUT_STEP))
	var last_x := mini(floori(FLOOR_BOUNDS.size.x / CUT_STEP), ceili((bounds.end.x - FLOOR_BOUNDS.position.x) / CUT_STEP))
	var first_z := maxi(0, floori((bounds.position.z - FLOOR_BOUNDS.position.y) / CUT_STEP))
	var last_z := mini(floori(FLOOR_BOUNDS.size.y / CUT_STEP), ceili((bounds.end.z - FLOOR_BOUNDS.position.y) / CUT_STEP))
	for z in range(first_z, last_z):
		var start := -1
		for x in range(first_x, last_x + 1):
			var below := false
			if x < last_x:
				var world_x := FLOOR_BOUNDS.position.x + (x + 0.5) * CUT_STEP
				var world_z := FLOOR_BOUNDS.position.y + (z + 0.5) * CUT_STEP
				var local := stair.to_local(Vector3(world_x, stair.global_position.y, world_z))
				var surface := _stair_surface_height(local)
				below = surface >= 0.0 and stair.to_global(Vector3(local.x, surface, local.z)).y < -0.06
			if below and start < 0:
				start = x
			elif not below and start >= 0:
				result.append(Rect2(FLOOR_BOUNDS.position + Vector2(start, z) * CUT_STEP, Vector2(x - start, 1) * CUT_STEP))
				start = -1
	return result


func _stair_surface_height(local: Vector3) -> float:
	if absf(local.x) > 1.98 or local.z < -1.42 or local.z > 4.22:
		return -1.0
	if local.z < 0.0:
		return 3.0
	if local.z > 2.82:
		return 1.5
	if local.x < -0.12:
		return 1.5 * local.z / 2.82
	if local.x > 0.12:
		return 3.0 - 1.5 * local.z / 2.82
	return -1.0


func _update_floor_collision(body: StaticBody3D) -> void:
	var original := body.get_node("CollisionShape3D") as CollisionShape3D
	for child in body.get_children():
		if child.name.begins_with("StairFloorRegion"):
			body.remove_child(child)
			child.queue_free()
	original.set_deferred("disabled", not _openings.is_empty())
	if _openings.is_empty():
		return
	var regions: Array[Rect2] = [FLOOR_BOUNDS]
	for opening in _openings:
		var remaining: Array[Rect2] = []
		for region in regions:
			var overlap := region.intersection(opening)
			if not overlap.has_area():
				remaining.append(region)
				continue
			for part in [
				Rect2(region.position, Vector2(region.size.x, overlap.position.y - region.position.y)),
				Rect2(Vector2(region.position.x, overlap.end.y), Vector2(region.size.x, region.end.y - overlap.end.y)),
				Rect2(Vector2(region.position.x, overlap.position.y), Vector2(overlap.position.x - region.position.x, overlap.size.y)),
				Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(region.end.x - overlap.end.x, overlap.size.y))
			]:
				if part.has_area():
					remaining.append(part)
		regions = remaining
	for index in regions.size():
		var region := regions[index]
		var collision := CollisionShape3D.new()
		collision.name = "StairFloorRegion%d" % index
		var box := BoxShape3D.new()
		box.size = Vector3(region.size.x, 0.2, region.size.y)
		collision.shape = box
		collision.position = Vector3(region.get_center().x, -0.1, region.get_center().y)
		body.add_child(collision)
