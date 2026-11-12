extends Node3D
## Rock thrown by the Titan. It flies a fixed-time arc to the point the player
## stood at when it was released, so a dodge roll or a step aside avoids it.

const HIT_RADIUS := 1.1
const HIT_HEIGHT := 1.8
const STUN_INTENSITY := 0.4

var damage := 0.0
var source: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flight := 0.8
var _age := 0.0
var _flying := false


func _ready() -> void:
	var material := StandardMaterial3D.new()
	var shade := randf_range(0.8, 1.15)
	material.albedo_color = Color(0.36, 0.32, 0.28) * shade
	material.roughness = 1.0
	# Every rock is a different lump: a jittered sphere, squashed unevenly.
	var source := SphereMesh.new()
	source.radius = 0.3
	source.height = 0.6
	source.radial_segments = 10
	source.rings = 6
	var arrays := source.get_mesh_arrays()
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var phase := Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var squash := Vector3(randf_range(0.75, 1.25), randf_range(0.7, 1.1), randf_range(0.75, 1.25)) * randf_range(0.85, 1.15)
	for i in vertices.size():
		var v := vertices[i]
		var bump := 1.0 + 0.18 * sin(v.x * 17.0 + phase.x) * sin(v.y * 13.0 + phase.y) + 0.14 * sin(v.z * 19.0 + phase.z)
		vertices[i] = v * bump * squash
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
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
	var previous := global_position
	var next := _from.lerp(_to, k) + Vector3.UP * (4.0 * k * (1.0 - k) * 2.2)
	# Walls and obstacles (layer 1) stop the rock where it hits them.
	var query := PhysicsRayQueryParameters3D.create(previous, next, 1)
	var player := get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player != null:
		query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and k < 1.0:
		global_position = hit.position
		_flying = false
		queue_free()
		return
	global_position = next
	rotate_x(delta * 9.0)
	if k >= 1.0:
		_land()


func _land() -> void:
	_flying = false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and damage > 0.0:
		var offset := player.global_position - _to
		var flat := Vector2(offset.x, offset.z)
		if flat.length() <= HIT_RADIUS and absf(offset.y) <= HIT_HEIGHT:
			_hit_player(player, flat.length())
	queue_free()


# A centred hit stuns longer (1 s) than a glancing one (0.5 s).
func _hit_player(player: Node3D, miss_distance: float) -> void:
	var before := _vitals(player)
	if player.has_method("note_hit_direction"):
		player.call("note_hit_direction", (player.global_position - _from).normalized())
	preload("res://game/features/infected/enemy_interaction_rules.gd").damage(player, damage)
	if _vitals(player) < before and player.has_method("apply_blast_stun"):
		player.call("apply_blast_stun", lerpf(1.0, 0.5, clampf(miss_distance / HIT_RADIUS, 0.0, 1.0)), STUN_INTENSITY)


func _vitals(player: Node3D) -> float:
	return float(player.get("health")) + float(player.get("armor")) if player.get("health") != null and player.get("armor") != null else 0.0
