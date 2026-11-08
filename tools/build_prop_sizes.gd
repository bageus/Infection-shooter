extends SceneTree
## Writes the largest extent (metres, at scale 1) of every environment model's intact shape.
## Usage: godot --headless --path . --script tools/build_prop_sizes.gd
const ROOT := "res://models/objects/enviroments"
const OUT := "res://game/bootstrap/app/prop_sizes.json"
const STAGES := ["LargeParts", "SmallFragments", "JaggedFragments", "PlantDestroyed", "PotFragments", "Fragments", "Primary", "Panels", "Medium", "Fine", "TopSecondary", "DamageReady", "Modular", "Door_Off", "Broken_7"]


func _initialize() -> void:
	var sizes := {}
	for sub in DirAccess.get_directories_at(ROOT):
		for file in DirAccess.get_files_at(ROOT + "/" + sub):
			if file.ends_with(".glb"):
				var scene := load(ROOT + "/" + sub + "/" + file) as PackedScene
				if scene == null:
					continue
				var node := scene.instantiate() as Node3D
				var box := _bounds(node, Transform3D.IDENTITY)
				sizes[file] = snappedf(maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.01)
				node.free()
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(sizes, "\t", true))
	print("Wrote ", sizes.size(), " model sizes")
	quit(0)


func _bounds(node: Node, to_root: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		box = to_root * (node as MeshInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		if child is Node3D and (STAGES.has(String(child.name)) or (child as Node3D).scale == Vector3.ZERO):
			continue
		var inner := _bounds(child, to_root * (child as Node3D).transform if child is Node3D else to_root)
		if inner.size != Vector3.ZERO or inner.position != Vector3.ZERO:
			box = inner if first else box.merge(inner)
			first = false
	return box
