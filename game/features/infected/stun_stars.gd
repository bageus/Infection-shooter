extends MeshInstance3D
## One shared quad with a shader: a crackling ring of energy circles the stunned head.
const HALO := preload("res://game/features/infected/stun_halo.gdshader")
static var _mesh: PlaneMesh
var _age := 0.0
var _fade := -1.0

static func spawn(body: Node3D, height: float, size: float) -> MeshInstance3D:
	var orbit: MeshInstance3D = load("res://game/features/infected/stun_stars.gd").new()
	orbit.name = "StunStars"
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = Vector2.ONE * 1.4
		var material := ShaderMaterial.new()
		material.shader = HALO
		_mesh.material = material
	orbit.mesh = _mesh
	orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(orbit)
	orbit.position = Vector3.UP * height
	orbit.scale = Vector3.ONE * size
	orbit.rotation.x = 0.35
	return orbit

func stop(seconds: float) -> void:
	_fade = maxf(seconds, 0.001)

func _process(delta: float) -> void:
	_age += delta
	rotation.y = _age * 2.8
	if _fade >= 0.0:
		var previous := _fade
		_fade = maxf(0.0, _fade - delta)
		scale *= _fade / maxf(previous, 0.001)
		if _fade == 0.0:
			queue_free()
