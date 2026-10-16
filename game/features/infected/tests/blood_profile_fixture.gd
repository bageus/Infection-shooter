extends RefCounted
## Measurement fixture, not AI/combat simulation; bodies keep their real geometry/leases.
const BAKE := preload("res://game/features/infected/body_blood_bake.gd")
const SCENES := [
	preload("res://game/features/infected/public/infected_hunger.tscn"),
	preload("res://game/features/infected/public/infected_revenant.tscn"),
	preload("res://game/features/infected/public/infected_brute.tscn"),
	preload("res://game/features/infected/public/infected_titan.tscn"),
	preload("res://game/features/infected/public/infected_colossus.tscn"),
	preload("res://game/features/infected/public/infected_horde.tscn"),
]
# 54/18/6/6/3/3 of the six scenes at count90; small smoke fixtures still include Hunger.
const TYPES := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 4, 5]
var stage: Node3D
var bodies: Array[Node] = []
var weapon := "SHOTGUN"
var mode := "full"
var paint_usec := 0
var init_usec := 0
var upload_usec := 0
var updates := 0
var blank_updates := 0
var triangles := 0
var near_triangles := 0


func setup(tree: SceneTree, count: int) -> void:
	stage = Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	tree.root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("11171b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.position = Vector3(14, 30, 35)
	camera.look_at(Vector3(14, 1, 12))
	camera.current = true
	for index in count:
		var actor: Node3D = SCENES[TYPES[index % TYPES.size()]].instantiate()
		stage.add_child(actor)
		actor.position = Vector3(index % 10 * 3, 1, index / 10 * 3)
		var parts: Node = actor.get("_parts")
		assert(parts != null and parts.enabled, "Profile requires supported live body geometry")
		bodies.append(parts)


func event(actor: int, ordinal: int) -> Dictionary:
	var parts := bodies[actor]
	var surface: Dictionary = parts._entries[0].data.surfaces[0]
	var index: int = ((ordinal * 47 + actor * 17) % int(surface.indices.size() / 3)) * 3
	var center: Vector3 = (surface.vertices[surface.indices[index]] + surface.vertices[surface.indices[index + 1]] + surface.vertices[surface.indices[index + 2]]) / 3.0
	return {"body": actor, "center": center, "radius": parts.wound_radius(weapon) / maxf(parts.world_scale, .01)}


func apply(hit: Dictionary) -> int:
	var parts := bodies[int(hit.body)]
	var started := Time.get_ticks_usec()
	if mode == "full":
		parts.add_rest_wound(hit.center, hit.radius)
	elif mode == "stages":
		_stages(parts, hit.center, hit.radius)
	else:
		_scan(parts, hit.center, hit.radius)
	return Time.get_ticks_usec() - started


func _stages(parts: Node, center: Vector3, radius: float) -> void:
	for entry: Dictionary in parts._entries:
		if not entry.has("masks"):
			var started := Time.get_ticks_usec()
			parts._create_masks(entry)
			init_usec += Time.get_ticks_usec() - started
			blank_updates += entry.masks.size()
		for surface in entry.masks.size():
			var image: Image = entry.masks[surface].image
			var started := Time.get_ticks_usec()
			var changed := BAKE.paint(image, entry.data.surfaces[surface], center, radius)
			paint_usec += Time.get_ticks_usec() - started
			if changed:
				started = Time.get_ticks_usec()
				entry.lease.page.textures[surface].update_layer(image, entry.lease.layer)
				upload_usec += Time.get_ticks_usec() - started
				updates += 1


func _scan(parts: Node, center: Vector3, radius: float) -> void:
	for entry: Dictionary in parts._entries:
		for surface: Dictionary in entry.data.surfaces:
			var vertices: PackedVector3Array = surface.vertices
			var indices: PackedInt32Array = surface.indices
			for index in range(0, indices.size() - 2, 3):
				triangles += 1
				if BAKE._near(vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]], center, radius * BAKE.SPREAD_MARGIN):
					near_triangles += 1


func counters() -> Dictionary:
	if mode == "full":
		return {"instrumented": false}
	return {"init_usec": init_usec, "paint_usec": paint_usec, "update_layer_cpu_usec": upload_usec,
		"paint_updates": updates, "blank_updates": blank_updates,
		"triangles_scanned": triangles, "near_triangles": near_triangles}


func reset_counters() -> void:
	paint_usec = 0
	init_usec = 0
	upload_usec = 0
	updates = 0
	blank_updates = 0
	triangles = 0
	near_triangles = 0


func topology() -> Array[Dictionary]:
	var unique := {}
	for parts in bodies:
		var actor: Node = parts.get_parent()
		var path: String = actor.scene_file_path
		if unique.has(path):
			unique[path].bodies += 1
			continue
		var surfaces := 0
		var triangles_count := 0
		for entry: Dictionary in parts._entries:
			for surface: Dictionary in entry.data.surfaces:
				surfaces += 1
				triangles_count += surface.indices.size() / 3
		unique[path] = {"scene": path, "bodies": 1, "surfaces": surfaces, "triangles": triangles_count, "world_scale": parts.world_scale}
	var result: Array[Dictionary] = []
	result.assign(unique.values())
	return result


func masks(capture_dir: String = "") -> Dictionary:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var bytes := 0
	var count := 0
	var pages := {}
	for index in bodies.size():
		for entry: Dictionary in bodies[index]._entries:
			if not entry.has("masks"):
				continue
			var page: RefCounted = entry.lease.page
			pages[page.get_instance_id()] = page.layer_count * entry.masks.size() * BAKE.SIZE * BAKE.SIZE * 2
			for surface in entry.masks.size():
				var image: Image = entry.masks[surface].image
				var data := image.get_data()
				hash.update(data)
				bytes += data.size()
				count += 1
				if not capture_dir.is_empty() and index in [0, bodies.size() - 1]:
					var preview := image.duplicate()
					preview.convert(Image.FORMAT_RGB8)
					assert(preview.save_png(capture_dir.path_join("body_%d_surface_%d.png" % [index, surface])) == OK)
	var nominal := 0
	for size: int in pages.values():
		nominal += size
	return {"sha256": hash.finish().hex_encode(), "cpu_image_bytes": bytes, "masks": count,
		"pages": pages.size(), "nominal_page_payload_bytes": nominal}
