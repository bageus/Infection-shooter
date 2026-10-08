extends Node3D

const TEST_DNA := preload("res://game/bootstrap/app/test_dna_pickup.gd")
const KEY := preload("res://game/bootstrap/app/mission_key.gd")
const WEAPON := preload("res://game/bootstrap/app/weapon_pickup.gd")
const FLOOR_BOUNDS := Rect2(-40, -30, 80, 60)
const CUT_STEP := 0.5

var _stage: Node3D
var _openings: Array[Rect2] = []
var _scan_remaining := 0.0


func setup(stage: Node3D, player: Node3D, infection: Node) -> void:
	_stage = stage
	_refresh_stairs()
	var key := KEY.new()
	key.name = "EmergencyKey"
	add_child(key)
	key.global_position = Vector3(20, 0.25, 15)
	spawn_weapon(3, Vector3(-20, 0.25, -15))
	for entry in [[4, Vector3(-18, 0.25, -12)], [5, Vector3(-15, 0.25, -12)], [6, Vector3(-12, 0.25, -12)], [7, Vector3(-9, 0.25, -12)]]:
		spawn_weapon(entry[0], entry[1])
	var dna := TEST_DNA.new()
	dna.name = "RespawningTestDNA"
	dna.position = Vector3(-17.5, 0.5, -15)
	dna.call("configure", player, infection)
	add_child(dna)


func _process(delta: float) -> void:
	_scan_remaining -= delta
	if _scan_remaining <= 0.0:
		_scan_remaining = 0.35
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
		next_openings.append_array(_stair_openings(stair, bounds))
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
