extends RefCounted
## Self-made (procedural) skill effects: meshes and shaders instead of the
## supplied sprite sheets, chosen in the settings for comparison. Each cast
## returns a skill_fx_node that animates itself and frees itself; the buff
## loops (storm field, blade orbit) run until stop().

const NODE := preload("res://game/features/player/skill_fx/skill_fx_node.gd")
const RIBBONS := preload("res://game/features/player/skill_fx/fx_ribbons.gd")
const RING_SHADER := preload("res://game/features/player/skill_fx/fx_ground_ring.gdshader")
const STORM_SHADER := preload("res://game/features/player/skill_fx/fx_storm_field.gdshader")
const ACID_SHADER := preload("res://game/features/player/skill_fx/fx_acid_pool.gdshader")
const COCOON_SHADER := preload("res://game/features/player/skill_fx/fx_cocoon.gdshader")
const SHIELD_SHADER := preload("res://game/features/player/skill_fx/fx_shield.gdshader")
const HEART_SHADER := preload("res://game/features/player/skill_fx/fx_heart.gdshader")
const TRAIL_SHADER := preload("res://game/features/player/skill_fx/fx_blade_trail.gdshader")
const PUFF_SHADER := preload("res://game/features/player/skill_fx/fx_puff.gdshader")

const SPIKE_LIFE := 0.7
const PULSE_LIFE := 0.55
const SPORE_BURST := 0.9
const BLADE_TURNS_PER_SECOND := 1.1
const BLADE_HEIGHT := 0.9
const BLADE_COUNT := 4
## Blades ride this share of the orbit radius (matches fx_blade_trail ring).
const BLADE_RING := 0.78

static var _materials := {}
static var _meshes := {}


# --- Casts -------------------------------------------------------------------

## Blood Burst: a ring of bone spikes bursts from the floor and sinks back,
## with a blood shock ring and flung droplets.
static func spike_burst(parent: Node, center: Vector3, radius: float) -> Node3D:
	var fx := _effect(parent, center, SPIKE_LIFE)
	if fx == null:
		return null
	var stain := _plane(fx, radius, _ring_material("blood_stain"))
	var shock := _plane(fx, radius, _ring_material("blood_shock"))
	var spikes: Array[Node3D] = []
	var timing: Array[Vector2] = []
	var count := 18
	for i in count:
		var outer := i % 2 == 1
		var angle := TAU * i / count + randf_range(-0.12, 0.12)
		var distance := radius * (randf_range(0.5, 0.78) if outer else randf_range(0.18, 0.4))
		var length := randf_range(0.6, 0.95) * (1.15 if outer else 0.9) * clampf(radius / 2.4, 0.6, 1.4)
		var pivot := Node3D.new()
		fx.add_child(pivot)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		pivot.position = outward * distance + Vector3.DOWN * 0.04
		pivot.basis = Basis(outward.cross(Vector3.UP).normalized(), -deg_to_rad(randf_range(28.0, 52.0)))
		var spike := MeshInstance3D.new()
		spike.mesh = _spike_mesh()
		spike.position.y = 0.5
		spike.material_override = _spike_material()
		pivot.add_child(spike)
		pivot.scale = Vector3.ONE * 0.001
		spikes.append(pivot)
		timing.append(Vector2(distance / radius * 0.07, length))
	var drops := _droplets(fx, 14, radius * 1.4, Color(0.45, 0.02, 0.04), Color(0.5, 0.0, 0.02))
	fx.step = func(age: float, fade: float) -> void:
		var progress := age / SPIKE_LIFE
		stain.set_instance_shader_parameter(&"progress", progress)
		shock.set_instance_shader_parameter(&"progress", minf(progress * 1.5, 1.0))
		for i in spikes.size():
			var t := age - timing[i].x
			var height := 0.0
			if t > 0.0:
				var rise := clampf(t / 0.07, 0.0, 1.0)
				height = _ease_out_back(rise) * (1.0 - smoothstep(0.32, 0.6, t))
			var width := 0.6 + 0.4 * minf(t / 0.07, 1.0) if t > 0.0 else 0.001
			spikes[i].scale = Vector3(width, maxf(height * timing[i].y, 0.001), width)
		_fly(drops, age, fade)
	return fx


