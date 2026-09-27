extends Node3D

var _base_y := 0.25
var _elapsed := 0.0


func _ready() -> void:
	_base_y = global_position.y
	var golden := StandardMaterial3D.new()
	golden.albedo_color = Color(0.92, 0.66, 0.12)
	golden.metallic = 0.78
	golden.roughness = 0.22
	var ring := TorusMesh.new()
	ring.inner_radius = 0.13
	ring.outer_radius = 0.2
	ring.material = golden
	_add_mesh(ring, Vector3(0.29, 0, 0))
	_add_bar(Vector3(-0.12, 0, 0), Vector3(0.6, 0.07, 0.07), golden)
	_add_bar(Vector3(-0.35, 0, 0.085), Vector3(0.07, 0.07, 0.19), golden)
	_add_bar(Vector3(-0.22, 0, 0.065), Vector3(0.07, 0.07, 0.15), golden)
	var hint := Label3D.new()
	hint.text = "АВАРИЙНЫЙ КЛЮЧ"
	hint.font_size = 36
	hint.pixel_size = 0.006
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.position.y = 0.65
	add_child(hint)


func _add_mesh(mesh: Mesh, offset: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	add_child(instance)


func _add_bar(offset: Vector3, dimensions: Vector3, material: Material) -> void:
	var bar := BoxMesh.new()
	bar.size = dimensions
	bar.material = material
	_add_mesh(bar, offset)


func _process(delta: float) -> void:
	_elapsed += delta
	global_position.y = _base_y + sin(_elapsed * 1.7) * 0.07
	rotation.y += delta * 0.6
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(global_position) <= 1.35:
		player.call("acquire_emergency_key")
		queue_free()
