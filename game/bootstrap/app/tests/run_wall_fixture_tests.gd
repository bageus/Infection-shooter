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
	_columns_and_overlaps()
	_blocked_fronts()
	_signs()
	_mount_heights()
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
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			back = minf(back, -bounds.end.x if path == PLACER.EXTINGUISHER else bounds.position.z)
		_check(is_equal_approx(-back, PLACER.BACK[path]) or absf(-back - PLACER.BACK[path]) < 0.002, "Back plane of %s is %.3f (found %.3f)" % [path.get_file(), PLACER.BACK[path], -back])
		node.free()


func _door_rules() -> void:
	var layout := _corridor([_wall("sliding_glass_door", 20.0, 0.0), _wall("elevator_door", 30.0, 0.0)])
	var plan := FIXTURES.plan(layout, [])
	var records: Array = plan.records
	_check(_count(records, "switch") == 6, "Wall door and glass door get three switch points each, the elevator none (%d)" % _count(records, "switch"))
	_check(_count(records, "alarm") == 2 and _count(records, "call_point") == 2, "Each of those doors gets one alarm point with a call point under it")
	_check(_count(records, "extinguisher") == 1, "The column gets one extinguisher (%d)" % _count(records, "extinguisher"))
	var hung := _corridor([{"scene": PLACER.EXTINGUISHER, "x": -7.0, "y": 1.5, "z": 0.9, "rotation_y": 0.0}])
	_check(_count(FIXTURES.plan(hung, []).records, "extinguisher") == 0, "A column that already has an extinguisher gets no second one")
	for record: Dictionary in records:
		var wanted := {"switch": 1.25, "alarm": 2.5, "call_point": 1.5, "extinguisher": 1.5}[record.auto_fixture] as float
		_check(is_equal_approx(float(record.y), wanted), "%s hangs at %.2f m" % [record.auto_fixture, wanted])
	_check(_mounted_on_walls(layout, records), "Every fixture sits on a wall or column face")
	var again: Array = FIXTURES.plan(layout, []).records
	_check(JSON.stringify(again) == JSON.stringify(records), "The pass is deterministic")
	var near_door := records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "switch" and absf(float(r.x) - 1.0) < 3.0)
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
	_hand_placed()
	_groups()
	_door_casing()


## Switches and alarms already placed by hand count toward the per-door totals.
func _hand_placed() -> void:
	var switch := "res://models/objects/enviroments/13/13_wall_light_switch.glb"
	var alarm := "res://models/objects/enviroments/13/13_wall_emergency_alarm.glb"
	var base := _corridor()
	_check(_count(FIXTURES.plan(base, []).records, "switch") == 3, "Reference: one door gets three switches")
	var hand := base + [{"scene": switch, "x": 2.0, "y": 1.25, "z": 0.16, "rotation_y": 0.0},
		{"scene": switch, "x": 2.1, "y": 1.25, "z": 0.16, "rotation_y": 0.0}]
	var records: Array = FIXTURES.plan(hand, []).records
	_check(_count(records, "switch") == 1, "Two switches hung by hand beside the door leave one to place (%d)" % _count(records, "switch"))
	_check(_count(FIXTURES.plan(hand + [{"scene": switch, "x": 0.0, "y": 1.25, "z": -0.16, "rotation_y": 180.0}], []).records, "switch") == 0,
		"Three hand-placed switches at the door leave none to place")
	var alarmed := base + [{"scene": alarm, "x": -3.0, "y": 2.5, "z": 0.16, "rotation_y": 0.0}]
	records = FIXTURES.plan(alarmed, []).records
	_check(_count(records, "alarm") == 0 and _count(records, "call_point") == 0, "A hand-placed alarm covers the door's one alarm point")
	var marked := hand.duplicate()
	marked[marked.size() - 1] = marked[marked.size() - 1].merged({"auto_fixture": "switch"})
	_check(_count(FIXTURES.plan(marked, []).records, "switch") == 2, "An automatic switch is not counted as hand-placed")


