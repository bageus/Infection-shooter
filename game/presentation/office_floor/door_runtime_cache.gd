extends RefCounted
## Derived geometry inputs only; the door keeps its lock, timing and motion state.
var _visual: Node3D
var _glass: StaticBody3D
var _glass_mode := false
var _shapes: Array[CollisionShape3D] = []
var _shapes_dirty := true


func bind(door: Node3D, glass_mode: bool) -> void:
	clear()
	_glass_mode = glass_mode
	if not glass_mode:
		return
	var parent := door.get_parent()
	_visual = parent.get_node_or_null("Visual") as Node3D
	_glass = parent.get_node_or_null("GlassBody") as StaticBody3D
	if is_instance_valid(_glass):
		_glass.child_entered_tree.connect(_child_changed)
		_glass.child_exiting_tree.connect(_child_changed)


func clear() -> void:
	if is_instance_valid(_glass):
		_glass.child_entered_tree.disconnect(_child_changed)
		_glass.child_exiting_tree.disconnect(_child_changed)
	_visual = null
	_glass = null
	_shapes.clear()
	_shapes_dirty = true


func local_player(door: Node3D, point: Vector3, glass_mode: bool) -> Vector3:
	if glass_mode != _glass_mode:
		bind(door, glass_mode)
	# Glass scenes can offset Visual from the controller. Preserve the original
	# local-XZ trigger, including parent rotation/scale and the ignored local Y.
	if is_instance_valid(_visual):
		point -= _visual.global_position - door.global_position
	return door.to_local(point)


func _child_changed(child: Node) -> void:
	if child is CollisionShape3D:
		_shapes_dirty = true


func refresh_glass_collision() -> void:
	if not is_instance_valid(_glass):
		return
	if _shapes_dirty:
		_shapes.clear()
		for child in _glass.get_children():
			if child is CollisionShape3D:
				_shapes.append(child)
		_shapes_dirty = false
	var broken := bool(_glass.get("_broken"))
	for shape in _shapes:
		if is_instance_valid(shape) and shape.disabled != broken:
			shape.set_deferred("disabled", broken)
