extends RefCounted
## Shared debris presentation for destroyed office objects: shrink-away expiry,
## a short dust puff and generic crumble chunks. Presentation only; the
## destroyed object keeps ownership of its own gameplay state.

const FRAGMENT_PATH := "res://game/presentation/office_floor/environment_fragment.gd" # loaded lazily: the fragment preloads this file
const FADE_SECONDS := 0.7
const FAST_FADE_SECONDS := 0.25
const MAX_DUST_PUFFS := 6
const DUST_GROUP := "debris_dust_puff"
const FADING_META := "debris_fading"


# Shrinks every visual child of the body to nothing, then frees it. Pieces keep
# resting on the floor while they shrink but can no longer be hit.
static func fade_free(body: Node3D, seconds: float = FADE_SECONDS) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or body.has_meta(FADING_META):
		return
	body.set_meta(FADING_META, true)
	if body is CollisionObject3D:
		(body as CollisionObject3D).collision_layer = 0
	var pivot := Node3D.new()
	pivot.name = "FadePivot"
	body.add_child(pivot)
	for child in body.get_children():
		if child is VisualInstance3D:
			child.reparent(pivot, true)
	var tween := body.create_tween()
	tween.tween_property(pivot, "scale", Vector3.ONE * 0.01, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(body.queue_free)


static func is_fading(body: Node) -> bool:
	return body.has_meta(FADING_META)


# One-shot dust cloud; skipped when the shared puff budget is used up.
static func dust_puff(host: Node3D, world_position: Vector3, size: float, tint: Color = Color(0.66, 0.62, 0.56, 0.34)) -> void:
	var world := host.get("effects_root") as Node3D
	if not is_instance_valid(world) or not host.is_inside_tree():
		return
	if host.get_tree().get_nodes_in_group(DUST_GROUP).size() >= MAX_DUST_PUFFS:
		return
	var scale_factor := clampf(size, 0.3, 3.0)
	var puff := GPUParticles3D.new()
	puff.name = "DebrisDust"
	puff.add_to_group(DUST_GROUP)
	puff.amount = clampi(roundi(14.0 + scale_factor * 12.0), 14, 48)
	puff.lifetime = 1.1
	puff.one_shot = true
	puff.explosiveness = 0.9
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12 + scale_factor * 0.12
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.1 + scale_factor * 0.5
	process.gravity = Vector3(0.0, 0.05, 0.0)
	process.damping_min = 0.8
	process.damping_max = 1.6
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.18, Color(1, 1, 1, 1.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	puff.process_material = process
	var sphere := SphereMesh.new()
	sphere.radius = 0.1 + scale_factor * 0.05
	sphere.height = sphere.radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	puff.draw_pass_1 = sphere
	world.add_child(puff)
	puff.global_position = world_position
	puff.emitting = true
	host.get_tree().create_timer(2.6).timeout.connect(puff.queue_free)


# Small tinted chunks for objects whose model cannot be split into parts.
static func spawn_chunks(host: Node3D, bounds: AABB, tint: Color, count: int, direction: Vector3, hit_position: Vector3) -> void:
	var world := host.get("effects_root") as Node3D
	if not is_instance_valid(world):
		return
	var fragment_script := load(FRAGMENT_PATH) as Script
	for index in count:
		var chunk := RigidBody3D.new()
		chunk.set_script(fragment_script)
		chunk.name = "Chunk_%d" % index
		chunk.set("piece_name", "Chunk")
		chunk.set("stage_index", 99)
		chunk.set("kickable", index % 4 == 0)
		chunk.mass = 0.15
		var size := Vector3(randf_range(0.04, 0.14), randf_range(0.03, 0.1), randf_range(0.04, 0.12))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		chunk.add_child(shape)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = tint.darkened(randf_range(0.0, 0.3))
		material.roughness = 0.9
		mesh.material = material
		visual.mesh = mesh
		chunk.add_child(visual)
		world.add_child(chunk)
		var spot := bounds.position + Vector3(randf() * bounds.size.x, randf() * bounds.size.y, randf() * bounds.size.z)
		chunk.global_position = spot
		chunk.global_rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var away := (spot - hit_position).normalized() * 0.6 + direction.normalized() * 0.4 + Vector3.UP * 0.5
		chunk.apply_central_impulse(away.normalized() * randf_range(0.2, 0.7))
		chunk.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
