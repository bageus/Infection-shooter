extends RefCounted
## Power Strike presentation: the fist gathers behind the player, lunges as a
## comet with a torn blood tail, and bursts at the end of its reach with a
## splash, a shock ring, flying droplets and a red mist. A wedge from the feet
## shows the struck area on the floor: a hairline flashes along it, then the
## area unfolds to both sides. Local -Z is forward.

const NODE := preload("res://game/features/player/skill_fx/skill_fx_node.gd")
const COMET_SHADER := preload("res://game/features/player/skill_fx/fx_strike_comet.gdshader")
const LANE_SHADER := preload("res://game/features/player/skill_fx/fx_strike_lane.gdshader")
const RING_SHADER := preload("res://game/features/player/skill_fx/fx_ground_ring.gdshader")
const DANGER := preload("res://game/features/combat/public/floor_danger_zone.gd")
const PUFF_SHADER := preload("res://game/features/player/skill_fx/fx_puff.gdshader")

const REACH := 2.6
const BACK := 0.8
const GATHER := 0.12
const LUNGE := 0.24
const LIFE := 1.2
const SPARKS := 10
const SMOKE := 3
const HEIGHT := 0.9

static var _materials := {}
static var _meshes := {}


static func play(parent: Node, center: Vector3, direction: Vector3) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx: Node3D = NODE.new()
	fx.name = "PowerStrikeFx"
	fx.life = LIFE
	parent.add_child(fx)
	fx.global_position = DANGER.floor_point(parent.get_world_3d(), center) + Vector3.UP * 0.03
	# Aim from the floor, not the body origin (at body height): a target at the
	# player's height would tilt the whole strike up into the air.
	fx.look_at(fx.global_position + direction, Vector3.UP)
	var lane := _lane(fx)
	var fist := _quad(fx, _material("comet", COMET_SHADER, {}))
	fist.position = Vector3(0.0, HEIGHT, BACK)
	var flash := _quad(fx, _material("flash", PUFF_SHADER, {"color": Color(0.85, 0.05, 0.07), "glow": 0.35}))
	flash.position = Vector3(0.0, HEIGHT, -REACH)
	flash.visible = false
	var ring := _plane(fx, _material("ring", RING_SHADER, {"color": Color(0.7, 0.02, 0.05), "core_color": Color(1.0, 0.45, 0.45), "glow": 0.3, "width": 0.06, "fill": 0.25, "brightness": 1.3, "jagged": 0.4}))
	ring.position = Vector3(0.0, 0.01, -REACH)
	ring.visible = false
	var smoke_material := _material("smoke", PUFF_SHADER, {"color": Color(0.4, 0.03, 0.05), "glow": 0.0})
	var smoke: Array[MeshInstance3D] = []
	for i in SMOKE:
		var puff := _quad(fx, smoke_material)
		puff.position = Vector3(randf_range(-0.5, 0.5), 0.3, -REACH + randf_range(-0.3, 0.2))
		puff.set_instance_shader_parameter(&"seed", randf() * 10.0)
		puff.visible = false
		smoke.append(puff)
	var spark_material := _material("spark", PUFF_SHADER, {"color": Color(0.6, 0.02, 0.04), "glow": 0.0})
	var sparks: Array[Dictionary] = []
	for i in SPARKS:
		var spark := _quad(fx, spark_material)
		spark.visible = false
		var angle := randf() * TAU
		var speed := randf_range(2.0, 5.0)
		# Splatter bounces off the wall: sideways and back towards the player, never past the reach.
		sparks.append({"node": spark, "velocity": Vector3(cos(angle) * speed, randf_range(1.5, 4.0), absf(sin(angle)) * speed * 0.5 + 0.5)})
	fx.step = _step.bind(lane, fist, flash, ring, smoke, sparks)
	return fx


