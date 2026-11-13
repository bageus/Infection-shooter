extends MultiMeshInstance3D
## Wide cartridge belt from the backpack feed port to the minigun feed port, rebuilt each frame in skeleton space.
const LINKS := 30
const ROUNDS_ACROSS := 3
## Belt sag as a share of the span: a deep loop down from the backpack, as drawn by Vadim.
const SAG := .5
## Strap pitch per link, strap width and thickness (m).
const LINK_PITCH := .02
const STRAP_WIDTH := .06
const STRAP_THICKNESS := .006
const ROUND_SPACING := .019
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


## Lays the strap links and their rounds along a sagging quadratic curve from start to end (skeleton space).
func update_belt(start: Vector3, end: Vector3) -> void:
	if start.is_equal_approx(end):
		return
	var control := (start + end) * .5 + Vector3.DOWN * start.distance_to(end) * SAG
	for i in LINKS:
		var t := (float(i) + .5) / LINKS
		var point := start.lerp(control, t).lerp(control.lerp(end, t), t)
		var tangent := ((control - start).lerp(end - control, t)).normalized()
		# Width runs horizontally across the belt; the strap lies flat on it.
		var side := tangent.cross(Vector3.UP).normalized()
		var normal := tangent.cross(side)
		multimesh.set_instance_transform(i, Transform3D(Basis(side, normal, tangent), point))
		for k in ROUNDS_ACROSS:
			var across := (float(k) - (ROUNDS_ACROSS - 1) * .5) * ROUND_SPACING
			var seat := point + side * across + normal * (STRAP_THICKNESS * .5 + ROUND_RADIUS)
			_rounds.multimesh.set_instance_transform(i * ROUNDS_ACROSS + k, Transform3D(Basis(side, tangent, side.cross(tangent)), seat))
