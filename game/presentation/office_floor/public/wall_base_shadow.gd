extends Node3D
## Soft baked contact shadow on the floor along both sides of a solid wall, so the
## wall/floor junction stays readable when real shadows are off. Two flat quads
## sharing one mesh and one material; they are visible only while shadows are off.

const SHADER := preload("res://game/presentation/office_floor/wall_base_shadow.gdshader")
const GROUP := &"wall_base_shadows"
## Same floor lift as the prop contact shadows (floor top .0135 plus a margin).
const FLOOR_Y := 0.0135 + 0.003
const DEPTH := 0.5
static var _shadows_allowed := true
static var _quad: QuadMesh
static var _material: ShaderMaterial

var _strips: Array[MeshInstance3D] = []


func _ready() -> void:
	var collision := get_parent().get_node_or_null("Body/CollisionShape3D") as CollisionShape3D
	var box := collision.shape as BoxShape3D if collision != null else null
	if box == null:
		return
	var center := collision.position
	var half_thickness := box.size.z * 0.5
	for side in 2:
		var strip := MeshInstance3D.new()
		strip.name = "Strip%d" % side
		strip.set_meta("planning_bounds_excluded", true)
		strip.mesh = _shared_quad()
		strip.material_override = _shared_material()
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The strip's -Z edge lies on the wall face; the second one is turned half a circle.
		var outward := 1.0 if side == 0 else -1.0
		var basis := Basis.from_scale(Vector3(box.size.x, 1.0, DEPTH))
		if side == 1:
			basis = Basis(Vector3.UP, PI) * basis
		strip.transform = Transform3D(basis, Vector3(center.x, 0.0, center.z + outward * (half_thickness + DEPTH * 0.5)))
		add_child(strip)
		strip.global_position.y = FLOOR_Y
		_strips.append(strip)
	add_to_group(GROUP)
	set_active(not _shadows_allowed)


## The shadow setting: the strips of every wall show only while shadows are off.
static func set_shadows_allowed(tree: SceneTree, allowed: bool) -> void:
	_shadows_allowed = allowed
	if tree != null:
		tree.call_group(GROUP, &"set_active", not allowed)


## Visible only while real shadows are off.
func set_active(active: bool) -> void:
	for strip in _strips:
		strip.visible = active


static func _shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.orientation = PlaneMesh.FACE_Y
		_quad.size = Vector2.ONE
	return _quad


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = -2
	return _material
