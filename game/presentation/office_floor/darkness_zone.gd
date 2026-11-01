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
const DOOR_PROBE := 0.9
const LIFTED_REACH := 0.35
const MAX_BLOCKERS := 8
const BLOCKER_REACH := 3.0
const DOOR_PROBE_TOLERANCE := 0.3
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
		_fade = move_toward(_fade, 0.0 if _player_inside() or _room_has_open_door() else 1.0, FADE_SPEED * delta)
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
				if _door_leads_here(door_node):
					_linked_doors.append(door_node)
			elif global_position.distance_to(door_node.global_position) <= door_link_radius:
				_linked_doors.append(door_node)


## A door belongs to the rooms it opens onto: those that contain the point just in front of it or just
## behind it, along the door's own normal. A room that merely lies near the door, around a corner or
## beside the wall, is not opened by it.
func _door_leads_here(door_node: Node3D) -> bool:
	var wall := (door_node.get_parent() as Node3D) if door_node.name == &"DoorController" else door_node
	var normal := wall.global_basis.orthonormalized().z
	normal.y = 0.0
	if normal.length() < 0.5:
		return _edge_distance(door_node.global_position) <= DOOR_REACH
	normal = normal.normalized()
	for side in [-1.0, 1.0]:
		if _edge_distance(wall.global_position + normal * DOOR_PROBE * side) <= DOOR_PROBE_TOLERANCE:
			return true
	return false


## Horizontal distance from a world point to this zone's rectangle (0 inside).
func _edge_distance(point: Vector3) -> float:
	var local := global_transform.affine_inverse() * point
	var half := size * 0.5
	var edge := Vector3(clampf(local.x, -half.x, half.x), 0.0, clampf(local.z, -half.y, half.y))
	var nearest := global_transform * edge
	return Vector2(nearest.x - point.x, nearest.z - point.z).length()


## An open door into any part of the room shows the whole room, as entering it does.
func _room_has_open_door() -> bool:
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		if zone.get("room_id") == room_id and not zone.get("permanent") and zone.call("_has_open_door"):
			return true
	return false


func _has_open_door() -> bool:
	for door in _linked_doors:
		if is_instance_valid(door) and door.has_method("is_open_for_exploration") and bool(door.call("is_open_for_exploration")):
			return true
	return false


## The cover lifts while the player stands in any part of the room. Entering takes standing inside a
## zone rectangle (hugging the far side of a wall does not count); once lifted it stays lifted a little
## beyond the rectangles, because the floor along an inner wall can lie just outside them.
func _player_inside() -> bool:
	if _player == null:
		return false
	var reach := LIFTED_REACH if _fade < 0.5 else 0.0
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		if zone.get("room_id") == room_id and not zone.get("permanent") and zone.call("_edge_distance", _player.global_position) <= reach:
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
		var blockers := _closed_rects_near(_player.global_position)
		material.set_shader_parameter("blocker_count", blockers.size())
		while blockers.size() < MAX_BLOCKERS:
			blockers.append(Vector4.ZERO)
		material.set_shader_parameter("blockers", blockers)


## Footprints (centre x, centre z, half x, half z) of the covers still up near the hero, once per frame.
## The lens never opens a surface inside one: that floor belongs to a closed room, not to the hero's side.
## shortcut: zones are treated as axis-aligned, which every authored zone is; handle rotation if one is not.
static var _rects_frame := -1
static var _rects: PackedVector4Array = PackedVector4Array()


func _closed_rects_near(point: Vector3) -> PackedVector4Array:
	var frame := Engine.get_process_frames()
	if frame != _rects_frame:
		_rects_frame = frame
		_rects = PackedVector4Array()
		var near: Array[Node3D] = []
		for zone: Node3D in get_tree().get_nodes_in_group("darkness_zone"):
			if zone.get("permanent") or not zone.overlay.visible:
				continue
			var half: Vector2 = zone.get("size") * 0.5
			if absf(zone.global_position.x - point.x) <= half.x + BLOCKER_REACH and absf(zone.global_position.z - point.z) <= half.y + BLOCKER_REACH:
				near.append(zone)
		near.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(point) < b.global_position.distance_squared_to(point))
		for zone in near.slice(0, MAX_BLOCKERS):
			var half: Vector2 = zone.get("size") * 0.5
			_rects.append(Vector4(zone.global_position.x, zone.global_position.z, half.x, half.y))
	return _rects.duplicate()


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
