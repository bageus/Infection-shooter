extends Node3D

## Floor chevrons from the player toward the current goal, shown when the floor hints setting is on.
## Each chevron rises forward and settles back. The trail follows a walkable route around walls.

const CHEVRON_COUNT := 3
const FIRST_DISTANCE := 2.0
const SPACING := 2.2
const BOB_AMPLITUDE := 0.22
const BOB_SPEED := 2.4
const BOB_PHASE := 0.7
const ARROW_SIZE := 2.0 # the drawing fills the quad at 2/3, so the arrow keeps its apparent size
const ARROW_SHADER := preload("res://game/bootstrap/app/floor_hint_arrow.gdshader")
const FLOOR_Y := 0.04
const END_CLEARANCE := 0.6
const ROUTE_REFRESH := 0.4
const ROUTE := preload("res://game/bootstrap/app/floor_route.gd")

var player: Node3D
# Returns the goal's floor position, or Vector3.INF when there is none.
var target_source: Callable
var _chevrons: Array[MeshInstance3D] = []
var _elapsed := 0.0
var _route = ROUTE.new()
var _waypoints: Array[Vector3] = [] # the walkable way from the last search, ending at the goal
var _route_age := 99.0
var _route_goal := Vector3.INF


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
	_route_age += delta
	var goal: Vector3 = target_source.call() if target_source.is_valid() else Vector3.INF
	var from := player.global_position if is_instance_valid(player) else Vector3.INF
	if not goal.is_finite() or not from.is_finite():
		_hide_all()
		return
	_refresh_route(from, goal)
	var path: Array[Vector3] = [Vector3(from.x, 0.0, from.z)]
	path.append_array(_waypoints)
	var length := _path_length(path)
	if length < FIRST_DISTANCE + END_CLEARANCE:
		_hide_all()
		return
	for index in _chevrons.size():
		var distance := FIRST_DISTANCE + index * SPACING
		var chevron := _chevrons[index]
		chevron.visible = distance < length - END_CLEARANCE
		if not chevron.visible:
			continue
		var bob := (0.5 + 0.5 * sin(_elapsed * BOB_SPEED - index * BOB_PHASE)) * BOB_AMPLITUDE
		var at := _along(path, distance + bob)
		chevron.global_position = Vector3(at[0].x, FLOOR_Y, at[0].z)
		chevron.rotation = Vector3(0.0, atan2(-at[1].x, -at[1].z), 0.0)
		var wave := 0.5 + 0.5 * sin(_elapsed * BOB_SPEED - index * BOB_PHASE)
		chevron.set_instance_shader_parameter(&"glow", lerpf(0.2, 1.0, wave))


func _hide_all() -> void:
	for chevron in _chevrons:
		chevron.visible = false


# Searches again when the goal moved or the last route is old; with no way found the trail points straight.
func _refresh_route(from: Vector3, goal: Vector3) -> void:
	var moved := not _route_goal.is_finite() or _route_goal.distance_to(goal) > 0.5
	if not moved and _route_age < ROUTE_REFRESH:
		return
	_route_age = 0.0
	_route_goal = goal
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())
	_waypoints = _route.find(get_world_3d().direct_space_state, from, goal, excluded)
	if _waypoints.is_empty():
		_waypoints = [Vector3(goal.x, 0.0, goal.z)]


func _path_length(path: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Returns [point, direction] at `distance` along the polyline.
func _along(path: Array[Vector3], distance: float) -> Array[Vector3]:
	var left := distance
	for i in range(1, path.size()):
		var segment := path[i] - path[i - 1]
		var length := segment.length()
		if length > 0.001 and (left <= length or i == path.size() - 1):
			return [path[i - 1] + segment / length * minf(left, length), segment / length]
		left -= length
	return [path[-1], Vector3.FORWARD]
