extends RefCounted
## Planner save pass: wall signs hang 1.75 m above their floor, urinals 0.25 m,
## hand dryers 1.25 m; light switches, fire alarm sounders and call points are
## placed automatically.

const GEOMETRY := preload("res://game/bootstrap/app/wall_fixture_geometry.gd")
const PLACER := preload("res://game/bootstrap/app/wall_fixture_placer.gd")
const SIGN_HEIGHT := 1.75
# Origin height above the floor for wall-mounted models that sit at one level.
const MOUNT_HEIGHTS := {"02_wall_urinal_improved": 0.25, "16_wall_urinal": 0.25,
	"05_wall_hand_dryer_improved": 1.25, "16_wall_hand_dryer": 1.25}
const META := &"planning_auto_fixture"
const SKIPPED_PATHS := ["planner_light", "darkness_zone", "blood_decal", "floor_pad", "/enviroments/12/", "/enviroments/01/01_floor_",
	"player.tscn", "corpse_", "part_hunger", "infected_"]


static func is_sign(scene: String) -> bool:
	return "/enviroments/13/" in scene and not scene in [PLACER.SWITCH, PLACER.ALARM, PLACER.CALL_POINT]


## Height above the floor the model hangs at, or -1 when the pass leaves it alone.
static func mount_height(scene: String) -> float:
	if is_sign(scene):
		return SIGN_HEIGHT
	return float(MOUNT_HEIGHTS.get(scene.get_file().get_basename(), -1.0))


## entries: {scene, x, y, z, rotation_y} of every placed object; blockers: world AABBs.
## Returns the corrected sign heights and the records of the automatic fixtures.
static func plan(entries: Array, blockers: Array) -> Dictionary:
	var geometry := GEOMETRY.new()
	geometry.load_records(entries)
	var sign_fixes: Array = []
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var height := mount_height(str(entry.scene))
		if height < 0.0:
			continue
		var floor_y: float = geometry.floor_at(Vector2(float(entry.x), float(entry.z)), float(entry.y))
		if absf(float(entry.y) - (floor_y + height)) > 0.001:
			sign_fixes.append({"index": index, "y": floor_y + height})
	for box: AABB in blockers:
		geometry.add_blocker(box)
	var placer := PLACER.new(geometry)
	var records := placer.run()
	return {"sign_fixes": sign_fixes, "records": records, "shortfall": placer.shortfall}


## Applies the pass to the live planner: corrects sign heights, replaces the
## previous automatic fixtures with fresh ones.
static func apply(objects: Node, loader: RefCounted) -> Dictionary:
	for node in objects.placed.duplicate():
		if is_instance_valid(node) and node.has_meta(META):
			objects.placed.erase(node)
			node.queue_free()
	var entries: Array = []
	var nodes: Array[Node3D] = []
	var blockers: Array = []
	for node in objects.placed:
		if not is_instance_valid(node) or str(node.get_meta("planning_actor_kind", "")) != "":
			continue
		var scene := str(node.get_meta("planning_scene_path", ""))
		if scene.is_empty():
			continue
		# Physics jitter below a millimetre must not flip a tie and move a fixture.
		entries.append({"scene": scene, "x": snappedf(node.position.x, 0.001), "y": snappedf(node.position.y, 0.001),
			"z": snappedf(node.position.z, 0.001), "rotation_y": snappedf(node.rotation_degrees.y, 0.01)})
		nodes.append(node)
		var box := _blocker_box(node, scene)
		if box.size != Vector3.ZERO:
			blockers.append(box)
	var result := plan(entries, blockers)
	for fix: Dictionary in result.sign_fixes:
		nodes[fix.index].position.y = fix.y
	var added: int = loader.append(result.records) if not result.records.is_empty() else 0
	return {"signs": result.sign_fixes.size(), "fixtures": added, "shortfall": result.shortfall}


static func _blocker_box(node: Node3D, scene: String) -> AABB:
	var file := scene.get_file().get_basename()
	if scene.begins_with(GEOMETRY.STRUCTURAL) and (GEOMETRY.SOLID.has(file) or GEOMETRY.OTHER.has(file)):
		return AABB()
	for token: String in SKIPPED_PATHS:
		if token in scene:
			return AABB()
	var box := AABB()
	var found := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		if visual.mesh == null or not visual.is_visible_in_tree() or visual.has_meta("planning_selection_highlight") or bool(visual.get_meta("planning_bounds_excluded", false)):
			continue
		if visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		var world := visual.global_transform * visual.get_aabb()
		box = world if not found else box.merge(world)
		found = true
	return box if found and box.size.y > 0.15 else AABB()
