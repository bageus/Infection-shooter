extends SceneTree
## surface_decor_v1 (ADR-0033): conference table finish, document print on the
## top paper sheet and 0-3 sticky notes along monitor edges.

const DECOR := preload("res://game/presentation/office_floor/office_surface_decor.gd")
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const PAPER := preload("res://game/presentation/office_floor/public/props/paper_prop.tscn")
const MODELS := "res://models/objects/enviroments/"
var failures := 0
var stage: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	_test_table()
	for model: String in DECOR.PAPER_MODELS:
		_test_paper(model)
	_test_document_variety()
	_test_stickers()
	_test_untouched_models()
	stage.queue_free()
	await process_frame
	await process_frame
	print("Surface decor tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _spawn(path: String, display_seed: int = 0) -> Node3D:
	var prop := (PAPER if "paper" in path or "office_file" in path else PROP).instantiate() as Node3D
	prop.set("model_path", path)
	if display_seed != 0:
		prop.call("configure_display", {"power": "off", "content": "static", "seed": display_seed})
	stage.add_child(prop)
	prop.set("freeze", true)
	return prop


func _test_table() -> void:
	var table := _spawn(MODELS + "07/07_table_longest.glb")
	var visual := table.get_node("Visual") as Node3D
	var top := visual.find_child("Top", true, false) as MeshInstance3D
	var leg := visual.find_child("Leg_BL", true, false) as MeshInstance3D
	var intact := visual.find_child("Intact", true, false)
	while intact != null and not intact is MeshInstance3D:
		intact = intact.find_child("Intact", false, false)
	_check(top != null and top.get_surface_override_material(0) == DECOR.material("wood"), "Table top is chocolate wood")
	_check(leg != null and leg.get_surface_override_material(0) == DECOR.material("graphite"), "Table legs are graphite")
	var intact_mesh := intact as MeshInstance3D
	var finishes := {}
	if intact_mesh != null:
		for surface in intact_mesh.get_surface_override_material_count():
			finishes[intact_mesh.get_surface_override_material(surface)] = true
	_check(finishes.has(DECOR.material("wood")) and finishes.has(DECOR.material("graphite")), "Intact table carries both finishes")
	_check(DECOR.material("wood").albedo_texture != null and DECOR.material("wood").uv1_triplanar, "Wood finish is a textured triplanar material")
	# Fragments copy per-surface overrides so broken pieces keep the finish.
	var piece := DAMAGE.spawn_piece(table, top, null, 0, 0, Vector3.FORWARD, top.global_position)
	if piece != null:
		var copy := piece.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_check(copy.get_surface_override_material(0) == DECOR.material("wood"), "Table fragment keeps the wood finish")
		piece.free()
	table.free()


func _test_paper(model: String) -> void:
	var paper := _spawn(MODELS + "09/" + model)
	var visual := paper.get_node("Visual") as Node3D
	var prints := visual.find_children("DocumentPrint", "MeshInstance3D", false, false)
	_check(prints.size() == 1, "%s gets exactly one document print" % model)
	if prints.size() == 1:
		var overlay := prints[0] as MeshInstance3D
		var top := -INF
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh != overlay and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > 0.000000000001:
				top = maxf(top, (visual.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()).end.y)
		var arrays := overlay.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var highest := -INF
		var lowest := INF
		for vertex in vertices:
			highest = maxf(highest, vertex.y)
			lowest = minf(lowest, vertex.y)
		_check(highest <= top + 0.004, "%s print lies on the sheet, not above it" % model)
		_check(lowest > 0.0, "%s print stays above the base" % model)
		var inside := true
		for uv in uvs:
			inside = inside and uv.x >= 0.0 and uv.y >= 0.0 and uv.x <= 1.0 and uv.y <= 1.0
		_check(inside, "%s print samples inside the atlas" % model)
		_check(overlay.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s print casts no shadow" % model)
	paper.free()


func _test_document_variety() -> void:
	var paper := _spawn(MODELS + "09/09_paper_stack.glb")
	var visual := paper.get_node("Visual") as Node3D
	for overlay in visual.find_children("DocumentPrint", "MeshInstance3D", false, false):
		overlay.free()
	var seen := {}
	for seed_value in range(12):
		var overlay := DECOR.print_document(visual, seed_value)
		var arrays := overlay.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var corner: Vector3 = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
		seen["%.3f %.3f %d" % [uvs[0].x, uvs[0].y, signi(int(corner.z * 1000.0))]] = true
		overlay.free()
	_check(seen.size() == 12, "Six documents in two orientations are all reachable")
	paper.free()


func _test_stickers() -> void:
	var counts := {}
	for display_seed in range(1, 41):
		var monitor := _spawn(MODELS + "05/05_monitor2_destructible.glb", display_seed)
		var visual := monitor.get_node("Visual") as Node3D
		var stickers := visual.find_children("Sticker*", "MeshInstance3D", false, false)
		counts[stickers.size()] = true
		_check(stickers.size() <= DECOR.MAX_STICKERS, "No more than three stickers per monitor")
		var display := visual.get_node("Display")
		var profile: Dictionary = (display.get("screens") as Array)[0]["profile"]
		var normal := Vector3(float(profile["normal"][0]), float(profile["normal"][1]), float(profile["normal"][2]))
		var center := Vector3(float(profile["center"][0]), float(profile["center"][1]), float(profile["center"][2]))
		var size := Vector2(float(profile["size"][0]), float(profile["size"][1]))
		var centers: Array[Vector3] = []
		for node in stickers:
			var vertices: PackedVector3Array = (node as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var middle := (vertices[0] + vertices[3]) * 0.5
			centers.append(middle)
			_check((middle - center).dot(normal) > 0.0, "Sticker sits in front of the screen plane")
			var planar := (middle - center) - normal * (middle - center).dot(normal)
			var near_edge := absf(planar.x) > size.x * 0.25 or absf(planar.y) > size.y * 0.35
			_check(near_edge, "Sticker is placed along an edge, not mid-screen")
		for i in centers.size():
			for j in range(i + 1, centers.size()):
				_check(centers[i].distance_to(centers[j]) > size.x * 0.1, "Stickers use distinct slots")
		# The display seed is persisted, so the same monitor keeps its stickers.
		var again := _spawn(MODELS + "05/05_monitor2_destructible.glb", display_seed)
		_check((again.get_node("Visual") as Node3D).find_children("Sticker*", "MeshInstance3D", false, false).size() == stickers.size(),
			"Stickers are stable for a display seed")
		again.free()
		monitor.free()
	_check(counts.size() == 4, "Monitors get 0, 1, 2 and 3 stickers across seeds")
	var server := _spawn(MODELS + "05/05_monitor3_server_destructible.glb", 7)
	_check(server.get_node("Visual").find_children("DocumentPrint", "", false, false).is_empty(), "Monitors get no documents")
	server.free()


func _test_untouched_models() -> void:
	for path in [MODELS + "05/05_laptop_destructible.glb", MODELS + "09/09_paper_A4_heavily_crumpled.glb", MODELS + "07/07_table_square.glb"]:
		var prop := _spawn(path, 5 if "laptop" in path else 0)
		var visual := prop.get_node("Visual") as Node3D
		var added := visual.find_children("Sticker*", "", false, false).size() + visual.find_children("DocumentPrint", "", false, false).size()
		_check(added == 0, "%s is not decorated" % path.get_file())
		prop.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAILED: " + message)
