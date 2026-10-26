extends SceneTree
const VIEW := preload("res://game/presentation/office_floor/public/baked_biomass_floor.gd")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const MAP := preload("res://game/bootstrap/app/planning_map_file.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const BAKE := preload("res://game/bootstrap/app/planning_biomass_bake.gd")
var failures := 0

class RejectedSave extends "res://game/bootstrap/app/planning_storage.gd":
	var capture_started := false
	func enforce_wall_fixtures() -> String: return ""
	func _prepare_save(_job: RefCounted = null) -> bool:
		var job := preload("res://game/bootstrap/app/planning_settle.gd").new()
		job.tick_limit = 1
		return await super._prepare_save(job)
	func _capture_save() -> Dictionary:
		capture_started = true
		return await super._capture_save()

class Objects extends Node:
	var session: Node
	var placed: Array = []
	var workstation_transforms := {}
	var player_spawn_defined := false

class Floor extends Node3D:
	var floor_size := Vector2(8, 8)
	var tile_y := 0.001
	var openings: Array[Rect2] = []
	func configure_surface_decals(_raw: Dictionary) -> void: pass
	func get_surface_decals() -> Dictionary: return {}

class Session extends Node3D:
	var active := false
	var host: Node3D
	var root: Node3D
	var storage: Variant

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_authored_cache()
	_signed_zero_signature()
	var records: Array = [{"scene": DECAL.resource_path, "blood_texture": "biomass_01", "blood_surface": "floor", "blood_attachment": {"owner": "", "mesh": ""}, "x": 2.0, "y": 0.0135, "z": 2.0, "scale_x": 2.0, "scale_z": 2.0, "rotation_y": 27.0}]
	var alive := func() -> bool: return true
	var progress := func(_text: String) -> void: pass
	var baker := VIEW.baker()
	var cache: Dictionary = await baker.build(records, Rect2(0, 0, 8, 8), 0.0135, self, alive, progress)
	_check(VIEW.valid(cache) and cache.pages.size() == 1, "Rotated scaled source bakes to one portable page")
	var session := Session.new()
	session.host = session
	session.root = Node3D.new()
	session.add_child(session.root)
	root.add_child(session)
	var piece := DECAL.instantiate()
	piece.call("configure_blood", "biomass_01", "floor")
	piece.call("set_floor_biomass_baked", true)
	session.root.add_child(piece)
	_check(piece.get("_visual") == null and piece.get("_fit") == null and not piece.is_processing(), "Baked cell loads without geometry, fusion job or process callback")
	BAKE.restore(session, cache)
	var view: Node3D = session.root.get_node("BakedFloorBiomass")
	_check(view.get_child_count() == 1 and not view.is_processing(), "Runtime page has one flat mesh and no callbacks")
	var image: Image = view.get("_images")[Vector2i.ZERO]
	var point := Vector3.INF
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.8:
				point = Vector3((x + 0.5) / 64.0, 0.0135, (y + 0.5) / 64.0)
				break
		if point.is_finite(): break
	_check(point.is_finite() and view.covers(point), "Footstep alpha matches raster page")
	_check(preload("res://game/presentation/office_floor/public/biomass_footstep_surface.gd").has_biomass_at(session.root, point), "Wet footsteps survive removing the original mesh")
	await _packed_scene(session, piece, cache)
	var data := {"version": 8, "objects": records, "floor_biomass_v1": cache}
	await _lighting_and_crop(records, alive, progress)
	var path := "user://biomass_bake_roundtrip.json"
	_check(not MAP.write(path, data).has("error"), "Map with page writes atomically")
	var read: Dictionary = MAP.read(path)
	_check(not read.has("error") and VIEW.valid(read.data.floor_biomass_v1), "Map reload reads saved PNG, without baking")
	var bad := cache.duplicate(true)
	bad.pages[0].png = "not a PNG"
	_check(not VIEW.valid(bad), "Malformed pixels are rejected before replacing a map")
	bad = cache.duplicate(true)
	bad.pages.append(bad.pages[0])
	_check(not VIEW.valid(bad), "Duplicate pages are rejected")
	BAKE.editing(session, true)
	_check(piece.get("_visual") != null and piece.is_processing() and not view.visible, "Planner restores editable relief cells")
	session.storage = {"authored_layout": {"objects": records}}
	view.cache.source_signature = BAKE.signature(records)
	BAKE.editing(session, false)
	_check(view.visible and piece.get("_visual") == null, "Unchanged saved map uses cache on exit")
	session.storage.authored_layout.objects = []
	BAKE.editing(session, false)
	_check(not view.visible and piece.get("_visual") != null, "Unsaved edits never display the stale cache")
	BAKE.restore(session, {})
	_check(not session.root.has_node("BakedFloorBiomass"), "Replacing map releases old pages")
	await _light_shadows()
	await _save_pipeline()
	session.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")
	print("Biomass floor bake tests: %d failures" % failures)
	quit(failures)


func _lighting_and_crop(records: Array, alive: Callable, progress: Callable) -> void:
	var black := func(_cell: Vector2i, _height: float) -> Image:
		return Image.create(4, 4, false, Image.FORMAT_RGB8)
	var builder := VIEW.baker()
	builder.exclusions.append(Rect2(1.9, 1.9, 0.2, 0.2))
	var result: Dictionary = await builder.build(records, Rect2(1.5, 1.5, 1, 1), 0.0135, self, alive, progress, black)
	_check(VIEW.valid(result), "A light bake produces valid pages")
	var page := Image.new()
	_check(page.load_png_from_buffer(Marshalls.base64_to_raw(result.pages[0].png)) == OK, "Encoded page decodes independently")
	var opaque := 0
	for y in 512:
		for x in 512:
			var pixel := page.get_pixel(x, y)
			if pixel.a > 0.1:
				opaque += 1
				_check(pixel.r == 0 and pixel.g == 0 and pixel.b == 0, "Lighting is multiplied once into saved RGB")
				var position := Vector2((x + 0.5) / 64.0, (y + 0.5) / 64.0)
				_check(Rect2(1.5, 1.5, 1, 1).has_point(position), "Raster stays within floor bounds")
				_check(not Rect2(1.9, 1.9, 0.2, 0.2).has_point(position), "Stair opening stays empty")
	_check(opaque > 0, "A clipped page retains biomass")


func _packed_scene(session: Node3D, piece: Node3D, cache: Dictionary) -> void:
	piece.set_meta("planning_scene_path", DECAL.resource_path)
	var exporter := preload("res://game/bootstrap/app/planning_scene_bake.gd").new(preload("res://game/bootstrap/app/planning_catalog.gd").new())
	exporter.biomass_cache = cache
	var label := Label.new()
	session.add_child(label)
	var path := "user://biomass_bake_scene.tscn"
	_check(await exporter.save_async([piece], path, session, label) == OK, "Save Layout scene embeds the same page cache")
	var resource := load(path) as PackedScene
	var loaded := resource.instantiate()
	session.add_child(loaded)
	_check(loaded.has_node("BakedFloorBiomass"), "Packed scene restores texture pages")
	var source: Node = loaded.get_child(0)
	_check(not source.is_processing() and source.get("_visual") == null, "Packed scene source loads without per-piece rendering")
	loaded.free()
	label.free()
	DirAccess.remove_absolute(path)


func _save_pipeline() -> void:
	var session := Session.new()
	session.active = true
	session.host = session
	session.root = Node3D.new()
	session.add_child(session.root)
	root.add_child(session)
	var floor_view := Floor.new()
	floor_view.name = "Floor"
	session.add_child(floor_view)
	var objects := Objects.new()
	objects.session = session
	session.add_child(objects)
	var storage := preload("res://game/bootstrap/app/planning_storage.gd").new()
	storage.session = session
	storage.objects = objects
	var status := Label.new()
	session.add_child(status)
	storage.controls = {"status": status}
	var piece := DECAL.instantiate()
	piece.call("configure_blood", "biomass_02", "floor")
	piece.position = Vector3(2, 0.0135, 2)
	piece.set_meta("planning_scene_path", DECAL.resource_path)
	session.root.add_child(piece)
	objects.placed = [piece]
	var data: Dictionary = await storage._capture_save()
	_check(data.has("floor_biomass_v1") and VIEW.valid(data.floor_biomass_v1), "Real save capture invokes baking and attaches cache")
	_check(data.floor_biomass_v1.source_signature == BAKE.signature(JSON.parse_string(JSON.stringify(data.objects))), "Fingerprint survives JSON integer/float conversion")
	var before: String = data.floor_biomass_v1.pages[0].png
	piece.position.x += 1.0
	var changed: Dictionary = await storage._capture_save()
	_check(changed.floor_biomass_v1.pages[0].png != before, "Save after a planner edit replaces baked pixels")
	_check(piece.is_processing(), "Saving while editing retains editable source")
	objects.placed.clear()
	piece.free()
	var falling := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	falling.add_child(shape)
	falling.position = Vector3(2, 10, 2)
	falling.set_meta("planning_scene_path", DECAL.resource_path)
	session.root.add_child(falling)
	objects.placed = [falling]
	paused = true
	var rejected := RejectedSave.new()
	rejected.session = session
	rejected.objects = objects
	rejected.controls = {"status": status}
	var path := rejected.SAVE_PATH
	_check(not MAP.write(path, {"version": 8, "objects": []}).has("error"), "Prior save exists before failed preparation")
	var previous := FileAccess.get_file_as_string(path)
	await rejected.save_layout()
	_check(not rejected.capture_started and not rejected.map_loading, "Unsettled physics prevents capture/bake/write and releases the UI")
	_check(status.text.begins_with("NOT SAVED") and not falling.has_meta("planning_settled_transform"), "Failure is shown instead of a false SAVED status")
	_check(FileAccess.get_file_as_string(path) == previous and not FileAccess.file_exists(path + ".bak"), "Prior save stays byte-identical, including backup, on timeout")
	paused = false
	session.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".bak")


