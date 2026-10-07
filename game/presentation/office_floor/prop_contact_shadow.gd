extends Node3D
## Light contact shadow under a floor-standing piece of furniture. It lies on
## the floor under the prop's footprint, follows it when it is pushed or
## knocked over and fades while the prop is in the air. Presentation only.

const SHADER := preload("res://game/presentation/office_floor/prop_contact_shadow.gdshader")
## Base floor top (tile_y .001 + half its .025 thickness) plus a lift above it.
const FLOOR_Y := 0.0135 + 0.003
## Only props standing on the floor with a footprint this wide get a shadow.
const MAX_BASE_HEIGHT := 0.15
const MIN_FOOTPRINT := 0.3
const MARGIN := 0.22
## Lifted this high above its resting floor the shadow is gone.
const FADE_HEIGHT := 0.6

static var _material: ShaderMaterial
static var _quad: QuadMesh

var _owner_prop: Node3D
var _local_bounds := AABB()
var _floor_y := FLOOR_Y
var _shadow: MeshInstance3D
var _visual: Node3D


## Measures the prop's meshes; false when the prop is not a floor-standing
## piece that should cast a contact shadow. The shadow hides with visual.
func configure(prop: Node3D, visual: Node3D, meshes: Array[MeshInstance3D]) -> bool:
	_owner_prop = prop
	_visual = visual
	var found := false
	var inverse := prop.global_transform.affine_inverse()
	for mesh in meshes:
		if not is_instance_valid(mesh) or mesh.mesh == null:
			continue
		var bounds: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		_local_bounds = bounds if not found else _local_bounds.merge(bounds)
		found = true
	if not found:
		return false
	var world := prop.global_transform * _local_bounds
	if world.position.y > FLOOR_Y + MAX_BASE_HEIGHT or minf(world.size.x, world.size.z) < MIN_FOOTPRINT:
		return false
	_floor_y = maxf(world.position.y, FLOOR_Y - 0.003) + 0.003
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadowQuad"
	_shadow.mesh = _shared_quad()
	_shadow.material_override = _shared_material()
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	set_notify_transform(true)
	visual.visibility_changed.connect(_update)
	_update()
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree() and _shadow != null:
		_update()


# Footprint of the oriented bounds on the floor, along the prop's own axes.
func _update() -> void:
	var frame := _owner_prop.global_transform
	var right := Vector3(frame.basis.x.x, 0.0, frame.basis.x.z)
	if right.length_squared() < 0.09:
		right = Vector3(frame.basis.y.x, 0.0, frame.basis.y.z)
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var ahead := right.cross(Vector3.UP)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var bottom := INF
	for corner in 8:
		var point := frame * _local_bounds.get_endpoint(corner)
		var flat := Vector2(point.dot(right), point.dot(ahead))
		low = low.min(flat)
		high = high.max(flat)
		bottom = minf(bottom, point.y)
	var half := (high - low) * 0.5 + Vector2(MARGIN, MARGIN)
	var middle := (high + low) * 0.5
	var center := right * middle.x + ahead * middle.y
	center.y = _floor_y
	# The quad faces +Z; lay it flat with its width along right.
	var basis := Basis(right * half.x * 2.0, ahead * half.y * 2.0, Vector3.UP)
	_shadow.global_transform = Transform3D(basis, center)
	_shadow.set_instance_shader_parameter(&"half_size", half)
	_shadow.set_instance_shader_parameter(&"margin", MARGIN)
	var lift := maxf(bottom - _floor_y, 0.0)
	_shadow.set_instance_shader_parameter(&"presence", 1.0 - smoothstep(0.05, FADE_HEIGHT, lift))
	_shadow.visible = _visual.is_visible_in_tree()


static func _shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


static func _shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = -2
	return _material
