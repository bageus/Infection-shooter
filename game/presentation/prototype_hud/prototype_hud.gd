extends CanvasLayer

@export var player_path: NodePath

@onready var health_bar: ProgressBar = $BottomLeft/Panel/VBox/HealthRow/HealthBar
@onready var health_value: Label = $BottomLeft/Panel/VBox/HealthRow/HealthValue
@onready var mutation_bar: ProgressBar = $BottomLeft/Panel/VBox/MutationRow/MutationBar
@onready var mutation_value: Label = $BottomLeft/Panel/VBox/MutationRow/MutationValue
@onready var critical_marker: ColorRect = $BottomLeft/Panel/VBox/MutationRow/MutationWrap/CriticalMarker
@onready var control_label: Label = $BottomLeft/Panel/VBox/ControlLabel
@onready var weapon_label: Label = $BottomRight/Panel/VBox/WeaponLabel
@onready var ammo_label: Label = $BottomRight/Panel/VBox/AmmoLabel

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
	critical_marker.position.x = mutation_bar.size.x * clampf(critical / 100.0, 0.0, 1.0) - 1.5

	if _infection.call("is_defeated"):
		control_label.text = "CONTROL LOST"
	elif _infection.call("is_control_lost"):
		control_label.text = "CONTROL LOST"
	elif mutation >= critical:
		control_label.text = "UNSTABLE"
	else:
		control_label.text = ""

	weapon_label.text = "RIFLE"
	if _weapon != null and _weapon.has_method("get_magazine_ammo"):
		ammo_label.text = "%d / %d" % [_weapon.call("get_magazine_ammo"), _weapon.call("get_reserve_ammo")]
