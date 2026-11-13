extends MultiMeshInstance3D
## Wide snake-like cartridge belt: it leaves the backpack port end-on, sags, and enters the minigun port end-on. Rebuilt each frame in skeleton space.
const LINKS := 30
const ROUNDS_ACROSS := 3
## Straight run out of each port, as a share of the span, so the belt leaves and enters end-on.
const LEAD := .3
## How far the belt sags below the midpoint, as a share of the span.
const DROP := .5
## Strap pitch per link, strap width and thickness (m).
const LINK_PITCH := .02
const STRAP_WIDTH := .09
const STRAP_THICKNESS := .006
const ROUND_SPACING := .03
const ROUND_RADIUS := .0065
const ROUND_LENGTH := .026
var _rounds: MultiMeshInstance3D


func _ready() -> void:
	var strap := BoxMesh.new()
	strap.size = Vector3(STRAP_WIDTH, STRAP_THICKNESS, LINK_PITCH)
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = Color(.2, .22, .14)
	canvas.roughness = .9
	strap.material = canvas
	var round := CylinderMesh.new()
	round.top_radius = ROUND_RADIUS
	round.bottom_radius = ROUND_RADIUS
	round.height = ROUND_LENGTH
	round.radial_segments = 6
	round.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(.44, .35, .2)
	brass.metallic = .55
	brass.roughness = .5
	round.material = brass
	multimesh = _make_multimesh(strap, LINKS)
	_rounds = MultiMeshInstance3D.new()
	_rounds.multimesh = _make_multimesh(round, LINKS * ROUNDS_ACROSS)
	add_child(_rounds)
	# Covers the whole hero so the belt is never culled while the arms swing.
	custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	_rounds.custom_aabb = custom_aabb
	visible = false


func _make_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_3D
	result.mesh = mesh
	result.instance_count = count
	return result


## Two cubic Hermite segments through a sagging midpoint. start_out and end_out are the port outward directions (skeleton space).
func update_belt(start: Vector3, start_out: Vector3, end: Vector3, end_out: Vector3) -> void:
	if start.is_equal_approx(end):
		return
	var span := start.distance_to(end)
	var reach := span * LEAD
	var mid := (start + end) * .5 + Vector3.DOWN * span * DROP
	var mid_dir := (end - start).normalized() * reach
	for i in LINKS:
		var s := (float(i) + .5) / LINKS
		var point: Vector3
		var tangent: Vector3
		if s < .5:
			point = _hermite(start, start_out * reach, mid, mid_dir, s * 2.0)
			tangent = _hermite_direction(start, start_out * reach, mid, mid_dir, s * 2.0)
		else:
			point = _hermite(mid, mid_dir, end, -end_out * reach, (s - .5) * 2.0)
			tangent = _hermite_direction(mid, mid_dir, end, -end_out * reach, (s - .5) * 2.0)
		tangent = tangent.normalized()
		# Width runs horizontally across the belt; the strap lies flat on it.
		var side := tangent.cross(Vector3.UP).normalized()
		var normal := tangent.cross(side)
		multimesh.set_instance_transform(i, Transform3D(Basis(side, normal, tangent), point))
		for k in ROUNDS_ACROSS:
			var across := (float(k) - (ROUNDS_ACROSS - 1) * .5) * ROUND_SPACING
			var seat := point + side * across + normal * (STRAP_THICKNESS * .5 + ROUND_RADIUS)
			_rounds.multimesh.set_instance_transform(i * ROUNDS_ACROSS + k, Transform3D(Basis(side, tangent, side.cross(tangent)), seat))


func _hermite(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + m0 * (t3 - 2.0 * t2 + t) + p1 * (3.0 * t2 - 2.0 * t3) + m1 * (t3 - t2)


func _hermite_direction(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, t: float) -> Vector3:
	var t2 := t * t
	return p0 * (6.0 * t2 - 6.0 * t) + m0 * (3.0 * t2 - 4.0 * t + 1.0) + p1 * (6.0 * t - 6.0 * t2) + m1 * (3.0 * t2 - 2.0 * t)
