extends RefCounted
## A large wooden crate is one authored mesh. When it breaks, the mesh is cut into its six walls
## (by the face each triangle lies nearest to) so the walls fall, topple and pile up as separate
## pieces instead of the whole crate being baked into the floor as one piece.

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const MODELS := ["crate_wood_large"]
const ARRAY_KINDS := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]


static func applies(model_path: String) -> bool:
	for model in MODELS:
		if model in model_path.get_file():
			return true
	return false


## A pallet is a tight stack: its boards and blocks only pull apart, and then fall onto the floor, when they
## are thrown outward from the middle. Velocity is set directly (an impulse on a body at rest is absorbed).
static func scatter_pallet(model_path: String, pieces: Array, center: Vector3) -> void:
	if "pallet" not in model_path.get_file():
		return
	for piece in pieces:
		var body := piece as RigidBody3D
		if body == null:
			continue
		var away := body.global_position - center
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.0004 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		body.sleeping = false
		body.linear_velocity += away * randf_range(1.2, 2.4) + Vector3.UP * randf_range(1.2, 2.2)
		body.angular_velocity += Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))


## Every visible mesh of the prop becomes a flying piece; a big wooden crate is cut into its walls first.
static func spawn_pieces(host: RigidBody3D, visual: Node3D, hit_position: Vector3, direction: Vector3) -> void:
	var cut := applies(str(host.get("model_path")))
	var index := 0
	for child in visual.find_children("*", "MeshInstance3D", true, false):
		var source := child as MeshInstance3D
		if source == null or source.mesh == null or not source.is_visible_in_tree():
			continue
		if not cut:
			DAMAGE.spawn_piece(host, source, host, 0, index, direction, hit_position)
			index += 1
			continue
		for wall: ArrayMesh in split(source.mesh):
			var piece := MeshInstance3D.new()
			piece.mesh = wall
			piece.name = "Wall_%d" % index
			source.get_parent().add_child(piece)
			piece.global_transform = source.global_transform
			DAMAGE.spawn_piece(host, piece, host, 0, index, direction, hit_position, true)
			piece.queue_free()
			index += 1


## Six meshes (-X, +X, -Y, +Y, -Z, +Z) that together hold every triangle of the mesh; empty walls are left out.
static func split(mesh: Mesh) -> Array[ArrayMesh]:
	var box := mesh.get_aabb()
	var walls: Array[ArrayMesh] = []
	var builders: Array[Dictionary] = []
	for wall in 6:
		builders.append({})
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var groups: Array[Array] = [[], [], [], [], [], []]
		for first in range(0, count - 2, 3):
			var corners := []
			for corner in 3:
				corners.append(indices[first + corner] if not indices.is_empty() else first + corner)
			var center := (vertices[corners[0]] + vertices[corners[1]] + vertices[corners[2]]) / 3.0
			groups[_nearest_wall(box, center)].append_array(corners)
		for wall in 6:
			if not groups[wall].is_empty():
				builders[wall][surface] = _surface(arrays, groups[wall])
	for wall in 6:
		if builders[wall].is_empty():
			continue
		var result := ArrayMesh.new()
		for surface: int in builders[wall]:
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, builders[wall][surface])
			result.surface_set_material(result.get_surface_count() - 1, mesh.surface_get_material(surface))
		walls.append(result)
	return walls


static func _nearest_wall(box: AABB, point: Vector3) -> int:
	var best := 0
	var best_distance := INF
	var end := box.end
	var distances := [point.x - box.position.x, end.x - point.x, point.y - box.position.y, end.y - point.y, point.z - box.position.z, end.z - point.z]
	for wall in 6:
		if distances[wall] < best_distance:
			best_distance = distances[wall]
			best = wall
	return best


# Unindexed copy of the listed corners; every present per-vertex array is carried over.
static func _surface(arrays: Array, corners: Array) -> Array:
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	for kind: int in ARRAY_KINDS:
		var source: Variant = arrays[kind]
		if source == null or source.is_empty():
			continue
		var stride: int = 4 if kind == Mesh.ARRAY_TANGENT else 1 # Tangents are flat floats, four per vertex.
		var copy: Variant = source.duplicate()
		copy.resize(corners.size() * stride)
		for slot in corners.size():
			for part in stride:
				copy[slot * stride + part] = source[corners[slot] * stride + part]
		result[kind] = copy
	return result
