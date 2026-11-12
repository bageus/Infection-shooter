extends RefCounted
## Effects quality hides small decor at once (and shows it again), so weak machines draw fewer objects.
## Low hides models up to 0.5 m, Medium up to 0.25 m, High shows everything. Hidden decor stays loaded, so the
## planner always shows everything.
const EFFECTS_QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const SIZES_PATH := "res://game/bootstrap/app/prop_sizes.json"
const MAX_SIZE_BY_LEVEL := [0.5, 0.25, 0.0]
const GROUP := &"trim_decor"
const META := &"trim_size"
const LAYERS := &"trim_layers"
const SHADOW := &"trim_shadow"
const ENVIRONMENT_DIR := "/models/objects/enviroments/"
static var _sizes: Dictionary = {}


## True when this record's model is small decor for the current effects quality.
## Records with an object id (quest targets, hosts) and desk items always stay.
static func drops(record: Dictionary, scene_path: String, planner_active: bool) -> bool:
	return _limit() > 0.0 and not planner_active and size_of(record, scene_path) <= _limit()


## Largest dimension in metres of a trimmable decor record, or INF when the record must always stay.
static func size_of(record: Dictionary, scene_path: String) -> float:
	if not scene_path.contains(ENVIRONMENT_DIR) or not scene_path.ends_with(".glb"):
		return INF
	if not str(record.get("object_id", "")).is_empty() or not str(record.get("desk_id", "")).is_empty():
		return INF
	var size: float = float(_table().get(scene_path.get_file(), INF))
	var scale := maxf(absf(float(record.get("scale_x", 1.0))), maxf(absf(float(record.get("scale_y", 1.0))), absf(float(record.get("scale_z", 1.0)))))
	# Cardboard boxes are 0.7 m but clutter the floor: they go with the Low setting too.
	if scene_path.get_file().begins_with("04_cardboard"):
		return minf(size * scale, MAX_SIZE_BY_LEVEL[0])
	return size * scale


## Tags a placed node so a later quality change can hide or show it without reloading the map.
static func tag(node: Node3D, record: Dictionary, scene_path: String) -> void:
	var size := size_of(record, scene_path)
	if size < INF:
		node.set_meta(META, size)
		node.add_to_group(GROUP)
		_show(node, size > _limit())


## Hides tagged decor that the current quality drops.
static func apply_live(tree: SceneTree) -> void:
	if tree == null:
		return
	var limit := _limit()
	for node in tree.get_nodes_in_group(GROUP):
		_show(node as Node3D, float(node.get_meta(META, INF)) > limit)


## Hidden decor is also switched off: no scripts, no physics, no hits, so it costs nothing.
static func _show(node: Node3D, shown: bool) -> void:
	node.visible = shown and not node.get_meta(&"room_culled", false)
	node.set_meta(&"trim_hidden", not shown) # Room culling must not show props the quality setting hides.
	node.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED
	_cast_shadows(node, Engine.get_meta("planning_active", false) or EFFECTS_QUALITY.at_least(EFFECTS_QUALITY.MEDIUM))
	var bodies := node.find_children("*", "CollisionObject3D", true, false)
	if node is CollisionObject3D:
		bodies.append(node)
	for body: CollisionObject3D in bodies:
		if not body.has_meta(LAYERS):
			body.set_meta(LAYERS, Vector2i(body.collision_layer, body.collision_mask))
		var saved: Vector2i = body.get_meta(LAYERS)
		body.collision_layer = saved.x if shown else 0
		body.collision_mask = saved.y if shown else 0


## Low draws props without casting into the sun's shadow map (each caster costs a second draw); their baked contact shadow stays.
static func _cast_shadows(node: Node3D, on: bool) -> void:
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := found as MeshInstance3D
		if not mesh_node.has_meta(SHADOW):
			mesh_node.set_meta(SHADOW, mesh_node.cast_shadow)
		mesh_node.cast_shadow = mesh_node.get_meta(SHADOW) if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _limit() -> float:
	if Engine.get_meta("planning_active", false):
		return 0.0 # The planner shows everything; leaving it applies the quality setting.
	return MAX_SIZE_BY_LEVEL[clampi(EFFECTS_QUALITY.level, 0, MAX_SIZE_BY_LEVEL.size() - 1)]


static func _table() -> Dictionary:
	if _sizes.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIZES_PATH))
		_sizes = parsed if parsed is Dictionary else {}
	return _sizes