## The palette chooses which automatic groups the pass places.
func _groups() -> void:
	var layout := _corridor()
	var both: Array = FIXTURES.plan(layout, []).records
	var only_switches: Array = FIXTURES.plan(layout, [], {"switches": true, "fire": false}).records
	var only_fire: Array = FIXTURES.plan(layout, [], {"switches": false, "fire": true}).records
	var none: Array = FIXTURES.plan(layout, [], {"switches": false, "fire": false}).records
	_check(_count(only_switches, "switch") == _count(both, "switch") and _count(only_switches, "alarm") + _count(only_switches, "call_point") == 0, "Switches only: no alarm points")
	_check(_count(only_fire, "switch") == 0 and _count(only_fire, "alarm") == _count(both, "alarm") and _count(only_fire, "call_point") == _count(both, "call_point"), "Fire only: no switches")
	_check(_count(none, "switch") + _count(none, "alarm") + _count(none, "call_point") == 0 and _count(none, "extinguisher") == 1, "Both off: no switches or alarms, the column extinguisher stays")
	_check(FIXTURES.regenerated_kinds({"switches": false, "fire": false}) == ["extinguisher"] and "call_point" in FIXTURES.regenerated_kinds({"fire": true}), "A group that is off is not regenerated")


## Fixtures never touch the casing around a door opening (it reaches 0.85 m from the door centre).
func _door_casing() -> void:
	var layout := _corridor([_wall("wall_emergency_door", 12.0, 0.0), _wall("wall_straight", 10.0, 0.0), _wall("wall_straight", 14.0, 0.0)])
	var records: Array = FIXTURES.plan(layout, []).records
	var near := 0
	for record: Dictionary in records:
		if record.auto_fixture == "extinguisher":
			continue
		var half := 0.08 if record.auto_fixture in ["alarm", "call_point"] else 0.043
		for door_x in [1.0, 12.0]:
			var along := absf(float(record.x) - door_x)
			if along < 1.2:
				near += 1
				_check(along - half >= 0.85 + 0.03, "%s at %.2f m from the door centre clears the casing" % [record.auto_fixture, along])
	_check(_count(records, "switch") == 6 and near >= 2, "Both doors still get their three switches (%d)" % _count(records, "switch"))
	_check(GEOMETRY.OPENING >= 0.85, "The door opening reaches the outer edge of the casing")


func _mounted_on_walls(layout: Array, records: Array) -> bool:
	var model := GEOMETRY.new()
	model.load_records(layout)
	for record: Dictionary in records:
		var turn := PLACER.EXTINGUISHER_TURN if record.scene == PLACER.EXTINGUISHER else 0.0
		var yaw := deg_to_rad(float(record.rotation_y) - turn)
		var normal := Vector2(sin(yaw), cos(yaw))
		var back := Vector2(float(record.x), float(record.z)) - normal * (float(PLACER.BACK[record.scene]) + PLACER.GAP)
		var found := false
		for face: Dictionary in model.faces:
			var along: float = (back - face.o).dot(face.t)
			if face.n.dot(normal) > 0.99 and absf((back - face.o).dot(face.n)) < 0.002 and model._within_range(face, along, 0.0):
				found = true
				break
		if not found:
			return false
	return true


func _columns_and_overlaps() -> void:
	var layout := [_wall("column", 0.0, 0.0, 0.0), _wall("wall_door", 6.0, 0.0), _wall("wall_straight", 4.0, 0.0), _wall("wall_straight", 8.0, 0.0)]
	var plan := FIXTURES.plan(layout, [])
	var on_column: Array = plan.records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "switch" and Vector2(float(r.x), float(r.z)).length() < 1.0)
	_check(on_column.is_empty(), "No light switch is placed on a column")
	var hung: Array = plan.records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "extinguisher")
	_check(hung.size() == 1, "The column still gets its extinguisher")
	var face := Vector2(float(hung[0].x), float(hung[0].z))
	_check(absf(maxf(absf(face.x), absf(face.y)) - (0.512 + PLACER.GAP + PLACER.BACK[PLACER.EXTINGUISHER])) < 0.001, "The extinguisher stands %.0f mm off the column body" % (PLACER.GAP * 1000.0))
	# A wall clock already hanging on every face leaves no room: nothing overlaps it.
	var clocks: Array = []
	for angle in [0.0, 90.0, 180.0, 270.0]:
		var direction := Vector3(sin(deg_to_rad(angle)), 0.0, cos(deg_to_rad(angle)))
		clocks.append(AABB(direction * 0.55 + Vector3(-0.25, 1.8, -0.25), Vector3(0.5, 0.5, 0.5)))
	var blocked := FIXTURES.plan(layout, clocks)
	_check(blocked.records.filter(func(r: Dictionary) -> bool: return r.auto_fixture == "extinguisher").is_empty(), "An extinguisher is not hung over a wall clock")


