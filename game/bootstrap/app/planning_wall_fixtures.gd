extends RefCounted
## Planner save pass for group 13: wall signs hang 1.75 m above their floor, and
## light switches, fire alarm sounders and call points are placed automatically.

const GEOMETRY := preload("res://game/bootstrap/app/wall_fixture_geometry.gd")
const PLACER := preload("res://game/bootstrap/app/wall_fixture_placer.gd")
const SIGN_HEIGHT := 1.75
const META := &"planning_auto_fixture"
const SKIPPED_PATHS := ["planner_light", "darkness_zone", "blood_decal", "floor_pad", "/enviroments/12/", "/enviroments/01/01_floor_",
	"player.tscn", "corpse_", "part_hunger", "infected_"]


static func is_sign(scene: String) -> bool:
	return "/enviroments/13/" in scene and not scene in [PLACER.SWITCH, PLACER.ALARM, PLACER.CALL_POINT]


## entries: {scene, x, y, z, rotation_y} of every placed object; blockers: world AABBs.
## Returns the corrected sign heights and the records of the automatic fixtures.
static func plan(entries: Array, blockers: Array) -> Dictionary:
	var geometry := GEOMETRY.new()
	geometry.load_records(entries)
	var sign_fixes: Array = []
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if not is_sign(str(entry.scene)):
			continue
		var floor_y: float = geometry.floor_at(Vector2(float(entry.x), float(entry.z)), float(entry.y))
		if absf(float(entry.y) - (floor_y + SIGN_HEIGHT)) > 0.001:
			sign_fixes.append({"index": index, "y": floor_y + SIGN_HEIGHT})
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
		entries.append({"scene": scene, "x": node.position.x, "y": node.position.y, "z": node.position.z, "rotation_y": node.rotation_degrees.y})
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
