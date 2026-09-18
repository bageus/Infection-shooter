extends Node3D

@onready var player: Node3D = $Player
@onready var enemies: Array[Node] = [
	$Enemies/Infected01,
	$Enemies/Infected02,
	$Enemies/Infected03,
	$Enemies/Infected04,
	$Enemies/Infected05,
]


func _ready() -> void:
	for enemy in enemies:
		if enemy != null and enemy.has_method("set_target"):
			enemy.call("set_target", player)
