extends Node3D

@export var size := Vector2(4.0, 4.0)
@export_range(0.0, 1.0, 0.05) var darkness := 0.88
@export var permanent := true
@export var reveal_distance := 2.2
@export var door_link_radius := 4.0
@export var require_door_open := true
## Exploration zones sharing a room_id (> 0) are one room under solid fog: it lifts while the
## player is inside, and otherwise shows only what the camera sees through open doors and glass.
@export var room_id := 0

const SHADER := preload("res://game/presentation/office_floor/darkness_zone.gdshader")
const DOOR_REACH := 1.5
const PORTALS := preload("res://game/presentation/office_floor/darkness_portals.gd")
const FADE_SPEED := 5.0
const PORTAL_REFRESH := 0.25

@onready var overlay: MeshInstance3D = $Overlay
var _revealed := false
var _player: Node3D
var _linked_doors: Array[Node3D] = []
var _fade := 1.0
var _portal_timer := 0.0
# Glass panes stay see-through after they break, so they are remembered once found.
var _glass_portals: Dictionary = {}
var _fog_enabled := true

func _ready() -> void:
	add_to_group("darkness_zone")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_revealed = false
	_rebuild()
	call_deferred("_find_linked_doors")

func _process(delta: float) -> void:
	if not _fog_enabled:
		return
	if room_id > 0 and not permanent:
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as Node3D
		_fade = move_toward(_fade, 0.0 if _player_inside() else 1.0, FADE_SPEED * delta)
		overlay.visible = _fade > 0.01
		set_meta("explored", not overlay.visible)
		_portal_timer -= delta
		if overlay.visible and _portal_timer <= 0.0:
			_portal_timer = PORTAL_REFRESH
			_push_portals()
		var material := overlay.mesh.material as ShaderMaterial if overlay.mesh != null else null
		if material != null:
			material.set_shader_parameter("darkness", _fade)
		return
	if permanent or _revealed or _player == null:
		return
	var delta_pos := _player.global_position - global_position
	delta_pos.y = 0.0
	if delta_pos.length() <= reveal_distance:
		reveal()
		return
	if require_door_open:
		for door in _linked_doors:
			if is_instance_valid(door) and door.has_method("is_open_for_exploration") and bool(door.call("is_open_for_exploration")):
				reveal()
				return

## Rendering permission from bootstrap; authored zones and exploration stay intact.
func set_fog_of_war_enabled(enabled: bool) -> void:
	_fog_enabled = enabled
	set_meta("planning_pick_disabled", not enabled)
	set_process(enabled)
	if overlay != null:
		overlay.visible = enabled and not _revealed and (permanent or room_id <= 0 or _fade > 0.01)


func reveal() -> void:
	if permanent or _revealed:
		return
	_revealed = true
	overlay.visible = false
	set_meta("explored", true)


func _find_linked_doors() -> void:
	_linked_doors.clear()
	if permanent:
		return
	for door in get_tree().get_nodes_in_group("interactive_doors"):
		if door is Node3D:
			var door_node := door as Node3D
			if room_id > 0:
				if _edge_distance(door_node.global_position) <= DOOR_REACH:
					_linked_doors.append(door_node)
			elif global_position.distance_to(door_node.global_position) <= door_link_radius:
				_linked_doors.append(door_node)


## Horizontal distance from a world point to this zone's rectangle (0 inside).
func _edge_distance(point: Vector3) -> float:
	var local := global_transform.affine_inverse() * point
	var half := size * 0.5
	var edge := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.y, half.y))
	var nearest := global_transform * edge
	return Vector2(nearest.x - point.x, nearest.z - point.z).length()


## The cover lifts while the player stands in any part of the room.
func _player_inside() -> bool:
	if _player == null:
		return false
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		if zone.get("room_id") == room_id and not zone.get("permanent") and zone.call("_edge_distance", _player.global_position) <= 0.3:
			return true
	return false


