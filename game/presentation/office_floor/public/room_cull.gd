extends RefCounted
## Room culling: a room that stays under solid fog (closed doors, no glass) cannot be seen, so its furniture is
## not drawn. Darkness zones hide the props inside their rectangle once the fog is fully up and show them again
## the moment it starts to lift. Structure (folder 01: walls, floors, doors, stairs) and props with an object or
## desk id always stay drawn.
const GROUP := &"room_prop"
const STRUCTURE_DIR := "/enviroments/01/"
const ENVIRONMENT_DIR := "/enviroments/"
const CELL := 4.0
const EDGE_MARGIN := 0.3
## Player setting: off keeps every prop drawn and simulated, as before culling existed.
static var enabled := true
const PARKED := &"parked"
static var _grid: Dictionary = {}
static var _indexed := -1


## Called when a prop is placed for play; marks it as cullable furniture.
static func tag(node: Node3D, record: Dictionary, scene_path: String) -> void:
	if scene_path.contains(ENVIRONMENT_DIR) and not scene_path.contains(STRUCTURE_DIR) \
			and str(record.get("object_id", "")).is_empty() and str(record.get("desk_id", "")).is_empty():
		node.add_to_group(GROUP)


## Visible tagged props whose centre lies inside the zone rectangle, away from its walls.
static func props_in(zone: Node3D, size: Vector2, tree: SceneTree) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if not enabled:
		return found
	_index(tree)
	var inverse := zone.global_transform.affine_inverse()
	var half := size * 0.5 - Vector2.ONE * EDGE_MARGIN
	var reach := size.length() * 0.5
	var centre := zone.global_position
	for cx in range(floori((centre.x - reach) / CELL), floori((centre.x + reach) / CELL) + 1):
		for cz in range(floori((centre.z - reach) / CELL), floori((centre.z + reach) / CELL) + 1):
			for entry in _grid.get(Vector2i(cx, cz), []):
				# Freed props may linger in the grid until the next re-index; a typed loop variable would error on them.
				if not is_instance_valid(entry) or not (entry as Node3D).visible:
					continue
				var prop := entry as Node3D
				var local := inverse * prop.global_position
				if absf(local.x) < half.x and absf(local.z) < half.y:
					found.append(prop)
	return found


static func set_shown(props: Array[Node3D], shown: bool) -> void:
	for prop in props:
		# A prop the effects quality hid meanwhile (meta set by the decor trim) stays hidden.
		if is_instance_valid(prop):
			prop.set_meta(&"room_culled", not shown) # The decor trim must not show a prop its room still hides.
			if not (shown and prop.get_meta(&"trim_hidden", false)):
				prop.visible = shown
			_park(prop, not shown)


## Shows every culled prop again, used when the setting is switched off.
static func restore_all(tree: SceneTree) -> void:
	var culled: Array[Node3D] = []
	for node in tree.get_nodes_in_group(GROUP):
		if node is Node3D and bool(node.get_meta(&"room_culled", false)):
			culled.append(node)
	set_shown(culled, true)


# A hidden prop stops colliding and simulating: its bodies lose their layers and freeze, its scripts stop.
static func _park(prop: Node3D, park: bool) -> void:
	if park == prop.has_meta(PARKED):
		return
	if park:
		var bodies: Array[Dictionary] = []
		var nodes: Array[Node] = [prop]
		nodes.append_array(prop.find_children("*", "CollisionObject3D", true, false))
		for node in nodes:
			if node is CollisionObject3D:
				var body := node as CollisionObject3D
				var rigid := body as RigidBody3D
				bodies.append({"body": body, "layer": body.collision_layer, "mask": body.collision_mask, "freeze": rigid.freeze if rigid else false})
				body.collision_layer = 0
				body.collision_mask = 0
				if rigid:
					rigid.freeze = true
		prop.set_meta(PARKED, {"process": prop.process_mode, "bodies": bodies})
		prop.process_mode = Node.PROCESS_MODE_DISABLED
		return
	var saved: Dictionary = prop.get_meta(PARKED)
	prop.remove_meta(PARKED)
	prop.process_mode = saved.process
	for entry: Dictionary in saved.bodies:
		var body := entry.body as CollisionObject3D
		if not is_instance_valid(body):
			continue
		body.collision_layer = entry.layer
		body.collision_mask = entry.mask
		if body is RigidBody3D:
			(body as RigidBody3D).freeze = entry.freeze


# One pass over all tagged props, redone when props are added or removed.
static func _index(tree: SceneTree) -> void:
	var all := tree.get_nodes_in_group(GROUP)
	if all.size() == _indexed:
		return
	_indexed = all.size()
	_grid.clear()
	for prop: Node3D in all:
		var key := Vector2i(floori(prop.global_position.x / CELL), floori(prop.global_position.z / CELL))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(prop)
