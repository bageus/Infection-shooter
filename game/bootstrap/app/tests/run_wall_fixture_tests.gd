extends SceneTree
## Group 13 level checks on save: signs at 1.75 m, automatic light switches and
## fire alarm points on walls and columns.
const FIXTURES := preload("res://game/bootstrap/app/planning_wall_fixtures.gd")
const GEOMETRY := preload("res://game/bootstrap/app/wall_fixture_geometry.gd")
const PLACER := preload("res://game/bootstrap/app/wall_fixture_placer.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const STRUCT := "res://game/presentation/office_floor/public/structural/"
const SIGN := "res://models/objects/enviroments/13/13_wall_exit_lit.glb"
const BASE_MAP := "res://game/presentation/office_floor/public/base_office_map.json"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(320, 180)
	_model_bounds()
	_door_rules()
	_blocked_fronts()
	_signs()
	_levels()
	_base_map()
	await _planner()
	print("Wall fixture tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _wall(file: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0) -> Dictionary:
	return {"scene": STRUCT + file + ".tscn", "x": x, "y": y, "z": z, "rotation_y": yaw}


## A 12 m wall along x with doors of several kinds, columns at both ends.
func _corridor(extra: Array = []) -> Array:
	var entries: Array = []
	for x in [-5.0, -3.0, -1.0, 3.0, 5.0, 7.0]:
		entries.append(_wall("wall_straight", x, 0.0))
	entries.append(_wall("wall_door", 1.0, 0.0))
	entries.append(_wall("column", -7.0, 0.0))
	return entries + extra


func _count(records: Array, kind: String) -> int:
	return records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == kind).size()


func _model_bounds() -> void:
	# The mounting offsets are the distance from each model origin to its back plane.
	for path: String in PLACER.BACK:
		var node := (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(node)
		var back := INF
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			back = minf(back, (mesh.global_transform * mesh.get_aabb()).position.z)
		_check(is_equal_approx(-back, PLACER.BACK[path]) or absf(-back - PLACER.BACK[path]) < 0.002, "Back plane of %s is %.3f (found %.3f)" % [path.get_file(), PLACER.BACK[path], -back])
		node.free()


func _door_rules() -> void:
	var layout := _corridor([_wall("sliding_glass_door", 20.0, 0.0), _wall("elevator_door", 30.0, 0.0)])
	var plan := FIXTURES.plan(layout, [])
	var records: Array = plan.records
	_check(_count(records, "switch") == 3, "A door gets three switch points; glass and elevator doors none (%d)" % _count(records, "switch"))
	_check(_count(records, "alarm") == 4 and _count(records, "call_point") == 4, "A door gets four alarm points, each with a call point")
	for record: Dictionary in records:
		var wanted := {"switch": 0.75, "alarm": 2.5, "call_point": 1.0}[record.auto_fixture] as float
		_check(is_equal_approx(float(record.y), wanted), "%s hangs at %.2f m" % [record.auto_fixture, wanted])
	_check(_mounted_on_walls(layout, records), "Every fixture sits on a wall or column face")
	var again: Array = FIXTURES.plan(layout, []).records
	_check(JSON.stringify(again) == JSON.stringify(records), "The pass is deterministic")
	var near_door := records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "switch")
	var sides := {}
	for record: Dictionary in near_door:
		sides[signf(float(record.z))] = int(sides.get(signf(float(record.z)), 0)) + 1
	_check(sides.size() == 2, "Switches go on both sides of a regular door")
	# Fire door: only the side the key opens from (local -z of the leaf).
	var fire := [_wall("wall_straight", 0.0, -2.0, 90.0), _wall("wall_emergency_door", 0.0, 0.0, 90.0), _wall("wall_straight", 0.0, 2.0, 90.0)]
	var fire_switches: Array = FIXTURES.plan(fire, []).records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "switch")
	_check(fire_switches.size() == 3, "Fire door gets three switch points (%d)" % fire_switches.size())
	for record: Dictionary in fire_switches:
		_check(float(record.x) < 0.0 and absf(float(record.rotation_y) + 90.0) < 0.01, "Fire door switch is on the key side facing away from the wall")


