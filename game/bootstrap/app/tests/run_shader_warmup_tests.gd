extends SceneTree
## Mission start draws every spatial shader once and then removes the quads.
const WARMUP := preload("res://game/bootstrap/app/shader_warmup.gd")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths := WARMUP.spatial_shader_paths()
	_check(paths.size() >= 10, "Project spatial shaders are found in every module")
	_check(Array(paths).all(func(path: String) -> bool: return (load(path) as Shader).get_mode() == Shader.MODE_SPATIAL), "Only spatial shaders are warmed")
	var app := MAIN.instantiate()
	root.add_child(app)
	current_scene = app
	var camera := (app.get("player") as Node).get("camera") as Camera3D
	var warmup := camera.get_node_or_null("ShaderWarmup")
	_check(warmup != null and warmup.get_child_count() == paths.size() + 2, "One quad per spatial shader plus the two runtime cull variants under the camera")
	var walls := preload("res://game/bootstrap/app/occlusion_wall_materials.gd")
	_check(walls.shader_for_cull(BaseMaterial3D.CULL_DISABLED) == walls.shader_for_cull(BaseMaterial3D.CULL_DISABLED) and walls.shader_for_cull(BaseMaterial3D.CULL_DISABLED) != walls.shader_for_cull(BaseMaterial3D.CULL_FRONT), "Cull variants are built once and shared, so the warm-up compiles the shaders walls use")
	var hit_viewport := app.get_node_or_null("HitEffectWarmup") as SubViewport
	var hit_effects := hit_viewport.get_node_or_null("HitEffects") if hit_viewport != null else null
	_check(hit_effects != null and hit_effects.get("effect_count") >= 8, "Hit effects (sparks, smoke, paper, dust, sheets, water) play once in a hidden viewport")
	_check(hit_effects != null and hit_effects.get_node_or_null("ExtinguisherHitFx/Nozzle/Jet") != null and (hit_effects.get_node("ExtinguisherHitFx/Nozzle/Jet") as GPUParticles3D).emitting, "The extinguisher powder jet plays in the hidden viewport")
	_check(hit_effects != null and hit_effects.get_children().any(func(n: Node) -> bool: return n.get_script() != null and str(n.get_script().resource_path).ends_with("extinguisher_burst.gd")), "The extinguisher rupture burst plays silently in the hidden viewport")
	var blast := hit_effects.get_node_or_null("GrenadeExplosionVfx") if hit_effects != null else null
	_check(blast != null and blast.get("muted") == true and blast.get_node("ImpactLight") != null, "A silent grenade blast (particles, smoke, light) plays in the hidden viewport")
	for i in 8:
		await process_frame
	_check(app.get_node_or_null("HitEffectWarmup") == null, "Hidden hit-effect viewport is freed after a few frames")
	_check(camera.get_node_or_null("ShaderWarmup") == null, "Warm-up quads are freed after a few frames")
	app.queue_free()
	await process_frame
	print("Shader warmup tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