func _blocked_fronts() -> void:
	var layout := _corridor()
	var desk := AABB(Vector3(-8.0, 0.0, 0.1), Vector3(18.0, 1.6, 0.9)) # a long desk against the +z side
	var plan := FIXTURES.plan(layout, [desk])
	for record: Dictionary in plan.records:
		if record.auto_fixture == "switch":
			_check(float(record.z) < 0.0, "No switch is placed behind a desk")
	_check(plan.shortfall.switch == 0, "The other side still takes the switches")
	var boxed := FIXTURES.plan(layout, [desk, AABB(Vector3(-8.0, 0.0, -1.0), Vector3(18.0, 1.6, 0.9))])
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


func _mount_heights() -> void:
	var layout := _corridor()
	layout.append({"scene": "res://models/objects/enviroments/02/02_wall_urinal_improved.glb", "x": -3.0, "y": 0.3, "z": 0.1, "rotation_y": 0.0})
	layout.append({"scene": "res://models/objects/enviroments/05/05_wall_hand_dryer_improved.glb", "x": 3.0, "y": 1.5, "z": 0.1, "rotation_y": 0.0})
	var fixes: Array = FIXTURES.plan(layout, []).sign_fixes
	_check(fixes.size() == 2 and is_equal_approx(float(fixes[0].y), 0.25) and is_equal_approx(float(fixes[1].y), 1.25), "Urinals go to 0.25 m and hand dryers to 1.25 m")


func _levels() -> void:
	# A second storey three metres down: heights are measured from its own floor.
	var layout := _corridor()
	for entry in _corridor():
		var copy: Dictionary = (entry as Dictionary).duplicate()
		copy.y = -3.0
		layout.append(copy)
	layout.append({"scene": SIGN, "x": 6.0, "y": -1.0, "z": 0.1, "rotation_y": 0.0})
	var plan := FIXTURES.plan(layout, [])
	_check(_count(plan.records, "switch") == 6 and _count(plan.records, "alarm") == 2, "Each level gets its own count")
	_check(plan.records.filter(func(r: Dictionary) -> bool: return is_equal_approx(float(r.y), -3.0 + 1.25) or is_equal_approx(float(r.y), 1.25) or is_equal_approx(float(r.y), -3.0 + 1.0) or is_equal_approx(float(r.y), 1.0) or is_equal_approx(float(r.y), -0.5) or is_equal_approx(float(r.y), 1.5) or is_equal_approx(float(r.y), -1.5) or is_equal_approx(float(r.y), 2.5)).size() == plan.records.size(), "Lower-level fixtures are measured from the lower floor")
	_check(plan.sign_fixes.size() == 1 and is_equal_approx(float(plan.sign_fixes[0].y), -3.0 + 1.75), "A sign on the lower level hangs 1.75 m above that floor")


