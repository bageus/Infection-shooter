extends Node3D

# Use the authored stair meshes as walkable static geometry. A single box around
# the imported object would seal the flights and stop the player at the entrance.
@export_file("*.glb") var model_path := "res://models/objects/enviroments/01/01_stairs.glb"


func _ready() -> void:
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_error("Staircase model unavailable: " + model_path)
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "Visual"
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "WalkableStairCollision"
	body.collision_layer = 3
	add_child(body)
	_add_mesh_collisions(visual, body)


func _add_mesh_collisions(node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree():
			var shape := mesh.mesh.create_trimesh_shape()
			if shape != null:
				var collision := CollisionShape3D.new()
				collision.shape = shape
				body.add_child(collision)
				collision.global_transform = mesh.global_transform
	for child in node.get_children():
		_add_mesh_collisions(child, body)
