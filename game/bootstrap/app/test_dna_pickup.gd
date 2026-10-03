extends Area3D

@export_range(0.1, 10.0) var respawn_seconds := 2.0
var _player: Node3D
var _infection: Node
var _art: Node3D
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
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.3, 0.95, 0.1)
	green.metallic = 0.35
	green.roughness = 0.3
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.78, 0.95, 0.86)
	var bead := SphereMesh.new()
	bead.radius = 0.055
	bead.height = 0.11
	bead.material = green
	for i in range(12):
		var angle := i * 0.65
		var left := Vector3(cos(angle) * 0.18, (i - 5.5) * 0.055, sin(angle) * 0.18)
		for point in [left, Vector3(-left.x, left.y, -left.z)]:
			var dot := MeshInstance3D.new()
			dot.mesh = bead
			dot.position = point
			_art.add_child(dot)
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.36, 0.025, 0.025)
		mesh.material = white
		bar.mesh = mesh
		bar.position.y = left.y
		bar.rotation.y = -angle
		_art.add_child(bar)
	var label := Label3D.new()
	label.font = preload("res://assets/interface/fonts/body.ttf")
	label.text = "DNA · STABILITY +5\nTEST PICKUP · RESPAWNS"
	label.font_size = 32
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.55
	_art.add_child(label)


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
	_waiting = true
	_art.hide()
	set_deferred("monitoring", false)
	_timer.start(respawn_seconds)


func _respawn() -> void:
	_waiting = false
	_art.show()
	set_deferred("monitoring", true)
