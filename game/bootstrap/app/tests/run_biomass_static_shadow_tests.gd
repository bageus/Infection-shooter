extends SceneTree
## Static bake pixels are independent of dynamic shadow preferences and quality.
const SAMPLER := preload("res://game/bootstrap/app/planning_biomass_light_bake.gd")
const LAMP := preload("res://game/presentation/office_floor/public/props/planner_light.tscn")
const SHADOWS := preload("res://game/bootstrap/app/menu/shadow_quality.gd")
const VIEW := preload("res://game/presentation/office_floor/public/baked_biomass_floor.gd")
var failures := 0
var host: Node3D
var controller: Controller
var obstacle: StaticBody3D

class Controller extends Node:
	var local_lights_enabled := true
	var shadows_allowed := true
	var world_environment: WorldEnvironment
	func set_shadows_allowed(value: bool) -> void: shadows_allowed = value


func _initialize() -> void: call_deferred("_run")


func _run() -> void:
	host = Node3D.new()
	root.add_child(host)
	current_scene = host
	controller = Controller.new()
	controller.name = "PlanningLighting"
	host.add_child(controller)
	obstacle = StaticBody3D.new()
	obstacle.position = Vector3(4, 2, 4)
	obstacle.add_to_group("camera_occluder")
	host.add_child(obstacle)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 0.2, 3)
	collision.shape = box
	obstacle.add_child(collision)
	await physics_frame
	await physics_frame
	for kind in ["point", "linear", "rectangle", "sun"]:
		await _source(kind)
	current_scene = null
	host.free()
	await process_frame
	await process_frame
	print("Biomass static shadow tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _sample() -> Image:
	var sampler := SAMPLER.new()
	sampler.configure(host, func() -> bool: return is_instance_valid(host))
	return await sampler.sample(Vector2i.ZERO, 0.0)


func _source(kind: String) -> void:
	var source: Node3D
	if kind == "sun":
		var sun := DirectionalLight3D.new()
		sun.name = "GlobalOverheadLight"
		sun.rotation_degrees.x = -90
		sun.shadow_enabled = true
		source = sun
	else:
		source = LAMP.instantiate()
		source.position = Vector3(4, 4, 4)
		source.call("configure_fixture", kind, false)
	host.add_child(source)
	if kind != "sun": source.call("set_local_lighting_enabled", true)
	SHADOWS.apply(self, true, 2)
	var reference := await _sample()
	_check(reference.get_pixel(16, 16).r < 0.3, "Structural occluder casts a baked shadow: " + kind)
	for enabled in [false, true]:
		for level in SHADOWS.level_count():
			SHADOWS.apply(self, enabled, level)
			var actual := await _sample()
			_check(actual.get_data() == reference.get_data(), "Whole grid preserves static shadows (%s, dynamic=%s, quality=%d)" % [kind, enabled, level])
			_check(controller.shadows_allowed == enabled, "Baking does not enable dynamic shadows")
			if kind == "sun":
				var distance := float(SHADOWS.LEVELS[level].distance) if enabled else SHADOWS.OFF_DISTANCE
				_check(is_equal_approx(source.get("directional_shadow_max_distance"), distance), "Baking leaves runtime sun range unchanged")
	# Unrelated props must not become permanent structural shadows.
	obstacle.remove_from_group("camera_occluder")
	var clear := await _sample()
	_check(clear.get_pixel(16, 16).r > reference.get_pixel(16, 16).r + 0.05, "Non-structural collider is skipped: " + kind)
	obstacle.add_to_group("camera_occluder")
	if kind == "point": await _portable_pages(reference)
	source.free()


func _portable_pages(reference: Image) -> void:
	var records: Array = [{"blood_texture": "biomass_01", "x": 4.0, "z": 4.0}]
	var caches: Array[Dictionary] = []
	for enabled in [true, false]:
		SHADOWS.apply(self, enabled, 0)
		var sampler := SAMPLER.new()
		sampler.configure(host, func() -> bool: return true)
		var builder := VIEW.baker()
		var cache: Dictionary = await builder.build(records, Rect2(0, 0, 8, 8), 0.0, self,
			func() -> bool: return true, func(_text: String) -> void: pass, sampler.sample)
		_check(VIEW.valid(cache) and cache.pages.size() == 1, "Real shaded biomass raster produces a portable PNG")
		caches.append(cache)
	_check(caches[0] == caches[1], "Actual PNG pages match with dynamic shadows on/off")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(caches[0]))
	_check(VIEW.valid(restored), "Saved shadow page survives JSON roundtrip")
	var view := VIEW.new()
	view.cache = restored
	host.add_child(view)
	_check(view.get_child_count() == 1 and not view.is_processing(), "Runtime loads ready pixels without a bake callback")
	var mesh := view.get_child(0) as MeshInstance3D
	var material := mesh.material_override as StandardMaterial3D
	_check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Cached shadow does not need runtime lighting or shadow passes")
	var pixels := material.albedo_texture.get_image().get_data()
	SHADOWS.apply(self, false, 3)
	_check(material.albedo_texture.get_image().get_data() == pixels, "Loading under another shadow profile retains saved pixels")
	_check(reference.get_pixel(16, 16).r < 0.3, "Reference page includes the structural shadow")
	view.free()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