## Fog is solid; the camera still sees in through open doors and glass, wherever they meet this room.
func _push_portals() -> void:
	var material := overlay.mesh.material as ShaderMaterial if overlay.mesh != null else null
	if material == null:
		return
	for body in get_tree().get_nodes_in_group("infected_breakable_glass"):
		for shape in body.find_children("*", "CollisionShape3D", true, false):
			if not _glass_portals.has(shape.get_instance_id()) and _edge_distance(shape.global_position) <= PORTALS.GLASS_REACH:
				var pane: Dictionary = PORTALS.pane(shape, global_position)
				if not pane.is_empty():
					_glass_portals[shape.get_instance_id()] = pane
	var portals: Array = _glass_portals.values()
	for door in _linked_doors:
		if is_instance_valid(door) and door.has_method("is_open_for_exploration") and bool(door.call("is_open_for_exploration")):
			portals.append(PORTALS.door(door, global_position))
	portals = portals.slice(0, PORTALS.MAX_PORTALS)
	var centres := PackedVector3Array()
	var normals := PackedVector3Array()
	var us := PackedVector3Array()
	var vs := PackedVector3Array()
	for portal: Dictionary in portals:
		centres.append(portal.centre)
		normals.append(portal.normal)
		us.append(portal.u)
		vs.append(portal.v)
	for _i in range(portals.size(), PORTALS.MAX_PORTALS):
		centres.append(Vector3.ZERO)
		normals.append(Vector3.ZERO)
		us.append(Vector3.ZERO)
		vs.append(Vector3.ZERO)
	material.set_shader_parameter("portal_count", portals.size())
	material.set_shader_parameter("portal_centre", centres)
	material.set_shader_parameter("portal_normal", normals)
	material.set_shader_parameter("portal_u", us)
	material.set_shader_parameter("portal_v", vs)


## True when the cover is up and the segment from `from` to `to` passes through it.
func blocks_view(from: Vector3, to: Vector3) -> bool:
	if not overlay.visible or not is_visible_in_tree():
		return false
	var top := global_position.y
	if (from.y - top) * (to.y - top) >= 0.0:
		return false
	var hit := from.lerp(to, (top - from.y) / (to.y - from.y))
	return _edge_distance(Vector3(hit.x, top, hit.z)) <= 0.0


func set_view_hole(center: Vector2, viewport: Vector2, radius: float, depth: float) -> void:
	var material := overlay.mesh.material as ShaderMaterial if overlay.mesh != null else null
	if material == null:
		return
	material.set_shader_parameter("hole_center", center)
	material.set_shader_parameter("viewport_size", viewport)
	material.set_shader_parameter("hole_radius", radius)
	material.set_shader_parameter("player_depth", depth)
	material.set_shader_parameter("lens_zone", _hero_in_room())
	material.set_shader_parameter("zone_inverse", global_transform.affine_inverse())
	material.set_shader_parameter("zone_half", size * 0.5)
	if _player != null:
		material.set_shader_parameter("hero_pos", _player.global_position)


## The lens opens this cover only when the hero stands in this zone, or in another part of its room.
func _hero_in_room() -> bool:
	if _player == null:
		return false
	if room_id <= 0:
		return _edge_distance(_player.global_position) <= 0.0
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		if zone.get("room_id") == room_id and zone.call("_edge_distance", _player.global_position) <= 0.0:
			return true
	return false


func configure_zone(new_size: Vector2, new_darkness: float, is_permanent: bool) -> void:
	size = new_size
	darkness = new_darkness
	permanent = is_permanent
	_rebuild()

func _rebuild() -> void:
	if overlay == null:
		return
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Y
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = 10
	material.set_shader_parameter("darkness", darkness)
	mesh.material = material
	overlay.mesh = mesh
	overlay.position = Vector3.ZERO
	overlay.rotation_degrees = Vector3.ZERO
	set_fog_of_war_enabled(_fog_enabled)
