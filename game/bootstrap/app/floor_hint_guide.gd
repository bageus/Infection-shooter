extends Node3D

## Floor chevrons from the player toward the current goal, shown when the floor hints setting is on.
## Each chevron rises forward and settles back, so the trail reads as a direction.

const CHEVRON_COUNT := 3
const FIRST_DISTANCE := 2.0
const SPACING := 2.2
const BOB_AMPLITUDE := 0.22
const BOB_SPEED := 2.4
const BOB_PHASE := 0.7
const ARM_LENGTH := 0.42
const ARM_WIDTH := 0.14
const FLOOR_Y := 0.04
const END_CLEARANCE := 0.6
const COLOR := Color(0.35, 0.95, 0.8)

var player: Node3D
# Returns the goal's floor position, or Vector3.INF when there is none.
var target_source: Callable
var _chevrons: Array[MeshInstance3D] = []
var _elapsed := 0.0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 1.2
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := _chevron_mesh()
	mesh.surface_set_material(0, material)
	for index in CHEVRON_COUNT:
		var chevron := MeshInstance3D.new()
		chevron.mesh = mesh
		chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(chevron)
		_chevrons.append(chevron)


## Settings: turning hints off hides the chevrons and stops their animation.
func set_hints_enabled(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)


func _process(delta: float) -> void:
	_elapsed += delta
	var goal: Vector3 = target_source.call() if target_source.is_valid() else Vector3.INF
	var from := player.global_position if is_instance_valid(player) else Vector3.INF
	var ahead := Vector3(goal.x - from.x, 0.0, goal.z - from.z) if goal.is_finite() and from.is_finite() else Vector3.ZERO
	var length := ahead.length()
	if length < FIRST_DISTANCE + END_CLEARANCE:
		for chevron in _chevrons:
			chevron.visible = false
		return
	var direction := ahead / length
	var yaw := atan2(-direction.x, -direction.z)
	for index in _chevrons.size():
		var distance := FIRST_DISTANCE + index * SPACING
		var chevron := _chevrons[index]
		chevron.visible = distance < length - END_CLEARANCE
		if not chevron.visible:
			continue
		var bob := (0.5 + 0.5 * sin(_elapsed * BOB_SPEED - index * BOB_PHASE)) * BOB_AMPLITUDE
		var spot := from + direction * (distance + bob)
		chevron.global_position = Vector3(spot.x, FLOOR_Y, spot.z)
		chevron.rotation = Vector3(0.0, yaw, 0.0)


# Two thin arms meeting at a tip, lying flat on the floor and pointing down -Z.
func _chevron_mesh() -> ArrayMesh:
	var tip := Vector3(0.0, 0.0, -ARM_LENGTH)
	var arms := [
		[tip, Vector3(-ARM_LENGTH, 0.0, ARM_LENGTH * 0.4)],
		[tip, Vector3(ARM_LENGTH, 0.0, ARM_LENGTH * 0.4)],
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for arm: Array in arms:
		var start: Vector3 = arm[0]
		var end: Vector3 = arm[1]
		var side := (end - start).cross(Vector3.UP).normalized() * ARM_WIDTH
		var quad := [start, end, end + side, start + side]
		for index in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(quad[index])
	surface.generate_normals()
	return surface.commit()
