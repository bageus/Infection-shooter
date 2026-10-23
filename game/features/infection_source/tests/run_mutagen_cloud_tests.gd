extends SceneTree
## Procedural smoke lifecycle, bounded layers and absorption regression checks.

const CLOUD := preload("res://game/features/infection_source/public/mutagen_cloud.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var first := _spawn(stage, Vector3.ZERO, 3.0)
	var second := _spawn(stage, Vector3(10, 0, 0), 3.0)
	await physics_frame
	first.call("activate")
	second.call("activate")
	var puffs := (first.get_node("Visual") as MultiMeshInstance3D).multimesh
	var range_limits: Vector2i = first.get("puff_count_range")
	_expect(puffs != null and puffs.instance_count >= range_limits.x and puffs.instance_count <= range_limits.y, "A cloud is built from several gas puffs.")
	var variants := {}
	var spins := {}
	var recorded: Array = first.get("_puffs")
	_expect(recorded.size() == puffs.instance_count, "Every puff is described.")
	for data in recorded:
		variants[int(round(data.r * 12.0))] = true
		spins[signf(data.b)] = true
		_expect(data.r >= 0.0 and data.r < 1.0, "Puff variant decorrelates procedural noise.")
	_expect(variants.size() == mini(puffs.instance_count, 12), "Every puff shows a different gas variant (%s of %d)." % [variants.keys(), puffs.instance_count])
	_expect(spins.size() >= 1, "Puffs spin.")
	_expect(_layout(first) != _layout(second), "Two clouds never look the same.")
	var haze := first.get_node("GroundHaze") as MultiMeshInstance3D
	_expect(haze.multimesh != null and haze.multimesh.instance_count == 1, "Low billboards merge into the gas without a flat floor reflection.")
	var material := (first.get_node("Visual") as GeometryInstance3D).material_override as ShaderMaterial
	_expect(material != null, "The cloud uses a procedural smoke material.")
	var uniforms := material.shader.get_shader_uniform_list().map(func(entry: Dictionary) -> String: return str(entry["name"]))
	_expect("atlas_a" not in uniforms and "atlas_b" not in uniforms and "flow_speed" in uniforms, "Smoke is animated without PNG sprite samplers.")
	_expect(bool(material.get_shader_parameter("wall_mask_enabled")), "Walls still clip the gas.")
	_expect(not (first.get_node("Spores") as GPUParticles3D).emitting, "Smoke activation avoids a separate GPU particle simulation.")
	_expect(puffs.instance_count + haze.multimesh.instance_count <= 5, "Transparent layers stay within the smoke budget.")
	var forever := _spawn(stage, Vector3(20, 0, 0), 14.0)
	forever.set("permanent", true)
	forever.call("activate")
	_expect(float(((forever.get_node("Visual") as GeometryInstance3D).material_override as ShaderMaterial).get_shader_parameter(&"looping")) > 0.5, "A permanent cloud loops its puffs.")
	for layer in ["Visual", "GroundHaze"]:
		var shader := ((forever.get_node(layer) as GeometryInstance3D).material_override as ShaderMaterial).shader
		_expect(not shader.code.contains("instance uniform"), "Cloud %s takes no instance-uniform slot (256-object renderer limit)." % layer)
	_check_refused_mutagen_stays(stage)
	await _check_overlapping_clouds_heal_once(stage)
	var depleted := [false]
	first.connect("depleted", func() -> void: depleted[0] = true)
	await create_timer(1.0).timeout
	var progress := float(((first.get_node("Visual") as GeometryInstance3D).material_override as ShaderMaterial).get_shader_parameter(&"progress"))
	_expect(progress > 0.2 and progress < 0.6, "Cloud age drives the shader (%.2f)." % progress)
	_expect(is_equal_approx(progress, float((haze.material_override as ShaderMaterial).get_shader_parameter(&"progress"))), "Haze ages with the cloud.")
	await create_timer(1.0).timeout
	_expect(not (first.get_node("Spores") as GPUParticles3D).emitting, "Spores stop as the cloud thins out.")
	await create_timer(1.3).timeout
	_expect(depleted[0] and not first.visible, "The death cloud dissipates and reports it.")
	_expect(forever.visible, "The permanent cloud stays.")
	stage.queue_free()
	await process_frame
	print("Mutagen cloud tests: %d failure(s)." % failures)
	quit(failures)


class Absorber extends Node:
	var accepts := true
	func absorb_mutagen(seconds: float) -> float:
		return seconds * 5.0 if accepts else 0.0


# During loss of control the infection takes no mutagen; the cloud keeps it
# for when control returns instead of draining for nothing.
func _check_refused_mutagen_stays(stage: Node3D) -> void:
	var cloud := _spawn(stage, Vector3(30, 0, 0), 14.0)
	cloud.call("activate")
	var body := Absorber.new()
	stage.add_child(body)
	var full := float(cloud.get("_absorption_remaining"))
	body.accepts = false
	cloud.call("_feed", body, 0.5)
	_expect(is_equal_approx(float(cloud.get("_absorption_remaining")), full), "A cloud keeps its mutagen while the player cannot absorb it.")
	body.accepts = true
	cloud.call("_feed", body, 0.5)
	_expect(is_equal_approx(float(cloud.get("_absorption_remaining")), full - 0.5), "Absorbed mutagen is spent from the cloud.")
	body.queue_free()
	cloud.queue_free()


class Visitor extends CharacterBody3D:
	var heal_calls := 0

	func _ready() -> void:
		var shape := CollisionShape3D.new()
		shape.shape = SphereShape3D.new()
		add_child(shape)

	func absorb_mutagen(_seconds: float) -> float:
		return 0.0

	func on_mutagen_cloud(_delta: float) -> void:
		heal_calls += 1


# Two clouds over one body still deliver one Devourer heal per physics frame.
func _check_overlapping_clouds_heal_once(stage: Node3D) -> void:
	var at := Vector3(40, 0, 0)
	var first := _spawn(stage, at, 14.0)
	var second := _spawn(stage, at, 14.0)
	first.set("heals_visitors", true)
	second.set("heals_visitors", true)
	first.call("activate")
	second.call("activate")
	var body := Visitor.new()
	stage.add_child(body)
	body.global_position = at + Vector3.UP * 0.5
	var frames := 0
	for _frame in 30:
		await physics_frame
		frames += 1
	_expect(body.heal_calls > 0, "A body inside overlapping clouds is healed.")
	_expect(body.heal_calls <= frames, "Overlapping clouds heal a body at most once per frame (%d of %d)." % [body.heal_calls, frames])
	body.queue_free()
	first.queue_free()
	second.queue_free()


func _spawn(stage: Node3D, at: Vector3, lifetime: float) -> Area3D:
	var cloud := CLOUD.instantiate() as Area3D
	cloud.set("lifetime_seconds", lifetime)
	stage.add_child(cloud)
	cloud.global_position = at
	return cloud


func _layout(cloud: Area3D) -> Array:
	var result := []
	for data in cloud.get("_puffs"):
		result.append([snappedf(data.r, 0.01), snappedf(data.g, 0.01)])
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
