extends Node3D

# One scene-local budget for bullet and wood marks, and another for settled debris.
const PROJECTION := preload("res://game/features/combat/impact_projection.gd")
const SURFACES := preload("res://game/features/combat/impact_surface_geometry.gd")
var _surfaces := SURFACES.new()


func register_surface(collider: Node3D, visual: Node3D) -> void:
	_surfaces.register(collider, visual)


func resolve_surface(collider: Node3D, point: Vector3, direction: Vector3) -> Dictionary:
	return _surfaces.resolve(collider, point, direction)


const MAX_MARKS := 40
const MAX_RETAINED := 40

var _marks: Array[Node3D] = []
var _retained: Array[RigidBody3D] = []
var _textures: Dictionary = {}


func texture_for(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path) as Texture2D
	if texture == null:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


func register_mark(mark: Node3D) -> void:
	_prune_marks()
	_marks.append(mark)
	var anchor := mark.get_parent() as Node3D
	if anchor != null:
		var callback := func() -> void:
			if is_instance_valid(mark) and not anchor.visible:
				mark.queue_free()
		anchor.visibility_changed.connect(callback)
		mark.tree_exiting.connect(func() -> void:
			if is_instance_valid(anchor) and anchor.visibility_changed.is_connected(callback):
				anchor.visibility_changed.disconnect(callback))
	while _marks.size() > MAX_MARKS:
		var oldest: Node3D = _marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func register_retained(body: RigidBody3D) -> void:
	_prune_retained()
	_retained.append(body)
	while _retained.size() > MAX_RETAINED:
		var oldest: RigidBody3D = _retained.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _prune_marks() -> void:
	for index in range(_marks.size() - 1, -1, -1):
		if not is_instance_valid(_marks[index]) or _marks[index].is_queued_for_deletion():
			_marks.remove_at(index)


func _prune_retained() -> void:
	for index in range(_retained.size() - 1, -1, -1):
		if not is_instance_valid(_retained[index]) or _retained[index].is_queued_for_deletion():
			_retained.remove_at(index)


func projected_geometry(collider: Node3D, projector: Transform3D, footprint: Vector2, depth: float = .12, skip_glass: bool = false) -> Array[Dictionary]:
	return PROJECTION.geometry(_surfaces, collider, projector, footprint, depth, skip_glass)


func project_surface(collider: Node3D, projector: Transform3D, footprint: Vector2, material: Material, depth: float = .12, skip_glass: bool = false) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for entry in projected_geometry(collider, projector, footprint, depth, skip_glass):
		var mark := MeshInstance3D.new()
		mark.set_meta("surface_mark", true)
		mark.mesh = entry["mesh"]
		mark.material_override = material
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		entry["anchor"].add_child(mark)
		result.append(mark)
	return result
