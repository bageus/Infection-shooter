extends SceneTree
## Dust zone: scene builds, density levels, save/load fields, menu switch fades it out.
const DUST := preload("res://game/presentation/office_floor/public/dust_zone.gd")
const SCENE := preload("res://game/presentation/office_floor/public/props/dust_zone.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var zone := SCENE.instantiate()
	zone.call("set_density", 2) # before entering the tree, like a freshly placed zone
	root.add_child(zone)
	await process_frame
	_check(zone.get_child_count() == 3, "two layers and a marker")
	var material := (zone.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	_check(is_equal_approx(float(material.get_shader_parameter("density")), 1.0), "dense level reaches the shader")
	zone.call("set_density", 0)
	_check(is_equal_approx(float(material.get_shader_parameter("density")), 0.3) and int(zone.get_meta("planning_dust")) == 0, "light level")
	zone.call("set_density", 9)
	_check(zone.call("get_density") == 2, "level is clamped")
	var levels: Array = CATALOG.new().lighting_catalog.filter(func(entry): return entry.kind == "dust").map(func(entry): return entry.dust)
	_check(levels == [2, 1, 0], "palette offers dense, weak and light dust")
	_check(bool(PREFS.DEFAULTS.dust), "dust is on by default")
	DUST.set_enabled(self, false)
	for _i in 120:
		await process_frame
	_check(not (zone.get_child(0) as MeshInstance3D).visible, "switch off fades the layers out")
	DUST.set_enabled(self, true)
	for _i in 120:
		await process_frame
	_check((zone.get_child(0) as MeshInstance3D).visible and is_equal_approx(float(material.get_shader_parameter("fade")), 1.0), "switch on fades back in")
	print("run_dust_zone_tests: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
