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
static var _grid: Dictionary = {}
static var _indexed := -1


## Called when a prop is placed for play; marks it as cullable furniture.
static func tag(node: Node3D, record: Dictionary, scene_path: String) -> void:
	if scene_path.contains(ENVIRONMENT_DIR) and not scene_path.contains(STRUCTURE_DIR) \
			and str(record.get("object_id", "")).is_empty() and str(record.get("desk_id", "")).is_empty():
		node.add_to_group(GROUP)


## Visible tagged props whose centre lies inside the zone rectangle, away from its walls.
static func props_in(zone: Node3D, size: Vector2, tree: SceneTree) -> Array[Node3D]:
	_index(tree)
	var found: Array[Node3D] = []
	var inverse := zone.global_transform.affine_inverse()
	var half := size * 0.5 - Vector2.ONE * EDGE_MARGIN
	var reach := size.length() * 0.5
	var centre := zone.global_position
	for cx in range(floori((centre.x - reach) / CELL), floori((centre.x + reach) / CELL) + 1):
		for cz in range(floori((centre.z - reach) / CELL), floori((centre.z + reach) / CELL) + 1):
			for prop: Node3D in _grid.get(Vector2i(cx, cz), []):
				if not is_instance_valid(prop) or not prop.visible:
					continue
				var local := inverse * prop.global_position
				if absf(local.x) < half.x and absf(local.z) < half.y:
					found.append(prop)
	return found


static func set_shown(props: Array[Node3D], shown: bool) -> void:
	for prop in props:
		if is_instance_valid(prop):
			prop.visible = shown


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
