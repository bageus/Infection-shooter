extends MultiMeshInstance3D
## Cartridge belt hanging from the backpack feed port to the minigun feed port, rebuilt each frame in skeleton space.
const LINKS := 30
## Belt sag as a share of the span: the belt hangs under its own weight.
const SAG := .12
const CARTRIDGE_RADIUS := .0095
const CARTRIDGE_LENGTH := .026


func _ready() -> void:
	var cartridge := CylinderMesh.new()
	cartridge.top_radius = CARTRIDGE_RADIUS
	cartridge.bottom_radius = CARTRIDGE_RADIUS
	cartridge.height = CARTRIDGE_LENGTH
	cartridge.radial_segments = 6
	cartridge.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(.44, .35, .2)
	brass.metallic = .55
	brass.roughness = .5
	cartridge.material = brass
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cartridge
	multimesh.instance_count = LINKS
	# Covers the whole hero so the belt is never culled while the arms swing.
	custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	visible = false


## Lays the links along a sagging quadratic curve from start to end (both in skeleton space).
func update_belt(start: Vector3, end: Vector3) -> void:
	if start.is_equal_approx(end):
		return
	var control := (start + end) * .5 + Vector3.DOWN * start.distance_to(end) * SAG
	for i in LINKS:
		var t := (float(i) + .5) / LINKS
		var point := start.lerp(control, t).lerp(control.lerp(end, t), t)
		var tangent := (control - start).lerp(end - control, t)
		multimesh.set_instance_transform(i, Transform3D(Basis(Quaternion(Vector3.UP, tangent.normalized())), point))
