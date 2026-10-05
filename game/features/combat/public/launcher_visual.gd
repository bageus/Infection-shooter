extends Node3D
const LAUNCHER_MODEL_PATH := "res://models/objects/weapons/six_chamber_launcher_lowpoly.glb"
const ART_SETUP := preload("res://game/features/combat/weapon_art_setup.gd")

# Imported art can be added later without changing weapon or pickup scenes.
func _ready() -> void:
	var visual := make_visual()
	add_child(visual)


static func launcher_model() -> PackedScene:
	if ResourceLoader.exists(LAUNCHER_MODEL_PATH):
		return load(LAUNCHER_MODEL_PATH) as PackedScene
	var folders := ["res://models/objects/weapons/"]
	for index in range(1, 14):
		folders.append("res://models/objects/enviroments/%02d/" % index)
	for directory_path in folders:
		for file: String in ResourceLoader.list_directory(directory_path):
			var lower := file.to_lower()
			if file.ends_with(".glb") and "casing" not in lower and ("launcher" in lower or "grenade" in lower):
				return load(directory_path + file) as PackedScene
	return null


# Public v1 pickup art: weapon indices match the player's existing slots.
static func make_pickup_visual(index: int) -> Node3D:
	var paths := [
		"res://models/objects/weapons/pistol_lowpoly.glb",
		"res://models/objects/weapons/uzi_lowpoly.glb",
		"res://models/objects/weapons/shotgun_lowpoly.glb",
		"res://models/objects/weapons/six_chamber_launcher_lowpoly.glb"
	]
	if index < 0 or index >= paths.size() or not ResourceLoader.exists(paths[index]):
		push_error("Weapon pickup model unavailable for index %d" % index)
		return Node3D.new()
	var model := load(paths[index]) as PackedScene
	var root := Node3D.new()
	if model != null:
		var visual := model.instantiate() as Node3D
		root.add_child(visual)
		var authored_root := ART_SETUP.find_marker(visual, "WeaponRoot")
		if authored_root != null:
			ART_SETUP.normalize_model(visual, authored_root)
	return root


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
	var model: PackedScene = launcher_model() if grenade_launcher else null
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
