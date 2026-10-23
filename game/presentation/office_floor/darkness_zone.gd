extends Node3D

@export var size := Vector2(4.0, 4.0)
@export_range(0.0, 1.0, 0.05) var darkness := 0.88
@export var permanent := true
@export var reveal_distance := 2.2
@export var door_link_radius := 4.0
@export var require_door_open := true
## Exploration zones sharing a room_id (> 0) are one room: it opens while a door of the room
## is open or the player is inside, and goes dark again when the door closes.
@export var room_id := 0

const SHADER := preload("res://game/presentation/office_floor/darkness_zone.gdshader")
const DOOR_REACH := 1.5

@onready var overlay: MeshInstance3D = $Overlay
var _revealed := false
var _player: Node3D
var _linked_doors: Array[Node3D] = []

func _ready() -> void:
	add_to_group("darkness_zone")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_revealed = false
	_rebuild()
	overlay.visible = true
	call_deferred("_find_linked_doors")

func _process(_delta: float) -> void:
	if room_id > 0 and not permanent:
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as Node3D
		overlay.visible = not _room_open()
		set_meta("explored", not overlay.visible)
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


## The whole room is lit while its player stands in any part or any of its doors is open.
func _room_open() -> bool:
	for zone in get_tree().get_nodes_in_group("darkness_zone"):
		if zone.get("room_id") != room_id or zone.get("permanent"):
			continue
		if _player != null and zone.call("_edge_distance", _player.global_position) <= 0.01:
			return true
		for door in zone.get("_linked_doors"):
			if is_instance_valid(door) and door.has_method("is_open_for_exploration") and bool(door.call("is_open_for_exploration")):
				return true
	return false


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
