extends Node3D

# One scene-local budget for bullet and wood marks, and another for settled debris.
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