## Retaliation: a crackling electric ring with bolts reaching out to it.
static func electric_pulse(parent: Node, center: Vector3, radius: float) -> Node3D:
	var fx := _effect(parent, center, PULSE_LIFE)
	if fx == null:
		return null
	var ring := _plane(fx, radius, _ring_material("electric"))
	var bolts := RIBBONS.new(fx, _ribbon_material("lightning"))
	var headings: Array[float] = []
	for i in 7:
		headings.append(TAU * i / 7.0 + randf_range(-0.3, 0.3))
	var state := {"next": 0.0}
	fx.step = func(age: float, fade: float) -> void:
		var progress := age / PULSE_LIFE
		ring.set_instance_shader_parameter(&"progress", progress)
		if age < state["next"]:
			return
		state["next"] = age + 0.04
		bolts.clear()
		if progress > 0.6:
			return
		var reach := (1.0 - pow(1.0 - minf(progress * 1.6, 1.0), 3.0)) * radius
		var origin := center + Vector3.UP * 0.35
		for heading in headings:
			if randf() < 0.3:
				continue
			var tip := center + Vector3(cos(heading), 0.0, sin(heading)) * reach + Vector3.UP * 0.05
			bolts.add_bolt(origin, tip, 0.11, 0.22, (1.0 - progress) * fade)
		bolts.commit()
	return fx


## Discharge: a flickering lightning link from each point to the next, and a
## spark where it strikes.
static func chain_lightning(parent: Node, points: Array[Vector3]) -> Node3D:
	if points.size() < 2:
		return null
	var fx := _effect(parent, points[0], 0.42)
	if fx == null:
		return null
	var bolts := RIBBONS.new(fx, _ribbon_material("lightning"))
	var sparks: Array[MeshInstance3D] = []
	for i in range(1, points.size()):
		var spark := _billboard(fx, _puff_material("spark"), 0.9)
		spark.global_position = points[i] + Vector3.UP * 1.0
		sparks.append(spark)
	var state := {"next": 0.0}
	fx.step = func(age: float, fade: float) -> void:
		var progress := age / 0.42
		for spark in sparks:
			spark.set_instance_shader_parameter(&"progress", progress)
		if age < state["next"]:
			return
		state["next"] = age + 0.045
		bolts.clear()
		var flicker := (1.0 - smoothstep(0.5, 1.0, progress)) * randf_range(0.65, 1.0) * fade
		for i in points.size() - 1:
			var from := points[i] + Vector3.UP * 1.0
			var to := points[i + 1] + Vector3.UP * 1.0
			bolts.add_bolt(from, to, 0.16, 0.28, flicker)
			bolts.add_bolt(from, to, 0.06, 0.45, flicker * 0.6)
		bolts.commit()
	return fx


## Acid Spit: a flat acid pool fixed on the floor for `seconds`.
static func acid_pool(parent: Node, center: Vector3, radius: float, seconds: float) -> Node3D:
	var fx := _effect(parent, center + Vector3.UP * 0.03, seconds)
	if fx == null:
		return null
	fx.fade_out = 0.8
	var pool := _plane(fx, radius, _material("acid", ACID_SHADER, {}))
	pool.rotation.y = randf() * TAU
	pool.set_instance_shader_parameter(&"seed", randf() * 10.0)
	fx.step = func(age: float, fade: float) -> void:
		pool.set_instance_shader_parameter(&"progress", age / seconds)
		pool.set_instance_shader_parameter(&"alpha", fade)
	return fx


## Spore Cocoon: a pulsing pod that swells for `fuse` seconds and bursts
## into a spore cloud over `radius`.
static func spore_cocoon(parent: Node, center: Vector3, radius: float, fuse: float) -> Node3D:
	var fx := _effect(parent, center, fuse + SPORE_BURST)
	if fx == null:
		return null
	var pod := MeshInstance3D.new()
	pod.mesh = _pod_mesh()
	pod.material_override = _material("cocoon", COCOON_SHADER, {})
	pod.set_instance_shader_parameter(&"seed", randf() * 10.0)
	pod.scale = Vector3.ONE * 0.01
	fx.add_child(pod)
	var cloud := _plane(fx, radius, _ring_material("spores"))
	cloud.visible = false
	var puffs: Array[MeshInstance3D] = []
	for i in 7:
		var puff := _billboard(fx, _puff_material("spores"), 0.01)
		var angle := randf() * TAU
		puff.position = Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.0, radius * 0.6) + Vector3.UP * randf_range(0.35, 0.8)
		puff.set_instance_shader_parameter(&"seed", randf() * 10.0)
		puff.visible = false
		puffs.append(puff)
	var spores := _droplets(fx, 26, radius * 2.2, Color(0.75, 1.0, 0.3), Color(0.5, 1.0, 0.1), 0.35, 3.0)
	for drop in spores:
		drop["node"].visible = false
	fx.step = func(age: float, fade: float) -> void:
		var size := 0.55
		if age < fuse:
			var grow := _ease_out_back(clampf(age / 0.25, 0.0, 1.0))
			pod.scale = Vector3.ONE * size * maxf(grow, 0.01)
			pod.set_instance_shader_parameter(&"charge", age / fuse)
			return
		var burst := age - fuse
		pod.visible = burst < 0.07
		pod.scale = Vector3.ONE * size * (1.0 + burst * 6.0)
		var progress := burst / SPORE_BURST
		cloud.visible = true
		cloud.set_instance_shader_parameter(&"progress", progress)
		for puff in puffs:
			puff.visible = true
			puff.scale = Vector3.ONE * lerpf(0.4, radius * 0.5, 1.0 - pow(1.0 - minf(progress * 1.5, 1.0), 2.0))
			puff.set_instance_shader_parameter(&"progress", progress)
		for drop in spores:
			drop["node"].visible = true
		_fly(spores, burst, 1.0 - smoothstep(0.5, 1.0, progress))
	return fx


