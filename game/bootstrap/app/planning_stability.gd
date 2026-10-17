extends RefCounted
## Conservative red warnings with a bounded round-robin query budget.
const PER_FRAME := 8
var _cursor := 0
var _marks := {}
var _material: StandardMaterial3D


func update(objects: Node, geometry: RefCounted) -> void:
	var nodes: Array = objects.placed
	if is_instance_valid(objects.selected):
		_check(objects.selected, geometry)
	for index in mini(PER_FRAME, nodes.size()):
		_cursor %= nodes.size()
		var node: Node3D = nodes[_cursor]
		_cursor += 1
		if is_instance_valid(node):
			_check(node, geometry)
	for node: Variant in _marks.keys():
		if not is_instance_valid(node):
			_marks.erase(node)


func clear() -> void:
	for marker: MeshInstance3D in _marks.values():
		if is_instance_valid(marker):
			marker.free()
	_marks.clear()


func _check(node: Node3D, geometry: RefCounted) -> void:
	if not may_move(node, AABB(Vector3.ZERO, Vector3.ONE)):
		if _marks.has(node):
			if is_instance_valid(_marks[node]):
				_marks[node].free()
			_marks.erase(node)
		return
	var bounds: AABB = geometry.call("_combined_aabb", node, true)
	if not _marks.has(node):
		var marker := MeshInstance3D.new()
		marker.name = "PlanningStabilityWarning"
		marker.set_meta("planning_bounds_excluded", true)
		marker.set_meta("planning_selection_highlight", true)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.mesh = BoxMesh.new()
		if _material == null:
			_material = StandardMaterial3D.new()
			_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_material.albedo_color = Color(1.0, 0.02, 0.01, 0.24)
		marker.material_override = _material
		node.add_child(marker)
		_marks[node] = marker
	var visual: MeshInstance3D = _marks[node]
	(visual.mesh as BoxMesh).size = bounds.size + Vector3.ONE * 0.015
	visual.position = bounds.get_center()


static func may_move(node: Node3D, bounds: AABB) -> bool:
	if node.has_method("get_decor_pose") and not node is RigidBody3D:
		var pose: Dictionary = node.call("get_decor_pose")
		return not pose.has("physics_v1") or not node.has_meta("planning_settled_transform") or node.get_meta("planning_settled_transform") != node.transform
	if not node is RigidBody3D or node.freeze or bounds.size.length_squared() < 0.00001:
		return false
	return preload("res://game/bootstrap/app/planning_physics_probe.gd").may_move(node)
