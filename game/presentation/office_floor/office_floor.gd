extends Node3D

@onready var player: Node3D = $Gameplay/Player
@onready var enemies: Array[Node] = [
	$Gameplay/Enemies/Infected1,
	$Gameplay/Enemies/Infected2,
	$Gameplay/Enemies/Infected3,
	$Gameplay/Enemies/Infected4,
	$Gameplay/Enemies/Infected5,
	$Gameplay/Enemies/Infected6,
]


func _ready() -> void:
	for enemy in enemies:
		if enemy != null and enemy.has_method("set_target"):
			enemy.call("set_target", player)