func _mounted_on_walls(layout: Array, records: Array) -> bool:
	var model := GEOMETRY.new()
	model.load_records(layout)
	for record: Dictionary in records:
		var normal := Vector2(sin(deg_to_rad(float(record.rotation_y))), cos(deg_to_rad(float(record.rotation_y))))
		var back := Vector2(float(record.x), float(record.z)) - normal * float(PLACER.BACK[record.scene])
		var found := false
		for face: Dictionary in model.faces:
			var along: float = (back - face.o).dot(face.t)
			if face.n.dot(normal) > 0.99 and absf((back - face.o).dot(face.n)) < 0.002 and model._within_range(face, along, 0.0):
				found = true
				break
		if not found:
			return false
	return true


func _blocked_fronts() -> void:
	var layout := _corridor()
	var desk := AABB(Vector3(-8.0, 0.0, 0.1), Vector3(18.0, 0.8, 0.9)) # a long desk against the +z side
	var plan := FIXTURES.plan(layout, [desk])
	for record: Dictionary in plan.records:
		if record.auto_fixture == "switch":
			_check(float(record.z) < 0.0, "No switch is placed behind a desk")
	_check(plan.shortfall.switch == 0, "The other side still takes the switches")
	var boxed := FIXTURES.plan(layout, [desk, AABB(Vector3(-8.0, 0.0, -1.0), Vector3(18.0, 0.8, 0.9))])
	_check(boxed.records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "switch").is_empty() and boxed.shortfall.switch == 3, "With both fronts blocked nothing is placed and the shortfall is reported")


func _signs() -> void:
	var layout := _corridor()
	var spots := [-5.0, -3.0, 3.0, 5.0]
	for index in 4:
		layout.append({"scene": SIGN, "x": spots[index], "y": [1.5, 2.0, 1.75, 2.6][index], "z": 0.1, "rotation_y": 0.0})
	var fixes: Array = FIXTURES.plan(layout, []).sign_fixes
	_check(fixes.size() == 3, "Signs off 1.75 m are corrected (%d of 4)" % fixes.size())
	for fix: Dictionary in fixes:
		_check(is_equal_approx(float(fix.y), 1.75), "Corrected sign height is 1.75 m")
	_check(not FIXTURES.is_sign(PLACER.SWITCH) and not FIXTURES.is_sign(PLACER.ALARM) and FIXTURES.is_sign(SIGN), "Switches and alarms are not treated as signs")


func _levels() -> void:
	# A second storey three metres down: heights are measured from its own floor.
	var layout := _corridor()
	for entry in _corridor():
		var copy: Dictionary = (entry as Dictionary).duplicate()
		copy.y = -3.0
		layout.append(copy)
	layout.append({"scene": SIGN, "x": 6.0, "y": -1.0, "z": 0.1, "rotation_y": 0.0})
	var plan := FIXTURES.plan(layout, [])
	_check(_count(plan.records, "switch") == 6 and _count(plan.records, "alarm") == 8, "Each level gets its own count")
	_check(plan.records.filter(func(r: Dictionary) -> bool: return is_equal_approx(float(r.y), -3.0 + 0.75) or is_equal_approx(float(r.y), 0.75) or is_equal_approx(float(r.y), -3.0 + 1.0) or is_equal_approx(float(r.y), 1.0) or is_equal_approx(float(r.y), -0.5) or is_equal_approx(float(r.y), 2.5)).size() == plan.records.size(), "Lower-level fixtures are measured from the lower floor")
	_check(plan.sign_fixes.size() == 1 and is_equal_approx(float(plan.sign_fixes[0].y), -3.0 + 1.75), "A sign on the lower level hangs 1.75 m above that floor")


