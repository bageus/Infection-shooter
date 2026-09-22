extends Node3D

@export var size := Vector2(4.0, 4.0)
@export_range(0.0, 1.0, 0.05) var darkness := 0.88
@export var permanent := true
@export var reveal_distance := 2.2

@onready var overlay: MeshInstance3D = $Overlay
var _revealed := false
var _player: Node3D

func _ready() -> void:
	add_to_group("darkness_zone")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_rebuild()

func _process(_delta: float) -> void:
	if permanent or _revealed or _player == null:
		return
	var delta_pos := _player.global_position - global_position
	delta_pos.y = 0.0
	if delta_pos.length() <= reveal_distance:
		_revealed = true
		overlay.visible = false

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
