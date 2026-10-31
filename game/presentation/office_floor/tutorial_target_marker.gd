extends Node3D
## Target ring plus a small downward arrow above the parent object; bobs gently and
## hides itself when the object is broken.

const COLOR := Color("ff5a1f")
const CLEARANCE := 0.28

var _host: Node3D
var _bob: Node3D
var _time := 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	_bob = Node3D.new()
	add_child(_bob)
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 1.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 10
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.17
	torus.outer_radius = 0.22
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0 - 37.0 # faces the tilted game camera
	ring.material_override = material
	ring.position.y = 0.34
	_bob.add_child(ring)
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	dot.mesh = sphere
	dot.material_override = material
	dot.position.y = 0.34
	_bob.add_child(dot)
	var arrow := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.2
	arrow.mesh = cone
	arrow.rotation_degrees.x = 180.0 # tip points down at the object
	arrow.material_override = material
	arrow.position.y = 0.1
	_bob.add_child(arrow)
	_place.call_deferred()


# Floats above the object's own top, whatever its size.
func _place() -> void:
	if _host == null or not is_inside_tree():
		return
	var top := 0.0
	var found := false
	for node in _host.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null or visual.get_parent() == _bob:
			continue
		var box := visual.global_transform * visual.get_aabb()
		top = box.end.y if not found else maxf(top, box.end.y)
		found = true
	if found:
		global_position = Vector3(_host.global_position.x, top + CLEARANCE, _host.global_position.z)
		global_rotation = Vector3.ZERO


func _process(delta: float) -> void:
	_time += delta
	_bob.position.y = sin(_time * 3.0) * 0.05
	visible = _is_standing()


func _is_standing() -> bool:
	if _host == null:
		return false
	var damage: Variant = _host.get("_damage")
	if damage == null:
		return true
	return not (bool(damage.broken) or bool(damage.glass_broken) or bool(damage.extinguisher_triggered)
			or bool(damage.transition_pending) or int(damage.variant_index) >= 0)