func _base_map() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE_MAP))
	var doors: int = data.objects.filter(func(r: Dictionary) -> bool:
		var file := str(r.scene).get_file()
		return file.begins_with("wall_door") or file == "wall_emergency_door.tscn" or file == "sliding_glass_door.tscn").size()
	var plan := FIXTURES.plan(data.objects, [])
	_check(_count(plan.records, "switch") + plan.shortfall.switch == doors * 3, "Base map: three switch points per door (%d doors incl. glass)" % doors)
	_check(_count(plan.records, "alarm") + plan.shortfall.alarm == doors * 1 and _count(plan.records, "call_point") == _count(plan.records, "alarm"), "Base map: one alarm point per door, one call point under each")
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
	var heights: Array = data.objects.filter(func(r: Dictionary) -> bool: return FIXTURES.mount_height(str(r.scene)) >= 0.0)
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
	records.append({"scene": STRUCT + "column.tscn", "x": -8.0, "y": 0.0, "z": 20.0})
	var report: Dictionary = objects.call("_apply_layout_data", {"version": 8, "objects": records})
	_check(int(report.get("loaded", 0)) == 7, "Planner test layout loads")
	var toggles: Variant = planner.controls.fixture_toggles
	_check(not toggles.switches.button_pressed and not toggles.fire.button_pressed, "Both palette toggles start off")
	var first_text: String = storage.call("enforce_wall_fixtures")
	await process_frame
	var only_column: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and n.has_meta("planning_auto_fixture"))
	_check(only_column.size() == 1, "With both toggles off a save places only the column extinguisher (%d)" % only_column.size())
	toggles.switches.button_pressed = true
	toggles.fire.button_pressed = true
	var text: String = storage.call("enforce_wall_fixtures")
	await process_frame
	var auto: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and n.has_meta("planning_auto_fixture"))
	_check(auto.size() == 3 + 1 + 1 + 1, "Save adds 3 switches, 1 alarm, 1 call point and a column extinguisher (%d)" % auto.size())
	_check(first_text.contains("signs adjusted 1") and text.contains("wall fixtures 6"), "Save reports the corrected sign and the placed fixtures: %s / %s" % [first_text, text])
	var wall_sign: Node3D = objects.placed.filter(func(n: Node3D) -> bool: return str(n.get_meta("planning_scene_path", "")) == SIGN)[0]
	_check(is_equal_approx(wall_sign.position.y, 1.75), "The sign was moved to 1.75 m")
	var first_records: Array = storage.call("_collect_layout_data").objects.filter(func(r: Dictionary) -> bool: return r.has("auto_fixture"))
	storage.call("enforce_wall_fixtures")
	await process_frame
	var second_records: Array = storage.call("_collect_layout_data").objects.filter(func(r: Dictionary) -> bool: return r.has("auto_fixture"))
	var same := first_records.size() == second_records.size()
	for index in mini(first_records.size(), second_records.size()):
		same = same and Vector3(first_records[index].x - second_records[index].x, first_records[index].y - second_records[index].y, first_records[index].z - second_records[index].z).length() < 0.001 and first_records[index].scene == second_records[index].scene
	_check(same, "A second save places the fixtures in the same spots and order")
	var extinguishers: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and str(n.get_meta("planning_scene_path", "")) == PLACER.EXTINGUISHER)
	_check(extinguishers.size() == 1, "Saving twice leaves one extinguisher on the column (%d)" % extinguishers.size())
	var again: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion() and n.has_meta("planning_auto_fixture"))
	_check(again.size() == auto.size(), "Saving twice does not duplicate the fixtures (%d)" % again.size())
	var saved: Array = storage.call("_collect_layout_data").objects.filter(func(r: Dictionary) -> bool: return r.has("auto_fixture"))
	_check(saved.size() == auto.size(), "The automatic fixtures are written to the map with their marker")
	var reload: Dictionary = objects.call("_apply_layout_data", {"version": 8, "objects": storage.call("_collect_layout_data").objects})
	_check(objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and n.has_meta("planning_auto_fixture")).size() == auto.size(), "The marker survives reloading the map")
	toggles.fire.button_pressed = false
	toggles.switches.button_pressed = false
	storage.call("enforce_wall_fixtures")
	await process_frame
	var kept: Array = objects.placed.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion() and n.has_meta("planning_auto_fixture"))
	_check(kept.size() == auto.size(), "Turning the toggles off leaves the fixtures already placed (%d of %d)" % [kept.size(), auto.size()])
	stage.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
