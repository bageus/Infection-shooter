extends SceneTree
## Every destructible office model must leave its debris above the floor: after a break and
## two seconds of physics no live fragment (collider or visual) may dip below the floor top.
##
## CI runs a representative subset. For every destructible model, which takes about 20 s with the
## simulation unpaced (about nine minutes without --fixed-fps):
##
##   godot --headless --fixed-fps 60 --path . --script game/presentation/office_floor/tests/run_debris_floor_tests.gd -- all
##
## Any other argument keeps the models whose path contains it. Models the prop cannot load log an error.

const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const REWORK := "res://docs/qa/destruction_model_rework.json"
const FLOOR_TOP := 0.0135
const TOLERANCE := 0.02
const SETTLE_SECONDS := 2.0
const MAX_HITS := 14
const FRAGMENT_ROUNDS := 2
const SUBSET := ["03_file_cabinet_largest", "03_file_cabinet_smaller", "03_bookshelf", "05_wall_TV_destructible", "07_table_longest", "08_divider_full_U.glb", "06_office_chair.glb", "10_couch_red"]

var failures := 0
var _filter := ""
var _vertices := {}
var _lowest_ever := INF


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_filter = args[0]
	seed(7)
	var stage := Node3D.new()
	root.add_child(stage)
	_add_floor(stage)
	var tested := 0
	for path in _model_paths():
		if not _is_selected(path):
			continue
		await _test_model(stage, path)
		tested += 1
	print("%d model(s) tested, %d failure(s)" % [tested, failures])
	quit(1 if failures > 0 else 0)


func _is_selected(path: String) -> bool:
	if _filter == "all":
		return true
	if not _filter.is_empty():
		return _filter in path
	for name in SUBSET:
		if name in path:
			return true
	return false


func _model_paths() -> Array[String]:
	var paths: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REWORK))
	if parsed is Dictionary:
		for entry in (parsed as Dictionary).get("models", []):
			var path := "res://" + String(entry.get("path", ""))
			if "01_floor_" in path:
				continue
			paths.append(path)
	return paths


func _test_model(stage: Node3D, path: String) -> void:
	_lowest_ever = INF
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", path)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = Vector3(0, FLOOR_TOP, 0)
	prop.call("configure_world", effects, null)
	await physics_frame
	for i in MAX_HITS:
		if not is_instance_valid(prop) or prop.collision_layer == 0:
			break
		prop.call("take_projectile_hit", 400.0, prop.global_position + Vector3(0, 0.4, 0), Vector3.UP, Vector3(0.3, 0.0, -1.0).normalized(), "GRENADE")
		await _step(effects, 2)
	# Settle, then shatter every piece again so the later stages are checked too.
	for round in FRAGMENT_ROUNDS:
		await _step(effects, int(0.6 * Engine.physics_ticks_per_second))
		for fragment in _fragments(effects):
			fragment.call("take_projectile_hit", 400.0, fragment.global_position, Vector3.UP, Vector3(0.3, 0.0, -1.0).normalized(), "GRENADE")
		await _step(effects, 1)
	await _step(effects, int(SETTLE_SECONDS * Engine.physics_ticks_per_second))
	var lowest := _lowest_ever
	var counted := 0
	var final_lowest := INF
	for fragment in _fragments(effects):
		final_lowest = minf(final_lowest, _lowest_point(fragment))
		counted += 1
	var ok := counted == 0 or (lowest >= FLOOR_TOP - TOLERANCE and final_lowest >= FLOOR_TOP - TOLERANCE)
	if not ok:
		failures += 1
	print("%s %s fragments=%d lowest_final=%.3f lowest_ever=%.3f" % [path.trim_prefix("res://models/objects/enviroments/"), "PASS" if ok else "FAIL", counted, final_lowest if counted > 0 else 0.0, lowest if counted > 0 else 0.0])
	if is_instance_valid(prop):
		prop.queue_free()
	effects.queue_free()
	await process_frame


# Advances physics and tracks the lowest point ever reached: a piece that tunnels may later be culled.
func _step(effects: Node, frames: int) -> void:
	for frame in frames:
		# Breakups are spread over frames by the destruction budget; let it finish, then step the new pieces once.
		var queue := effects.get_node_or_null("DestructionBudget")
		while queue != null and int(queue.call("pending")) > 0:
			await process_frame
		await physics_frame
		for fragment in _fragments(effects):
			_lowest_ever = minf(_lowest_ever, _lowest_point(fragment))


func _fragments(effects: Node) -> Array[RigidBody3D]:
	var found: Array[RigidBody3D] = []
	for child in effects.get_children():
		if child is RigidBody3D and child.is_in_group("fallen_environment_fragment") and not child.is_queued_for_deletion():
			found.append(child)
	return found


# Lowest world y over the collider box and every visual mesh box of a fragment.
func _lowest_point(fragment: RigidBody3D) -> float:
	var lowest := INF
	for child in fragment.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var size: Vector3 = ((child as CollisionShape3D).shape as BoxShape3D).size
			lowest = minf(lowest, _box_lowest(AABB(-size * 0.5, size), (child as Node3D).global_transform))
		elif child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			lowest = minf(lowest, _mesh_lowest(child as MeshInstance3D))
	return lowest


# Lowest world y of the real mesh vertices, so a tilted piece is not judged by its loose AABB corners.
func _mesh_lowest(instance: MeshInstance3D) -> float:
	var mesh := instance.mesh
	if not _vertices.has(mesh):
		_vertices[mesh] = mesh.get_faces()
	var xform := instance.global_transform
	var lowest := INF
	for vertex in _vertices[mesh] as PackedVector3Array:
		lowest = minf(lowest, (xform * vertex).y)
	return lowest


func _box_lowest(box: AABB, xform: Transform3D) -> float:
	var lowest := INF
	for corner in 8:
		lowest = minf(lowest, (xform * box.get_endpoint(corner)).y)
	return lowest


func _add_floor(stage: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	floor_body.position.y = FLOOR_TOP - 0.1
