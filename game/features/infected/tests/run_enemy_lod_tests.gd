extends SceneTree
## Preserve imported LOD buffers when adding rest-space wound coordinates.
const BODY := preload("res://game/features/infected/body_part_mesh.gd")
const SCENES := [
	"res://game/features/infected/public/infected_capsule.tscn",
	"res://game/features/infected/public/mutant_level2.tscn",
	"res://game/features/infected/public/infected_hunger.tscn",
	"res://game/features/infected/public/infected_revenant.tscn",
	"res://game/features/infected/public/infected_brute.tscn",
	"res://game/features/infected/public/infected_titan.tscn",
	"res://game/features/infected/public/infected_colossus.tscn",
	"res://game/features/infected/public/infected_horde.tscn",
]
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for vertex_count in [4, 65537]:
		for stride in [4, 8]:
			_check_preparation(vertex_count, stride)
	_check_preparation(4, 4, false)
	_check_baked_models()
	var imported_lods := 0
	for path: String in SCENES:
		var enemy := (load(path) as PackedScene).instantiate()
		var snapshots: Array[Dictionary] = []
		for instance: MeshInstance3D in enemy.find_children("*", "MeshInstance3D", true, false):
			if not instance.mesh is ArrayMesh:
				continue
			var source := instance.mesh as ArrayMesh
			for surface in source.get_surface_count():
				var lods: Array = RenderingServer.mesh_get_surface(source.get_rid(), surface).get("lods", [])
				imported_lods += lods.size()
				snapshots.append({"instance": instance, "surface": surface, "lods": lods})
		root.add_child(enemy)
		for snapshot: Dictionary in snapshots:
			var instance: MeshInstance3D = snapshot.instance
			var after: Array = RenderingServer.mesh_get_surface(instance.mesh.get_rid(), snapshot.surface).get("lods", [])
			_expect(after == snapshot.lods, "Ready enemy preserves exact LOD bytes/thresholds: " + path)
		enemy.queue_free()
		await process_frame
	_expect(imported_lods > 0, "Real enemy assets exercise imported LODs")
	print("Enemy LOD tests: %d imported levels, %d failures" % [imported_lods, failures])
	quit(0 if failures == 0 else 1)


func _check_baked_models() -> void:
	for enemy: String in ["Hunger", "Revenant", "Brute", "Titan", "Colossus", "Horde"]:
		for suffix: String in ["_game.res", "_rig_mesh.res"]:
			var mesh := load("res://models/objects/characters/enemy/game/" + enemy + suffix) as ArrayMesh
			for surface in mesh.get_surface_count():
				var stored := RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
				var stride := RenderingServer.mesh_surface_get_format_index_stride(stored.format, stored.vertex_count)
				var lods: Array = stored.get("lods", [])
				_expect(not lods.is_empty(), "Baked enemy has LODs: " + enemy + suffix)
				for lod: Dictionary in lods:
					var bytes: PackedByteArray = lod.index_data
					_expect(lod.edge_length > 0 and bytes.size() < stored.index_data.size(), "LOD has threshold and fewer triangles")
					_expect(bytes.size() % (3 * stride) == 0, "LOD indices form triangles")
					for offset in range(0, bytes.size(), stride):
						var index := bytes.decode_u16(offset) if stride == 2 else bytes.decode_u32(offset)
						_expect(index < stored.vertex_count, "LOD references original vertices")


func _check_preparation(vertex_count: int, stride: int, with_lods: bool = true) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	bones.resize(vertex_count * stride)
	weights.resize(vertex_count * stride)
	for index in vertex_count:
		vertices[index] = Vector3(index % 2, (index / 2) % 2, 0)
		normals[index] = Vector3.BACK
		weights[index * stride] = 1.0
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, vertex_count - 1, 0, vertex_count - 1, 2])
	var lods := {2.5: PackedInt32Array([0, 1, vertex_count - 1]), 9.0: PackedInt32Array([0, vertex_count - 1, 2])} if with_lods else {}
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if stride == 8 else 0
	var source := ArrayMesh.new()
	for surface in 2:
		source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods, flags)
		source.surface_set_material(surface, StandardMaterial3D.new())
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Root")
	var instance := MeshInstance3D.new()
	instance.mesh = source
	var data := BODY.prepare(instance, skeleton)
	var converted := instance.mesh as ArrayMesh
	_expect(converted.get_surface_count() == 2, "All surfaces retained")
	for surface in source.get_surface_count():
		var before := RenderingServer.mesh_get_surface(source.get_rid(), surface)
		var after := RenderingServer.mesh_get_surface(converted.get_rid(), surface)
		_expect(after.get("lods", []) == before.get("lods", []), "Exact 16/32-bit LOD bytes and thresholds retained")
		_expect(before.get("lods", []).size() == (2 if with_lods else 0), "Source LODs remain unchanged")
		_expect(after.index_data == before.index_data, "Base triangle indices retained")
		_expect(converted.surface_get_material(surface) == source.surface_get_material(surface), "Material retained")
		var output := converted.surface_get_arrays(surface)
		for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			_expect(output[slot] == source.surface_get_arrays(surface)[slot], "Vertex/skin streams retained")
		_expect((output[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array).size() == vertex_count * 4, "Wound coordinates added")
		_expect(data.surfaces[surface].stride == stride, "Bone stride retained")
		_expect(data.surfaces[surface].indices == arrays[Mesh.ARRAY_INDEX], "Severing uses full base topology")
	var second := MeshInstance3D.new()
	second.mesh = source
	var cached := BODY.prepare(second, skeleton)
	_expect(second.mesh == converted and is_same(cached, data), "Cache shares prepared mesh and data")
	_expect(is_same(BODY.prepare(instance, skeleton), data), "Already prepared mesh keeps cache identity")
	second.free()
	instance.free()
	skeleton.free()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
