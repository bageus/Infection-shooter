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
	# The source GLB contains two 1.5 m flights joined by a turn landing. Thin
	# imported treads alone leave gaps a CharacterBody can fall through.
	_add_walkable_box(body, Vector3(-1.06, 0.67, 1.41), Vector3(1.85, 0.18, 3.2), -atan(1.5 / 2.82))
	_add_walkable_box(body, Vector3(1.06, 2.17, 1.41), Vector3(1.85, 0.18, 3.2), atan(1.5 / 2.82))
	_add_walkable_box(body, Vector3(0, -0.11, -0.71), Vector3(3.9, 0.20, 1.4), 0.0)
	_add_walkable_box(body, Vector3(0, 1.40, 3.52), Vector3(3.9, 0.20, 1.4), 0.0)
	_add_walkable_box(body, Vector3(0, 2.90, -0.71), Vector3(3.9, 0.20, 1.4), 0.0)


func _add_mesh_collisions(node: Node, body: StaticBody3D) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.visible and not ("step" in mesh.name.to_lower() or "riser" in mesh.name.to_lower() or "tread" in mesh.name.to_lower()):
			var shape := mesh.mesh.create_trimesh_shape()
			if shape != null:
				var collision := CollisionShape3D.new()
				collision.shape = shape
				body.add_child(collision)
				collision.global_transform = mesh.global_transform
	for child in node.get_children():
		_add_mesh_collisions(child, body)


func _add_walkable_box(body: StaticBody3D, center: Vector3, dimensions: Vector3, tilt: float) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collision.shape = box
	collision.position = center
	collision.rotation.x = tilt
	body.add_child(collision)
