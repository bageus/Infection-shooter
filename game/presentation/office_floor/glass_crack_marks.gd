extends RefCounted

# Explicit references make these assets available in exported builds as well as the editor.
# Each impact center is measured in texture UVs so the hole lands on the bullet hit.
const CRACK_TEXTURES = [
	preload("res://models/objects/textures/Asymmetric bullet-impact glass crack overlay.png"),
	preload("res://models/objects/textures/Bullet Impact Glass Crack Decal.png"),
	preload("res://models/objects/textures/Diagonal bullet-impact glass cracks.png"),
	preload("res://models/objects/textures/Fine bullet-damaged glass crack overlay.png"),
	preload("res://models/objects/textures/Shattered glass impact crack decal.png"),
	preload("res://models/objects/textures/Spiderweb Bullet Impact Crack Decal.png"),
	preload("res://models/objects/textures/Starburst bullet impact glass crack.png"),
	preload("res://models/objects/textures/Twin Impact Cracked Glass Decal.png"),
]
const IMPACT_CENTERS = [
	Vector2(0.24, 0.56), Vector2(0.5, 0.5), Vector2(0.54, 0.51),
	Vector2(0.51, 0.53), Vector2(0.5, 0.5), Vector2(0.51, 0.49),
	Vector2(0.52, 0.53), Vector2(0.47, 0.48),
]


static func spawn(pane: StaticBody3D, point: Vector3, normal: Vector3, max_size: float = 0.65) -> void:
	var mark := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	var pool := pane.get("impact_pool") as Node
	var variant := randi_range(0, CRACK_TEXTURES.size() - 1)
	material.albedo_texture = CRACK_TEXTURES[variant] as Texture2D
	if material.albedo_texture != null:
		var quad := QuadMesh.new()
		var size := minf(randf_range(0.38, 0.65), max_size)
		quad.size = Vector2.ONE * size
		var center: Vector2 = IMPACT_CENTERS[variant]
		quad.center_offset = Vector3((0.5 - center.x) * size, (center.y - 0.5) * size, 0.0)
		quad.material = material
		mark.mesh = quad
	else:
		mark.mesh = _fallback_fracture(material)
	pane.add_child(mark)
	var outward := normal.normalized() if not normal.is_zero_approx() else Vector3.FORWARD
	mark.global_position = point + outward * 0.025
	var up := Vector3.FORWARD if absf(outward.y) > 0.9 else Vector3.UP
	mark.global_basis = Basis.looking_at(-outward, up) * Basis(Vector3.FORWARD, randf() * TAU)
	if pool != null:
		pool.call("register_mark", mark)


static func _fallback_fracture(material: Material) -> Mesh:
	material.albedo_color = Color(0.82, 0.94, 1.0, 0.72)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var arms := randi_range(6, 11)
	for i in arms:
		var angle := TAU * float(i) / float(arms) + randf_range(-0.16, 0.16)
		var length := randf_range(0.13, 0.29)
		var bend := Vector3(cos(angle) * length * 0.48, sin(angle) * length * 0.48, 0)
		var end := Vector3(cos(angle + 0.18) * length, sin(angle + 0.18) * length, 0)
		lines.surface_add_vertex(Vector3.ZERO)
		lines.surface_add_vertex(bend)
		lines.surface_add_vertex(bend)
		lines.surface_add_vertex(end)
	lines.surface_end()
	return lines
