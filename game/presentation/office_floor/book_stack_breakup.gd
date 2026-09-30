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
	if not is_instance_valid(host.get("effects_root")):
		return
	var source_mesh := _first_mesh(visual)
	if source_mesh == null:
		return
	var bounds: AABB = source_mesh.global_transform * source_mesh.get_aabb()
	var count := clampi(roundi(bounds.size.length() / 0.11), 3, 8)
	var axis := host.global_basis.x.normalized()
	for index in count:
		var book := (BOOKS[index % BOOKS.size()] as PackedScene).instantiate() as Node3D
		if book == null:
			continue
		(host.get("effects_root") as Node3D).add_child(book)
		book.global_rotation.y = host.global_rotation.y + randf_range(-0.15, 0.15)
		var offset := (float(index) - float(count - 1) * 0.5) * 0.085
		var target := bounds.get_center() + axis * offset
		book.global_position = target
		var mesh := _first_mesh(book)
		if mesh != null:
			var book_bounds: AABB = mesh.global_transform * mesh.get_aabb()
			book.global_position += target - book_bounds.get_center()
			book.global_position.y += bounds.position.y + randf_range(0.0, 0.06) - (mesh.global_transform * mesh.get_aabb()).position.y
			DAMAGE.spawn_piece(host, mesh, null, 0, index, (direction + axis * randf_range(-0.8, 0.8)).normalized(), hit_position)
		book.queue_free()


static func _first_mesh(root: Node) -> MeshInstance3D:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			return mesh
	return null
