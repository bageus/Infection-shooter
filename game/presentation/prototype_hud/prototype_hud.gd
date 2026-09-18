extends CanvasLayer

@export var player_path: NodePath

@onready var health_bar: ProgressBar = $BottomLeft/Frame/Rows/Health/HealthBar
@onready var health_value: Label = $BottomLeft/Frame/Rows/Health/HealthValue
@onready var mutation_bar: ProgressBar = $BottomLeft/Frame/Rows/Mutation/MutationWrap/MutationBar
@onready var mutation_value: Label = $BottomLeft/Frame/Rows/Mutation/MutationValue
@onready var critical_marker: ColorRect = $BottomLeft/Frame/Rows/Mutation/MutationWrap/CriticalMarker
@onready var control_label: Label = $BottomLeft/Frame/Rows/ControlLabel
@onready var weapon_name: Label = $BottomRight/Frame/WeaponRow/WeaponName
@onready var magazine_value: Label = $BottomRight/Frame/AmmoRow/Magazine
@onready var reserve_value: Label = $BottomRight/Frame/AmmoRow/Reserve

var _player: Node
var _infection: Node
var _weapon: Node


func _ready() -> void:
	_player = get_node(player_path)
	_infection = _player.get_node("InfectionRuntime")
	_weapon = _player.get_node("AimPivot/PrototypeRifle")
	health_bar.max_value = _player.max_health
	mutation_bar.max_value = 100.0


func _process(_delta: float) -> void:
	if _player == null or _infection == null:
		return

	health_bar.value = _player.health
	health_value.text = "%d / %d" % [roundi(_player.health), roundi(_player.max_health)]

	var mutation: float = _infection.call("get_mutation")
	var critical: float = _infection.call("get_critical_threshold")
	mutation_bar.value = mutation
	mutation_value.text = "%d / 100" % roundi(mutation)
	critical_marker.position.x = maxf(0.0, mutation_bar.size.x * clampf(critical / 100.0, 0.0, 1.0) - 1.5)

	if _infection.call("is_defeated") or _infection.call("is_control_lost"):
		control_label.text = "CONTROL LOST"
	elif mutation >= critical:
		control_label.text = "UNSTABLE"
	else:
		control_label.text = ""

	weapon_name.text = "RIFLE"
	magazine_value.text = str(_weapon.call("get_magazine_ammo"))
	reserve_value.text = "/ %d" % _weapon.call("get_reserve_ammo")
