extends Node3D

const BEACON := preload("res://game/features/pickups/public/pickup_beacon.gd")
const GOLD := Color(0.95, 0.7, 0.16)
const HOVER := 0.3

var _base_y := 0.0
var _elapsed := 0.0
var _runtime_active := false
var _art: Node3D
var _beacon: Node3D


func _ready() -> void:
	add_to_group("hidden_outline")
	add_to_group("mission_key")
	_art = Node3D.new()
	add_child(_art)
	var golden := StandardMaterial3D.new()
	golden.albedo_color = GOLD
	golden.metallic = 0.85
	golden.roughness = 0.24
	golden.emission_enabled = true
	golden.emission = GOLD
	golden.emission_energy_multiplier = 0.25
	# Same outline as the HUD icon: bow ring on the left, shaft, two bit teeth.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.085
	ring.outer_radius = 0.16
	ring.material = golden
	_add_mesh(ring, Vector3(-0.28, 0, 0), Vector3(PI * 0.5, 0, 0))
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.032
	shaft.bottom_radius = 0.032
	shaft.height = 0.5
	shaft.radial_segments = 12
	shaft.material = golden
	_add_mesh(shaft, Vector3(0.06, 0, 0), Vector3(0, 0, PI * 0.5))
	_add_bar(Vector3(-0.11, 0, 0), Vector3(0.05, 0.11, 0.08), golden)
	_add_bar(Vector3(0.2, -0.065, 0), Vector3(0.06, 0.13, 0.05), golden)
	_add_bar(Vector3(0.3, -0.05, 0), Vector3(0.06, 0.1, 0.05), golden)
	_art.scale = Vector3.ONE * 1.2
	# The beacon keeps its orientation while the key spins; its arrow waits for reveal_arrow().
	_beacon = BEACON.make(GOLD, 0.7, 1.15, 0.9)
	_beacon.call("set_arrow_visible", false)
	add_child(_beacon)


# The mission calls this once the player has searched for a while; the arrow then blinks above the key.
func reveal_arrow() -> void:
	_beacon.call("set_arrow_visible", true)


func _add_mesh(mesh: Mesh, offset: Vector3, rotated := Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	instance.rotation = rotated
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.add_child(instance)


func _add_bar(offset: Vector3, dimensions: Vector3, material: Material) -> void:
	var bar := BoxMesh.new()
	bar.size = dimensions
	bar.material = material
	_add_mesh(bar, offset)


func _process(delta: float) -> void:
	if not _runtime_active:
		# The mission layout moves the key after _ready: hover above its final floor spot.
		_base_y = global_position.y + HOVER
		_runtime_active = true
	_elapsed += delta
	global_position.y = _base_y + sin(_elapsed * 1.7) * 0.07
	_art.rotation.y += delta * 0.9
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(global_position) <= 1.35:
		player.call("acquire_emergency_key")
		queue_free()
