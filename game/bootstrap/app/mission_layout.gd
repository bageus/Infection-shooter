extends Node3D

const KEY := preload("res://game/bootstrap/app/mission_key.gd")
const WEAPON := preload("res://game/bootstrap/app/weapon_pickup.gd")
const DOOR := preload("res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn")
const FLOOR_BOUNDS := Rect2(-40, -30, 80, 60)
const TILE_STEP := 2.0

var _stage: Node3D
var _openings: Array[Rect2] = []
var _scan_remaining := 0.0


func setup(stage: Node3D) -> void:
	_stage = stage
	_refresh_stairs()
	var door := DOOR.instantiate() as Node3D
	door.name = "LockedEmergencyDoor"
	stage.get_node("Structure").add_child(door)
	door.global_position = Vector3(-20, 0, 8.6)
	var key := KEY.new()
	key.name = "EmergencyKey"
	add_child(key)
	key.global_position = Vector3(20, 0.25, 15)
	spawn_weapon(3, Vector3(-20, 0.25, -15))


func _process(delta: float) -> void:
	_scan_remaining -= delta
	if _scan_remaining <= 0.0:
		_scan_remaining = 0.35
		_refresh_stairs()


func spawn_weapon(index: int, world_position: Vector3) -> void:
	var item := WEAPON.new()
	item.weapon_index = index
	item.name = "DroppedLauncher" if index == 3 else "DroppedWeapon"
	add_child(item)
	item.global_position = Vector3(world_position.x, 0.25, world_position.z)
	item.set("_base_position", item.global_position)


func goal_reached(location: Vector3) -> bool:
	if location.y >= -1.3:
		return false
	for opening in _openings:
		if opening.grow(-0.25).has_point(Vector2(location.x, location.z)):
			return true
	return false


func _refresh_stairs() -> void:
	if _stage == null:
		return
	var next_openings: Array[Rect2] = []
	for node in _stage.get_node("PlanningObjects").get_children():
		if not node is Node3D:
			continue
		var stair := node as Node3D
		var asset_path := str(stair.get_meta("planning_scene_path", ""))
		if asset_path.is_empty():
			asset_path = str(stair.get("model_path"))
		if asset_path.get_file() not in ["01_stairs.glb", "01_stairs_2.glb"]:
			continue
		var bounds := _visual_bounds(stair)
		# An upstairs flight needs the unbroken ground floor beneath it.
		if bounds.size.length_squared() < 0.01 or bounds.position.y > -0.4 or bounds.end.y < -0.05:
			continue
		var area := _tile_aligned(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.1))
		if area.has_area():
			next_openings.append(area)
	if next_openings == _openings:
		return
	_openings = next_openings
	_stage.get_node("Floor").call("set_stair_openings", _openings)
	_update_floor_collision(_stage.get_node("FloorBody") as StaticBody3D)


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


func _tile_aligned(area: Rect2) -> Rect2:
	var start := Vector2(
		floorf((area.position.x - FLOOR_BOUNDS.position.x) / TILE_STEP) * TILE_STEP + FLOOR_BOUNDS.position.x,
		floorf((area.position.y - FLOOR_BOUNDS.position.y) / TILE_STEP) * TILE_STEP + FLOOR_BOUNDS.position.y
	)
	var finish := Vector2(
		ceilf((area.end.x - FLOOR_BOUNDS.position.x) / TILE_STEP) * TILE_STEP + FLOOR_BOUNDS.position.x,
		ceilf((area.end.y - FLOOR_BOUNDS.position.y) / TILE_STEP) * TILE_STEP + FLOOR_BOUNDS.position.y
	)
	return Rect2(start, finish - start).intersection(FLOOR_BOUNDS)


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
