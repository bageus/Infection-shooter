extends RefCounted

const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
const BOOKS := [
	preload("res://models/objects/enviroments/09/09_book_small.glb"),
	preload("res://models/objects/enviroments/09/09_book_big.glb"),
	preload("res://models/objects/enviroments/09/09_book_fat.glb")
]


static func contains(model_path: String) -> bool:
	return model_path.get_file().get_basename() in ["09_books", "09_books_alt", "09_books_alt_2"]


static func scatter(host: Node3D, visual: Node3D, hit_position: Vector3, direction: Vector3) -> void:
	var source_mesh := visual.find_child("*", "MeshInstance3D", true, false) as MeshInstance3D
	if source_mesh == null:
		return
	var bounds: AABB = source_mesh.global_transform * source_mesh.get_aabb()
	var count := clampi(roundi(bounds.size.length() / 0.11), 3, 8)
	var axis := host.global_basis.x.normalized()
	for index in count:
		var book := (BOOKS[index % BOOKS.size()] as PackedScene).instantiate() as Node3D
		if book == null:
			continue
		host.get_tree().current_scene.add_child(book)
		book.global_rotation.y = host.global_rotation.y + randf_range(-0.15, 0.15)
		var offset := (float(index) - float(count - 1) * 0.5) * 0.085
		var target := bounds.get_center() + axis * offset
		book.global_position = target
		var mesh := book.find_child("*", "MeshInstance3D", true, false) as MeshInstance3D
		if mesh != null:
			var book_bounds: AABB = mesh.global_transform * mesh.get_aabb()
			book.global_position += target - book_bounds.get_center()
			book.global_position.y += bounds.position.y + randf_range(0.0, 0.06) - (mesh.global_transform * mesh.get_aabb()).position.y
			DAMAGE.spawn_piece(host, mesh, null, 0, index, (direction + axis * randf_range(-0.8, 0.8)).normalized(), hit_position)
		book.queue_free()
