extends Node3D
const LAUNCHER_MODEL_PATH := "res://models/objects/weapons/six_chamber_launcher_lowpoly.glb"

# Imported art can be added later without changing weapon or pickup scenes.
func _ready() -> void:
	var visual := make_visual()
	add_child(visual)
	if launcher_model() != null:
		# Authored barrel points along +X; the weapon muzzle points along -Z.
		visual.rotation_degrees.y = 90.0


static func launcher_model() -> PackedScene:
	if ResourceLoader.exists(LAUNCHER_MODEL_PATH):
		return load(LAUNCHER_MODEL_PATH) as PackedScene
	var folders := ["res://models/objects/weapons/"]
	for index in range(1, 14):
		folders.append("res://models/objects/enviroments/%02d/" % index)
	for directory_path in folders:
		var directory := DirAccess.open(directory_path)
		if directory == null:
			continue
		for file in directory.get_files():
			var lower := file.to_lower()
			if file.ends_with(".glb") and "casing" not in lower and ("launcher" in lower or "grenade" in lower):
				return load(directory_path + file) as PackedScene
	return null


static func casing_model() -> PackedScene:
	var path := "res://models/objects/enviroments/12/12_launcher_casing_lowpoly.glb"
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = 0.04
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.6, 0.18)
	cylinder.material = material
	var node := MeshInstance3D.new()
	node.mesh = cylinder
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	return packed


static func make_visual(grenade_launcher: bool = true) -> Node3D:
	var model := launcher_model() if grenade_launcher else null
	if model != null:
		return model.instantiate() as Node3D
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.17, 0.22, 0.23) if grenade_launcher else Color(0.24, 0.28, 0.32)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.75, 0.52, 0.17)
	_add_box(root, Vector3(0, 0.0, -0.3), Vector3(0.17, 0.16, 0.7), metal)
	_add_box(root, Vector3(0, -0.12, 0.16), Vector3(0.12, 0.3, 0.26), metal)
	if grenade_launcher:
		var drum := CylinderMesh.new()
		drum.top_radius = 0.2
		drum.bottom_radius = 0.2
		drum.height = 0.22
		drum.material = brass
		var drum_visual := MeshInstance3D.new()
		drum_visual.mesh = drum
		drum_visual.rotation.z = PI * 0.5
		drum_visual.position = Vector3(0, -0.15, -0.1)
		root.add_child(drum_visual)
	return root


static func _add_box(parent: Node3D, position_value: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position_value
	parent.add_child(node)