func _light_shadows() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var roof := StaticBody3D.new()
	roof.position = Vector3(2, 1.5, 2)
	roof.add_to_group("camera_occluder")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(4, 0.1, 4)
	roof.add_child(shape)
	stage.add_child(roof)
	await physics_frame
	var sampler := preload("res://game/bootstrap/app/planning_biomass_light_bake.gd").new()
	sampler.tree = self
	sampler.world = stage.get_world_3d()
	sampler.alive = func() -> bool: return is_instance_valid(stage)
	sampler.ambient = Color(0, 0, 0)
	var lamp := {"position": Vector3(2, 3, 2), "direction": Vector3.DOWN, "color": Color.RED, "energy": 2.0, "range": 6.0, "angle": 0.7, "cone": 1.0, "attenuation": 1.0, "shadows": false}
	sampler.lamps = [lamp]
	roof.remove_from_group("camera_occluder")
	var lit: Image = await sampler.sample(Vector2i.ZERO, 0.0135)
	_check(lit.get_pixel(8, 8).r > 0.5 and lit.get_pixel(8, 8).g == 0, "Authored light color/energy are baked")
	roof.add_to_group("camera_occluder")
	var shadowed: Image = await sampler.sample(Vector2i.ZERO, 0.0135)
	_check(shadowed.get_pixel(8, 8).r == 0, "Structural shadow is baked even with legacy dynamic shadows=false")
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	var arrays := plane.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for index in vertices.size():
		_check(uvs[index].is_equal_approx(Vector2(vertices[index].x / 8 + 0.5, vertices[index].z / 8 + 0.5)), "Page UV orientation matches footstep/query coordinates")
	stage.free()


