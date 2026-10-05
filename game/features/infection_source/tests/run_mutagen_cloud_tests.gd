extends SceneTree
## Runtime checks for the mutagen cloud look: each activation builds its own
## random set of gas puffs from both sheets (12 variants), a ground haze and
## spores; permanent clouds loop their puffs; a death cloud dissipates and
## reports depletion.

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
		_expect(data.r >= 0.0 and data.r < 1.0, "Puff variant indexes one of the 12 sheet cells.")
	_expect(variants.size() == mini(puffs.instance_count, 12), "Every puff shows a different gas variant (%s of %d)." % [variants.keys(), puffs.instance_count])
	_expect(spins.size() >= 1, "Puffs spin.")
	_expect(_layout(first) != _layout(second), "Two clouds never look the same.")
	var haze := first.get_node("GroundHaze") as MultiMeshInstance3D
	_expect(haze.multimesh != null and haze.multimesh.instance_count == 3, "Low billboards merge into the gas without a flat floor reflection.")
	var material := (first.get_node("Visual") as GeometryInstance3D).material_override as ShaderMaterial
	_expect(material != null and material.get_shader_parameter("atlas_a") != null and material.get_shader_parameter("atlas_b") != null, "The cloud draws from both mutagen sheets.")
	_expect(bool(material.get_shader_parameter("wall_mask_enabled")), "Walls still clip the gas.")
	_expect((first.get_node("Spores") as GPUParticles3D).emitting, "Glowing spores rise from a fresh cloud.")
	var forever := _spawn(stage, Vector3(20, 0, 0), 14.0)
	forever.set("permanent", true)
	forever.call("activate")
	_expect(float((forever.get_node("Visual") as GeometryInstance3D).get_instance_shader_parameter(&"looping")) > 0.5, "A permanent cloud loops its puffs.")
	var depleted := [false]
	first.connect("depleted", func() -> void: depleted[0] = true)
	await create_timer(1.0).timeout
	var progress := float((first.get_node("Visual") as GeometryInstance3D).get_instance_shader_parameter(&"progress"))
	_expect(progress > 0.2 and progress < 0.6, "Cloud age drives the shader (%.2f)." % progress)
	_expect(is_equal_approx(progress, float(haze.get_instance_shader_parameter(&"progress"))), "Haze ages with the cloud.")
	await create_timer(1.0).timeout
	_expect(not (first.get_node("Spores") as GPUParticles3D).emitting, "Spores stop as the cloud thins out.")
	await create_timer(1.3).timeout
	_expect(depleted[0] and not first.visible, "The death cloud dissipates and reports it.")
	_expect(forever.visible, "The permanent cloud stays.")
	stage.queue_free()
	await process_frame
	print("Mutagen cloud tests: %d failure(s)." % failures)
	quit(failures)


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
