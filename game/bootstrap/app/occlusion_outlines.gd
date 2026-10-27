extends RefCounted
## Yellow outline through walls for items the player is close to in the same room but the camera cannot see.
const OUTLINE := preload("res://game/bootstrap/app/occlusion_outline.gd")
const QUERY_LAYER := preload("res://game/bootstrap/app/occlusion_query_layer.gd")
const GROUPS: Array[StringName] = [&"occlusion_items", &"weapon_pickups", &"interactive_doors", &"hidden_outline"]
# DNA and armor share the item group but are not on the outlined list.
const EXCLUDED_GROUPS: Array[StringName] = [&"armor_pickups"]
const RADIUS := 6.0
const RELEASE_RADIUS := 6.5
const INTERVAL := 0.15
const SAME_SPACE_STOP := 0.4
const CHEST := 0.9
const DOORWAY := 0.6
var outlines: Dictionary = {}
var rays_last_tick := 0
var _elapsed := 0.0


func tick(delta: float, effects: Node) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = 0.0
	rays_last_tick = 0
	var player: Node3D = effects.player
	var seen: Dictionary = {}
	for group in GROUPS:
		for node: Node in effects.get_tree().get_nodes_in_group(group):
			var item := node as Node3D
			if item == null or seen.has(item.get_instance_id()) or not effects.world.is_ancestor_of(item):
				continue
			seen[item.get_instance_id()] = true
			if not _eligible(item):
				continue
			var id := item.get_instance_id()
			var limit := RELEASE_RADIUS if outlines.has(id) and outlines[id].shown else RADIUS
			var show := _flat_distance(player, item) <= limit and item.is_visible_in_tree() and same_space(effects, item) and hidden_from_camera(effects, item)
			if show and not outlines.has(id):
				outlines[id] = OUTLINE.new(item)
			if outlines.has(id):
				outlines[id].set_revealed(show)
	for id in outlines.keys():
		if not seen.has(id) or outlines[id].target.get_ref() == null:
			outlines[id].clear()
			outlines.erase(id)


func _eligible(item: Node) -> bool:
	for group in EXCLUDED_GROUPS:
		if item.is_in_group(group):
			return false
	return not String(item.scene_file_path).ends_with("dna_pickup.tscn")


func _flat_distance(a: Node3D, b: Node3D) -> float:
	var delta := a.global_position - b.global_position
	delta.y = 0.0
	return delta.length()


## Same room: equal fog-of-war room ids (the player's reach covers a doorway); outside any room, no wall at chest height.
func same_space(effects: Node, item: Node3D) -> bool:
	var player_room := _room_of(effects, effects.player.global_position, DOORWAY)
	if player_room != _room_of(effects, item.global_position, 0.3):
		return false
	if player_room > 0:
		return true
	var from: Vector3 = effects.player.global_position + Vector3.UP * CHEST
	var to := Vector3(item.global_position.x, from.y, item.global_position.z)
	var gap := to - from
	if gap.length() <= SAME_SPACE_STOP:
		return true
	to = from + gap.normalized() * (gap.length() - SAME_SPACE_STOP)
	rays_last_tick += 1
	return not _hits_structure(effects, from, to, null)


func _room_of(effects: Node, point: Vector3, reach: float) -> int:
	for zone: Node in effects.get_tree().get_nodes_in_group("darkness_zone"):
		var room := int(zone.get("room_id"))
		if room > 0 and not zone.get("permanent") and zone.call("_edge_distance", point) <= reach:
			return room
	return 0


## The camera ray is stopped by a structure or by solid fog before it reaches the item.
func hidden_from_camera(effects: Node, item: Node3D) -> bool:
	var camera: Camera3D = effects.camera
	var point := item.global_position + Vector3.UP * 0.3
	if camera.is_position_behind(point) or not effects.get_viewport().get_visible_rect().grow(60.0).has_point(camera.unproject_position(point)):
		return false
	for zone: Node in effects.get_tree().get_nodes_in_group("darkness_zone"):
		if zone.has_method("blocks_view") and zone.call("blocks_view", camera.global_position, point):
			return true
	rays_last_tick += 1
	return _hits_structure(effects, camera.global_position, point, item)


func _hits_structure(effects: Node, from: Vector3, to: Vector3, own: Node3D) -> bool:
	var exclude: Array[RID] = []
	for _attempt in 3:
		var query := PhysicsRayQueryParameters3D.create(from, to, QUERY_LAYER.MASK)
		query.exclude = exclude
		var hit: Dictionary = effects.world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider := hit.collider as Node
		if own != null and own.is_ancestor_of(collider):
			exclude.append((collider as CollisionObject3D).get_rid())
			continue
		var ancestor := collider
		while ancestor != null and ancestor != effects.world:
			if ancestor.is_in_group("camera_occluder") and (ancestor as Node3D).is_visible_in_tree():
				return true
			ancestor = ancestor.get_parent()
		return false
	return false


func clear() -> void:
	for outline in outlines.values():
		outline.clear()
	outlines.clear()
	_elapsed = 0.0
