extends Node3D
## Three procedural gold stars orbit the owning body's head, without an atlas.
var _age := 0.0
var _stars: Array[MeshInstance3D] = []

func _init() -> void:
	name = "StunStars"
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a := TAU * float(i) / 10.0
		var b := TAU * float(i + 1) / 10.0
		var ra := .12 if i % 2 == 0 else .055
		var rb := .12 if (i + 1) % 2 == 0 else .055
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(sin(a) * ra, cos(a) * ra, 0))
		mesh.surface_add_vertex(Vector3(sin(b) * rb, cos(b) * rb, 0))
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, .78, .05)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 3:
		var star := MeshInstance3D.new()
		star.mesh = mesh
		star.material_override = material
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(star)
		_stars.append(star)
	_process(0.0)

func _process(delta: float) -> void:
	_age += delta
	for i in _stars.size():
		var angle := _age * 3.0 + TAU * float(i) / 3.0
		_stars[i].position = Vector3(cos(angle) * .3, sin(angle * 2.0) * .05, sin(angle) * .3)

func stop(fade: float = .2) -> void:
	set_process(false)
	var tween := create_tween().set_parallel(true)
	for star in _stars:
		tween.tween_property(star, "transparency", 1.0, maxf(fade, .01))
	tween.chain().tween_callback(queue_free)
