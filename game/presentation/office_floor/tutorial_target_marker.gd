extends Node3D
## Quest target marker above the parent object: a pulsing floor reticle with rotating chevrons, a chasing
## down-arrow that bobs and a light beam (all drawn by tutorial_target_marker.gdshader); hides itself when the object is broken. It stays hidden until the tutorial reveals its kind, and walls hide it.

const COLOR := Color("ff5a1f")
const CLEARANCE := 0.45
const BEAM_HEIGHT := 2.0
const SHADER := preload("res://game/presentation/office_floor/tutorial_target_marker.gdshader")

var _host: Node3D
var _bob: Node3D
var _ground: MeshInstance3D
var _beam: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	_host = get_parent() as Node3D
	_bob = Node3D.new()
	add_child(_bob)
	_bob.add_child(_quad(1, QuadMesh.new(), Vector2(0.7, 0.7), 10, 0.0))
	_ground = _quad(0, PlaneMesh.new(), Vector2(2.2, 2.2), 8, 0.0)
	add_child(_ground)
	_beam = _quad(2, QuadMesh.new(), Vector2(0.5, BEAM_HEIGHT), 9, 0.0)
	add_child(_beam)
	_place.call_deferred()


# One animated quad drawn by the marker shader (mode: 0 floor reticle, 1 arrow, 2 beam).
func _quad(mode: int, mesh: PrimitiveMesh, size: Vector2, priority: int, y: float) -> MeshInstance3D:
	mesh.set("size", size)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("tint", COLOR)
	material.render_priority = priority
	var quad := MeshInstance3D.new()
	quad.mesh = mesh
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position.y = y
	return quad


# Floats above the object's own top and rings its footprint, whatever its size.
func _place() -> void:
	if _host == null or not is_inside_tree():
		return
	var top := 0.0
	var found := false
	var footprint := Vector2(0.7, 0.7)
	for node in _host.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null or visual.get_parent() == _bob or visual.get_parent() == self:
			continue
		var box := visual.global_transform * visual.get_aabb()
		top = box.end.y if not found else maxf(top, box.end.y)
		footprint = Vector2(box.size.x, box.size.z) if not found else footprint.max(Vector2(box.size.x, box.size.z))
		found = true
	if found:
		global_position = Vector3(_host.global_position.x, top + CLEARANCE, _host.global_position.z)
		global_rotation = Vector3.ZERO
		var diameter := clampf(maxf(footprint.x, footprint.y) + 1.3, 1.8, 5.0)
		(_ground.mesh as PlaneMesh).size = Vector2(diameter, diameter)
	var floor_y := _host.global_position.y + 0.03 - global_position.y
	_ground.position.y = floor_y
	var beam_top := 1.0 + CLEARANCE
	(_beam.mesh as QuadMesh).size.y = beam_top - floor_y
	_beam.position.y = floor_y + (beam_top - floor_y) * 0.5


func _process(delta: float) -> void:
	_time += delta
	_bob.position.y = 0.12 + sin(_time * 3.0) * 0.06
	visible = _host != null and bool(_host.get_meta(&"planning_tutorial_revealed", false)) and _is_standing()


func _is_standing() -> bool:
	if _host == null:
		return false
	var damage: Variant = _host.get("_damage")
	if damage == null:
		return true
	return not (bool(damage.broken) or bool(damage.glass_broken) or bool(damage.extinguisher_triggered)
			or bool(damage.transition_pending) or int(damage.variant_index) >= 0)
