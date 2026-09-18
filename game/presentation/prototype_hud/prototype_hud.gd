extends CanvasLayer

@export var player_path: NodePath

@onready var health_bar: ProgressBar = $Margin/Panel/VBox/HealthBar
@onready var health_label: Label = $Margin/Panel/VBox/HealthLabel
@onready var mutation_bar: ProgressBar = $Margin/Panel/VBox/MutationBar
@onready var mutation_label: Label = $Margin/Panel/VBox/MutationLabel
@onready var critical_label: Label = $Margin/Panel/VBox/CriticalLabel
@onready var control_label: Label = $Margin/Panel/VBox/ControlLabel

var _player: Node
var _infection: Node


func _ready() -> void:
	_player = get_node(player_path)
	_infection = _player.get_node("InfectionRuntime")
	health_bar.max_value = _player.max_health
	mutation_bar.max_value = 100.0
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _player == null or _infection == null:
		return

	health_bar.value = _player.health
	health_label.text = "HP  %d / %d" % [roundi(_player.health), roundi(_player.max_health)]

	var mutation: float = _infection.call("get_mutation")
	var critical: float = _infection.call("get_critical_threshold")
	mutation_bar.value = mutation
	mutation_label.text = "MUTATION  %d / 100" % roundi(mutation)
	critical_label.text = "CRITICAL  %d" % roundi(critical)

	if _infection.call("is_defeated"):
		control_label.text = "CONTROL: DEFEAT"
	elif _infection.call("is_control_lost"):
		control_label.text = "CONTROL: LOST"
	elif mutation >= critical:
		control_label.text = "CONTROL: UNSTABLE"
	else:
		control_label.text = "CONTROL: STABLE"
