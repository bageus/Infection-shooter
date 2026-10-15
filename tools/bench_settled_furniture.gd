extends SceneTree
## Reproducible wall-clock workload; Performance timing monitors are deliberately unused.
const MAP := preload("res://game/presentation/office_floor/public/base_office_layout.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SEARCH_BUDGET := preload("res://game/features/infected/public/chase_search_budget.gd")
var stage: Node3D
var bodies: Array[RigidBody3D] = []
var props: Array[RigidBody3D] = []
var target: Node3D
var enemies := 0
var warmup := 240
var tick := 0
var previous := 0
var times: Array[int] = []
var active_counts: Array[int] = []
var frozen_counts: Array[int] = []
var active_kickable := 0
var meshes := 0
var shadow_meshes := 0
var shadow_triangles := 0
var triangle_cache: Dictionary = {}
var candidates: Dictionary = {0.2: [0,0,0], 0.3: [0,0,0], 0.4: [0,0,0], 0.45: [0,0,0], 0.5: [0,0,0]}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemies="):
			enemies = int(arg.trim_prefix("--enemies="))
		if arg.begins_with("--warmup="):
			warmup = int(arg.trim_prefix("--warmup="))
	call_deferred("_setup")

func _setup() -> void:
	seed(7841)
	var loaded := Time.get_ticks_usec()
	stage = MAP.instantiate() as Node3D
	root.add_child(stage)
	# The authored layout excludes Main.tscn's floor body; reproduce that exact support.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 3
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80, .2, 60)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.1
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	_collect(stage)
	_inventory()
	target = Node3D.new()
	stage.add_child(target)
	target.position = Vector3(12, 1, 0)
	var budget := SEARCH_BUDGET.new()
	stage.add_child(budget)
	for index in enemies:
		var actor := HUNGER.instantiate() as CharacterBody3D
		actor.position = Vector3(-20 + (index % 10) * .85, 1, -10 + (index / 10) * .85)
		stage.add_child(actor)
		actor.call("set_target", target)
		actor.call("configure_chase_budget", budget)
	print(JSON.stringify({"inventory": true, "bodies": bodies.size(), "environment_props": props.size(),
		"visible_meshes": meshes, "shadow_meshes": shadow_meshes, "shadow_triangles": shadow_triangles,
		"threshold_candidates": candidates, "setup_ms": (Time.get_ticks_usec() - loaded) / 1000.0}))
	await physics_frame
	previous = Time.get_ticks_usec()
	physics_frame.connect(_step)

func _collect(node: Node) -> void:
	if node is RigidBody3D:
		bodies.append(node)
		if node.get("model_path") != null:
			props.append(node)
	for child in node.get_children():
		_collect(child)

func _visible_meshes(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is Node3D and not node.visible:
		return
	if node is MeshInstance3D and node.mesh != null and not bool(node.get_meta("planning_bounds_excluded", false)):
		found.append(node)
	for child in node.get_children():
		_visible_meshes(child, found)

func _triangles(mesh: Mesh) -> int:
	var id := mesh.get_instance_id()
	if triangle_cache.has(id):
		return int(triangle_cache[id])
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	triangle_cache[id] = total
	return total

func _inventory() -> void:
	for prop in props:
		var visible: Array[MeshInstance3D] = []
		_visible_meshes(prop.get_node_or_null("Visual"), visible)
		var bounds := AABB()
		var count := 0
		var triangles := 0
		for mesh in visible:
			var box: AABB = prop.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
			bounds = box if count == 0 else bounds.merge(box)
			count += 1
			meshes += 1
			if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_meshes += 1
				var shadow: Mesh = mesh.mesh.shadow_mesh if mesh.mesh.shadow_mesh != null else mesh.mesh
				var tris := _triangles(shadow)
				shadow_triangles += tris
				triangles += tris
		var extent := (bounds.size * prop.global_basis.get_scale().abs()).max_axis_index()
		var size := (bounds.size * prop.global_basis.get_scale().abs())[extent]
		for threshold: float in candidates:
			if size > 0.0 and size <= threshold and not str(prop.get("model_path")).contains("/01/"):
				candidates[threshold][0] += 1
				candidates[threshold][1] += count
				candidates[threshold][2] += triangles

func _step() -> void:
	var now := Time.get_ticks_usec()
	if tick > warmup:
		times.append(now - previous)
		var active := 0
		var frozen := 0
		active_kickable = 0
		for body in bodies:
			if not is_instance_valid(body):
				continue
			if body.freeze:
				frozen += 1
			elif not body.sleeping:
				active += 1
				if bool(body.get_meta("kickable_prop", false)):
					active_kickable += 1
		active_counts.append(active)
		frozen_counts.append(frozen)
	previous = now
	target.position.z = 3.0 * sin(float(tick) / 60.0)
	if times.size() == 239:
		_report()
	tick += 1

func _report() -> void:
	physics_frame.disconnect(_step)
	var total := 0
	for usec in times:
		total += usec
	times.sort()
	var active_models: Dictionary = {}
	for body in bodies:
		if is_instance_valid(body) and not body.freeze and not body.sleeping and not bool(body.get_meta("kickable_prop", false)):
			var model := str(body.get("model_path"))
			active_models[model.get_file()] = int(active_models.get(model.get_file(), 0)) + 1
	print(JSON.stringify({"active_non_kickable_models": active_models, "ticks": times.size(), "warmup": warmup, "enemies": enemies,
		"wall_mean_ms": float(total) / times.size() / 1000.0, "wall_p95_ms": times[int(times.size() * .95)] / 1000.0,
		"active_start": active_counts[0], "active_end": active_counts[-1],
		"active_kickable_end": active_kickable, "frozen_start": frozen_counts[0], "frozen_end": frozen_counts[-1]}))
	stage.free()
	await process_frame
	quit()