func _signed_zero_signature() -> void:
	# Construct the sign at runtime: JSON intentionally erases IEEE negative zero.
	var negative_zero := -absf(float("0"))
	var records: Array = [{"scene": DECAL.resource_path, "blood_texture": "biomass_01", "blood_surface": "floor", "x": 2.0, "rotation_x": negative_zero, "blood_normal": [negative_zero, 1.0, negative_zero]}]
	var signature := BAKE.signature(records)
	_check(signature == BAKE.signature(JSON.parse_string(JSON.stringify(records))), "Signed zero fingerprint survives JSON save/load")
	var positive: Array = records.duplicate(true)
	positive[0].rotation_x = absf(negative_zero)
	positive[0].blood_normal = [absf(negative_zero), 1.0, absf(negative_zero)]
	_check(signature == BAKE.signature(positive), "Positive and negative zero describe the same baked surface")
	positive[0].x += 0.25
	_check(signature != BAKE.signature(positive), "A real placement edit still invalidates the cache")


func _authored_cache() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/presentation/office_floor/public/base_office_map.json"))
	var cache: Dictionary = data.get("floor_biomass_v1", {})
	_check(VIEW.valid(cache), "Authored map retains valid baked biomass pages")
	_check(str(cache.get("source_signature", "")) == BAKE.signature(data.objects), "Authored bake matches current map placements")
	var packed := load("res://game/presentation/office_floor/public/base_office_layout.tscn") as PackedScene
	var state := packed.get_state()
	var scene_cache: Dictionary = {}
	for index in state.get_node_property_count(0):
		if state.get_node_property_name(0, index) == &"metadata/floor_biomass_v1":
			scene_cache = state.get_node_property_value(0, index)
	_check(VIEW.valid(scene_cache) and scene_cache.get("source_signature", "") == cache.get("source_signature", ""), "Baked scene and JSON carry the same current source signature")
	var scene_pages: Array = scene_cache.get("pages", [])
	var json_pages: Array = cache.get("pages", [])
	_check(scene_pages.size() == json_pages.size(), "Scene and JSON retain the same number of baked pages")
	for index in mini(scene_pages.size(), json_pages.size()):
		var a: Dictionary = scene_pages[index]
		var b: Dictionary = json_pages[index]
		_check(int(a.x) == int(b.x) and int(a.z) == int(b.z) and str(a.png) == str(b.png), "Scene and JSON retain identical PNG bytes/cells despite JSON numeric types")