## Claws: three hot slashes swept across the struck enemy, facing the camera.
static func claw_slash(parent: Node, point: Vector3) -> Node3D:
	var fx := _effect(parent, point, 0.3)
	if fx == null:
		return null
	var camera := fx.get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	var up := camera.global_basis.y if camera != null else Vector3.UP
	var tilt := randf_range(-0.35, 0.35)
	var along := (right * cos(tilt - 0.8) + up * sin(tilt - 0.8)).normalized()
	var across := (right * cos(tilt + 0.77) + up * sin(tilt + 0.77)).normalized()
	var slashes: Array[MeshInstance3D] = []
	for i in 3:
		var strip := RIBBONS.new(fx, _ribbon_material("claw"))
		var offset := across * (float(i) - 1.0) * 0.2
		var arc: Array[Vector3] = []
		for k in 9:
			var t := k / 8.0
			arc.append(point + offset + along * (t - 0.5) * 1.3 + across * sin(PI * t) * 0.15)
		strip.add_path(arc, 0.17, 1.0)
		strip.commit()
		slashes.append(strip.instance)
	fx.step = func(age: float, _fade: float) -> void:
		for i in slashes.size():
			slashes[i].set_instance_shader_parameter(&"progress", clampf((age - i * 0.025) / 0.27, 0.0, 1.0))
	return fx


## Armor gained or soaking a hit: a hex dome flashes around the player.
static func energy_shield(parent: Node, center: Vector3) -> Node3D:
	var fx := _effect(parent, center, 0.5)
	if fx == null:
		return null
	var dome := MeshInstance3D.new()
	dome.mesh = _bubble_mesh()
	dome.position.y = 0.95
	dome.material_override = _material("shield", SHIELD_SHADER, {})
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(dome)
	fx.step = func(age: float, _fade: float) -> void:
		dome.set_instance_shader_parameter(&"progress", age / 0.5)
		dome.scale = Vector3(1.0, 0.95, 1.0) * (0.92 + 0.08 * minf(age / 0.08, 1.0))
	return fx


## Second Heart: a beating heart above the player for `seconds`.
static func heartbeat(parent: Node, point: Vector3, seconds: float) -> Node3D:
	var fx := _effect(parent, point, seconds)
	if fx == null:
		return null
	fx.fade_in = 0.15
	fx.fade_out = 0.35
	var heart := _billboard(fx, _material("heart", HEART_SHADER, {}), 1.0)
	fx.step = func(age: float, fade: float) -> void:
		heart.set_instance_shader_parameter(&"clock", age)
		heart.set_instance_shader_parameter(&"alpha", fade)
	return fx


# --- Buff loops ----------------------------------------------------------------

## Storm Pulse: a charged field with arcs around the player until stop().
static func storm_field(parent: Node, center: Vector3, radius: float) -> Node3D:
	var fx := _effect(parent, center + Vector3.UP * 0.04, INF)
	if fx == null:
		return null
	fx.fade_in = 0.25
	var field := _plane(fx, radius, _material("storm", STORM_SHADER, {}))
	fx.step = func(_age: float, fade: float) -> void:
		field.set_instance_shader_parameter(&"alpha", fade)
	return fx


