extends MeshInstance3D
## Area skills show their reach with a low, semi-transparent dome lying on the
## floor at the damage radius. A timed dome fades in, holds and fades out; an
## open-ended one (seconds = INF) stays until stop().

const SHADER := preload("res://game/features/player/range_dome.gdshader")
## Dome height as a share of its radius, capped so wide domes stay low.
const HEIGHT_SHARE := 0.3
const MAX_HEIGHT := 0.9
const FADE_IN := 0.12
const FADE_OUT := 0.3

static var _mesh: SphereMesh
static var _material: ShaderMaterial

var _time := 0.0
var _length := INF
var _fade_out := FADE_OUT


static func spawn(parent: Node, center: Vector3, radius: float, tint: Color, seconds: float = INF) -> MeshInstance3D:
	if parent == null or not parent.is_inside_tree() or radius <= 0.0:
		return null
	var dome: MeshInstance3D = load("res://game/features/player/range_dome.gd").new()
	dome.call("_setup", radius, tint, seconds)
	parent.add_child(dome)
	dome.global_position = center + Vector3.UP * 0.02
	return dome


func _setup(radius: float, tint: Color, seconds: float) -> void:
	name = "RangeDome"
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.is_hemisphere = true
		_mesh.radius = 1.0
		_mesh.height = 1.0
		_mesh.radial_segments = 48
		_mesh.rings = 12
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter(&"height", _top())
	mesh = _mesh
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var height := minf(radius * HEIGHT_SHARE, MAX_HEIGHT)
	scale = Vector3(radius, height / _top(), radius)
	_length = seconds
	set_instance_shader_parameter(&"tint", tint)
	set_instance_shader_parameter(&"fade", 0.0)


# Local height of the hemisphere's top (Godot may build it from y 0 to 0.5).
static func _top() -> float:
	return maxf(_mesh.get_aabb().end.y, 0.01)


## Fades the dome out over `seconds` and frees it.
func stop(seconds: float = FADE_OUT) -> void:
	_fade_out = maxf(seconds, 0.01)
	_length = minf(_length, _time + _fade_out)


func _process(delta: float) -> void:
	_time += delta
	if _time >= _length:
		queue_free()
		return
	var alpha := clampf(_time / FADE_IN, 0.0, 1.0)
	if is_finite(_length):
		alpha *= clampf((_length - _time) / _fade_out, 0.0, 1.0)
	set_instance_shader_parameter(&"fade", alpha)
