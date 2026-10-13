extends Area3D

const BEACON := preload("res://game/features/pickups/public/pickup_beacon.gd")

@export_range(0.1, 10.0) var respawn_seconds := 2.0
var _player: Node3D
var _infection: Node
var _art: Node3D
var _beacon: Node3D
var _timer: Timer
var _waiting := false
var _time := 0.0


func configure(player: Node3D, infection: Node) -> void:
	_player = player
	_infection = infection


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.05
	shape.shape = sphere
	add_child(shape)
	_art = Node3D.new()
	add_child(_art)
	_build_helix()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_respawn)
	add_child(_timer)
	body_entered.connect(_collect)


func _build_helix() -> void:
	var strand_material := StandardMaterial3D.new()
	strand_material.albedo_color = Color(0.3, 0.95, 0.1)
	strand_material.emission_enabled = true
	strand_material.emission = Color(0.2, 0.9, 0.08)
	strand_material.emission_energy_multiplier = 0.6
	strand_material.metallic = 0.3
	strand_material.roughness = 0.3
	var rung_material := StandardMaterial3D.new()
	rung_material.albedo_color = Color(0.78, 0.95, 0.86)
	rung_material.emission_enabled = true
	rung_material.emission = Color(0.6, 0.95, 0.75)
	rung_material.emission_energy_multiplier = 0.35
	var link := CylinderMesh.new()
	link.top_radius = 0.016
	link.bottom_radius = 0.016
	link.height = 1.0
	link.radial_segments = 8
	link.rings = 1
	link.material = strand_material
	var rung := CylinderMesh.new()
	rung.top_radius = 0.009
	rung.bottom_radius = 0.009
	rung.height = 1.0
	rung.radial_segments = 6
	rung.rings = 1
	rung.material = rung_material
	var bead := SphereMesh.new()
	bead.radius = 0.026
	bead.height = 0.052
	bead.radial_segments = 10
	bead.rings = 5
	bead.material = strand_material
	var links: Array[Transform3D] = []
	var rungs: Array[Transform3D] = []
	var beads: Array[Transform3D] = []
	var steps := 36
	var turns := 2.0
	var radius := 0.075
	var height := 0.42
	for i in range(steps + 1):
		var angle := TAU * turns * i / steps
		var y := (float(i) / steps - 0.5) * height
		var a := Vector3(cos(angle) * radius, y, sin(angle) * radius)
		var b := Vector3(-a.x, y, -a.z)
		beads.append(Transform3D(Basis(), a))
		beads.append(Transform3D(Basis(), b))
		if i % 3 == 0:
			rungs.append(_segment(a, b))
		if i > 0:
			var prev_angle := TAU * turns * (i - 1) / steps
			var prev_y := (float(i - 1) / steps - 0.5) * height
			var pa := Vector3(cos(prev_angle) * radius, prev_y, sin(prev_angle) * radius)
			links.append(_segment(pa, a))
			links.append(_segment(Vector3(-pa.x, prev_y, -pa.z), b))
	_add_multimesh(link, links)
	_add_multimesh(rung, rungs)
	_add_multimesh(bead, beads)
	# Glow only; the arrow marks the pickup from a distance.
	_beacon = BEACON.make(Color(0.3, 1.0, 0.2), 0.65, 0.95, 0.9)
	add_child(_beacon)


## Unit-height cylinder stretched between two points.
func _segment(from: Vector3, to: Vector3) -> Transform3D:
	var along := to - from
	var up := along.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	return Transform3D(Basis(side, up * along.length(), side.cross(up)), (from + to) * 0.5)


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.add_child(instance)


func _process(delta: float) -> void:
	if _waiting:
		return
	_time += delta
	_art.position.y = sin(_time * 1.6) * 0.045
	_art.rotation.y += delta * 0.6


func _collect(body: Node3D) -> void:
	if _waiting or body != _player or not is_instance_valid(_infection):
		return
	_infection.call("add_control_ampule")
	if body.has_method("play_item_sound"):
		body.call("play_item_sound", &"dna_pickup")
	_waiting = true
	_art.hide()
	_beacon.hide()
	set_deferred("monitoring", false)
	_timer.start(respawn_seconds)


func _respawn() -> void:
	_waiting = false
	_art.show()
	_beacon.show()
	set_deferred("monitoring", true)