func _base_map() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE_MAP))
	var doors: int = data.objects.filter(func(r: Dictionary) -> bool:
		var file := str(r.scene).get_file()
		return file.begins_with("wall_door") or file == "wall_emergency_door.tscn").size()
	var plan := FIXTURES.plan(data.objects, [])
	_check(_count(plan.records, "switch") + plan.shortfall.switch == doors * 3, "Base map: three switch points per door (%d doors)" % doors)
	_check(_count(plan.records, "alarm") + plan.shortfall.alarm == doors * 4 and _count(plan.records, "call_point") == _count(plan.records, "alarm"), "Base map: four alarm points per door, one call point under each")
	_check(plan.shortfall.switch == 0 and plan.shortfall.alarm == 0, "Base map has room for every point")
	_check(_mounted_on_walls(data.objects, plan.records), "Base map: every fixture sits on a wall or column face")
	var seen := {}
	for record: Dictionary in plan.records:
		var key := "%s|%.3f|%.3f|%.3f" % [record.scene, record.x, record.y, record.z]
		_check(not seen.has(key), "No duplicate fixture " + key)
		seen[key] = true
	var model := GEOMETRY.new()
	model.load_records(data.objects)
	for record: Dictionary in plan.records:
		if record.auto_fixture != "call_point":
			continue
		var twin: Array = plan.records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "alarm" and Vector2(float(r.x) - float(record.x), float(r.z) - float(record.z)).length() < 0.02)
		_check(not twin.is_empty(), "A call point has an alarm directly above it")
	var heights: Array = data.objects.filter(func(r: Dictionary) -> bool: return FIXTURES.is_sign(str(r.scene)))
	_check(heights.size() > 0 and plan.sign_fixes.size() <= heights.size(), "Base map signs are checked")


func _planner() -> void:
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var planner: Node = stage.get("planning_mode")
	var objects: Variant = planner.get("objects")
	var storage: Variant = planner.get("storage")
	objects.clear_layout(false, true)
	var records: Array = []
	for x in [-3.0, -1.0, 3.0, 5.0]:
		records.append({"scene": STRUCT + "wall_straight.tscn", "x": x, "y": 0.0, "z": 20.0})
	records.append({"scene": STRUCT + "wall_door.tscn", "x": 1.0, "y": 0.0, "z": 20.0})
	records.append({"scene": SIGN, "x": 4.0, "y": 2.0, "z": 20.1})
	var report: Dictionary = objects.call("_apply_layout_data", {"version": 8, "objects": records})
	_check(int(report.get("loaded", 0)) == 6, "Planner test layout loads")
	var text: String = storage.call("enforce_wall_fixtures")
	await process_frame
	var auto: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and n.has_meta("planning_auto_fixture"))
	_check(auto.size() == 3 + 8, "Save adds 3 switches, 4 alarms and 4 call points (%d)" % auto.size())
	_check(text.contains("signs adjusted 1"), "Save reports the corrected sign: " + text)
	var wall_sign: Node3D = objects.placed.filter(func(n: Node3D) -> bool: return str(n.get_meta("planning_scene_path", "")) == SIGN)[0]
	_check(is_equal_approx(wall_sign.position.y, 1.75), "The sign was moved to 1.75 m")
	storage.call("enforce_wall_fixtures")
	await process_frame
	var again: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion() and n.has_meta("planning_auto_fixture"))
	_check(again.size() == auto.size(), "Saving twice does not duplicate the fixtures (%d)" % again.size())
	var saved: Array = storage.call("_collect_layout_data").objects.filter(func(r: Dictionary) -> bool: return r.has("auto_fixture"))
	_check(saved.size() == auto.size(), "The automatic fixtures are written to the map with their marker")
	var reload: Dictionary = objects.call("_apply_layout_data", {"version": 8, "objects": storage.call("_collect_layout_data").objects})
	_check(objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and n.has_meta("planning_auto_fixture")).size() == auto.size(), "The marker survives reloading the map")
	stage.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