## Bone Blades: blades circling the player with comet trails until stop().
static func blade_orbit(parent: Node, center: Vector3, radius: float) -> Node3D:
	var fx := _effect(parent, center, INF)
	if fx == null:
		return null
	fx.fade_in = 0.2
	var trail := _plane(fx, radius, _material("trail", TRAIL_SHADER, {}))
	trail.position.y = BLADE_HEIGHT
	var blades: Array[MeshInstance3D] = []
	for i in BLADE_COUNT:
		var blade := MeshInstance3D.new()
		blade.mesh = _blade_mesh()
		blade.material_override = _blade_material()
		fx.add_child(blade)
		blades.append(blade)
	var ring := radius * BLADE_RING
	fx.step = func(age: float, fade: float) -> void:
		var lead := fmod(age * TAU * BLADE_TURNS_PER_SECOND, TAU)
		trail.set_instance_shader_parameter(&"angle", lead)
		trail.set_instance_shader_parameter(&"alpha", fade)
		for i in blades.size():
			var angle := lead + TAU * i / blades.size()
			var tangent := Vector3(-sin(angle), 0.0, -cos(angle))
			var outward := Vector3(cos(angle), 0.0, -sin(angle))
			blades[i].position = outward * ring + Vector3.UP * BLADE_HEIGHT
			blades[i].basis = Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP)).rotated(tangent, 0.35) * Basis.from_scale(Vector3.ONE * 1.3 * maxf(fade, 0.01))
	return fx


# --- Helpers -----------------------------------------------------------------

static func _effect(parent: Node, point: Vector3, life: float) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx: Node3D = NODE.new()
	fx.name = "SkillFx"
	fx.life = life
	parent.add_child(fx, true)
	fx.global_position = point
	return fx


static func _plane(fx: Node3D, radius: float, material: Material) -> MeshInstance3D:
	if not _meshes.has("plane"):
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		_meshes["plane"] = plane
	var node := MeshInstance3D.new()
	node.mesh = _meshes["plane"]
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	node.position.y = 0.03
	node.set_instance_shader_parameter(&"seed", randf() * 10.0)
	fx.add_child(node)
	return node


static func _billboard(fx: Node3D, material: Material, size: float) -> MeshInstance3D:
	if not _meshes.has("quad"):
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		_meshes["quad"] = quad
	var node := MeshInstance3D.new()
	node.mesh = _meshes["quad"]
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.scale = Vector3.ONE * size
	fx.add_child(node)
	return node


# Small glowing balls flung out from the origin: blood droplets or spores.
static func _droplets(fx: Node3D, count: int, speed: float, albedo: Color, glow: Color, lift := 0.6, drag := 0.0) -> Array[Dictionary]:
	if not _meshes.has("drop"):
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		sphere.radial_segments = 8
		sphere.rings = 4
		_meshes["drop"] = sphere
	var key := "drop|%s" % albedo.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = albedo
		material.emission_enabled = true
		material.emission = glow
		material.emission_energy_multiplier = 1.2
		material.roughness = 0.3
		_materials[key] = material
	var drops: Array[Dictionary] = []
	for i in count:
		var node := MeshInstance3D.new()
		node.mesh = _meshes["drop"]
		node.material_override = _materials[key]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var size := randf_range(0.04, 0.08)
		node.scale = Vector3.ONE * size
		node.position = Vector3.UP * 0.3
		fx.add_child(node)
		var angle := randf() * TAU
		var velocity := Vector3(cos(angle), 0.0, sin(angle)) * speed * randf_range(0.35, 0.7) + Vector3.UP * speed * lift * randf_range(0.5, 1.0)
		drops.append({"node": node, "velocity": velocity, "size": size, "drag": drag})
	return drops


static func _fly(drops: Array[Dictionary], age: float, fade: float) -> void:
	for drop in drops:
		var node: MeshInstance3D = drop["node"]
		var velocity: Vector3 = drop["velocity"]
		var drag := float(drop["drag"])
		# Closed-form flight: drag slows the throw, gravity pulls it down.
		var reach := age if drag <= 0.0 else (1.0 - exp(-drag * age)) / drag
		var gravity := 12.0 if drag <= 0.0 else 1.5
		var point := Vector3(velocity.x * reach, 0.3 + velocity.y * reach - 0.5 * gravity * age * age, velocity.z * reach)
		node.position = Vector3(point.x, maxf(point.y, 0.02), point.z)
		var landed := point.y <= 0.02
		node.scale = Vector3.ONE * float(drop["size"]) * fade * (0.6 if landed else 1.0)


static func _ease_out_back(t: float) -> float:
	var s := 1.9
	t -= 1.0
	return t * t * ((s + 1.0) * t + s) + 1.0


static func _material(key: String, shader: Shader, params: Dictionary) -> ShaderMaterial:
	if _materials.has(key):
		return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = shader
	for name: String in params:
		material.set_shader_parameter(name, params[name])
	_materials[key] = material
	return material


