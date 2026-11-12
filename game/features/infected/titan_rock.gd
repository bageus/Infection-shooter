extends Node3D
## Rock thrown by the Titan. It flies a fixed-time arc to the point the player
## stood at when it was released, so a dodge roll or a step aside avoids it.

const HIT_RADIUS := 1.1
const HIT_HEIGHT := 1.8

var damage := 0.0
var source: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flight := 0.8
var _age := 0.0
var _flying := false


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.32, 0.28)
	material.roughness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.7
	mesh.radial_segments = 8
	mesh.rings = 5
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)


func launch(from: Vector3, to: Vector3, flight_seconds: float) -> void:
	_from = from
	_to = to
	_flight = maxf(flight_seconds, 0.1)
	_age = 0.0
	_flying = true


func _physics_process(delta: float) -> void:
	if not _flying:
		return
	_age += delta
	var k := clampf(_age / _flight, 0.0, 1.0)
	global_position = _from.lerp(_to, k) + Vector3.UP * (4.0 * k * (1.0 - k) * 2.2)
	rotate_x(delta * 9.0)
	if k >= 1.0:
		_land()


func _land() -> void:
	_flying = false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and damage > 0.0:
		var offset := player.global_position - _to
		if Vector2(offset.x, offset.z).length() <= HIT_RADIUS and absf(offset.y) <= HIT_HEIGHT:
			preload("res://game/features/infected/enemy_interaction_rules.gd").damage(player, damage)
	queue_free()
