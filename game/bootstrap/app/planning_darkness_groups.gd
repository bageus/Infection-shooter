extends Node3D
## Temporary world-space group markers; never children of authored darkness zones.
var markers: Dictionary = {}
var _fill: StandardMaterial3D
var _edge: StandardMaterial3D


func _init() -> void:
	set_process(false)
	_fill = _material(Color(0.08, 0.8, 1.0, 0.2))
	_edge = _material(Color(0.1, 0.95, 1.0, 1.0))


func refresh(zones: Array[Node3D], group: int) -> void:
	var wanted := {}
	for zone in zones:
		if int(zone.get("room_id")) != group:
			continue
		var id := zone.get_instance_id()
		wanted[id] = true
		if not markers.has(id):
			var marker := MeshInstance3D.new()
			marker.name = "DarknessGroupHighlight"
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker.set_meta("planning_bounds_excluded", true)
			marker.set_meta("planning_selection_highlight", true)
			add_child(marker)
			markers[id] = {"source": weakref(zone), "visual": marker, "size": Vector2.ZERO}
	for id in markers.keys():
		if not wanted.has(id):
			_remove(id)
	set_process(not markers.is_empty())
	_process(0.0)


func clear() -> void:
	for id in markers.keys():
		_remove(id)
	set_process(false)


func _remove(id: int) -> void:
	var visual: MeshInstance3D = markers[id].visual
	visual.hide()
	visual.queue_free()
	markers.erase(id)


func _process(_delta: float) -> void:
	for id in markers.keys():
		var entry: Dictionary = markers[id]
		var zone := entry.source.get_ref() as Node3D
		if not is_instance_valid(zone) or zone.is_queued_for_deletion():
			_remove(id)
			continue
		var size: Vector2 = zone.get("size")
		var visual: MeshInstance3D = entry.visual
		if size != entry.size:
			visual.mesh = _mesh(size)
			entry.size = size
		visual.global_transform = zone.global_transform
	set_process(not markers.is_empty())


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.render_priority = 126
	material.albedo_color = color
	return material


func _mesh(size: Vector2) -> ImmediateMesh:
	var x := size.x * 0.5
	var z := size.y * 0.5
	var corners := [Vector3(-x, 0.04, -z), Vector3(x, 0.04, -z), Vector3(x, 0.04, z), Vector3(-x, 0.04, z)]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _fill)
	for index in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(corners[index])
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _edge)
	for index in 4:
		mesh.surface_add_vertex(corners[index])
		mesh.surface_add_vertex(corners[(index + 1) % 4])
	mesh.surface_end()
	return mesh
