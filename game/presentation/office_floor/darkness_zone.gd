extends Node3D

@export var size := Vector2(4.0, 4.0)
@export_range(0.0, 1.0, 0.05) var darkness := 0.88
@export var permanent := true
@export var reveal_distance := 2.2
@export var door_link_radius := 4.0
@export var require_door_open := true

@onready var overlay: MeshInstance3D = $Overlay
var _revealed := false
var _player: Node3D
var _linked_doors: Array[Node3D] = []

func _ready() -> void:
	add_to_group("darkness_zone")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_rebuild()
	call_deferred("_find_linked_doors")

func _process(_delta: float) -> void:
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
			if global_position.distance_to(door_node.global_position) <= door_link_radius:
				_linked_doors.append(door_node)


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
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.0, 0.0, 0.0, darkness)
	material.no_depth_test = true
	mesh.material = material
	overlay.mesh = mesh
	overlay.position.y = 5.0
	overlay.rotation_degrees.x = -90.0