static func _step(age: float, _fade: float, lane: MeshInstance3D, fist: MeshInstance3D, flash: MeshInstance3D, ring: MeshInstance3D, smoke: Array[MeshInstance3D], sparks: Array[Dictionary]) -> void:
	lane.set_instance_shader_parameter(&"alpha", clampf(1.0 - (age - 0.3) / 0.65, 0.0, 1.0) if age > 0.3 else clampf(age / 0.04, 0.0, 1.0))
	lane.set_instance_shader_parameter(&"open", lerpf(0.03, 1.0, smoothstep(0.05, 0.25, age)))
	var arrival := GATHER + LUNGE
	if age < arrival:
		var travel := clampf((age - GATHER) / LUNGE, 0.0, 1.0)
		# Decelerates into the end of the reach, like a fist meeting a wall.
		fist.position.z = lerpf(BACK, -REACH, 1.0 - (1.0 - travel) * (1.0 - travel))
		var gather := clampf(age / GATHER, 0.0, 1.0)
		fist.set_instance_shader_parameter(&"size", Vector2(lerpf(0.25, 0.5, gather), lerpf(0.5, 1.0, gather) + travel * 1.8))
		fist.set_instance_shader_parameter(&"alpha", gather)
	else:
		fist.visible = false
	var since := age - arrival
	if since < 0.0:
		return
	var burst := clampf(since / 0.35, 0.0, 1.0)
	flash.visible = since < 0.2
	flash.scale = Vector3.ONE * lerpf(0.7, 1.9, burst)
	flash.set_instance_shader_parameter(&"progress", clampf(since / 0.2, 0.0, 1.0) * 0.6)
	ring.visible = true
	ring.scale = Vector3.ONE * 3.4
	ring.set_instance_shader_parameter(&"progress", clampf(since / 0.55, 0.0, 1.0))
	for puff in smoke:
		puff.visible = true
		puff.scale = Vector3.ONE * lerpf(0.5, 1.7, burst)
		puff.set_instance_shader_parameter(&"progress", clampf(since / 0.7, 0.0, 1.0))
	for spark in sparks:
		var node: MeshInstance3D = spark["node"]
		var velocity: Vector3 = spark["velocity"]
		node.visible = since < 0.5
		var point := Vector3(velocity.x * since, HEIGHT + velocity.y * since - 7.0 * since * since, -REACH + velocity.z * since)
		node.position = Vector3(point.x, maxf(point.y, 0.03), point.z)
		node.scale = Vector3.ONE * 0.16 * (1.0 - since / 0.5)
		node.set_instance_shader_parameter(&"progress", 0.25)


# The scorched wedge: bright edges, faint fill, chevrons running outwards.
static func _lane(fx: Node3D) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows := 7
	var columns := [[-1.0, 0.8], [0.0, 0.12], [1.0, 0.8]]
	for row in rows + 1:
		var along := float(row) / rows
		var half_width := lerpf(0.5, 1.5, along)
		for column: Array in columns:
			vertices.append(Vector3(float(column[0]) * half_width, 0.0, lerpf(0.0, -REACH, along)))
			colors.append(Color(float(column[1]), 1.0 - along * along, 0.0, 1.0))
			uvs.append(Vector2(float(column[0]), along * (REACH + 0.2)))
	for row in rows:
		for column in 2:
			var a := row * 3 + column
			indices.append_array([a, a + 1, a + 3, a + 1, a + 4, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var lane := MeshInstance3D.new()
	lane.mesh = mesh
	lane.material_override = _material("lane", LANE_SHADER, {"tint": Vector3(0.6, 0.02, 0.05), "core": Vector3(1.0, 0.35, 0.35), "flow": -2.6, "opacity": 0.95})
	lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(lane)
	return lane


static func _quad(fx: Node3D, material: Material) -> MeshInstance3D:
	if not _meshes.has("quad"):
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_meshes["quad"] = quad
	var node := MeshInstance3D.new()
	node.mesh = _meshes["quad"]
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(node)
	return node


static func _plane(fx: Node3D, material: Material) -> MeshInstance3D:
	if not _meshes.has("plane"):
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		_meshes["plane"] = plane
	var node := MeshInstance3D.new()
	node.mesh = _meshes["plane"]
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(node)
	return node


static func _material(key: String, shader: Shader, params: Dictionary) -> ShaderMaterial:
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = shader
		for name: String in params:
			material.set_shader_parameter(name, params[name])
		_materials[key] = material
	return _materials[key]
