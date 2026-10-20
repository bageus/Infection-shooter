extends Node3D

## Floor chevrons from the player toward the current goal, shown when the floor hints setting is on.
## Each chevron rises forward and settles back, so the trail reads as a direction.

const CHEVRON_COUNT := 3
const FIRST_DISTANCE := 2.0
const SPACING := 2.2
const BOB_AMPLITUDE := 0.22
const BOB_SPEED := 2.4
const BOB_PHASE := 0.7
const ARROW_SIZE := 1.5
const ARROW_SHADER := preload("res://game/bootstrap/app/floor_hint_arrow.gdshader")
const FLOOR_Y := 0.04
const END_CLEARANCE := 0.6

var player: Node3D
# Returns the goal's floor position, or Vector3.INF when there is none.
var target_source: Callable
var _chevrons: Array[MeshInstance3D] = []
var _elapsed := 0.0


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * ARROW_SIZE
	var material := ShaderMaterial.new()
	material.shader = ARROW_SHADER
	for index in CHEVRON_COUNT:
		# One shared material; each arrow's own light and wear come from instance uniforms.
		var chevron := MeshInstance3D.new()
		chevron.mesh = plane
		chevron.material_override = material
		chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chevron.set_instance_shader_parameter(&"seed", float(index) * 1.7)
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
		var wave := 0.5 + 0.5 * sin(_elapsed * BOB_SPEED - index * BOB_PHASE)
		chevron.set_instance_shader_parameter(&"glow", lerpf(0.2, 1.0, wave))
