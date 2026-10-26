extends Node3D
## Planner object: a broken-floor hole that a wave of infected comes out of.
## Settings live in the config (spawn_config.gd); the wave director runs the wave.

const MARKER_FONT := preload("res://assets/interface/fonts/body.ttf")
const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const SPAWN_HOLE := preload("res://game/features/spawning/spawn_hole.gd")
const POINT_GROUP := &"enemy_spawn_points"
const SLOT_ANGLE := 2.39996
const SLOT_TRIES := 8
const WORLD_MASK := 1

var _config := SPAWN_CONFIG.defaults()
var _marker: Label3D


func _ready() -> void:
	add_to_group(POINT_GROUP)
	SPAWN_HOLE.build(self, str(get_meta(&"planning_object_id", "")).hash())
	_marker = Label3D.new()
	_marker.name = "PlanningMarker"
	_marker.font = MARKER_FONT
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0009
	_marker.font_size = 28
	_marker.outline_size = 10
	_marker.position = Vector3(0.0, 0.9, 0.0)
	_marker.visible = false
	add_child(_marker)
	_refresh_marker()


func configure_spawn(config: Dictionary) -> void:
	_config = SPAWN_CONFIG.sanitize(config)
	_refresh_marker()


func get_spawn_config() -> Dictionary:
	return _config.duplicate(true)


## The planner shows the wave summary over the hole; the game does not.
func set_planning_visual(enabled: bool) -> void:
	if _marker != null:
		_marker.visible = enabled


## World position of the `index`-th infected of a wave: on a ring around the
## hole, in the first free direction that no wall or furniture blocks.
func spawn_position(index: int) -> Vector3:
	var reach := maxf(absf(scale.x), absf(scale.z))
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var centre := global_position + Vector3(0.0, 0.6, 0.0)
	for attempt in SLOT_TRIES:
		var angle := (index + attempt) * SLOT_ANGLE
		var radius := (1.15 + 0.3 * float(index % 3)) * reach
		var candidate := global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		if space == null or not _blocked(space, centre, candidate + Vector3(0.0, 0.6, 0.0)):
			return candidate
	return global_position + Vector3(0.3, 0.0, 0.3)


func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return not space.intersect_ray(query).is_empty()


func _refresh_marker() -> void:
	if _marker != null:
		_marker.text = "СПАВН " + SPAWN_CONFIG.summary(_config)
