extends RefCounted
## Spent brass lying around the map is 5 cm long but its model has 3-4 surfaces and over 1000 vertices.
## Placed casings swap it for one shared 8-sided cylinder of the same size and material: one draw call each.
const SEGMENTS := 8
static var _meshes: Dictionary = {}


static func apply(node: Node3D, scene_path: String) -> void:
	var file := scene_path.get_file()
	if not (file.begins_with("12_") and file.ends_with("_casing.glb")):
		return
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var source := found as MeshInstance3D
		if source.mesh == null or source.mesh.get_surface_count() < 2 or source.skeleton != NodePath():
			continue
		var box := source.mesh.get_aabb()
		var axis := box.size.max_axis_index()
		var key := [file, snappedf(box.size.x, 0.0001), snappedf(box.size.y, 0.0001), snappedf(box.size.z, 0.0001)]
		if not _meshes.has(key):
			var cylinder := CylinderMesh.new()
			cylinder.height = box.size[axis]
			cylinder.top_radius = (box.size[(axis + 1) % 3] + box.size[(axis + 2) % 3]) / 4.0
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.radial_segments = SEGMENTS
			cylinder.rings = 1
			cylinder.material = source.mesh.surface_get_material(0)
			_meshes[key] = cylinder
		# CylinderMesh stands along Y: tip it onto the model's long axis and onto the model's centre.
		var along := Basis.IDENTITY if axis == 1 else (Basis(Vector3.BACK, PI / 2.0) if axis == 0 else Basis(Vector3.RIGHT, PI / 2.0))
		source.mesh = _meshes[key]
		source.transform = source.transform * Transform3D(along, box.get_center())