static func _ring_material(kind: String) -> ShaderMaterial:
	var params: Dictionary = {
		"blood_stain": {"color": Color(0.22, 0.0, 0.015), "core_color": Color(0.4, 0.02, 0.03), "glow": 0.0, "width": 0.08, "fill": 0.3, "brightness": 1.0, "jagged": 0.35},
		"blood_shock": {"color": Color(1.0, 0.12, 0.08), "core_color": Color(1.0, 0.75, 0.6), "glow": 1.0, "width": 0.05, "fill": 0.1, "brightness": 1.3},
		"electric": {"color": Color(0.3, 0.65, 1.0), "core_color": Color(0.9, 0.97, 1.0), "glow": 1.0, "width": 0.05, "fill": 0.2, "brightness": 1.7, "jagged": 1.0},
		"spores": {"color": Color(0.5, 0.85, 0.18), "core_color": Color(0.85, 1.0, 0.55), "glow": 0.4, "width": 0.07, "fill": 0.3, "brightness": 1.0, "jagged": 0.3},
	}[kind]
	return _material("ring_" + kind, RING_SHADER, params)


static func _ribbon_material(kind: String) -> ShaderMaterial:
	var params: Dictionary = {
		"lightning": {"color": Color(0.35, 0.7, 1.0), "core_color": Color(0.95, 0.98, 1.0), "glow": 1.0, "brightness": 2.0},
		"claw": {"color": Color(0.95, 0.12, 0.08), "core_color": Color(1.0, 0.92, 0.85), "glow": 0.5, "sweep": 1.0, "brightness": 1.6},
	}[kind]
	return _material("ribbon_" + kind, RIBBONS.SHADER, params)


static func _puff_material(kind: String) -> ShaderMaterial:
	var params: Dictionary = {
		"spores": {"color": Color(0.5, 0.8, 0.22), "glow": 0.2},
		"spark": {"color": Color(0.55, 0.85, 1.0), "glow": 1.0},
	}[kind]
	return _material("puff_" + kind, PUFF_SHADER, params)


static func _spike_material() -> StandardMaterial3D:
	if not _materials.has("spike"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.42, 0.05, 0.06)
		material.roughness = 0.28
		material.metallic = 0.15
		material.emission_enabled = true
		material.emission = Color(0.55, 0.02, 0.03)
		material.emission_energy_multiplier = 0.5
		material.rim_enabled = true
		material.rim = 0.6
		_materials["spike"] = material
	return _materials["spike"]


static func _blade_material() -> StandardMaterial3D:
	if not _materials.has("blade"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.92, 0.9, 0.82)
		material.roughness = 0.3
		material.metallic = 0.2
		material.emission_enabled = true
		material.emission = Color(0.4, 0.9, 1.0)
		material.emission_energy_multiplier = 0.7
		material.rim_enabled = true
		material.rim = 0.5
		_materials["blade"] = material
	return _materials["blade"]


static func _spike_mesh() -> Mesh:
	if not _meshes.has("spike"):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.11
		cone.height = 1.0
		cone.radial_segments = 6
		cone.rings = 1
		_meshes["spike"] = cone
	return _meshes["spike"]


static func _pod_mesh() -> Mesh:
	if not _meshes.has("pod"):
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 1.6
		sphere.radial_segments = 32
		sphere.rings = 16
		_meshes["pod"] = sphere
	return _meshes["pod"]


static func _bubble_mesh() -> Mesh:
	if not _meshes.has("bubble"):
		var sphere := SphereMesh.new()
		sphere.radius = 1.05
		sphere.height = 2.1
		sphere.radial_segments = 32
		sphere.rings = 16
		_meshes["bubble"] = sphere
	return _meshes["bubble"]


# A curved bone blade along +X: a thin double-edged leaf with a ridge.
static func _blade_mesh() -> Mesh:
	if _meshes.has("blade"):
		return _meshes["blade"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.32, 0.0, 0.05)
	var back := Vector3(-0.24, 0.0, 0.0)
	var edge_a := Vector3(0.0, 0.0, 0.09)
	var edge_b := Vector3(0.02, 0.0, -0.05)
	var top := Vector3(0.02, 0.025, 0.02)
	var bottom := Vector3(0.02, -0.025, 0.02)
	for ridge in [top, bottom]:
		for pair in [[tip, edge_a], [edge_a, back], [back, edge_b], [edge_b, tip]]:
			var a: Vector3 = pair[0]
			var b: Vector3 = pair[1]
			if ridge == bottom:
				var swap := a
				a = b
				b = swap
			tool.add_vertex(ridge)
			tool.add_vertex(a)
			tool.add_vertex(b)
	tool.generate_normals()
	_meshes["blade"] = tool.commit()
	return _meshes["blade"]
